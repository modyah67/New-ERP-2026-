-- Migration 335: Comprehensive Unified Packing Order Accounting, Cancellation, and Price Cascading
-- Date: 2026-08-18

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. rpc_confirm_packing_order
-- ─────────────────────────────────────────────────────────────────────────────
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

  -- Cost components
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

  -- 1. Produce Raw Cost & Sorting
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

  v_tot_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_sortings WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 1030: تكلفة المحصول فقط بره عن الهالك والفرز
  v_fruit_net_cost := GREATEST(0, v_tot_raw_cost - v_tot_sorting_cost);

  -- 2. Produce Waste Cost (51102)
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 3. Packaging Materials Base Cost (1040 - بدون الهالك)
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

  -- 4. Packaging Waste Cost (51104)
  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 2);
  v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;

  -- 5. Additional Cost Items (حساب المورد / المصروفات)
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 6. Total Finished Goods Cost (1031)
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
  -- JOURNAL ENTRY LINES: Pure Direct Decomposition
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

  -- ── 2. CR 1030 مخزون المحاصيل (تكلفة المحصول الصافي بدون الهالك والفرز) ──
  IF v_fruit_net_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_fruit_net_cost, 'EGP', v_fruit_net_cost,
      'تحويل محاصيل خام (صافي) - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_fruit_net_cost;
  END IF;

  -- ── 3. CR 51102 هالك وفاقد المحاصيل (هالك المحاصيل فقط) ──
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

  -- ── 4. CR 1040 مخزون مواد التعبئة والتغليف (مواد التعبئة فقط بدون الهالك) ──
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


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. rpc_cancel_packing_order
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(
  p_packing_order_id BIGINT
)
RETURNS JSON
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
  v_sum_debit       NUMERIC := 0;
  v_sum_credit      NUMERIC := 0;
  r_cost            RECORD;
  v_supplier_id     UUID;
  v_supp_str        TEXT;
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

  -- ── 2. Create Reversing Journal Entry ──
  v_je_id := v_order.journal_entry_id;
  IF v_je_id IS NOT NULL THEN
    SELECT company_id INTO v_company_id FROM public.journal_entries WHERE id = v_je_id;
    IF v_company_id IS NULL THEN
      SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
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

    -- Reverse every ledger line symmetrically
    FOR r_ale IN
      SELECT * FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id
    LOOP
      IF COALESCE(r_ale.debit, 0) > 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency,
          amount_in_base_currency, description, company_id
        ) VALUES (
          v_rev_je_id, r_ale.account_id, 0, r_ale.debit,
          COALESCE(r_ale.currency, 'EGP'),
          COALESCE(r_ale.amount_in_base_currency, r_ale.debit),
          'عكس: ' || COALESCE(r_ale.description, ''),
          v_company_id
        );
        v_sum_credit := v_sum_credit + COALESCE(r_ale.amount_in_base_currency, r_ale.debit);
      ELSIF COALESCE(r_ale.credit, 0) > 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency,
          amount_in_base_currency, description, company_id
        ) VALUES (
          v_rev_je_id, r_ale.account_id, r_ale.credit, 0,
          COALESCE(r_ale.currency, 'EGP'),
          COALESCE(r_ale.amount_in_base_currency, r_ale.credit),
          'عكس: ' || COALESCE(r_ale.description, ''),
          v_company_id
        );
        v_sum_debit := v_sum_debit + COALESCE(r_ale.amount_in_base_currency, r_ale.credit);
      END IF;
    END LOOP;

    -- Symmetrical balance check
    IF ABS(ROUND(v_sum_debit, 2) - ROUND(v_sum_credit, 2)) > 0.01 THEN
      RAISE EXCEPTION 'قيد عكس أمر التعبئة غير متوازن: مدين=% دائن=%', ROUND(v_sum_debit, 2), ROUND(v_sum_credit, 2);
    END IF;

    UPDATE public.journal_entries
    SET description = COALESCE(description, '') || ' [تم عكسه بالقيد #' || v_rev_je_id::text || ']'
    WHERE id = v_je_id;
  END IF;

  -- ── 3. Reverse Supplier Subledger Entries ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    IF r_cost.currency_snapshot IS NOT NULL THEN
      v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        v_supplier_id := v_supp_str::uuid;
        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
          'debit', p_packing_order_id, 'packing_cost_cancellation', p_packing_order_id::text,
          'إلغاء بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ')',
          now()
        );
        UPDATE public.suppliers
        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - r_cost.base_amount)
        WHERE id = v_supplier_id;
      END IF;
    END IF;
  END LOOP;

  -- ── 4. Restore Stock in Warehouse ──
  v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);

  IF v_notes ? 'fruit_allocation' THEN
    WITH restored_fruits AS (
      SELECT
        (el->>'batch_id')::bigint AS batch_id,
        COALESCE((el->>'quantity')::numeric, (el->>'used_qty')::numeric, 0) AS quantity
      FROM jsonb_array_elements(
        CASE WHEN jsonb_typeof(v_notes->'fruit_allocation') = 'array' THEN v_notes->'fruit_allocation' ELSE jsonb_build_array(v_notes->'fruit_allocation') END
      ) el
      WHERE COALESCE((el->>'quantity')::numeric, (el->>'used_qty')::numeric, 0) > 0
        AND NULLIF(el->>'batch_id', '') IS NOT NULL
    )
    UPDATE public.station_product_batches b
    SET remaining_quantity = b.remaining_quantity + u.quantity
    FROM restored_fruits u
    WHERE b.id = u.batch_id;
  END IF;

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    WITH restored_materials AS (
      SELECT
        (el->>'batch_id')::bigint AS batch_id,
        COALESCE((el->>'used_qty')::numeric, (el->>'quantity')::numeric, 0) AS used_qty
      FROM jsonb_array_elements(v_notes->'materials') el
      WHERE COALESCE((el->>'used_qty')::numeric, (el->>'quantity')::numeric, 0) > 0
        AND NULLIF(el->>'batch_id', '') IS NOT NULL
    )
    UPDATE public.station_product_batches b
    SET remaining_quantity = b.remaining_quantity + u.used_qty
    FROM restored_materials u
    WHERE b.id = u.batch_id;
  END IF;

  -- Sync station_products
  IF v_station_id IS NOT NULL THEN
    UPDATE public.station_products sp
    SET quantity = COALESCE((
      SELECT SUM(remaining_quantity)
      FROM public.station_product_batches spb
      WHERE spb.station_id = v_station_id
        AND (spb.product_name = sp.product_name OR (spb.product_code IS NOT NULL AND spb.product_code != '' AND spb.product_code = sp.product_code))
    ), 0),
    updated_at = now()
    WHERE sp.station_id = v_station_id;
  END IF;

  -- Update packing order status
  UPDATE public.packing_orders
  SET status = 'cancelled',
      reversal_journal_entry_id = v_rev_je_id,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'reversal_journal_entry_id', v_rev_je_id
  );
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. rpc_refresh_packing_order_prices
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_refresh_packing_order_prices(
    p_order_id BIGINT
)
RETURNS JSONB
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
    v_unit_cost NUMERIC;

    -- Recalculated cost components
    v_new_raw_fruit_cost NUMERIC := 0;
    v_fruit_unit_cost NUMERIC := 0;
    v_waste_weight NUMERIC := 0;
    v_sorted_weight NUMERIC := 0;
    v_new_crop_waste NUMERIC := 0;
    v_new_sorting_cost NUMERIC := 0;
    v_new_fruit_net NUMERIC := 0;

    v_new_material_cost NUMERIC := 0;
    v_mat_waste_pct NUMERIC := 0;
    v_new_mat_waste NUMERIC := 0;
    v_other_cost_base NUMERIC := 0;
    v_new_total_cost NUMERIC := 0;
    v_packing_cost_per_carton NUMERIC := 0;

    -- Account resolution
    v_company_id UUID;
    v_finished_inv_acc INT;
    v_raw_inv_acc INT;
    v_crop_waste_acc INT;
    v_pkg_inv_acc INT;
    v_pkg_waste_acc INT;
    v_credit_acc INT;
    v_supp_leaf_acc INT;
    r_cost RECORD;
    v_supplier_id UUID;
    v_supp_str TEXT;
BEGIN
    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

    -- A. Refresh Fruit Allocation Prices
    v_fruit_allocation := v_notes -> 'fruit_allocation';
    IF jsonb_typeof(v_fruit_allocation) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_fruit_allocation) LOOP
            SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            
            IF FOUND THEN
                v_unit_cost := COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1);
                v_new_raw_fruit_cost := v_new_raw_fruit_cost + (COALESCE((v_elem->>'quantity')::numeric, 0) * v_unit_cost);
                v_fruit_unit_cost := v_unit_cost;
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(
                    jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_unit_cost))
                );
            ELSE
                v_new_raw_fruit_cost := v_new_raw_fruit_cost + COALESCE((v_elem->>'fruit_cost')::numeric, 0);
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(v_fruit_allocation) = 'object' THEN
        SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex
        FROM station_product_batches WHERE id = (v_fruit_allocation->>'batch_id')::bigint;
        
        IF FOUND THEN
            v_unit_cost := COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1);
            v_new_raw_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * v_unit_cost;
            v_fruit_unit_cost := v_unit_cost;
            v_updated_fruit_allocations := jsonb_set(v_fruit_allocation, '{unit_cost}', to_jsonb(v_unit_cost));
        ELSE
            v_new_raw_fruit_cost := COALESCE((v_fruit_allocation->>'fruit_cost')::numeric, 0);
            v_updated_fruit_allocations := v_fruit_allocation;
        END IF;
    END IF;

    -- B. Refresh Materials Prices
    v_materials := v_notes -> 'materials';
    IF jsonb_typeof(v_materials) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
            SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            
            IF FOUND THEN
                v_unit_cost := COALESCE(v_batch_price, 0) * COALESCE(NULLIF(v_batch_ex, 0), 1);
                v_new_material_cost := v_new_material_cost + (COALESCE((v_elem->>'used_qty')::numeric, (v_elem->>'quantity')::numeric, 0) * v_unit_cost);
                v_elem := jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_unit_cost));
                v_elem := jsonb_set(v_elem, '{total}', to_jsonb(COALESCE((v_elem->>'used_qty')::numeric, (v_elem->>'quantity')::numeric, 0) * v_unit_cost));
                v_updated_materials := v_updated_materials || jsonb_build_array(v_elem);
            ELSE
                v_new_material_cost := v_new_material_cost + COALESCE((v_elem->>'total')::numeric, 0);
                v_updated_materials := v_updated_materials || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    END IF;

    -- C. Recalculate Weights & Fruit Components
    v_waste_weight := COALESCE((v_notes->>'waste_weight')::numeric, 0);
    v_sorted_weight := COALESCE((v_notes->>'sorted_weight')::numeric, 0);
    
    IF v_fruit_unit_cost > 0 THEN
        v_new_crop_waste := ROUND(v_waste_weight * v_fruit_unit_cost, 2);
        v_new_sorting_cost := ROUND(v_sorted_weight * v_fruit_unit_cost, 2);
        v_notes := jsonb_set(v_notes, '{product_cost_per_kg}', to_jsonb(v_fruit_unit_cost));
        v_notes := jsonb_set(v_notes, '{waste_cost}', to_jsonb(v_new_crop_waste));
        v_notes := jsonb_set(v_notes, '{sorting_cost}', to_jsonb(v_new_sorting_cost));
    ELSE
        v_new_crop_waste := COALESCE((v_notes->>'waste_cost')::numeric, 0);
        v_new_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
    END IF;

    v_new_fruit_net := GREATEST(0, v_new_raw_fruit_cost - v_new_sorting_cost);

    -- D. Material Waste
    v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
    v_new_mat_waste := ROUND(v_new_material_cost * (v_mat_waste_pct / 100.0), 2);

    -- E. Other Costs
    v_other_cost_base := 0;
    FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_order_id LOOP
        v_other_cost_base := v_other_cost_base + COALESCE(r_cost.base_amount, 0);
    END LOOP;
    IF v_other_cost_base = 0 THEN
        v_other_cost_base := COALESCE(v_order.other_cost_base, 0);
    END IF;

    -- F. Total Cost
    v_new_total_cost := v_new_fruit_net + v_new_crop_waste + v_new_material_cost + v_new_mat_waste + v_other_cost_base;

    IF COALESCE(v_order.carton_count, 0) > 0 THEN
        v_packing_cost_per_carton := ROUND(v_new_total_cost / v_order.carton_count, 2);
    END IF;

    IF jsonb_typeof(v_fruit_allocation) = 'array' OR jsonb_typeof(v_fruit_allocation) = 'object' THEN
        v_notes := jsonb_set(v_notes, '{fruit_allocation}', v_updated_fruit_allocations);
    END IF;
    IF jsonb_typeof(v_materials) = 'array' THEN
        v_notes := jsonb_set(v_notes, '{materials}', v_updated_materials);
    END IF;

    -- G. Update Packing Order Record
    UPDATE public.packing_orders
    SET 
        fruit_cost_base = v_new_raw_fruit_cost,
        fruit_cost_allocated = v_new_raw_fruit_cost,
        material_cost_base = v_new_material_cost,
        actual_material_cost = v_new_material_cost,
        estimated_material_cost = v_new_material_cost,
        total_packing_cost = v_new_total_cost,
        packing_cost_per_carton = v_packing_cost_per_carton,
        notes = v_notes::text,
        needs_price_refresh = false,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- H. Update Journal Entry Lines If Confirmed
    IF v_order.status = 'completed' AND v_order.journal_entry_id IS NOT NULL THEN
        SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
        IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

        SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
        IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;

        SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
        SELECT id INTO v_crop_waste_acc FROM accounts WHERE account_code = '51102' LIMIT 1;
        SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
        IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;
        SELECT id INTO v_pkg_waste_acc FROM accounts WHERE account_code = '51104' LIMIT 1;

        -- Clear old lines and insert updated lines
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;

        -- 1. DR 1031 مخزون الإنتاج التام
        IF v_new_total_cost > 0 THEN
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_order.journal_entry_id, v_finished_inv_acc, v_new_total_cost, 0, 'EGP', v_new_total_cost,
                'مخزون الإنتاج التام - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text) || ' (' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',
                v_company_id
            );
        END IF;

        -- 2. CR 1030 مخزون المحاصيل
        IF v_new_fruit_net > 0 THEN
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_order.journal_entry_id, v_raw_inv_acc, 0, v_new_fruit_net, 'EGP', v_new_fruit_net,
                'تحويل محاصيل خام (صافي) - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text),
                v_company_id
            );
        END IF;

        -- 3. CR 51102 هالك وفاقد المحاصيل
        IF v_new_crop_waste > 0 AND v_crop_waste_acc IS NOT NULL THEN
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_order.journal_entry_id, v_crop_waste_acc, 0, v_new_crop_waste, 'EGP', v_new_crop_waste,
                'هالك وفاقد المحاصيل - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text),
                v_company_id
            );
        END IF;

        -- 4. CR 1040 مخزون مواد التعبئة والتغليف
        IF v_new_material_cost > 0 THEN
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_order.journal_entry_id, v_pkg_inv_acc, 0, v_new_material_cost, 'EGP', v_new_material_cost,
                'سحب واستهلاك مواد تعبئة (أساسي) - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text),
                v_company_id
            );
        END IF;

        -- 5. CR 51104 هالك وفاقد مواد التعبئة والتغليف
        IF v_new_mat_waste > 0 THEN
            DECLARE
                v_target_acc INT := COALESCE(v_pkg_waste_acc, v_pkg_inv_acc);
            BEGIN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_order.journal_entry_id, v_target_acc, 0, v_new_mat_waste, 'EGP', v_new_mat_waste,
                    'هالك وفاقد مواد التعبئة والتغليف - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text),
                    v_company_id
                );
            END;
        END IF;

        -- 6. CR حساب المورد / المصروفات الإضافية
        FOR r_cost IN
            SELECT * FROM public.packing_order_cost_items
            WHERE packing_order_id = p_order_id AND COALESCE(base_amount, 0) > 0
        LOOP
            v_credit_acc := NULL;
            IF r_cost.currency_snapshot IS NOT NULL THEN
                v_supp_str := r_cost.currency_snapshot->>'supplier_id';
                IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
                    v_supplier_id := v_supp_str::uuid;
                    SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
                    IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
                END IF;
            END IF;

            IF v_credit_acc IS NULL THEN
                SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' AND company_id = v_company_id LIMIT 1;
                IF v_credit_acc IS NULL THEN SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' LIMIT 1; END IF;
            END IF;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_order.journal_entry_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
                'مصروفات أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text) || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'),
                v_company_id
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'new_total_cost', v_new_total_cost,
        'fruit_cost', v_new_fruit_net,
        'material_cost', v_new_material_cost
    );
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. rpc_edit_purchase_item_price
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_edit_purchase_item_price(
  p_purchase_id TEXT,
  p_item_id TEXT,
  p_new_price NUMERIC,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
  v_purchase RECORD;
  v_old_total NUMERIC;
  v_new_item_total NUMERIC;
  v_delta NUMERIC;
  v_product_code TEXT;
  v_product_name TEXT;
  v_raw_material_id UUID;
  v_batch_record RECORD;
  r_po RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  SELECT * INTO v_item FROM purchase_invoice_items WHERE id::TEXT = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'صنف المشتريات غير موجود'; END IF;

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة المشتريات غير موجودة'; END IF;

  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_raw_material_id := v_item.raw_material_id;

  -- 1. Update purchase invoice item
  UPDATE purchase_invoice_items
  SET unit_cost = p_new_price, total_cost = v_new_item_total
  WHERE id::TEXT = p_item_id;

  -- 2. Update purchase invoice totals
  UPDATE purchase_invoices
  SET subtotal = COALESCE(subtotal, 0) + v_delta,
      total_amount = COALESCE(total_amount, 0) + v_delta,
      remaining_amount = COALESCE(remaining_amount, 0) + v_delta,
      updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  -- 3. Update stock_batches
  UPDATE stock_batches
  SET purchase_cost = p_new_price, average_cost = p_new_price, updated_at = now()
  WHERE purchase_invoice_id::TEXT = p_purchase_id AND product_id::TEXT = v_raw_material_id::TEXT;

  -- 4. Get product code and name for station_product_batches
  SELECT code, name INTO v_product_code, v_product_name FROM raw_materials WHERE id = v_raw_material_id;

  -- 5. Update station_product_batches & refresh packing orders
  FOR v_batch_record IN 
      SELECT id FROM station_product_batches 
      WHERE source_type = 'purchase'
        AND purchase_invoice_id::TEXT = p_purchase_id
        AND (
          (v_product_code IS NOT NULL AND v_product_code != '' AND product_code = v_product_code)
          OR (product_name = COALESCE(v_product_name, '') || ' (مادة تعبئة)')
          OR (product_code = '' AND COALESCE(v_product_code, '') = '')
        )
  LOOP
      UPDATE station_product_batches SET unit_cost = p_new_price WHERE id = v_batch_record.id;

      -- Cascade update immediately to all affected packing orders
      FOR r_po IN
          SELECT DISTINCT po.id FROM packing_orders po
          WHERE po.notes IS NOT NULL AND po.notes != '' AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(
                  CASE 
                      WHEN jsonb_typeof(po.notes::jsonb -> 'materials') = 'object' THEN jsonb_build_array(po.notes::jsonb -> 'materials')
                      WHEN jsonb_typeof(po.notes::jsonb -> 'materials') = 'array' THEN po.notes::jsonb -> 'materials'
                      ELSE '[]'::jsonb 
                  END
              ) AS elem
              WHERE (elem->>'batch_id')::bigint = v_batch_record.id
          )
      LOOP
          PERFORM public.rpc_refresh_packing_order_prices(r_po.id);
      END LOOP;
  END LOOP;

  -- 6. Update supplier balance
  IF v_purchase.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta
    WHERE id = v_purchase.supplier_id;
  END IF;

  NOTIFY pgrst, 'reload_schema';
  RETURN jsonb_build_object('success', true, 'delta', v_delta);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. rpc_edit_lot_price
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_edit_lot_price(
    p_lot_id BIGINT,
    p_new_price NUMERIC,
    p_exchange_rate NUMERIC,
    p_currency TEXT,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_lot RECORD;
    v_new_total_cost NUMERIC;
    v_old_total_cost NUMERIC;
    v_effective_cost NUMERIC;
    v_total_graded NUMERIC := 0;
    v_grading RECORD;
    v_net_wt NUMERIC;
    v_new_fruit_cost_per_kg NUMERIC;
    v_batch_record RECORD;
    r_po RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'غير مصرح لك بتعديل سعر المحصول'; END IF;

    SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
    IF NOT FOUND THEN RAISE EXCEPTION 'رقم المحصول غير موجود (id=%)', p_lot_id; END IF;

    v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
    v_net_wt := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

    IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
      v_new_total_cost := COALESCE(v_lot.carton_count, 0) * p_new_price;
    ELSE
      v_new_total_cost := COALESCE(v_lot.gross_weight_kg, 0) * p_new_price;
    END IF;

    v_new_fruit_cost_per_kg := CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END;

    UPDATE lot_receipts
    SET price_per_carton = CASE WHEN COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN p_new_price ELSE price_per_carton END,
        fruit_cost_per_kg = v_new_fruit_cost_per_kg,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;

    IF v_lot.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(p_lot_id, 'UPDATE');
    END IF;

    SELECT COALESCE(SUM(weight_kg), 0) INTO v_total_graded FROM lot_grading_results WHERE lot_id = p_lot_id;
    IF v_total_graded > 0 THEN
      v_effective_cost := v_new_total_cost / v_total_graded;
      FOR v_grading IN (SELECT stock_batch_id FROM lot_grading_results WHERE lot_id = p_lot_id AND stock_batch_id IS NOT NULL) LOOP
        UPDATE stock_batches
        SET purchase_cost = v_effective_cost, average_cost = v_effective_cost
        WHERE id = v_grading.stock_batch_id;
      END LOOP;
    END IF;

    FOR v_batch_record IN 
        SELECT id FROM station_product_batches 
        WHERE source_type = 'lot_receipt' AND (product_code = v_lot.lot_number OR lot_id = p_lot_id)
    LOOP
        UPDATE station_product_batches
        SET unit_cost = v_new_fruit_cost_per_kg,
            exchange_rate = p_exchange_rate,
            currency = p_currency
        WHERE id = v_batch_record.id;
        
        -- Cascade update immediately to all affected packing orders
        FOR r_po IN
            SELECT DISTINCT po.id FROM packing_orders po
            WHERE po.notes IS NOT NULL AND po.notes != '' AND EXISTS (
                SELECT 1 FROM jsonb_array_elements(
                    CASE 
                        WHEN jsonb_typeof(po.notes::jsonb -> 'fruit_allocation') = 'object' THEN jsonb_build_array(po.notes::jsonb -> 'fruit_allocation')
                        WHEN jsonb_typeof(po.notes::jsonb -> 'fruit_allocation') = 'array' THEN po.notes::jsonb -> 'fruit_allocation'
                        ELSE '[]'::jsonb 
                    END
                ) AS elem
                WHERE (elem->>'batch_id')::bigint = v_batch_record.id
            )
        LOOP
            PERFORM public.rpc_refresh_packing_order_prices(r_po.id);
        END LOOP;
    END LOOP;

    NOTIFY pgrst, 'reload_schema';
    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_packing_order(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_refresh_packing_order_prices(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;
