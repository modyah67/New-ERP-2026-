-- ============================================================================
-- Migration 359: Add Clearing Entries for Waste & Cost Item Accounts
-- ============================================================================
-- Adds DR/CR clearing entries for:
--   51102 (هالك المحاصيل) - Crop Waste
--   51104 (هالك مواد التعبئة) - Packaging Waste
--   51101 (بنود التكلفة) - Cost Items
-- These are zero-net (DR + CR = 0) entries that appear in the ledger
-- to document the waste/cost allocation before absorption into 1031.
--
-- rpc_cancel_packing_order does NOT need changes because it reverses
-- ALL account_ledger_entries from the original JE automatically.
-- ============================================================================

-- 1. Update rpc_confirm_packing_order
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(p_packing_order_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
  v_sorting_inv_acc INT;
  v_pkg_inv_acc INT;
  v_waste_acc INT;        -- 51102
  v_pkg_waste_acc INT;    -- 51104
  v_cost_item_acc INT;    -- 51101
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
  v_posted_cost_items NUMERIC := 0;
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

  BEGIN
    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_notes) = 'string' THEN
      v_notes := (v_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_notes := '{}'::jsonb;
  END;

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
          'none',
          NULL,
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

  -- 2. Produce Waste Cost
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- Net Fruit Cost (Good Fruit entering product)
  v_fruit_net_cost := GREATEST(0, v_tot_raw_cost - v_tot_sorting_cost - v_tot_waste_cost);

  -- 3. Packaging Materials Base Cost (1040) & Waste
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

  -- 4. Packaging Waste Cost
  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 2);
  v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;

  -- 5. Additional Cost Items
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
    v_finished_goods_cost := v_fruit_net_cost + v_tot_waste_cost + v_tot_pkg_drawn + v_tot_pkg_waste + v_tot_cost_items;
  END IF;

  -- ── G. Resolve COA Accounts ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc := public.resolve_gl_account('1031', v_company_id);
  v_sorting_inv_acc  := public.resolve_gl_account('1032', v_company_id);
  v_raw_inv_acc      := public.resolve_gl_account('1030', v_company_id);
  v_pkg_inv_acc      := public.resolve_gl_account('1040', v_company_id);
  v_waste_acc        := public.resolve_gl_account('51102', v_company_id);
  v_pkg_waste_acc    := public.resolve_gl_account('51104', v_company_id);
  v_cost_item_acc    := public.resolve_gl_account('51101', v_company_id);

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
  IF v_entry_num IS NULL OR v_entry_num = '' THEN
    v_entry_num := 'PO-JE-' || LPAD(v_je_id::text, 5, '0');
  END IF;
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- ══════════════════════════════════════════════════════════════════════════
  -- H. JOURNAL ENTRY LINES
  -- ══════════════════════════════════════════════════════════════════════════

  -- ── 1. DR 1031: تكلفة المحصول الخام الصافي ──
  IF v_fruit_net_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_fruit_net_cost, 0, 'EGP', v_fruit_net_cost,
      'تكلفة المحصول الخام الصافي الداخل في الإنتاج - أمر تعبئة ' || v_order_num || ' (' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_fruit_net_cost;
  END IF;

  -- ── 2. DR 1031: هالك المحاصيل ──
  IF v_tot_waste_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_waste_cost, 0, 'EGP', v_tot_waste_cost,
      'تحميل هالك وفاقد المحاصيل على الإنتاج التام - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_waste_cost;
  END IF;

  -- ── 3. DR 1031: مواد التعبئة الأساسية ──
  IF v_tot_pkg_drawn > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_pkg_drawn, 0, 'EGP', v_tot_pkg_drawn,
      'تكلفة مواد التعبئة والتغليف الأساسية - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_pkg_drawn;
  END IF;

  -- ── 4. DR 1031: هالك مواد التعبئة ──
  IF v_tot_pkg_waste > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_pkg_waste, 0, 'EGP', v_tot_pkg_waste,
      'تحميل هالك وفاقد مواد التعبئة على الإنتاج التام - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_pkg_waste;
  END IF;

  -- ── 5. DR 1031: بنود التكلفة الإضافية ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, r_cost.base_amount, 0, 'EGP', r_cost.base_amount,
      'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'),
      v_company_id
    );
    v_sum_debit := v_sum_debit + r_cost.base_amount;
  END LOOP;

  -- Fallback for other_cost_base without cost_items rows
  IF v_tot_cost_items > 0 AND NOT EXISTS (SELECT 1 FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0) THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'مصروفات إضافية أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_cost_items;
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  -- CLEARING ENTRIES (مدين ثم دائن — صافي = صفر — للتوثيق في دفتر الأستاذ)
  -- ══════════════════════════════════════════════════════════════════════════

  -- ── DR/CR 51102: هالك المحاصيل (Clearing) ──
  IF v_tot_waste_cost > 0 AND v_waste_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_waste_acc, v_tot_waste_cost, 0, 'EGP', v_tot_waste_cost,
      'إثبات هالك محاصيل - أمر تعبئة ' || v_order_num, v_company_id
    );
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_waste_acc, 0, v_tot_waste_cost, 'EGP', v_tot_waste_cost,
      'تحميل هالك محاصيل على الإنتاج التام - أمر تعبئة ' || v_order_num, v_company_id
    );
  END IF;

  -- ── DR/CR 51104: هالك مواد التعبئة (Clearing) ──
  IF v_tot_pkg_waste > 0 AND v_pkg_waste_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_waste_acc, v_tot_pkg_waste, 0, 'EGP', v_tot_pkg_waste,
      'إثبات هالك مواد تعبئة - أمر تعبئة ' || v_order_num, v_company_id
    );
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_waste_acc, 0, v_tot_pkg_waste, 'EGP', v_tot_pkg_waste,
      'تحميل هالك مواد تعبئة على الإنتاج التام - أمر تعبئة ' || v_order_num, v_company_id
    );
  END IF;

  -- ── DR/CR 51101: بنود التكلفة الإضافية (Clearing per cost item) ──
  IF v_cost_item_acc IS NOT NULL THEN
    FOR r_cost IN
      SELECT * FROM public.packing_order_cost_items
      WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
    LOOP
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_cost_item_acc, r_cost.base_amount, 0, 'EGP', r_cost.base_amount,
        'إثبات بند تكلفة: ' || COALESCE(r_cost.name, '') || ' - أمر تعبئة ' || v_order_num, v_company_id
      );
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_cost_item_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
        'تحميل بند تكلفة على الإنتاج التام: ' || COALESCE(r_cost.name, '') || ' - أمر تعبئة ' || v_order_num, v_company_id
      );
    END LOOP;
  END IF;

  -- Fallback clearing for other_cost_base without individual rows
  IF v_tot_cost_items > 0 AND v_cost_item_acc IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0) THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_cost_item_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'إثبات بنود تكلفة إضافية - أمر تعبئة ' || v_order_num, v_company_id
    );
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_cost_item_acc, 0, v_tot_cost_items, 'EGP', v_tot_cost_items,
      'تحميل بنود تكلفة على الإنتاج التام - أمر تعبئة ' || v_order_num, v_company_id
    );
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  -- DEBIT & CREDIT ENTRIES (الأصول والموردين)
  -- ══════════════════════════════════════════════════════════════════════════

  -- ── 6. DR 1032: مخزون الفرز ──
  IF v_tot_sorting_cost > 0 AND v_sorting_inv_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, 'EGP', v_tot_sorting_cost,
      'مخزون الفرز - أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_sorting_cost;
  END IF;

  -- ── 7. CR 1030: مخزون المحاصيل ──
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,
      'صرف محصول خام بالكامل (إجمالي شامل الهالك والفرز) - أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- ── 8. CR 1040: مخزون مواد التعبئة ──
  IF v_tot_pkg_consumed > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_consumed, 'EGP', v_tot_pkg_consumed,
      'صرف مواد تعبئة وتغليف بالكامل (إجمالي شامل الهالك) - أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_consumed;
  END IF;

  -- ── 9. CR حسابات الموردين ──
  v_posted_cost_items := 0;
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;
    v_supplier_id := NULL;

    IF r_cost.currency_snapshot IS NOT NULL THEN
      v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        v_supplier_id := v_supp_str::uuid;
        SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
        IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
      END IF;
    END IF;

    IF v_credit_acc IS NULL THEN
      v_credit_acc := public.resolve_gl_account('2000', v_company_id);
    END IF;

    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
      'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
    );
    v_sum_credit := v_sum_credit + r_cost.base_amount;
    v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

    IF v_supplier_id IS NOT NULL THEN
      INSERT INTO public.ledger_entries (
        entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
      ) VALUES (
        v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
        'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
        'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
      );
      UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
    END IF;
  END LOOP;

  -- Fallback credit
  IF v_tot_cost_items > v_posted_cost_items THEN
    v_credit_acc := public.resolve_gl_account('2000', v_company_id);
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_credit_acc, 0, (v_tot_cost_items - v_posted_cost_items), 'EGP', (v_tot_cost_items - v_posted_cost_items),
      'مصروفات إضافية أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_credit := v_sum_credit + (v_tot_cost_items - v_posted_cost_items);
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  -- VALIDATION
  -- ══════════════════════════════════════════════════════════════════════════
  IF ROUND(v_sum_debit, 2) != ROUND(v_sum_credit, 2) THEN
    RAISE EXCEPTION 'فشل تأكيد أمر التعبئة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
  END IF;

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
    'sorting_inventory_cost', v_tot_sorting_cost,
    'crop_waste_cost', v_tot_waste_cost,
    'packaging_base_cost', v_tot_pkg_drawn,
    'packaging_waste_cost', v_tot_pkg_waste,
    'packaging_total_cost', v_tot_pkg_consumed,
    'supplier_costs', v_tot_cost_items,
    'debit', v_sum_debit,
    'credit', v_sum_credit
  );
END;
$function$;


-- ============================================================================
-- 2. Update rpc_refresh_packing_order_prices (same clearing logic)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_refresh_packing_order_prices(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
    v_qty NUMERIC;
    v_item_total NUMERIC;

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
    v_tot_pkg_consumed NUMERIC := 0;
    v_other_cost_base NUMERIC := 0;
    v_new_total_cost NUMERIC := 0;
    v_packing_cost_per_carton NUMERIC := 0;

    v_company_id UUID;
    v_finished_inv_acc INT;
    v_raw_inv_acc INT;
    v_sorting_inv_acc INT;
    v_pkg_inv_acc INT;
    v_waste_acc INT;
    v_pkg_waste_acc INT;
    v_cost_item_acc INT;
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
    IF jsonb_typeof(v_notes) = 'string' THEN
        BEGIN v_notes := (v_notes #>> '{}')::jsonb; EXCEPTION WHEN OTHERS THEN v_notes := '{}'::jsonb; END;
    END IF;

    -- A. Refresh Fruit Allocation Prices
    v_fruit_allocation := v_notes -> 'fruit_allocation';
    IF jsonb_typeof(v_fruit_allocation) = 'object' THEN
        v_fruit_allocation := jsonb_build_array(v_fruit_allocation);
    END IF;

    IF jsonb_typeof(v_fruit_allocation) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_fruit_allocation) LOOP
            v_unit_cost := NULL;
            v_qty := COALESCE((v_elem->>'quantity')::numeric, (v_elem->>'used_qty')::numeric, 0);

            IF v_elem ? 'batch_id' AND v_elem->>'batch_id' IS NOT NULL AND v_elem->>'batch_id' != '' THEN
                SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex
                FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
                IF FOUND AND v_batch_price IS NOT NULL THEN
                    v_unit_cost := v_batch_price * COALESCE(NULLIF(v_batch_ex, 0), 1);
                END IF;
            END IF;

            IF v_unit_cost IS NULL AND v_elem ? 'lot_id' AND v_elem->>'lot_id' IS NOT NULL AND v_elem->>'lot_id' != '' THEN
                SELECT unit_price INTO v_unit_cost FROM inventory_lots WHERE id = (v_elem->>'lot_id')::bigint;
            END IF;

            IF v_unit_cost IS NULL THEN
                v_unit_cost := COALESCE((v_elem->>'unit_cost')::numeric, (v_notes->>'product_cost_per_kg')::numeric, 0);
            END IF;

            v_item_total := ROUND(v_qty * v_unit_cost, 2);
            v_new_raw_fruit_cost := v_new_raw_fruit_cost + v_item_total;
            v_fruit_unit_cost := v_unit_cost;

            v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(
                jsonb_set(jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_unit_cost)), '{total}', to_jsonb(v_item_total))
            );
        END LOOP;
    ELSE
        v_new_raw_fruit_cost := COALESCE(v_order.fruit_cost_base, 0);
        v_fruit_unit_cost := COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0);
    END IF;

    -- B. Refresh Materials Prices
    v_materials := v_notes -> 'materials';
    IF jsonb_typeof(v_materials) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
            v_unit_cost := NULL;
            v_qty := COALESCE((v_elem->>'used_qty')::numeric, (v_elem->>'quantity')::numeric, 0);

            IF v_elem ? 'batch_id' AND v_elem->>'batch_id' IS NOT NULL AND v_elem->>'batch_id' != '' THEN
                SELECT unit_cost, exchange_rate INTO v_batch_price, v_batch_ex
                FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
                IF FOUND AND v_batch_price IS NOT NULL THEN
                    v_unit_cost := v_batch_price * COALESCE(NULLIF(v_batch_ex, 0), 1);
                END IF;
            END IF;

            IF v_unit_cost IS NULL THEN
                v_unit_cost := COALESCE((v_elem->>'unit_cost')::numeric, 0);
            END IF;

            v_item_total := ROUND(v_qty * v_unit_cost, 2);
            v_new_material_cost := v_new_material_cost + v_item_total;

            v_updated_materials := v_updated_materials || jsonb_build_array(
                jsonb_set(jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_unit_cost)), '{total}', to_jsonb(v_item_total))
            );
        END LOOP;
    ELSE
        v_new_material_cost := COALESCE(v_order.material_cost_base, 0);
    END IF;

    -- C. Recalculate Weights & Fruit Components
    v_waste_weight := COALESCE((v_notes->>'waste_weight')::numeric, 0);
    v_sorted_weight := COALESCE((v_notes->>'sorted_weight')::numeric, 0);

    IF v_fruit_unit_cost > 0 AND (v_waste_weight > 0 OR v_sorted_weight > 0) THEN
        v_new_crop_waste := ROUND(v_waste_weight * v_fruit_unit_cost, 2);
        v_new_sorting_cost := ROUND(v_sorted_weight * v_fruit_unit_cost, 2);
        v_notes := jsonb_set(v_notes, '{product_cost_per_kg}', to_jsonb(v_fruit_unit_cost));
        v_notes := jsonb_set(v_notes, '{waste_cost}', to_jsonb(v_new_crop_waste));
        v_notes := jsonb_set(v_notes, '{sorting_cost}', to_jsonb(v_new_sorting_cost));
    ELSE
        v_new_crop_waste := COALESCE((v_notes->>'waste_cost')::numeric, 0);
        v_new_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
    END IF;

    v_new_fruit_net := GREATEST(0, v_new_raw_fruit_cost - v_new_sorting_cost - v_new_crop_waste);

    -- D. Material Waste
    v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
    v_new_mat_waste := ROUND(v_new_material_cost * (v_mat_waste_pct / 100.0), 2);
    v_tot_pkg_consumed := v_new_material_cost + v_new_mat_waste;

    -- E. Other Costs
    v_other_cost_base := 0;
    FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_order_id LOOP
        v_other_cost_base := v_other_cost_base + COALESCE(r_cost.base_amount, 0);
    END LOOP;
    IF v_other_cost_base = 0 THEN
        v_other_cost_base := COALESCE(v_order.other_cost_base, 0);
    END IF;

    -- F. Total Cost (1031)
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

        v_finished_inv_acc := public.resolve_gl_account('1031', v_company_id);
        v_sorting_inv_acc := public.resolve_gl_account('1032', v_company_id);
        v_raw_inv_acc := public.resolve_gl_account('1030', v_company_id);
        v_pkg_inv_acc := public.resolve_gl_account('1040', v_company_id);
        v_waste_acc := public.resolve_gl_account('51102', v_company_id);
        v_pkg_waste_acc := public.resolve_gl_account('51104', v_company_id);
        v_cost_item_acc := public.resolve_gl_account('51101', v_company_id);

        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;

        -- 1. DR 1031: Net Fruit
        IF v_new_fruit_net > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_finished_inv_acc, v_new_fruit_net, 0, 'EGP', v_new_fruit_net,
                'تكلفة المحصول الخام الصافي - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text) || ' (' || COALESCE(v_order.carton_count, 0) || ' كرتونة)', v_company_id);
        END IF;

        -- 2. DR 1031: Crop Waste
        IF v_new_crop_waste > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_finished_inv_acc, v_new_crop_waste, 0, 'EGP', v_new_crop_waste,
                'تحميل هالك المحاصيل على الإنتاج التام - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        -- 3. DR 1031: Basic Packaging
        IF v_new_material_cost > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_finished_inv_acc, v_new_material_cost, 0, 'EGP', v_new_material_cost,
                'تكلفة مواد التعبئة الأساسية - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        -- 4. DR 1031: Packaging Waste
        IF v_new_mat_waste > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_finished_inv_acc, v_new_mat_waste, 0, 'EGP', v_new_mat_waste,
                'تحميل هالك مواد التعبئة على الإنتاج التام - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        -- 5. DR 1031: Additional Costs
        FOR r_cost IN
            SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_order_id AND COALESCE(base_amount, 0) > 0
        LOOP
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_finished_inv_acc, r_cost.base_amount, 0, 'EGP', r_cost.base_amount,
                'مصروفات أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text) || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id);
        END LOOP;

        -- ═══ CLEARING ENTRIES ═══

        IF v_new_crop_waste > 0 AND v_waste_acc IS NOT NULL THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_waste_acc, v_new_crop_waste, 0, 'EGP', v_new_crop_waste, 'إثبات هالك محاصيل - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_waste_acc, 0, v_new_crop_waste, 'EGP', v_new_crop_waste, 'تحميل هالك محاصيل على الإنتاج التام - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        IF v_new_mat_waste > 0 AND v_pkg_waste_acc IS NOT NULL THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_pkg_waste_acc, v_new_mat_waste, 0, 'EGP', v_new_mat_waste, 'إثبات هالك مواد تعبئة - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_pkg_waste_acc, 0, v_new_mat_waste, 'EGP', v_new_mat_waste, 'تحميل هالك مواد تعبئة على الإنتاج التام - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        IF v_cost_item_acc IS NOT NULL THEN
            FOR r_cost IN
                SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_order_id AND COALESCE(base_amount, 0) > 0
            LOOP
                INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_order.journal_entry_id, v_cost_item_acc, r_cost.base_amount, 0, 'EGP', r_cost.base_amount, 'إثبات بند تكلفة: ' || COALESCE(r_cost.name, '') || ' - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
                INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_order.journal_entry_id, v_cost_item_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount, 'تحميل بند تكلفة على الإنتاج التام: ' || COALESCE(r_cost.name, '') || ' - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
            END LOOP;
        END IF;

        -- ═══ END CLEARING ═══

        -- 6. DR 1032: Sorting
        IF v_new_sorting_cost > 0 AND v_sorting_inv_acc IS NOT NULL THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_sorting_inv_acc, v_new_sorting_cost, 0, 'EGP', v_new_sorting_cost,
                'مخزون الفرز - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        -- 7. CR 1030
        IF v_new_raw_fruit_cost > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_raw_inv_acc, 0, v_new_raw_fruit_cost, 'EGP', v_new_raw_fruit_cost,
                'صرف محصول خام بالكامل - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        -- 8. CR 1040
        IF v_tot_pkg_consumed > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_pkg_inv_acc, 0, v_tot_pkg_consumed, 'EGP', v_tot_pkg_consumed,
                'صرف مواد تعبئة بالكامل - أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text), v_company_id);
        END IF;

        -- 9. CR Suppliers
        FOR r_cost IN
            SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_order_id AND COALESCE(base_amount, 0) > 0
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
                v_credit_acc := public.resolve_gl_account('2000', v_company_id);
            END IF;

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_order.journal_entry_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
                'مصروفات أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text) || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id);
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'new_total_cost', v_new_total_cost,
        'fruit_cost', v_new_fruit_net,
        'material_cost', v_new_material_cost
    );
END;
$function$;
