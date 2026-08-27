-- Add flag to packing_orders
ALTER TABLE "public"."packing_orders" ADD COLUMN IF NOT EXISTS "needs_price_refresh" BOOLEAN DEFAULT false;

-- Create an RPC to flag packing orders that use a specific batch
CREATE OR REPLACE FUNCTION "public"."rpc_flag_packing_orders_for_refresh"("p_batch_type" text, "p_batch_id" bigint) RETURNS void
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF p_batch_type = 'fruit' THEN
        UPDATE packing_orders po
        SET needs_price_refresh = true
        WHERE po.notes IS NOT NULL AND po.notes != '' AND EXISTS (
            SELECT 1 FROM jsonb_array_elements(
                CASE 
                    WHEN jsonb_typeof(po.notes::jsonb -> 'fruit_allocation') = 'object' THEN jsonb_build_array(po.notes::jsonb -> 'fruit_allocation')
                    WHEN jsonb_typeof(po.notes::jsonb -> 'fruit_allocation') = 'array' THEN po.notes::jsonb -> 'fruit_allocation'
                    ELSE '[]'::jsonb 
                END
            ) AS elem
            WHERE (elem->>'batch_id')::bigint = p_batch_id
        );
    ELSIF p_batch_type = 'material' THEN
        UPDATE packing_orders po
        SET needs_price_refresh = true
        WHERE po.notes IS NOT NULL AND po.notes != '' AND EXISTS (
            SELECT 1 FROM jsonb_array_elements(
                CASE 
                    WHEN jsonb_typeof(po.notes::jsonb -> 'materials') = 'object' THEN jsonb_build_array(po.notes::jsonb -> 'materials')
                    WHEN jsonb_typeof(po.notes::jsonb -> 'materials') = 'array' THEN po.notes::jsonb -> 'materials'
                    ELSE '[]'::jsonb 
                END
            ) AS elem
            WHERE (elem->>'batch_id')::bigint = p_batch_id
        );
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION rpc_edit_purchase_item_price(
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
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  -- Get the item
  SELECT * INTO v_item
  FROM purchase_invoice_items
  WHERE id::TEXT = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'صنف المشتريات غير موجود';
  END IF;

  -- Get the purchase
  SELECT * INTO v_purchase
  FROM purchase_invoices
  WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  -- Calculate delta
  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_raw_material_id := v_item.raw_material_id;

  -- 1. Update item
  UPDATE purchase_invoice_items
  SET unit_cost = p_new_price,
      total_cost = v_new_item_total
  WHERE id::TEXT = p_item_id;

  -- 2. Update purchase totals
  UPDATE purchase_invoices
  SET subtotal = COALESCE(subtotal, 0) + v_delta,
      total_amount = COALESCE(total_amount, 0) + v_delta,
      remaining_amount = COALESCE(remaining_amount, 0) + v_delta,
      updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  -- 3. Update stock_batches (match by purchase_invoice_id + product_id)
  -- Also flag affected packing orders!
  FOR v_batch_record IN 
      SELECT id FROM stock_batches 
      WHERE purchase_invoice_id::TEXT = p_purchase_id AND product_id::TEXT = v_raw_material_id::TEXT 
  LOOP
      PERFORM rpc_flag_packing_orders_for_refresh('fruit', v_batch_record.id);
  END LOOP;

  UPDATE stock_batches
  SET purchase_cost = p_new_price,
      average_cost = p_new_price,
      updated_at = now()
  WHERE purchase_invoice_id::TEXT = p_purchase_id
    AND product_id::TEXT = v_raw_material_id::TEXT;

  -- 4. Get product code and name for station_product_batches
  SELECT code, name INTO v_product_code, v_product_name
  FROM raw_materials
  WHERE id = v_raw_material_id;

  -- 5. Update station_product_batches
  FOR v_batch_record IN 
      SELECT id FROM station_product_batches 
      WHERE source_type = 'purchase'
        AND purchase_invoice_id::TEXT = p_purchase_id
        AND (
          (v_product_code IS NOT NULL AND v_product_code != '' AND product_code = v_product_code)
          OR
          (product_name = COALESCE(v_product_name, '') || ' (مادة تعبئة)')
          OR
          (product_code = '' AND COALESCE(v_product_code, '') = '')
        )
  LOOP
      PERFORM rpc_flag_packing_orders_for_refresh('material', v_batch_record.id);
  END LOOP;

  UPDATE station_product_batches
  SET unit_cost = p_new_price
  WHERE source_type = 'purchase'
    AND purchase_invoice_id::TEXT = p_purchase_id
    AND (
      (v_product_code IS NOT NULL AND v_product_code != '' AND product_code = v_product_code)
      OR
      (product_name = COALESCE(v_product_name, '') || ' (مادة تعبئة)')
      OR
      (product_code = '' AND COALESCE(v_product_code, '') = '')
    );

  -- 6. Recalculate raw_materials.default_purchase_price
  IF v_raw_material_id IS NOT NULL THEN
    UPDATE raw_materials
    SET default_purchase_price = COALESCE(
      (SELECT SUM(purchase_cost * remaining_quantity) / NULLIF(SUM(remaining_quantity), 0)
       FROM stock_batches
       WHERE product_id::TEXT = v_raw_material_id::TEXT AND status = 'active'),
      default_purchase_price
    ),
    updated_at = now()
    WHERE id = v_raw_material_id;
  END IF;

  -- 7. Update supplier outstanding_balance
  IF v_purchase.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta
    WHERE id = v_purchase.supplier_id;
  END IF;

  -- 8. Refresh PostgREST schema cache
  NOTIFY pgrst, 'reload schema';

  RETURN jsonb_build_object(
    'success', true,
    'delta', v_delta
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تعديل السعر: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION "public"."rpc_refresh_packing_order_prices"("p_order_id" bigint) RETURNS jsonb
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_order RECORD;
    v_notes JSONB;
    v_new_fruit_cost NUMERIC := 0;
    v_new_material_cost NUMERIC := 0;
    v_other_cost_base NUMERIC := 0;
    v_total_cost NUMERIC := 0;
    v_packing_cost_per_carton NUMERIC := 0;
    v_fruit_allocation JSONB;
    v_materials JSONB;
    v_elem JSONB;
    v_batch_price NUMERIC;
    v_updated_fruit_allocations JSONB := '[]'::jsonb;
    v_updated_materials JSONB := '[]'::jsonb;
BEGIN
    SELECT * INTO v_order FROM packing_orders WHERE id = p_order_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb ELSE '{}'::jsonb END;
    
    -- 1. Refresh fruit allocation
    v_fruit_allocation := v_notes -> 'fruit_allocation';
    IF jsonb_typeof(v_fruit_allocation) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_fruit_allocation) LOOP
            SELECT average_cost INTO v_batch_price FROM stock_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_fruit_cost := v_new_fruit_cost + (COALESCE((v_elem->>'quantity')::numeric, 0) * COALESCE(v_batch_price, 0));
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(jsonb_set(v_elem, '{unit_cost}', to_jsonb(COALESCE(v_batch_price, 0))));
            ELSE
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(v_fruit_allocation) = 'object' THEN
        SELECT average_cost INTO v_batch_price FROM stock_batches WHERE id = (v_fruit_allocation->>'batch_id')::bigint;
        IF FOUND THEN
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * COALESCE(v_batch_price, 0);
            v_updated_fruit_allocations := jsonb_set(v_fruit_allocation, '{unit_cost}', to_jsonb(COALESCE(v_batch_price, 0)));
        ELSE
            v_updated_fruit_allocations := v_fruit_allocation;
        END IF;
    END IF;

    -- 2. Refresh materials
    v_materials := v_notes -> 'materials';
    IF jsonb_typeof(v_materials) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
            SELECT unit_cost INTO v_batch_price FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_material_cost := v_new_material_cost + (COALESCE((v_elem->>'used_qty')::numeric, 0) * COALESCE(v_batch_price, 0));
                v_elem := jsonb_set(v_elem, '{unit_cost}', to_jsonb(COALESCE(v_batch_price, 0)));
                v_elem := jsonb_set(v_elem, '{total_cost}', to_jsonb(COALESCE((v_elem->>'used_qty')::numeric, 0) * COALESCE(v_batch_price, 0)));
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

    RETURN jsonb_build_object('success', true);
END;
$$;
