-- ============================================================================
-- Migration 312: Fix Packing Order GL Accounting, Wastage Allocation, and Price Adjustments
-- ============================================================================

-- 1. Register packing_cost_adjustment document sequence if missing
INSERT INTO sys_document_types (code, name, prefix)
VALUES ('packing_cost_adjustment', 'تسوية تكلفة أمر تعبئة', 'PKADJ')
ON CONFLICT (code) DO NOTHING;

-- 2. Enhanced rpc_confirm_packing_order with separate Produce Waste Debit and balanced GL
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
  v_tot_final_cost  NUMERIC := 0;
  v_tot_raw_cost    NUMERIC := 0;
  v_tot_pkg_cost    NUMERIC := 0;
  v_tot_waste_cost  NUMERIC := 0;
  v_tot_cost_items  NUMERIC := 0;
  v_finished_goods_cost NUMERIC := 0;
  v_raw_materials_credit NUMERIC := 0;

  v_supplier_id     UUID;
  v_supp_str        TEXT;
  v_target_line_idx INTEGER;
  v_amt_egp         NUMERIC;
  v_max_cost_item_id BIGINT;
  v_current_balance NUMERIC;
  v_treasury_tx_id  BIGINT;
  v_bank_tx_id      BIGINT;
  v_tx_desc         TEXT;
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

  -- ── D. Prepare for allocation ──
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

  -- ── E. Allocate cost items ──
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

  -- ── F. Calculate Totals ──
  v_tot_final_cost := 0;
  v_tot_raw_cost := 0;
  FOR v_i IN 1..v_n LOOP
    v_tot_raw_cost := v_tot_raw_cost + v_line_raw[v_i];
    v_tot_final_cost := v_tot_final_cost + v_line_raw[v_i] + v_line_overhead[v_i];
  END LOOP;

  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;

  -- Produce Waste Cost
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id;
  END IF;

  IF v_tot_final_cost = 0 THEN
    v_tot_raw_cost   := COALESCE(v_order.fruit_cost_allocated, v_order.fruit_cost_base, 0);
    v_tot_pkg_cost   := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
    v_tot_final_cost := COALESCE(v_order.total_packing_cost, (v_tot_raw_cost + v_tot_pkg_cost + v_tot_cost_items));
  ELSE
    v_tot_pkg_cost := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_tot_final_cost := v_tot_final_cost + v_tot_pkg_cost;
  END IF;

  -- Net finished goods cost excludes produce waste (waste is expensed separately)
  v_finished_goods_cost := v_tot_final_cost;
  v_raw_materials_credit := v_tot_raw_cost + v_tot_waste_cost;

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

  -- ── H. Resolve GL accounts & Finalize Single Balanced JE ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;

  SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
  SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

  -- Expense / Waste Accounts
  SELECT id INTO v_waste_acc FROM accounts WHERE account_code IN ('5041', '5050', '5040') AND allow_posting = true LIMIT 1;
  IF v_waste_acc IS NULL THEN
    SELECT id INTO v_waste_acc FROM accounts
    WHERE (account_name ILIKE '%هالك%' OR account_name ILIKE '%فاقد%' OR name ILIKE '%waste%' OR name ILIKE '%loss%')
      AND allow_posting = true LIMIT 1;
  END IF;

  SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '5040' LIMIT 1;
  IF v_expense_acc IS NULL THEN SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '51101' LIMIT 1; END IF;
  IF v_expense_acc IS NULL THEN SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '6000' LIMIT 1; END IF;
  IF v_waste_acc IS NULL THEN v_waste_acc := v_expense_acc; END IF;

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

  -- 1. DR Finished Goods Inventory (329,050)
  IF v_finished_goods_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, 'EGP', v_finished_goods_cost,
      'مخزون تام - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text), v_company_id
    );
    v_sum_debit := v_sum_debit + v_finished_goods_cost;
  END IF;

  -- 2. DR Produce Waste / Loss Expense (5,000)
  IF v_tot_waste_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_waste_acc, v_tot_waste_cost, 0, 'EGP', v_tot_waste_cost,
      'هالك محاصيل - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text), v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_waste_cost;
  END IF;

  -- 3. CR Raw Materials & Produce Inventory (63,500 + 5,000 = 68,500)
  IF v_raw_materials_credit > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_raw_materials_credit, 'EGP', v_raw_materials_credit,
      'تحويل محاصيل خام وهالك - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text), v_company_id
    );
    v_sum_credit := v_sum_credit + v_raw_materials_credit;
  END IF;

  -- 4. CR Packaging Materials Inventory (251,000 + 12,550 = 263,550)
  IF v_tot_pkg_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_cost, 'EGP', v_tot_pkg_cost,
      'تكلفة مواد تعبئة وفاقد - أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text), v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_cost;
  END IF;

  -- 5. CR Overheads (Suppliers/AP or Expense) (2,000)
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
    'total_final_cost', v_tot_final_cost, 'total_raw_cost', v_tot_raw_cost,
    'total_packaging_cost', v_tot_pkg_cost, 'total_waste_cost', v_tot_waste_cost,
    'total_overhead', v_tot_cost_items, 'lines_count', v_n,
    'debit', v_sum_debit, 'credit', v_sum_credit
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;


-- 3. Price Adjustments on Confirmed Packing Orders
CREATE OR REPLACE FUNCTION public.rpc_refresh_packing_order_prices(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order RECORD;
    v_notes JSONB;
    v_fruit_allocation JSONB;
    v_materials JSONB;
    v_elem JSONB;
    v_updated_fruit_allocations JSONB := '[]'::jsonb;
    v_updated_materials JSONB := '[]'::jsonb;
    v_batch_price NUMERIC;
    v_batch_ex NUMERIC;
    v_new_fruit_cost NUMERIC := 0;
    v_new_material_cost NUMERIC := 0;
    v_other_cost_base NUMERIC := 0;
    v_total_cost NUMERIC := 0;
    v_packing_cost_per_carton NUMERIC := 0;

    v_old_total_cost NUMERIC := 0;
    v_old_fruit_cost NUMERIC := 0;
    v_old_mat_cost NUMERIC := 0;
    v_cost_delta NUMERIC := 0;
    v_fruit_delta NUMERIC := 0;
    v_mat_delta NUMERIC := 0;
    v_company_id UUID;
    v_finished_inv_acc BIGINT;
    v_raw_inv_acc BIGINT;
    v_pkg_inv_acc BIGINT;
    v_adj_je_id BIGINT;
    v_adj_entry_num TEXT;
BEGIN
    SELECT * INTO v_order FROM packing_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb ELSE '{}'::jsonb END;
    
    -- 1. Refresh fruit allocation
    v_fruit_allocation := v_notes -> 'fruit_allocation';
    IF jsonb_typeof(v_fruit_allocation) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_fruit_allocation) LOOP
            SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex 
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_fruit_cost := v_new_fruit_cost + (COALESCE((v_elem->>'quantity')::numeric, 0) * (COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1)));
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(jsonb_set(v_elem, '{unit_cost}', to_jsonb(COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1))));
            ELSE
                v_new_fruit_cost := v_new_fruit_cost + COALESCE((v_elem->>'fruit_cost')::numeric, 0);
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(v_fruit_allocation) = 'object' THEN
        SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex 
        FROM station_product_batches WHERE id = (v_fruit_allocation->>'batch_id')::bigint;
        IF FOUND THEN
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * (COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1));
            v_updated_fruit_allocations := jsonb_set(v_fruit_allocation, '{unit_cost}', to_jsonb(COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1)));
        ELSE
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'fruit_cost')::numeric, 0);
            v_updated_fruit_allocations := v_fruit_allocation;
        END IF;
    END IF;

    -- 2. Refresh materials
    v_materials := v_notes -> 'materials';
    IF jsonb_typeof(v_materials) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
            SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex 
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_material_cost := v_new_material_cost + (COALESCE((v_elem->>'used_qty')::numeric, 0) * (COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1)));
                v_elem := jsonb_set(v_elem, '{unit_cost}', to_jsonb(COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1)));
                v_elem := jsonb_set(v_elem, '{total_cost}', to_jsonb(COALESCE((v_elem->>'used_qty')::numeric, 0) * (COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1))));
                v_updated_materials := v_updated_materials || jsonb_build_array(v_elem);
            ELSE
                v_new_material_cost := v_new_material_cost + COALESCE((v_elem->>'total_cost')::numeric, 0);
                v_updated_materials := v_updated_materials || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    END IF;

    IF jsonb_typeof(v_fruit_allocation) = 'array' OR jsonb_typeof(v_fruit_allocation) = 'object' THEN
        v_notes := jsonb_set(v_notes, '{fruit_allocation}', v_updated_fruit_allocations);
    END IF;
    IF jsonb_typeof(v_materials) = 'array' THEN
        v_notes := jsonb_set(v_notes, '{materials}', v_updated_materials);
    END IF;

    v_other_cost_base := COALESCE(v_order.other_cost_base, 0);
    v_total_cost := v_new_fruit_cost + v_new_material_cost + v_other_cost_base;
    
    IF COALESCE(v_order.carton_count, 0) > 0 THEN
        v_packing_cost_per_carton := v_total_cost / v_order.carton_count;
    END IF;

    v_old_total_cost := COALESCE(v_order.total_packing_cost, 0);
    v_old_fruit_cost := COALESCE(v_order.fruit_cost_base, 0);
    v_old_mat_cost   := COALESCE(v_order.material_cost_base, 0);

    v_cost_delta  := v_total_cost - v_old_total_cost;
    v_fruit_delta := v_new_fruit_cost - v_old_fruit_cost;
    v_mat_delta   := v_new_material_cost - v_old_mat_cost;

    -- 3. Post Adjustment Journal Entry if completed and price delta exists
    IF v_order.status = 'completed' AND v_order.journal_entry_id IS NOT NULL AND ABS(v_cost_delta) >= 0.01 THEN
        SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
        IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

        SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
        IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;

        SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
        SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
        IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status,
            is_auto_generated, source_type, source_id, company_id,
            created_by, created_at, updated_at
        ) VALUES (
            'PENDING',
            CURRENT_DATE,
            'تسوية تكلفة أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text),
            'posted', true, 'packing_cost_adjustment', p_order_id::text, v_company_id,
            auth.uid(), now(), now()
        ) RETURNING id INTO v_adj_je_id;

        v_adj_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_cost_adjustment', NULL, NULL);
        UPDATE public.journal_entries SET entry_number = v_adj_entry_num WHERE id = v_adj_je_id;

        IF v_cost_delta > 0 THEN
            -- Increase in Finished Goods
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_adj_je_id, v_finished_inv_acc, v_cost_delta, 0, 'EGP', v_cost_delta,
                'تسوية تكلفة بالزيادة - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
            );

            IF v_fruit_delta > 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_raw_inv_acc, 0, v_fruit_delta, 'EGP', v_fruit_delta,
                    'تسوية تكلفة محاصيل بالزيادة - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            ELSIF v_fruit_delta < 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_raw_inv_acc, ABS(v_fruit_delta), 0, 'EGP', ABS(v_fruit_delta),
                    'تسوية تكلفة محاصيل بالنقصان - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            END IF;

            IF v_mat_delta > 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_pkg_inv_acc, 0, v_mat_delta, 'EGP', v_mat_delta,
                    'تسوية مواد تعبئة بالزيادة - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            ELSIF v_mat_delta < 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_pkg_inv_acc, ABS(v_mat_delta), 0, 'EGP', ABS(v_mat_delta),
                    'تسوية مواد تعبئة بالنقصان - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            END IF;
        ELSE
            -- Decrease in Finished Goods
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_adj_je_id, v_finished_inv_acc, 0, ABS(v_cost_delta), 'EGP', ABS(v_cost_delta),
                'تسوية تكلفة بالنقصان - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
            );

            IF v_fruit_delta < 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_raw_inv_acc, ABS(v_fruit_delta), 0, 'EGP', ABS(v_fruit_delta),
                    'تسوية تكلفة محاصيل بالنقصان - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            ELSIF v_fruit_delta > 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_raw_inv_acc, 0, v_fruit_delta, 'EGP', v_fruit_delta,
                    'تسوية تكلفة محاصيل بالزيادة - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            END IF;

            IF v_mat_delta < 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_pkg_inv_acc, ABS(v_mat_delta), 0, 'EGP', ABS(v_mat_delta),
                    'تسوية مواد تعبئة بالنقصان - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            ELSIF v_mat_delta > 0 THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_adj_je_id, v_pkg_inv_acc, 0, v_mat_delta, 'EGP', v_mat_delta,
                    'تسوية مواد تعبئة بالزيادة - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id
                );
            END IF;
        END IF;
    END IF;

    UPDATE packing_orders
    SET 
        fruit_cost_base = v_new_fruit_cost,
        fruit_cost_allocated = v_new_fruit_cost,
        material_cost_base = v_new_material_cost,
        actual_material_cost = v_new_material_cost,
        estimated_material_cost = v_new_material_cost,
        total_packing_cost = v_total_cost,
        packing_cost_per_carton = v_packing_cost_per_carton,
        notes = v_notes::text,
        needs_price_refresh = false,
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'cost_delta', v_cost_delta,
        'adj_journal_entry_id', v_adj_je_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_refresh_packing_order_prices(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';
