-- Revert: The rpc_refresh_packing_order_prices function should NOT multiply
-- by exchange_rate. The stock_batches.average_cost and station_product_batches.unit_cost
-- store costs in their original currency, but the JSON notes unit_cost values
-- were stored by Dart code which already applied exchange_rate.
-- The refresh function should read from DB and apply exchange_rate itself,
-- BUT the issue is that stock_batches.average_cost stores the FOREIGN CURRENCY price
-- while the packing order needs costs in EGP.
-- AND fruit allocation uses station_product_batches, not stock_batches.

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
        RETURN jsonb_build_object('success', false, 'error', 'Ø£Ù…Ø± Ø§Ù„ØªØ¹Ø¨Ø¦Ø© ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯');
    END IF;

    v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb ELSE '{}'::jsonb END;
    
    -- 1. Refresh fruit allocation
    -- fruit allocation uses station_product_batches NOT stock_batches!
    v_fruit_allocation := v_notes -> 'fruit_allocation';
    IF jsonb_typeof(v_fruit_allocation) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_fruit_allocation) LOOP
            SELECT unit_cost, COALESCE(NULLIF(exchange_rate, 0), 1) INTO v_batch_price, v_batch_ex
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_fruit_cost := v_new_fruit_cost + (COALESCE((v_elem->>'quantity')::numeric, 0) * (v_batch_price * v_batch_ex));
                -- Dart multiplies by exchange_rate itself from the lot, so we just store the new foreign unit cost
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_batch_price)));
            ELSE
                v_new_fruit_cost := v_new_fruit_cost + COALESCE((v_elem->>'quantity')::numeric, 0) * (COALESCE((v_elem->>'unit_cost')::numeric, 0) * COALESCE((v_elem->>'exchange_rate')::numeric, 1));
                v_updated_fruit_allocations := v_updated_fruit_allocations || jsonb_build_array(v_elem);
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(v_fruit_allocation) = 'object' THEN
        SELECT unit_cost, COALESCE(NULLIF(exchange_rate, 0), 1) INTO v_batch_price, v_batch_ex
        FROM station_product_batches WHERE id = (v_fruit_allocation->>'batch_id')::bigint;
        IF FOUND THEN
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * (v_batch_price * v_batch_ex);
            v_updated_fruit_allocations := jsonb_set(v_fruit_allocation, '{unit_cost}', to_jsonb(v_batch_price));
        ELSE
            v_new_fruit_cost := COALESCE((v_fruit_allocation->>'quantity')::numeric, 0) * (COALESCE((v_fruit_allocation->>'unit_cost')::numeric, 0) * COALESCE((v_fruit_allocation->>'exchange_rate')::numeric, 1));
            v_updated_fruit_allocations := v_fruit_allocation;
        END IF;
    END IF;

    -- 2. Refresh materials
    v_materials := v_notes -> 'materials';
    IF jsonb_typeof(v_materials) = 'array' THEN
        FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
            SELECT unit_cost, COALESCE(NULLIF(exchange_rate, 0), 1) INTO v_batch_price, v_batch_ex
            FROM station_product_batches WHERE id = (v_elem->>'batch_id')::bigint;
            IF FOUND THEN
                v_new_material_cost := v_new_material_cost + (COALESCE((v_elem->>'used_qty')::numeric, 0) * (v_batch_price * v_batch_ex));
                v_elem := jsonb_set(v_elem, '{unit_cost}', to_jsonb(v_batch_price));
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
    
    -- 3. Update packing_order_lines proportionally so UI is consistent
    -- Using NULLIF to avoid division by zero
    UPDATE packing_order_lines
    SET 
        raw_material_cost = CASE WHEN COALESCE(v_order.total_gross_weight, 0) > 0 THEN v_new_fruit_cost * (total_gross_weight / v_order.total_gross_weight) ELSE 0 END,
        allocated_shared_packaging = CASE WHEN COALESCE(v_order.total_gross_weight, 0) > 0 THEN v_new_material_cost * (total_gross_weight / v_order.total_gross_weight) ELSE 0 END,
        allocated_cost_items = CASE WHEN COALESCE(v_order.total_gross_weight, 0) > 0 THEN v_other_cost_base * (total_gross_weight / v_order.total_gross_weight) ELSE 0 END,
        final_cost = (CASE WHEN COALESCE(v_order.total_gross_weight, 0) > 0 THEN v_new_fruit_cost * (total_gross_weight / v_order.total_gross_weight) ELSE 0 END) +
                     (CASE WHEN COALESCE(v_order.total_gross_weight, 0) > 0 THEN v_new_material_cost * (total_gross_weight / v_order.total_gross_weight) ELSE 0 END) +
                     (CASE WHEN COALESCE(v_order.total_gross_weight, 0) > 0 THEN v_other_cost_base * (total_gross_weight / v_order.total_gross_weight) ELSE 0 END)
    WHERE packing_order_id = p_order_id;

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
