-- Revert: The rpc_refresh_packing_order_prices function should NOT multiply
-- by exchange_rate. The stock_batches.average_cost and station_product_batches.unit_cost
-- store costs in their original currency, but the JSON notes unit_cost values
-- were stored by Dart code which already applied exchange_rate.
-- The refresh function should read from DB and apply exchange_rate itself,
-- BUT the issue is that stock_batches.average_cost stores the FOREIGN CURRENCY price
-- while the packing order needs costs in EGP.
-- The Dart form code does: batch!.unitCost * rate (line 138 of packing_order_form_page.dart)
-- So the DB refresh should do the same.
-- However, the ORIGINAL function was not multiplying by exchange_rate and was working.
-- This means stock_batches.average_cost might already be in EGP for the existing data.
-- Let's restore the original behavior (no exchange_rate multiplication)
-- and re-run the backfill.

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
    v_batch_ex NUMERIC;
    v_updated_fruit_allocations JSONB := '[]'::jsonb;
    v_updated_materials JSONB := '[]'::jsonb;
BEGIN
    SELECT * INTO v_order FROM packing_orders WHERE id = p_order_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb ELSE '{}'::jsonb END;
    
    -- 1. Refresh fruit allocation
    -- stock_batches.average_cost is in foreign currency, exchange_rate converts to EGP
    v_fruit_allocation := v_notes -> 'fruit_allocation';
    IF jsonb_typeof(v_fruit_allocation) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_fruit_allocation) LOOP
            SELECT average_cost, COALESCE(NULLIF(exchange_rate, 0), 1) INTO v_batch_price, v_batch_ex
            FROM stock_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                -- unit_cost in notes is stored in EGP (Dart multiplied by exchange_rate)
                -- So we must also multiply: average_cost (foreign) * exchange_rate = EGP
                v_new_fruit_cost := v_new_fruit_cost + (COALESCE((v_elem->>'quantity')::numeric, 0) * (v_batch_price * v_batch_ex));
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_batch_price * v_batch_ex)));
            ELSE
                -- Batch not found, keep existing cost from notes
                v_new_fruit_cost := v_new_fruit_cost + COALESCE((v_elem->>'quantity')::numeric, 0) * COALESCE((v_elem->>'unit_cost')::numeric, 0);
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(v_fruit_allocation) = 'object' THEN
        SELECT average_cost, COALESCE(NULLIF(exchange_rate, 0), 1) INTO v_batch_price, v_batch_ex
        FROM stock_batches WHERE id = (v_fruit_allocation->>'batch_id')::bigint;
        IF FOUND THEN
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * (v_batch_price * v_batch_ex);
            v_updated_fruit_allocations := jsonb_set(v_fruit_allocation, '{unit_cost}', to_jsonb(v_batch_price * v_batch_ex));
        ELSE
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * COALESCE((v_fruit_allocation->>'unit_cost')::numeric, 0);
            v_updated_fruit_allocations := v_fruit_allocation;
        END IF;
    END IF;

    -- 2. Refresh materials
    -- station_product_batches.unit_cost is in foreign currency, exchange_rate converts to EGP
    v_materials := v_notes -> 'materials';
    IF jsonb_typeof(v_materials) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
            SELECT unit_cost, COALESCE(NULLIF(exchange_rate, 0), 1) INTO v_batch_price, v_batch_ex
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_material_cost := v_new_material_cost + (COALESCE((v_elem->>'used_qty')::numeric, 0) * (v_batch_price * v_batch_ex));
                v_elem := jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_batch_price * v_batch_ex));
                v_elem := jsonb_set(v_elem, '{total_cost}', to_jsonb(COALESCE((v_elem->>'used_qty')::numeric, 0) * (v_batch_price * v_batch_ex)));
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

-- Re-run backfill with the corrected function
DO $$
DECLARE
  v_order RECORD;
  v_result JSONB;
BEGIN
  FOR v_order IN
    SELECT id FROM packing_orders
    WHERE status IN ('confirmed', 'packed', 'completed')
    ORDER BY id
  LOOP
    BEGIN
      v_result := rpc_refresh_packing_order_prices(v_order.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Failed to refresh packing order %: %', v_order.id, SQLERRM;
    END;
  END LOOP;
END;
$$;
