-- Migration 392: Fix Packing Order JE Timezone

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(p_packing_order_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
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
    RETURN json_build_object('success', false, 'error', 'الأمر تم تأكيده مسبقاً ولا يمكن تكرار التأكيد');
  END IF;

  v_company_id := v_order.company_id;
  IF v_company_id IS NULL THEN
     SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;

  v_order_num := COALESCE(v_order.order_number, v_order.id::text);
  v_station_id := NULLIF(REGEXP_REPLACE(v_order.station_id, '\D', '', 'g'), '')::INT;
  v_packed_at := COALESCE(v_order.packed_at, v_order.created_at, now());

  -- ── B. Identify Accounts ──
  SELECT id INTO v_finished_inv_acc FROM public.accounts WHERE account_code = '1031' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_raw_inv_acc FROM public.accounts WHERE account_code = '1030' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_sorting_inv_acc FROM public.accounts WHERE account_code = '1032' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_pkg_inv_acc FROM public.accounts WHERE account_code = '1033' AND company_id = v_company_id LIMIT 1;
  
  -- The three required DR/CR clearing accounts
  SELECT id INTO v_waste_acc FROM public.accounts WHERE account_code = '51102' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_pkg_waste_acc FROM public.accounts WHERE account_code = '51104' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_cost_item_acc FROM public.accounts WHERE account_code = '51101' AND company_id = v_company_id LIMIT 1;
  
  IF v_finished_inv_acc IS NULL OR v_raw_inv_acc IS NULL OR v_sorting_inv_acc IS NULL OR v_pkg_inv_acc IS NULL OR v_waste_acc IS NULL OR v_pkg_waste_acc IS NULL OR v_cost_item_acc IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'حسابات المخزون أو التشغيل (1030,1031,1032,1033,51101,51102,51104) غير معرفة بشكل صحيح');
  END IF;

  -- ── C. Snapshot Exchange Rates & Compute Local Costs ──
  FOR r_cost IN
    SELECT id, original_amount, exchange_rate, base_amount
    FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
    v_amt_egp := r_cost.base_amount;
    IF v_amt_egp IS NULL OR v_amt_egp = 0 THEN
       v_amt_egp := r_cost.original_amount * r_cost.exchange_rate;
       UPDATE public.packing_order_cost_items SET base_amount = v_amt_egp WHERE id = r_cost.id;
    END IF;
  END LOOP;

  -- ── D. Deduct Raw Crops (1030) ──
  IF v_order.lot_receipts IS NOT NULL AND jsonb_typeof(v_order.lot_receipts) = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_order.lot_receipts) LOOP
      IF v_el ? 'cost_allocations' AND jsonb_typeof(v_el->'cost_allocations') = 'array' THEN
        FOR v_alloc IN SELECT * FROM jsonb_array_elements(v_el->'cost_allocations') LOOP
          v_batch_id := (v_alloc->>'batch_id')::BIGINT;
          v_used_qty := COALESCE((v_alloc->>'used_qty')::NUMERIC, 0);
          IF v_batch_id IS NOT NULL AND v_used_qty > 0 THEN
            SELECT remaining_quantity, product_name INTO v_curr_rem, v_pname
            FROM public.station_product_batches WHERE id = v_batch_id FOR UPDATE;
            
            IF v_curr_rem < v_used_qty THEN
              RETURN json_build_object('success', false, 'error', 'الرصيد لا يكفي للصنف الخام ' || COALESCE(v_pname, ''));
            END IF;
            
            UPDATE public.station_product_batches
            SET remaining_quantity = remaining_quantity - v_used_qty,
                updated_at = now()
            WHERE id = v_batch_id;
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  END IF;

  -- ── E. Deduct Packaging Materials (1033) ──
  IF v_order.packaging_materials IS NOT NULL AND jsonb_typeof(v_order.packaging_materials) = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_order.packaging_materials) LOOP
      v_pcode := v_el->>'product_code';
      v_used_qty := COALESCE((v_el->>'used_qty')::NUMERIC, 0);
      IF v_pcode IS NOT NULL AND v_used_qty > 0 THEN
        v_rem_needed := v_used_qty;
        FOR r_b IN
          SELECT id, remaining_quantity, product_name
          FROM public.station_product_batches
          WHERE station_id = v_station_id AND product_code = v_pcode AND remaining_quantity > 0
          ORDER BY receipt_date ASC, id ASC
          FOR UPDATE
        LOOP
          IF v_rem_needed <= 0 THEN EXIT; END IF;
          v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - v_take, updated_at = now()
          WHERE id = r_b.id;
          v_rem_needed := v_rem_needed - v_take;
        END LOOP;
        IF v_rem_needed > 0 THEN
           RETURN json_build_object('success', false, 'error', 'الرصيد لا يكفي لمادة التعبئة: ' || COALESCE(v_pcode, ''));
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- ── F. Extract Precomputed Costs from Packing Order Lines ──
  SELECT
    COALESCE(SUM(total_raw_cost), 0),
    COALESCE(SUM(total_waste_cost), 0),
    COALESCE(SUM(total_sorting_cost), 0),
    COALESCE(SUM(total_packaging_cost), 0),
    COALESCE(SUM(total_overhead), 0),
    COALESCE(SUM(total_final_cost), 0)
  INTO
    v_tot_raw_cost,
    v_tot_waste_cost,
    v_tot_sorting_cost,
    v_tot_pkg_consumed,
    v_tot_cost_items,
    v_finished_goods_cost
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;

  v_fruit_net_cost := v_tot_raw_cost - v_tot_sorting_cost;

  -- ── G. Compute Packaging Waste ──
  IF v_order.packaging_materials IS NOT NULL AND jsonb_typeof(v_order.packaging_materials) = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_order.packaging_materials) LOOP
      v_used_qty := COALESCE((v_el->>'used_qty')::NUMERIC, 0);
      v_amt_egp := COALESCE((v_el->>'unit_cost')::NUMERIC, 0);
      v_mat_waste_pct := COALESCE((v_el->>'waste_percent')::NUMERIC, 0);
      v_tot_pkg_drawn := v_tot_pkg_drawn + (v_used_qty * v_amt_egp);
      v_tot_pkg_waste := v_tot_pkg_waste + ((v_used_qty * v_amt_egp) * (v_mat_waste_pct / 100.0));
    END LOOP;
  END IF;

  -- ── H. Add Finished Goods (1031) to Inventory ──
  FOR v_lines IN
    SELECT id, product_name, product_code, (carton_count * net_weight_per_carton) AS net_weight, total_final_cost
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id
  LOOP
    IF v_lines.net_weight > 0 THEN
      INSERT INTO public.station_product_batches (
        station_id, product_name, product_code, batch_number,
        initial_quantity, remaining_quantity, unit_cost,
        receipt_date, source_type, source_id, company_id
      ) VALUES (
        v_station_id, v_lines.product_name, v_lines.product_code, v_order_num,
        v_lines.net_weight, v_lines.net_weight, (v_lines.total_final_cost / v_lines.net_weight),
        v_packed_at, 'packing_order', p_packing_order_id::text, v_company_id
      );
    END IF;
  END LOOP;

  -- ── I. Add Sorted By-Products (1032) to Inventory ──
  IF COALESCE(v_order.sorted_weight, 0) > 0 THEN
    INSERT INTO public.station_product_batches (
      station_id, product_name, batch_number,
      initial_quantity, remaining_quantity, unit_cost,
      receipt_date, source_type, source_id, company_id
    ) VALUES (
      v_station_id, 'فرز - أمر ' || v_order_num, v_order_num,
      v_order.sorted_weight, v_order.sorted_weight,
      CASE WHEN v_order.sorted_weight > 0 THEN (v_tot_sorting_cost / v_order.sorted_weight) ELSE 0 END,
      v_packed_at, 'packing_order_sorting', p_packing_order_id::text, v_company_id
    );
  END IF;

  -- ── J. Generate Journal Entry ──
  -- We now use TIMEZONE transformation here for the date
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
    COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),
    'قيد أمر تعبئة رقم ' || v_order_num,
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    p_user_id, now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := 'JE-' || to_char(now(), 'YYMM') || '-' || LPAD(v_je_id::text, 5, '0');
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- 1) Debit: 1031 Finished Goods
  IF v_finished_goods_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES (v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, v_finished_goods_cost, 0, 'تكلفة المنتج التام');
    v_sum_debit := v_sum_debit + v_finished_goods_cost;
  END IF;

  -- 2) Debit: 1032 Sorting Inventory
  IF v_tot_sorting_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES (v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, v_tot_sorting_cost, 0, 'تكلفة الفرز');
    v_sum_debit := v_sum_debit + v_tot_sorting_cost;
  END IF;

  -- 3) Zero-Net Clearing: 51102 Crop Waste
  IF v_tot_waste_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES
      (v_je_id, v_waste_acc, v_tot_waste_cost, 0, v_tot_waste_cost, 0, 'إثبات هالك محصول'),
      (v_je_id, v_waste_acc, 0, v_tot_waste_cost, 0, v_tot_waste_cost, 'إقفال هالك محصول في التام');
    v_sum_debit := v_sum_debit + v_tot_waste_cost;
    v_sum_credit := v_sum_credit + v_tot_waste_cost;
  END IF;

  -- 4) Zero-Net Clearing: 51104 Packaging Waste
  IF v_tot_pkg_waste > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES
      (v_je_id, v_pkg_waste_acc, v_tot_pkg_waste, 0, v_tot_pkg_waste, 0, 'إثبات هالك تعبئة'),
      (v_je_id, v_pkg_waste_acc, 0, v_tot_pkg_waste, 0, v_tot_pkg_waste, 'إقفال هالك تعبئة في التام');
    v_sum_debit := v_sum_debit + v_tot_pkg_waste;
    v_sum_credit := v_sum_credit + v_tot_pkg_waste;
  END IF;

  -- 5) Zero-Net Clearing: 51101 Cost Items Overheads
  IF v_tot_cost_items > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES
      (v_je_id, v_cost_item_acc, v_tot_cost_items, 0, v_tot_cost_items, 0, 'إثبات تكاليف إضافية'),
      (v_je_id, v_cost_item_acc, 0, v_tot_cost_items, 0, v_tot_cost_items, 'إقفال التكاليف الإضافية في التام');
    v_sum_debit := v_sum_debit + v_tot_cost_items;
    v_sum_credit := v_sum_credit + v_tot_cost_items;
  END IF;

  -- 6) Credit: 1030 Raw Crops Consumed
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES (v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 0, v_tot_raw_cost, 'استهلاك محصول خام');
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- 7) Credit: 1033 Packaging Consumed
  IF v_tot_pkg_drawn > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
    VALUES (v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_drawn, 0, v_tot_pkg_drawn, 'استهلاك مواد تعبئة');
    v_sum_credit := v_sum_credit + v_tot_pkg_drawn;
  END IF;

  -- 8) Credit: Suppliers/Treasury for Overheads
  FOR r_cost IN
    SELECT c.supplier_id, c.base_amount, c.name, s.name as supplier_name,
           c.payment_source_type, c.payment_source_id
    FROM public.packing_order_cost_items c
    LEFT JOIN public.suppliers s ON s.id = c.supplier_id
    WHERE c.packing_order_id = p_packing_order_id
  LOOP
    IF r_cost.base_amount > 0 THEN
      IF r_cost.payment_source_type = 'bank' AND r_cost.payment_source_id IS NOT NULL THEN
         SELECT account_id INTO v_credit_acc
         FROM public.company_bank_accounts
         WHERE id = r_cost.payment_source_id::UUID LIMIT 1;
         
         v_supp_str := 'دفع من البنك: ' || COALESCE(r_cost.name, '');
      ELSIF r_cost.payment_source_type = 'treasury' AND r_cost.payment_source_id IS NOT NULL THEN
         SELECT account_id INTO v_credit_acc
         FROM public.company_treasuries
         WHERE id = r_cost.payment_source_id::UUID LIMIT 1;

         v_supp_str := 'دفع من الخزينة: ' || COALESCE(r_cost.name, '');
      ELSE
         v_credit_acc := NULL;
         IF r_cost.supplier_id IS NOT NULL THEN
           SELECT s.account_id INTO v_supp_leaf_acc
           FROM public.suppliers s WHERE s.id = r_cost.supplier_id LIMIT 1;
           
           IF v_supp_leaf_acc IS NOT NULL THEN
              SELECT id INTO v_credit_acc FROM public.accounts WHERE id = v_supp_leaf_acc AND is_leaf = true LIMIT 1;
           END IF;
           
           IF v_credit_acc IS NULL THEN
              SELECT a.id INTO v_credit_acc
              FROM public.accounts a
              WHERE a.company_id = v_company_id
                AND a.is_leaf = true
                AND (a.name ILIKE '%مورد%' || COALESCE(r_cost.supplier_name, '') || '%'
                     OR a.account_name ILIKE '%مورد%' || COALESCE(r_cost.supplier_name, '') || '%')
              LIMIT 1;
           END IF;
         END IF;

         IF v_credit_acc IS NULL THEN
            SELECT id INTO v_credit_acc FROM public.accounts
            WHERE company_id = v_company_id AND account_code LIKE '201%' AND is_leaf = true
            ORDER BY account_code ASC LIMIT 1;
         END IF;

         v_supp_str := 'مستحقات لـ: ' || COALESCE(r_cost.supplier_name, 'مورد متنوع');
      END IF;

      IF v_credit_acc IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, base_debit, base_credit, description)
        VALUES (v_je_id, v_credit_acc, 0, r_cost.base_amount, 0, r_cost.base_amount, v_supp_str);
        v_sum_credit := v_sum_credit + r_cost.base_amount;
      END IF;
    END IF;
  END LOOP;

  -- Verify Balancing
  IF ABS(v_sum_debit - v_sum_credit) > 0.1 THEN
     RAISE EXCEPTION 'فشل تأكيد أمر التعبئة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
  END IF;

  UPDATE public.packing_orders
  SET status = 'completed',
      journal_entry_id = v_je_id,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'journal_entry_id', v_je_id,
    'total_final_cost', v_finished_goods_cost,
    'total_raw_cost', v_tot_raw_cost,
    'total_packaging_cost', v_tot_pkg_consumed,
    'total_overhead', v_tot_cost_items,
    'lines_count', v_n,
    'debit', v_sum_debit,
    'credit', v_sum_credit
  );
END;
$$;

COMMIT;