-- Migration 334: Automatic Cascade of Purchase/Lot Price Edits to Packing Orders & GL Entries
-- Date: 2026-08-18

-- 1. Function to Refresh Packing Order Prices and Update Its Journal Entry Automatically
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


-- 2. Edit Purchase Item Price Function: Automatic Cascade to Packing Orders
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


-- 3. Edit Lot Price Function: Automatic Cascade to Packing Orders
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

GRANT EXECUTE ON FUNCTION public.rpc_refresh_packing_order_prices(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;
