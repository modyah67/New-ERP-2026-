-- ============================================================================
-- Migration 320: Definitive Packing Order General Ledger & Multi-Currency Accounting
-- ============================================================================
-- 1. rpc_confirm_packing_order:
--    - Finished Goods Cost = Produce Cost + Produce Waste - Sorting Cost + Packaging Cost + Packaging Waste + Additional Costs
--      (e.g. 50,000 + 5,000 - 5,000 + 50,000 + 2,500 + 2,000 = 104,500 EGP).
--    - DR Finished Goods Inventory (1031): 104,500.00 EGP (Capitalized export product asset).
--    - CR Produce Inventory (1030): 50,000.00 EGP (Actual raw fruit drawn).
--    - CR Packaging Materials Inventory (1040): 52,500.00 EGP (Materials consumed + packaging waste, preserving foreign currency if any).
--    - CR Supplier / Additional Cost Accounts: 2,000.00 EGP ($40.00 USD / EUR) on specific supplier accounts.
--    - Single balanced Journal Entry (Total Debits = Total Credits = 104,500.00 EGP).
--
-- 2. rpc_cancel_packing_order:
--    - Restores inventory batches (Produce & Materials).
--    - Reverses inventory entries (DR Produce 50,000, DR Packaging 52,500, CR Finished Goods 104,500).
--    - PRESERVES supplier payables ($40.00 / 2,000 EGP) recognizing the rendered service as cancellation expense (DR 51101 2,000 EGP).
--    - Supplier balances and ledger entries remain 100% untouched.
-- ============================================================================

-- ── 1. Update rpc_confirm_packing_order ──
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order           RECORD;
  v_notes           JSONB;
  v_station_id      INTEGER;
  v_alloc           JSONB;
  v_el              JSONB;
  v_batch_id        BIGINT;
  v_used_qty        NUMERIC;
  v_curr_rem        NUMERIC;
  v_pname           TEXT;
  v_pcode           TEXT;
  v_sp_qty          NUMERIC;
  v_new_batch_id    INTEGER;
  v_company_id      UUID;
  v_finished_inv_acc BIGINT;
  v_raw_inv_acc     BIGINT;
  v_pkg_inv_acc     BIGINT;
  v_waste_acc       BIGINT;
  v_expense_acc     BIGINT;
  v_credit_acc      BIGINT;
  v_credit_currency TEXT;
  v_je_id           BIGINT;
  v_entry_num       TEXT;
  v_sum_debit       NUMERIC := 0;
  v_sum_credit      NUMERIC := 0;

  v_line_ids        BIGINT[] := ARRAY[]::BIGINT[];
  v_line_raw        NUMERIC[] := ARRAY[]::NUMERIC[];
  v_line_net        NUMERIC[] := ARRAY[]::NUMERIC[];
  v_line_overhead   NUMERIC[] := ARRAY[]::NUMERIC[];
  v_bases           NUMERIC[] := ARRAY[]::NUMERIC[];
  v_shares          NUMERIC[] := ARRAY[]::NUMERIC[];
  v_n               INT := 0;
  v_lines           RECORD;
  r_cost            RECORD;
  v_amount          NUMERIC;
  v_method          TEXT;
  v_assigned        NUMERIC;
  v_part            NUMERIC;

  v_tot_raw_cost    NUMERIC := 0;
  v_tot_pkg_cost    NUMERIC := 0;
  v_tot_waste_cost  NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_tot_cost_items  NUMERIC := 0;
  v_finished_goods_cost NUMERIC := 0;

  v_supplier_id     UUID;
  v_supp_str        TEXT;
  v_target_line_idx INTEGER;
  v_amt_egp         NUMERIC;
  v_max_cost_item_id BIGINT;
  v_current_balance NUMERIC;
  v_treasury_tx_id  BIGINT;
  v_bank_tx_id      BIGINT;
  v_tx_desc         TEXT;
  v_mat_waste_multiplier NUMERIC := 1.0;
  v_mat_waste_pct   NUMERIC := 0.0;
  v_pkg_line_count  INT := 0;
BEGIN
  -- ── 0. Lock and validate order ──
  SELECT * INTO v_order
  FROM public.packing_orders
  WHERE id = p_packing_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status = 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة مؤكد بالفعل');
  END IF;

  IF v_order.status != 'draft' AND v_order.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'حالة أمر التعبئة لا تسمح بالتأكيد: ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id::integer;
  v_notes := CASE
    WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb
    ELSE '{}'::jsonb
  END;

  -- ── A. Fruit Inventory Deduction ──
  IF v_notes ? 'fruit_allocation' THEN
    v_alloc := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_alloc) = 'object' THEN
      v_alloc := jsonb_build_array(v_alloc);
    END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'دفعة المحصول رقم % غير موجودة في المحطة', v_batch_id;
        END IF;

        IF v_curr_rem < v_used_qty THEN
          RAISE EXCEPTION 'الكمية المتبقية في دفعة المحصول (%) أقل من المطلوب سحبه (%)', v_curr_rem, v_used_qty;
        END IF;

        UPDATE public.station_product_batches
        SET remaining_quantity = remaining_quantity - v_used_qty
        WHERE id = v_batch_id;

        -- Update station_products total
        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

        UPDATE public.station_products
        SET quantity = v_sp_qty,
            updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
      END IF;
    END LOOP;
  END IF;

  -- ── B. Material Inventory Deduction ──
  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials')
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'used_qty')::numeric, (v_el->>'quantity')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_used_qty > 0 THEN
        IF v_batch_id IS NOT NULL AND v_batch_id > 0 THEN
          SELECT remaining_quantity INTO v_curr_rem
          FROM public.station_product_batches
          WHERE id = v_batch_id
          FOR UPDATE;

          IF FOUND AND v_curr_rem >= v_used_qty THEN
            UPDATE public.station_product_batches
            SET remaining_quantity = remaining_quantity - v_used_qty
            WHERE id = v_batch_id;
          ELSE
            -- Deduct across batches FIFO
            DECLARE
              v_rem_needed NUMERIC := v_used_qty;
              r_b RECORD;
              v_take NUMERIC;
            BEGIN
              FOR r_b IN (
                SELECT id, remaining_quantity
                FROM public.station_product_batches
                WHERE station_id = v_station_id
                  AND (product_name = v_pname OR product_code = v_pcode)
                  AND remaining_quantity > 0
                ORDER BY id ASC
                FOR UPDATE
              ) LOOP
                IF v_rem_needed <= 0 THEN EXIT; END IF;
                v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
                UPDATE public.station_product_batches
                SET remaining_quantity = remaining_quantity - v_take
                WHERE id = r_b.id;
                v_rem_needed := v_rem_needed - v_take;
              END LOOP;
            END;
          END IF;
        ELSE
          -- Deduct across batches FIFO
          DECLARE
            v_rem_needed NUMERIC := v_used_qty;
            r_b RECORD;
            v_take NUMERIC;
          BEGIN
            FOR r_b IN (
              SELECT id, remaining_quantity
              FROM public.station_product_batches
              WHERE station_id = v_station_id
                AND (product_name = v_pname OR product_code = v_pcode)
                AND remaining_quantity > 0
              ORDER BY id ASC
              FOR UPDATE
            ) LOOP
              IF v_rem_needed <= 0 THEN EXIT; END IF;
              v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
              UPDATE public.station_product_batches
              SET remaining_quantity = remaining_quantity - v_take
              WHERE id = r_b.id;
              v_rem_needed := v_rem_needed - v_take;
            END LOOP;
          END;
        END IF;

        -- Update station_products total
        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);

        UPDATE public.station_products
        SET quantity = v_sp_qty,
            updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);
      END IF;
    END LOOP;

    -- Sync raw_materials and stock_batches
    DECLARE
      r_mat RECORD;
      v_mat_id UUID;
      r_sb RECORD;
      v_rem_to_deduct NUMERIC;
      v_take_qty NUMERIC;
    BEGIN
      FOR r_mat IN (
        SELECT
          elem->>'product_code' AS pcode,
          elem->>'product_name' AS pname,
          SUM(COALESCE((elem->>'used_qty')::numeric, (elem->>'quantity')::numeric, 0)) AS total_used
        FROM jsonb_array_elements(v_notes->'materials') AS elem
        GROUP BY elem->>'product_code', elem->>'product_name'
      ) LOOP
        v_mat_id := NULL;
        IF r_mat.pcode IS NOT NULL AND r_mat.pcode != '' THEN
          SELECT id INTO v_mat_id FROM public.raw_materials
          WHERE code = r_mat.pcode
            AND (name = r_mat.pname OR name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR name || ' (مادة تعبئة)' = r_mat.pname)
          LIMIT 1;
        END IF;
        IF v_mat_id IS NULL AND r_mat.pcode IS NOT NULL AND r_mat.pcode != '' THEN
          SELECT id INTO v_mat_id FROM public.raw_materials WHERE code = r_mat.pcode LIMIT 1;
        END IF;
        IF v_mat_id IS NULL THEN
          SELECT id INTO v_mat_id FROM public.raw_materials
          WHERE name = r_mat.pname OR name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR name || ' (مادة تعبئة)' = r_mat.pname
          LIMIT 1;
        END IF;

        IF v_mat_id IS NOT NULL THEN
          UPDATE public.raw_materials
          SET quantity = (
            SELECT COALESCE(SUM(remaining_quantity), 0)
            FROM public.station_product_batches
            WHERE (product_code = r_mat.pcode OR product_name = r_mat.pname OR product_name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR product_name = r_mat.pname || ' (مادة تعبئة)')
              AND source_type != 'lot_receipt'
          ),
          updated_at = NOW()
          WHERE id = v_mat_id;

          v_rem_to_deduct := r_mat.total_used;
          FOR r_sb IN (
            SELECT * FROM public.stock_batches
            WHERE product_id = v_mat_id
              AND remaining_quantity > 0
              AND status = 'active'
            ORDER BY created_at ASC
            FOR UPDATE
          ) LOOP
            IF v_rem_to_deduct <= 0 THEN EXIT; END IF;
            v_take_qty := LEAST(r_sb.remaining_quantity, v_rem_to_deduct);
            UPDATE public.stock_batches
            SET remaining_quantity = remaining_quantity - v_take_qty,
                status = CASE WHEN remaining_quantity - v_take_qty <= 0 THEN 'depleted' ELSE 'active' END,
                updated_at = NOW()
            WHERE id = r_sb.id;
            v_rem_to_deduct := v_rem_to_deduct - v_take_qty;
          END LOOP;
        END IF;
      END LOOP;
    END;
  END IF;

  -- ── C. Rebuild cost items from notes ──
  IF v_notes ? 'cost_items' THEN
    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;
    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;
    IF v_max_cost_item_id > 0 THEN
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);
    ELSE
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), 1, false);
    END IF;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);
      IF v_amt_egp > 0 THEN
        v_supplier_id := NULL;
        v_supp_str := v_el->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
        END IF;

        v_target_line_idx := NULL;
        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' AND v_el->>'target_line_index' != 'null' THEN
          v_target_line_idx := (v_el->>'target_line_index')::integer;
        END IF;

        INSERT INTO public.packing_order_cost_items (
          packing_order_id, name, category,
          base_amount, original_amount, original_currency,
          payment_source_type, payment_source_id,
          allocation_method, target_line_id,
          currency_snapshot
        ) VALUES (
          p_packing_order_id,
          v_el->>'name',
          CASE WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'other') THEN v_el->>'category' ELSE 'other' END,
          v_amt_egp,
          COALESCE((v_el->>'total')::numeric, v_amt_egp),
          COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
          v_el->>'payment_source_type',
          NULLIF(v_el->>'payment_source_id', '')::integer,
          v_el->>'allocation_method',
          v_target_line_idx,
          jsonb_build_object(
            'supplier_id', v_supplier_id,
            'supplier_name', v_el->>'supplier_name',
            'target_line_index', v_target_line_idx
          )
        );
      END IF;
    END LOOP;
  END IF;

  -- ── D. Prepare for line allocation ──
  v_n := 0;
  v_bases := ARRAY[]::NUMERIC[];
  FOR v_lines IN
    SELECT id, COALESCE(raw_material_cost, 0) as rc, COALESCE(total_net_weight, 0) as nw
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id
    ORDER BY id
  LOOP
    v_n := v_n + 1;
    v_line_ids[v_n] := v_lines.id;
    v_line_raw[v_n] := v_lines.rc;
    v_line_net[v_n] := v_lines.nw;
    v_line_overhead[v_n] := 0;
    v_bases[v_n] := v_lines.rc;
  END LOOP;

  -- ── E. Allocate cost items across lines ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_amount := COALESCE(r_cost.base_amount, 0);
    IF v_amount <= 0 THEN CONTINUE; END IF;

    IF r_cost.target_line_id IS NOT NULL THEN
      IF r_cost.target_line_id >= 0 AND r_cost.target_line_id < v_n THEN
        v_line_overhead[r_cost.target_line_id + 1] := v_line_overhead[r_cost.target_line_id + 1] + v_amount;
      END IF;
      CONTINUE;
    END IF;

    v_method := COALESCE(r_cost.allocation_method, 'EQUAL');
    IF v_method = 'WEIGHT' THEN
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_net[v_i]; END LOOP;
    ELSIF v_method = 'COST' THEN
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_raw[v_i]; END LOOP;
    ELSE
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := 1; END LOOP;
    END IF;

    IF v_n > 0 THEN
      v_shares := public._packing_allocate_shares(v_method, v_bases);
      v_assigned := 0;
      FOR v_i IN 1..v_n LOOP
        IF v_i = v_n THEN
          v_part := ROUND(v_amount - v_assigned, 2);
        ELSE
          v_part := ROUND(v_amount * v_shares[v_i], 2);
        END IF;
        v_line_overhead[v_i] := v_line_overhead[v_i] + v_part;
        v_assigned := v_assigned + v_part;
      END LOOP;
    END IF;
  END LOOP;

  -- ── F. Calculate Cost Components According to the Business Rule ──
  -- Rule: Finished Goods = (Produce Cost + Produce Waste - Sorting) + (Packaging Cost + Packaging Waste) + Additional Costs

  -- 1. Produce Gross Drawn Cost
  v_tot_raw_cost := COALESCE(v_order.fruit_cost_base, 0);
  IF v_tot_raw_cost = 0 THEN
    IF v_notes ? 'fruit_allocation' THEN
      DECLARE
        v_f_elem JSONB;
        v_f_arr JSONB := v_notes->'fruit_allocation';
      BEGIN
        IF jsonb_typeof(v_f_arr) = 'object' THEN v_f_arr := jsonb_build_array(v_f_arr); END IF;
        FOR v_f_elem IN SELECT * FROM jsonb_array_elements(v_f_arr) LOOP
          v_tot_raw_cost := v_tot_raw_cost + (COALESCE((v_f_elem->>'quantity')::numeric, 0) * COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0));
        END LOOP;
      END;
    END IF;
  END IF;
  IF v_tot_raw_cost = 0 THEN
    v_tot_raw_cost := COALESCE(v_order.fruit_cost_allocated, 0);
  END IF;

  -- 2. Produce Waste Cost
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 3. Sorting Cost
  v_tot_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id;
  END IF;
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_sortings
    WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 4. Packaging Materials Cost (with packaging waste)
  v_tot_pkg_cost := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);

  -- 5. Additional Cost Items
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 6. Finished Goods Capitalized Cost = (Produce + Waste - Sorting) + Packaging + Overheads
  -- In standard calculation: if Produce is 50,000, Waste 5,000, Sorting 5,000 -> Produce component = 50,000.
  v_finished_goods_cost := COALESCE(v_order.total_packing_cost, (v_tot_raw_cost + v_tot_waste_cost - v_tot_sorting_cost + v_tot_pkg_cost + v_tot_cost_items));

  -- ── G. Process Payments for Treasury/Bank ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    IF r_cost.payment_source_id IS NOT NULL AND r_cost.payment_source_type IN ('treasury', 'bank') THEN
      v_tx_desc := 'مصروف أمر تعبئة: ' || COALESCE(r_cost.name, 'بند تكلفة');
      v_supplier_id := NULL;
      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
        END IF;
      END IF;

      IF r_cost.payment_source_type = 'treasury' AND r_cost.treasury_transaction_id IS NULL THEN
        SELECT balance INTO v_current_balance
        FROM public.treasury_balances
        WHERE treasury_id = r_cost.payment_source_id AND currency = r_cost.original_currency
        FOR UPDATE;
        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة للبند %', r_cost.name;
        END IF;
        PERFORM public.spend_custody(r_cost.payment_source_id, r_cost.original_currency, r_cost.original_amount, v_tx_desc, NULL, v_supplier_id, NULL, NULL, NULL);
        SELECT id INTO v_treasury_tx_id FROM public.treasury_transactions
        WHERE treasury_id = r_cost.payment_source_id AND type = 'expense' AND amount = r_cost.original_amount AND currency = r_cost.original_currency
        ORDER BY created_at DESC LIMIT 1;
        UPDATE public.packing_order_cost_items SET treasury_transaction_id = v_treasury_tx_id WHERE id = r_cost.id;
      ELSIF r_cost.payment_source_type = 'bank' AND r_cost.bank_transaction_id IS NULL THEN
        SELECT balance INTO v_current_balance FROM public.bank_accounts WHERE id = r_cost.payment_source_id FOR UPDATE;
        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في البنك للبند %', r_cost.name;
        END IF;
        SELECT (public.withdraw_bank_account(r_cost.payment_source_id::integer, r_cost.original_amount, v_tx_desc, CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END, v_supplier_id::text, NULL)->>'bank_tx_id')::integer INTO v_bank_tx_id;
        UPDATE public.packing_order_cost_items SET bank_transaction_id = v_bank_tx_id WHERE id = r_cost.id;
      END IF;
    END IF;
  END LOOP;

  -- ── H. Resolve GL Accounts ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;

  SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
  SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

  SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '5040' LIMIT 1;
  IF v_expense_acc IS NULL THEN SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '51101' LIMIT 1; END IF;
  IF v_expense_acc IS NULL THEN SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '6000' LIMIT 1; END IF;

  IF v_finished_inv_acc IS NULL OR v_raw_inv_acc IS NULL THEN
    RAISE EXCEPTION 'حسابات المخزون (1030/1031) غير موجودة في شجرة الحسابات';
  END IF;

  IF v_order.journal_entry_id IS NOT NULL THEN
    DELETE FROM account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;
    DELETE FROM journal_entries WHERE id = v_order.journal_entry_id;
  END IF;

  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status,
    is_auto_generated, source_type, source_id, company_id,
    created_by, created_at, updated_at
  ) VALUES (
    'PENDING',
    COALESCE(v_order.packed_at::date, v_order.created_at::date, CURRENT_DATE),
    'قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text),
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    auth.uid(), now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- ── 1. DR Finished Goods Inventory (Full Capitalized Production Cost) ──
  IF v_finished_goods_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, 'EGP', v_finished_goods_cost,
      'مخزون تام - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ' (صافي ' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_finished_goods_cost;
  END IF;

  -- ── 2. CR Raw Materials & Produce Inventory (Exact produce cost drawn) ──
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,
      'تحويل محاصيل خام - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text),
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- ── 3. CR Packaging Materials Inventory (Materials with foreign currency preserved) ──
  v_pkg_line_count := 0;
  v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
  v_mat_waste_multiplier := 1.0 + (v_mat_waste_pct / 100.0);

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    DECLARE
      v_m_el JSONB;
      v_m_curr TEXT;
      v_m_foreign NUMERIC;
      v_m_base NUMERIC;
      v_m_rate NUMERIC;
    BEGIN
      FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials') LOOP
        v_m_curr := COALESCE(NULLIF(v_m_el->>'currency', ''), 'EGP');
        v_m_foreign := COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) * COALESCE((v_m_el->>'unit_cost')::numeric, 0) * v_mat_waste_multiplier;
        v_m_rate := COALESCE(NULLIF((v_m_el->>'exchange_rate')::numeric, 0), 1.0);
        v_m_base := v_m_foreign * v_m_rate;

        IF v_m_base > 0 THEN
          v_pkg_line_count := v_pkg_line_count + 1;
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_pkg_inv_acc, 0, v_m_foreign, v_m_curr, v_m_base,
            'تكلفة مواد تعبئة وفاقد - ' || COALESCE(v_m_el->>'product_name', 'مادة تعبئة') || ' (أمر ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ')',
            v_company_id
          );
          v_sum_credit := v_sum_credit + v_m_base;
        END IF;
      END LOOP;
    END;
  END IF;

  -- Fallback if materials were not in notes array
  IF v_pkg_line_count = 0 AND v_tot_pkg_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_cost, 'EGP', v_tot_pkg_cost,
      'تكلفة مواد تعبئة وفاقد - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text),
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_cost;
  END IF;

  -- ── 4. CR Overheads (Suppliers/AP or Expense) ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;
    v_credit_currency := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');

    IF r_cost.payment_source_type IN ('treasury', 'bank') THEN
       v_credit_acc := v_expense_acc;
    ELSE
       v_supplier_id := NULL;
       IF r_cost.currency_snapshot IS NOT NULL THEN
         v_supp_str := r_cost.currency_snapshot->>'supplier_id';
         IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
           v_supplier_id := v_supp_str::uuid;
         END IF;
       END IF;

       IF v_supplier_id IS NOT NULL THEN
         SELECT a.id INTO v_credit_acc
         FROM public.suppliers s
         JOIN public.accounts a ON a.id = s.account_id
         WHERE s.id = v_supplier_id;

         INSERT INTO public.ledger_entries (
           entity_type, entity_id, entry_type, amount, currency,
           reference_type, reference_text, description, created_by
         ) VALUES (
           'supplier', v_supplier_id::text, 'credit', r_cost.original_amount, v_credit_currency,
           'packing_cost', p_packing_order_id::text,
           'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')',
           auth.uid()
         );

         UPDATE public.suppliers
         SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.original_amount,
             updated_at = now()
         WHERE id = v_supplier_id;
       END IF;

       IF v_credit_acc IS NULL THEN
         SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' LIMIT 1;
       END IF;
    END IF;

    IF v_credit_acc IS NOT NULL THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, r_cost.original_amount,
        v_credit_currency, r_cost.base_amount,
        'مصروفات أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ' - ' || COALESCE(r_cost.name, ''),
        v_company_id
      );
      v_sum_credit := v_sum_credit + r_cost.base_amount;
    END IF;
  END LOOP;

  -- Balance check
  IF ABS(ROUND(v_sum_debit, 2) - ROUND(v_sum_credit, 2)) > 0.01 THEN
    RAISE EXCEPTION
      'قيد أمر التعبئة غير متوازن: مدين=% دائن=% فرق=%',
      ROUND(v_sum_debit, 2), ROUND(v_sum_credit, 2),
      ROUND(v_sum_debit - v_sum_credit, 2);
  END IF;

  UPDATE public.packing_orders
  SET status = 'completed', journal_entry_id = v_je_id, updated_at = now()
  WHERE id = p_packing_order_id;

  FOR i IN 1..v_n LOOP
    UPDATE public.packing_order_lines
    SET allocated_cost_items = COALESCE(v_line_overhead[i], 0),
        final_cost = COALESCE(v_line_raw[i], 0) + COALESCE(v_line_overhead[i], 0),
        final_unit_cost = CASE WHEN COALESCE(v_line_net[i], 0) > 0 THEN (COALESCE(v_line_raw[i], 0) + COALESCE(v_line_overhead[i], 0)) / v_line_net[i] ELSE 0 END
    WHERE id = v_line_ids[i];
  END LOOP;

  RETURN json_build_object(
    'success', true, 'journal_entry_id', v_je_id,
    'finished_goods_cost', v_finished_goods_cost,
    'total_raw_cost', v_tot_raw_cost,
    'total_packaging_cost', v_tot_pkg_cost,
    'total_waste_cost', v_tot_waste_cost,
    'total_sorting_cost', v_tot_sorting_cost,
    'total_overhead', v_tot_cost_items,
    'lines_count', v_n,
    'debit', v_sum_debit, 'credit', v_sum_credit
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;


-- ── 2. Update rpc_cancel_packing_order ──
CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order           RECORD;
  v_notes           JSONB;
  v_station_id      INTEGER;
  v_je_id           BIGINT;
  v_rev_je_id       BIGINT;
  v_entry_num       TEXT;
  v_company_id      UUID;
  v_sold_sortings   INT;
  r_ale             RECORD;
  v_acc_code        TEXT;
  v_cancel_exp_acc  BIGINT;
  v_sum_debit       NUMERIC := 0;
  v_sum_credit      NUMERIC := 0;
BEGIN
  -- ── 1. Validate Order ──
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  SELECT COUNT(*) INTO v_sold_sortings
  FROM public.packing_order_sortings
  WHERE packing_order_id = p_packing_order_id
    AND (status = 'sold' OR COALESCE(total_sale_amount, 0) > 0);

  IF v_sold_sortings > 0 THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن الإلغاء: يوجد فرز مباع مرتبط بالأمر');
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  -- ── 2. Create Reversing Journal Entry (Keep Original for Audit Trail) ──
  v_je_id := v_order.journal_entry_id;
  IF v_je_id IS NULL THEN
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'packing_order' AND source_id = p_packing_order_id::text
    ORDER BY id DESC LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    SELECT company_id INTO v_company_id FROM public.journal_entries WHERE id = v_je_id;
    IF v_company_id IS NULL THEN
      SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- Resolve Cancellation Expense account
    SELECT id INTO v_cancel_exp_acc FROM accounts WHERE account_code = '51101' LIMIT 1;
    IF v_cancel_exp_acc IS NULL THEN
      SELECT id INTO v_cancel_exp_acc FROM accounts WHERE account_code = '6000' LIMIT 1;
    END IF;

    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      CURRENT_DATE,
      'عكس قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text)
        || ' (مرجع القيد الأصلي #' || v_je_id::text || ')',
      'posted', true, 'packing_order_reversal', p_packing_order_id::text,
      v_company_id, auth.uid(), NOW(), NOW()
    ) RETURNING id INTO v_rev_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_rev_je_id;

    FOR r_ale IN
      SELECT * FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id
    LOOP
      SELECT account_code INTO v_acc_code FROM public.accounts WHERE id = r_ale.account_id;

      -- Case A: Finished Goods Debit -> Reverse by Crediting Finished Goods
      IF COALESCE(r_ale.debit, 0) > 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency,
          amount_in_base_currency, description, company_id
        ) VALUES (
          v_rev_je_id,
          r_ale.account_id,
          0,
          r_ale.debit,
          COALESCE(r_ale.currency, 'EGP'),
          COALESCE(r_ale.amount_in_base_currency, r_ale.debit),
          'عكس: ' || COALESCE(r_ale.description, ''),
          v_company_id
        );
        v_sum_credit := v_sum_credit + COALESCE(r_ale.amount_in_base_currency, r_ale.debit);

      -- Case B: Credit lines (Inventory vs Supplier/Service)
      ELSIF COALESCE(r_ale.credit, 0) > 0 THEN
        -- B.1 Inventory Credits (1030 Produce, 1040 Packaging) -> Reverse by Debiting Inventory (Stock restored)
        IF v_acc_code IN ('1030', '1040') THEN
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency,
            amount_in_base_currency, description, company_id
          ) VALUES (
            v_rev_je_id,
            r_ale.account_id,
            r_ale.credit,
            0,
            COALESCE(r_ale.currency, 'EGP'),
            COALESCE(r_ale.amount_in_base_currency, r_ale.credit),
            'استرجاع مخزون: ' || COALESCE(r_ale.description, ''),
            v_company_id
          );
          v_sum_debit := v_sum_debit + COALESCE(r_ale.amount_in_base_currency, r_ale.credit);

        -- B.2 Supplier / Service lines -> DO NOT reverse supplier balance!
        -- Instead, record the service as a Cancellation / Sunk Expense.
        ELSE
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency,
            amount_in_base_currency, description, company_id
          ) VALUES (
            v_rev_je_id,
            v_cancel_exp_acc,
            r_ale.amount_in_base_currency,
            0,
            'EGP',
            r_ale.amount_in_base_currency,
            'مصروف خدمات أمر تعبئة ملغي - ' || COALESCE(r_ale.description, ''),
            v_company_id
          );
          v_sum_debit := v_sum_debit + r_ale.amount_in_base_currency;
        END IF;
      END IF;
    END LOOP;

    -- Symmetrical balance check
    IF ABS(ROUND(v_sum_debit, 2) - ROUND(v_sum_credit, 2)) > 0.01 THEN
      RAISE EXCEPTION
        'قيد عكس أمر التعبئة غير متوازن: مدين=% دائن=% فرق=%',
        ROUND(v_sum_debit, 2), ROUND(v_sum_credit, 2),
        ROUND(v_sum_debit - v_sum_credit, 2);
    END IF;

    UPDATE public.journal_entries
    SET description = COALESCE(description, '') || ' [تم عكسه بالقيد #' || v_rev_je_id::text || ']'
    WHERE id = v_je_id;
  END IF;

  -- ── 3. Restore Stock in Warehouse ──
  v_notes := v_order.notes;
  IF jsonb_typeof(v_notes) = 'object' AND v_notes ? 'notes' AND jsonb_typeof(v_notes->'notes') = 'string' THEN
    BEGIN v_notes := (v_notes->>'notes')::jsonb; EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF jsonb_typeof(v_notes) = 'string' THEN
    BEGIN v_notes := (v_notes#>>'{}')::jsonb; EXCEPTION WHEN OTHERS THEN v_notes := '{}'::jsonb; END;
  END IF;
  IF v_notes IS NULL THEN v_notes := '{}'::jsonb; END IF;

  -- Restore fruit batches
  IF v_notes ? 'fruit_allocation' THEN
    IF jsonb_typeof(v_notes->'fruit_allocation') = 'array' THEN
      WITH restored_fruits AS (
        SELECT
          (el->>'batch_id')::bigint AS batch_id,
          (el->>'quantity')::numeric AS quantity
        FROM jsonb_array_elements(v_notes->'fruit_allocation') el
        WHERE (el->>'quantity')::numeric > 0
          AND NULLIF(el->>'batch_id', '') IS NOT NULL
      )
      UPDATE public.station_product_batches b
      SET remaining_quantity = b.remaining_quantity + u.quantity
      FROM restored_fruits u
      WHERE b.id = u.batch_id;
    ELSIF jsonb_typeof(v_notes->'fruit_allocation') = 'object' THEN
      IF NULLIF(v_notes->'fruit_allocation'->>'batch_id', '') IS NOT NULL THEN
        UPDATE public.station_product_batches b
        SET remaining_quantity = b.remaining_quantity + (v_notes->'fruit_allocation'->>'quantity')::numeric
        WHERE b.id = (v_notes->'fruit_allocation'->>'batch_id')::bigint;
      END IF;
    END IF;
  END IF;

  -- Restore material batches
  IF v_notes ? 'materials' THEN
    WITH restored_materials AS (
      SELECT
        (el->>'batch_id')::bigint AS batch_id,
        (el->>'used_qty')::numeric AS used_qty
      FROM jsonb_array_elements(v_notes->'materials') el
      WHERE (el->>'used_qty')::numeric > 0
        AND NULLIF(el->>'batch_id', '') IS NOT NULL
    )
    UPDATE public.station_product_batches b
    SET remaining_quantity = b.remaining_quantity + u.used_qty
    FROM restored_materials u
    WHERE b.id = u.batch_id;
  END IF;

  -- Sync station_products for fruit
  IF v_notes ? 'fruit_allocation' THEN
    DECLARE
      r_fruit RECORD;
    BEGIN
      FOR r_fruit IN (
        SELECT DISTINCT el->>'product_name' AS pname
        FROM (
          SELECT jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_notes->'fruit_allocation') = 'array'
                 THEN v_notes->'fruit_allocation'
                 ELSE jsonb_build_array(v_notes->'fruit_allocation')
            END
          ) AS el
        ) sub
        WHERE NULLIF(el->>'product_name', '') IS NOT NULL
      ) LOOP
        UPDATE public.station_products
        SET quantity = (
          SELECT COALESCE(SUM(remaining_quantity), 0)
          FROM public.station_product_batches
          WHERE station_id = v_station_id AND product_name = r_fruit.pname
        ),
        updated_at = NOW()
        WHERE station_id = v_station_id AND product_name = r_fruit.pname;
      END LOOP;
    END;
  END IF;

  -- Sync station_products, raw_materials, and stock_batches for materials
  IF v_notes ? 'materials' THEN
    DECLARE
      r_mat RECORD;
      v_mat_id UUID;
    BEGIN
      FOR r_mat IN (
        SELECT
          el->>'product_name' AS pname,
          el->>'product_code' AS pcode,
          SUM((el->>'used_qty')::numeric) AS total_used
        FROM jsonb_array_elements(v_notes->'materials') AS el
        WHERE (el->>'used_qty')::numeric > 0
        GROUP BY el->>'product_name', el->>'product_code'
      ) LOOP
        UPDATE public.station_products
        SET quantity = (
          SELECT COALESCE(SUM(remaining_quantity), 0)
          FROM public.station_product_batches
          WHERE station_id = v_station_id AND product_name = r_mat.pname
        ),
        updated_at = NOW()
        WHERE station_id = v_station_id AND product_name = r_mat.pname;

        v_mat_id := NULL;
        IF r_mat.pcode IS NOT NULL AND r_mat.pcode != '' THEN
          SELECT id INTO v_mat_id FROM public.raw_materials WHERE code = r_mat.pcode LIMIT 1;
        END IF;
        IF v_mat_id IS NULL THEN
          SELECT id INTO v_mat_id FROM public.raw_materials
          WHERE name = r_mat.pname OR name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR name || ' (مادة تعبئة)' = r_mat.pname
          LIMIT 1;
        END IF;

        IF v_mat_id IS NOT NULL THEN
          UPDATE public.raw_materials
          SET quantity = (
            SELECT COALESCE(SUM(remaining_quantity), 0)
            FROM public.station_product_batches
            WHERE (product_code = r_mat.pcode OR product_name = r_mat.pname OR product_name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR product_name = r_mat.pname || ' (مادة تعبئة)')
              AND source_type != 'lot_receipt'
          ),
          updated_at = NOW()
          WHERE id = v_mat_id;

          -- Restore to latest stock batch or active stock batch
          UPDATE public.stock_batches
          SET remaining_quantity = remaining_quantity + r_mat.total_used,
              status = 'active',
              updated_at = NOW()
          WHERE id = (
            SELECT id FROM public.stock_batches
            WHERE product_id = v_mat_id
            ORDER BY created_at DESC LIMIT 1
          );
        END IF;
      END LOOP;
    END;
  END IF;

  -- ── 4. Delete pending (unsold) sortings ──
  DELETE FROM public.packing_order_sortings
  WHERE packing_order_id = p_packing_order_id
    AND status = 'pending'
    AND COALESCE(total_sale_amount, 0) = 0;

  -- ── 5. Mark cancelled (Do NOT touch suppliers or cost item ledger entries!) ──
  UPDATE public.packing_orders
  SET status = 'cancelled',
      reversal_journal_entry_id = v_rev_je_id,
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'original_journal_entry_id', v_je_id,
    'reversal_journal_entry_id', v_rev_je_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_packing_order(bigint) TO authenticated;

NOTIFY pgrst, 'reload schema';
