-- Migration 331: Direct Decomposition of Packing Order Cost to Accounts
-- Date: 2026-08-18
--
-- ACCOUNTING MAPPING (Directly from Packing Order Breakdown):
--   1. DR 1031 (مخزون الإنتاج التام)            = Total Packing Cost (104,500.00)
--   2. CR 1030 (مخزون المحاصيل)                 = Fruit Cost Net of Sorting (45,000.00)
--   3. CR 51102 (هالك وفاقد المحاصيل)           = Crop Waste Cost (5,000.00) [if > 0]
--   4. CR 1040 (مخزون مواد التعبئة والتغليف)    = Base Packaging Cost (50,000.00)
--   5. CR 51104 (هالك وفاقد مواد التعبئة)       = Packaging Waste Cost (2,500.00) [if > 0]
--   6. CR Supplier / Cash Accounts              = Additional Cost Items (2,000.00) [if > 0]
--
-- EXACT TOTAL OF JOURNAL ENTRY:
--   Total DR = 104,500.00
--   Total CR = 45,000 + 5,000 + 50,000 + 2,500 + 2,000 = 104,500.00
--   Difference = 0.00 ✓

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(
  p_packing_order_id BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_station_id INT;
  v_packed_at TIMESTAMPTZ;
  v_company_id UUID;

  -- Cost components directly read from order
  v_tot_raw_cost NUMERIC := 0;
  v_tot_waste_cost NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_fruit_net_cost NUMERIC := 0;
  v_mat_waste_pct NUMERIC := 0;
  v_tot_pkg_drawn NUMERIC := 0;
  v_tot_pkg_waste NUMERIC := 0;
  v_tot_pkg_consumed NUMERIC := 0;
  v_tot_cost_items NUMERIC := 0;
  v_finished_goods_cost NUMERIC := 0;

  -- Account IDs
  v_finished_inv_acc INT;
  v_raw_inv_acc INT;
  v_pkg_inv_acc INT;
  v_crop_waste_acc INT;
  v_pkg_waste_acc INT;
  v_credit_acc INT;
  v_supp_leaf_acc INT;

  -- Journal entry tracking
  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  -- Loop variables
  v_el JSONB;
  r_cost RECORD;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_tx_desc TEXT;
  v_current_balance NUMERIC;
  v_treasury_tx_id BIGINT;
  v_bank_tx_id INT;

  -- Inventory deduction variables
  v_alloc JSONB;
  v_batch_id BIGINT;
  v_used_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_curr_rem NUMERIC;
  v_sp_qty NUMERIC;
  v_rem_needed NUMERIC;
  r_b RECORD;
  v_take NUMERIC;

  -- Cost allocation arrays
  v_n INT := 0;
  v_lines RECORD;
  v_line_ids BIGINT[];
  v_line_raw NUMERIC[];
  v_line_net NUMERIC[];
  v_line_overhead NUMERIC[];
  v_bases NUMERIC[];
  v_shares NUMERIC[];
  v_amount NUMERIC;
  v_method TEXT;
  v_assigned NUMERIC;
  v_part NUMERIC;
  v_max_cost_item_id BIGINT;
BEGIN
  -- ── A. Validate Packing Order ──
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status = 'completed' THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة مؤكد بالفعل',
      'journal_entry_id', v_order.journal_entry_id
    );
  END IF;

  IF v_order.status != 'draft' AND v_order.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'حالة أمر التعبئة لا تسمح بالتأكيد: ' || v_order.status);
  END IF;

  v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);
  v_station_id := v_order.station_id;
  v_packed_at := COALESCE(v_order.packed_at, now());

  -- ── B. Fruit Inventory Deduction ──
  IF v_notes ? 'fruit_allocation' THEN
    v_alloc := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_alloc) = 'object' THEN v_alloc := jsonb_build_array(v_alloc); END IF;

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

        IF FOUND AND v_curr_rem >= v_used_qty THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - v_used_qty
          WHERE id = v_batch_id;

          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
          FROM public.station_product_batches
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

          UPDATE public.station_products
          SET quantity = v_sp_qty, updated_at = NOW()
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- ── C. Material Inventory Deduction ──
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
            v_rem_needed := v_used_qty;
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
          END IF;
        ELSE
          v_rem_needed := v_used_qty;
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
        END IF;

        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);

        UPDATE public.station_products
        SET quantity = v_sp_qty, updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);
      END IF;
    END LOOP;
  END IF;

  -- ── D. Rebuild Cost Items from Notes ──
  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
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

  -- ── E. Allocate Cost Items Across Lines ──
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

  -- ══════════════════════════════════════════════════════════════════════════
  -- F. Calculate Cost Values Directly from Packing Order Data
  -- ══════════════════════════════════════════════════════════════════════════

  -- 1. Produce Raw Cost
  v_tot_raw_cost := COALESCE(v_order.fruit_cost_base, 0);
  IF v_tot_raw_cost = 0 THEN
    IF v_notes ? 'fruit_allocation' THEN
      DECLARE
        v_f_elem JSONB;
        v_f_arr JSONB := v_notes->'fruit_allocation';
      BEGIN
        IF jsonb_typeof(v_f_arr) = 'object' THEN v_f_arr := jsonb_build_array(v_f_arr); END IF;
        FOR v_f_elem IN SELECT * FROM jsonb_array_elements(v_f_arr) LOOP
          v_tot_raw_cost := v_tot_raw_cost + (
            COALESCE((v_f_elem->>'quantity')::numeric, 0) *
            COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0)
          );
        END LOOP;
      END;
    END IF;
  END IF;
  IF v_tot_raw_cost = 0 THEN
    v_tot_raw_cost := COALESCE(v_order.fruit_cost_allocated, 0);
  END IF;

  -- 2. Produce Waste Cost (51102)
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 3. Produce Sorting Cost (51103)
  v_tot_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_sortings WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- Produce cost net of sorting (تكلفة المحصول بدون الهالك والفرز)
  v_fruit_net_cost := GREATEST(0, v_tot_raw_cost - v_tot_sorting_cost);

  -- 4. Packaging Materials Base Cost (1040 - بدون الهالك)
  v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
  v_tot_pkg_drawn := 0;

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    DECLARE
      v_m_el JSONB;
    BEGIN
      FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials') LOOP
        v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE(
          (v_m_el->>'total')::numeric,
          (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) *
           COALESCE((v_m_el->>'unit_cost')::numeric, 0))
        );
      END LOOP;
    END;
  END IF;

  IF v_tot_pkg_drawn = 0 THEN
    v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    IF v_mat_waste_pct > 0 THEN
      v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 2);
    END IF;
  END IF;

  -- 5. Packaging Waste Cost (51104 - هالك مواد التعبئة فقط)
  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 2);
  v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;

  -- 6. Additional Cost Items (حساب المورد / المصروفات)
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 7. Total Finished Goods Cost (1031 - إجمالي تكلفة أمر التعبئة الكاملة)
  v_finished_goods_cost := COALESCE(v_order.total_packing_cost, 0);
  IF v_finished_goods_cost = 0 THEN
    v_finished_goods_cost := v_fruit_net_cost + v_tot_waste_cost + v_tot_pkg_consumed + v_tot_cost_items;
  END IF;

  -- ── G. Process Direct Treasury / Bank Payments ──
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

  -- ── H. Resolve COA Accounts (Arabic Names) ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  -- 1031 مخزون الإنتاج التام
  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;

  -- 1030 مخزون المحاصيل
  SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;

  -- 51102 هالك وفاقد المحاصيل
  SELECT id INTO v_crop_waste_acc FROM accounts WHERE account_code = '51102' LIMIT 1;

  -- 1040 مخزون مواد التعبئة والتغليف
  SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

  -- 51104 هالك وفاقد مواد التعبئة والتغليف
  SELECT id INTO v_pkg_waste_acc FROM accounts WHERE account_code = '51104' LIMIT 1;

  -- Clean up previous JE if exists
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
    'قيد أمر تعبئة رقم ' || v_order_num,
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    auth.uid(), now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- ══════════════════════════════════════════════════════════════════════════
  -- JOURNAL ENTRY LINES
  -- ══════════════════════════════════════════════════════════════════════════

  -- ── 1. DR 1031 مخزون الإنتاج التام (إجمالي تكلفة أمر التعبئة) ──
  IF v_finished_goods_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, 'EGP', v_finished_goods_cost,
      'مخزون الإنتاج التام - أمر تعبئة ' || v_order_num || ' (' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_finished_goods_cost;
  END IF;

  -- ── 2. CR 1030 مخزون المحاصيل (تكلفة المحصول فقط بدون الهالك وبدون الفرز) ──
  IF v_fruit_net_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_fruit_net_cost, 'EGP', v_fruit_net_cost,
      'تحويل محاصيل خام - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_fruit_net_cost;
  END IF;

  -- ── 3. CR 51102 هالك وفاقد المحاصيل (هالك المحصول فقط) ──
  IF v_tot_waste_cost > 0 AND v_crop_waste_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_crop_waste_acc, 0, v_tot_waste_cost, 'EGP', v_tot_waste_cost,
      'هالك وفاقد المحاصيل - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_waste_cost;
  END IF;

  -- ── 4. CR 1040 مخزون مواد التعبئة والتغليف (تكلفة مواد التعبئة فقط بدون الهالك) ──
  IF v_tot_pkg_drawn > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_drawn, 'EGP', v_tot_pkg_drawn,
      'سحب واستهلاك مواد تعبئة (أساسي) - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_drawn;
  END IF;

  -- ── 5. CR 51104 هالك وفاقد مواد التعبئة والتغليف (هالك مواد التعبئة فقط) ──
  IF v_tot_pkg_waste > 0 THEN
    DECLARE
      v_waste_target_acc INT := COALESCE(v_pkg_waste_acc, v_pkg_inv_acc);
    BEGIN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_waste_target_acc, 0, v_tot_pkg_waste, 'EGP', v_tot_pkg_waste,
        'هالك وفاقد مواد التعبئة والتغليف - أمر تعبئة ' || v_order_num,
        v_company_id
      );
      v_sum_credit := v_sum_credit + v_tot_pkg_waste;
    END;
  END IF;

  -- ── 6. CR حساب المورد / الخزينة / البنك (بنود التكلفة الإضافية) ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;
    v_supplier_id := NULL;

    IF r_cost.payment_source_type = 'treasury' AND r_cost.payment_source_id IS NOT NULL THEN
      SELECT tb.account_id INTO v_credit_acc FROM public.treasury_balances tb WHERE tb.treasury_id = r_cost.payment_source_id AND tb.currency = r_cost.original_currency LIMIT 1;
      IF v_credit_acc IS NULL THEN v_credit_acc := public.resolve_treasury_account(r_cost.payment_source_id, r_cost.original_currency, v_company_id); END IF;
    ELSIF r_cost.payment_source_type = 'bank' AND r_cost.payment_source_id IS NOT NULL THEN
      SELECT ba.account_id INTO v_credit_acc FROM public.bank_accounts ba WHERE ba.id = r_cost.payment_source_id LIMIT 1;
    END IF;

    IF v_credit_acc IS NULL THEN
      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
        END IF;
      END IF;
    END IF;

    IF v_credit_acc IS NULL THEN
      SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' AND company_id = v_company_id LIMIT 1;
      IF v_credit_acc IS NULL THEN SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' LIMIT 1; END IF;
    END IF;

    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
      'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'),
      v_company_id
    );
    v_sum_credit := v_sum_credit + r_cost.base_amount;

    -- Subledger entry in supplier's original currency
    IF v_supplier_id IS NOT NULL THEN
      INSERT INTO public.ledger_entries (
        entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
      ) VALUES (
        v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
        'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
        'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')',
        now()
      );
      UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
    END IF;
  END LOOP;

  -- ══════════════════════════════════════════════════════════════════════════
  -- VALIDATION: Entry MUST be 100% balanced
  -- ══════════════════════════════════════════════════════════════════════════
  IF ROUND(v_sum_debit, 2) != ROUND(v_sum_credit, 2) THEN
    RAISE EXCEPTION 'فشل تأكيد أمر التعبئة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
  END IF;

  -- Update packing order record
  UPDATE public.packing_orders
  SET status = 'completed',
      journal_entry_id = v_je_id,
      reversal_journal_entry_id = NULL,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'journal_entry_id', v_je_id,
    'finished_goods_cost', v_finished_goods_cost,
    'fruit_net_cost', v_fruit_net_cost,
    'crop_waste_cost', v_tot_waste_cost,
    'packaging_base_cost', v_tot_pkg_drawn,
    'packaging_waste_cost', v_tot_pkg_waste,
    'supplier_costs', v_tot_cost_items,
    'debit', v_sum_debit,
    'credit', v_sum_credit
  );
END;
$func$;

NOTIFY pgrst, 'reload_schema';
