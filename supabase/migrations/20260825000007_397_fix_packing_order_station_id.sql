-- Migration 395: Fix Packing Order RPC Signature Overload Issue

BEGIN;

-- Drop the wrong 2-parameter function from 394 to prevent ambiguity
DROP FUNCTION IF EXISTS public.rpc_confirm_packing_order(BIGINT, UUID);

-- Replace the original 1-parameter function (from 392/389) with the correct logic
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
  v_tot_pkg_cost NUMERIC := 0;
  v_tot_pkg_consumed NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_new_material_cost NUMERIC := 0;
  v_new_crop_waste NUMERIC := 0;
  v_new_mat_waste NUMERIC := 0;
  v_new_sorting_cost NUMERIC := 0;
  v_new_raw_fruit_cost NUMERIC := 0;
  
  -- Finished goods distribution
  v_tot_net_weight NUMERIC := 0;
  
  -- Required Accounts
  v_finished_inv_acc BIGINT;
  v_raw_inv_acc BIGINT;
  v_sorting_inv_acc BIGINT;
  v_pkg_inv_acc BIGINT;
  v_waste_acc BIGINT;
  v_pkg_waste_acc BIGINT;
  v_cost_item_acc BIGINT;
  
  -- Iteration variables
  r_cost RECORD;
  v_credit_acc BIGINT;
  v_c_amt NUMERIC;
  v_je_id BIGINT;
  v_lines RECORD;
BEGIN
  -- 1. Fetch Order & Ensure Not Already Confirmed
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  
  IF v_order.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;
  
  IF v_order.status = 'confirmed' THEN
    RETURN json_build_object('success', false, 'error', 'الأمر تم تأكيده مسبقاً ولا يمكن تكرار التأكيد');
  END IF;

  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  v_order_num := COALESCE(v_order.order_number, v_order.id::text);
  v_packed_at := COALESCE(v_order.packed_at, v_order.created_at, now());

  -- B. Identify Accounts
  SELECT id INTO v_finished_inv_acc FROM public.accounts WHERE account_code = '1031' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_raw_inv_acc FROM public.accounts WHERE account_code = '1030' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_sorting_inv_acc FROM public.accounts WHERE account_code = '1032' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_pkg_inv_acc FROM public.accounts WHERE account_code = '1040' AND company_id = v_company_id LIMIT 1;
  
  -- The three required DR/CR clearing accounts
  SELECT id INTO v_waste_acc FROM public.accounts WHERE account_code = '51102' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_pkg_waste_acc FROM public.accounts WHERE account_code = '51104' AND company_id = v_company_id LIMIT 1;
  SELECT id INTO v_cost_item_acc FROM public.accounts WHERE account_code = '51101' AND company_id = v_company_id LIMIT 1;
  
  IF v_finished_inv_acc IS NULL OR v_raw_inv_acc IS NULL OR v_sorting_inv_acc IS NULL OR v_pkg_inv_acc IS NULL OR v_waste_acc IS NULL OR v_pkg_waste_acc IS NULL OR v_cost_item_acc IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'حسابات المخزون أو التشغيل (1030,1031,1032,1040,51101,51102,51104) غير معرفة بشكل صحيح');
  END IF;

  -- Get station
  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
     v_station_id := 1;
  END IF;

  -- 2. Delete Existing Inventory Batches
  DELETE FROM public.station_product_batches
  WHERE source_type IN ('packing_order', 'packing_order_sorting')
    AND source_id = p_packing_order_id::text;

  -- 3. Process Packed Lines (Finished Goods)
  FOR v_lines IN 
    SELECT * FROM public.packing_order_lines 
    WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_net_weight := v_tot_net_weight + COALESCE(v_lines.net_weight, 0);
    v_tot_raw_cost := v_tot_raw_cost + COALESCE(v_lines.raw_material_cost, 0);
    v_tot_pkg_cost := v_tot_pkg_cost + COALESCE(v_lines.packing_material_cost, 0);
    
    IF COALESCE(v_lines.net_weight, 0) > 0 THEN
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

  -- Calculate sorting cost 
  IF COALESCE(v_order.sorted_weight, 0) > 0 THEN
     v_tot_sorting_cost := COALESCE(v_order.raw_crop_cost_per_kg, 0) * v_order.sorted_weight;
  END IF;

  -- 4. Create Sorting Batch (if applicable)
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


  -- 5. Create Journal Entry
  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status,
    is_auto_generated, source_type, source_id, company_id,
    created_by, created_at, updated_at
  ) VALUES (
    'PENDING',
    COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),
    'قيد أمر تعبئة رقم ' || v_order_num,
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    auth.uid(), now(), now()
  ) RETURNING id INTO v_je_id;

  UPDATE public.packing_orders 
  SET journal_entry_id = v_je_id,
      status = 'confirmed',
      updated_at = now()
  WHERE id = p_packing_order_id;


  -- 6. Insert GL Lines
  -- 1) Debit 1031 (Finished Goods)
  IF COALESCE(v_order.total_final_cost, 0) > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, 
        amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, v_order.total_final_cost, 0, 'EGP', v_order.total_final_cost,
        'تكلفة إنتاج تام - أمر تعبئة ' || v_order_num, v_company_id
      );
  END IF;

  -- 2) Debit 1032 (Sorting)
  IF v_tot_sorting_cost > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, 
        amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, 'EGP', v_tot_sorting_cost,
        'مخزون فرز - أمر تعبئة ' || v_order_num, v_company_id
      );
  END IF;

  -- 3) Debit 51102 & Credit 51102 (Waste Zeroing)
  IF COALESCE(v_order.waste_weight, 0) > 0 THEN
      v_c_amt := v_order.waste_weight * COALESCE(v_order.raw_crop_cost_per_kg, 0);
      IF v_c_amt > 0 THEN
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, 
            amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_waste_acc, v_c_amt, 0, 'EGP', v_c_amt,
            'إثبات هالك محاصيل - أمر تعبئة ' || v_order_num, v_company_id
          );
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, 
            amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_waste_acc, 0, v_c_amt, 'EGP', v_c_amt,
            'تحميل هالك محاصيل على الإنتاج - أمر تعبئة ' || v_order_num, v_company_id
          );
      END IF;
  END IF;

  -- 4) Debit 51104 & Credit 51104 (Pkg Waste Zeroing)
  IF COALESCE(v_order.waste_packing_cost, 0) > 0 THEN
      v_c_amt := v_order.waste_packing_cost;
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, 
        amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_pkg_waste_acc, v_c_amt, 0, 'EGP', v_c_amt,
        'إثبات هالك مواد تعبئة - أمر تعبئة ' || v_order_num, v_company_id
      );
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, 
        amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_pkg_waste_acc, 0, v_c_amt, 'EGP', v_c_amt,
        'تحميل هالك مواد تعبئة على الإنتاج - أمر تعبئة ' || v_order_num, v_company_id
      );
  END IF;

  -- 5) Debit 51101 & Credit Supplier (Additional Costs)
  FOR r_cost IN
      SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
       IF r_cost.base_amount > 0 THEN
           INSERT INTO public.account_ledger_entries (
             journal_entry_id, account_id, debit, credit, currency, 
             amount_in_base_currency, description, company_id
           ) VALUES (
             v_je_id, v_cost_item_acc, r_cost.base_amount, 0, 'EGP', r_cost.base_amount,
             'إثبات بند تكلفة: ' || COALESCE(r_cost.name, '') || ' - أمر تعبئة ' || v_order_num, v_company_id
           );
           INSERT INTO public.account_ledger_entries (
             journal_entry_id, account_id, debit, credit, currency, 
             amount_in_base_currency, description, company_id
           ) VALUES (
             v_je_id, v_cost_item_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
             'تحميل بند تكلفة على الإنتاج: ' || COALESCE(r_cost.name, '') || ' - أمر تعبئة ' || v_order_num, v_company_id
           );

           v_credit_acc := NULL;
           IF r_cost.supplier_id IS NOT NULL THEN
             SELECT a.id INTO v_credit_acc
             FROM public.suppliers s
             JOIN public.accounts a ON (
                 a.name ILIKE '%مورد%' || COALESCE(s.name, '') || '%'
                 OR a.account_name ILIKE '%مورد%' || COALESCE(s.name, '') || '%'
             )
             WHERE s.id = r_cost.supplier_id
               AND a.company_id = v_company_id
               AND a.is_leaf = true LIMIT 1;
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

           IF v_credit_acc IS NULL THEN
              SELECT id INTO v_credit_acc FROM public.accounts
              WHERE company_id = v_company_id AND account_code LIKE '201%' AND is_leaf = true
              ORDER BY account_code ASC LIMIT 1;
           END IF;

           IF v_credit_acc IS NOT NULL THEN
               INSERT INTO public.account_ledger_entries (
                 journal_entry_id, account_id, debit, credit, currency, 
                 amount_in_base_currency, description, company_id
               ) VALUES (
                 v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
                 'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
               );
           END IF;
       END IF;
  END LOOP;

  -- 6) Credit 1030 (Raw Material consumed)
  IF COALESCE(v_order.raw_crop_cost, 0) > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, 
        amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_raw_inv_acc, 0, v_order.raw_crop_cost, 'EGP', v_order.raw_crop_cost,
        'صرف محصول خام - أمر تعبئة ' || v_order_num, v_company_id
      );
  END IF;

  -- 7) Credit 1033 (Packaging Materials consumed)
  SELECT SUM(COALESCE(base_amount, 0)) INTO v_tot_pkg_consumed 
  FROM public.packing_order_packing_materials 
  WHERE packing_order_id = p_packing_order_id;
  
  IF COALESCE(v_tot_pkg_consumed, 0) > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, 
        amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_consumed, 'EGP', v_tot_pkg_consumed,
        'صرف مواد تعبئة - أمر تعبئة ' || v_order_num, v_company_id
      );
  END IF;

  RETURN json_build_object('success', true, 'message', 'تم تأكيد الأمر وإنشاء القيد بنجاح', 'journal_entry_id', v_je_id);

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

COMMIT;