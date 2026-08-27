-- Migration 339: Fix column "lot_id" does not exist in rpc_edit_lot_price
-- Description: Removes invalid reference to non-existent lot_id column on station_product_batches and ensures GL adjustment is cleanly delegated to sync_supplier_ledger_for_lot.

BEGIN;

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
    v_delta_cost NUMERIC;
    v_effective_cost NUMERIC;
    v_total_graded NUMERIC := 0;
    v_grading RECORD;
    v_net_wt NUMERIC;
    v_new_fruit_cost_per_kg NUMERIC;
    v_batch_record RECORD;
    r_po RECORD;
BEGIN
    SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
    IF NOT FOUND THEN RAISE EXCEPTION 'رقم المحصول غير موجود (id=%)', p_lot_id; END IF;

    v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
    v_net_wt := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

    IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
      v_new_total_cost := COALESCE(v_lot.carton_count, 0) * p_new_price;
    ELSE
      v_new_total_cost := COALESCE(v_lot.gross_weight_kg, 0) * p_new_price;
    END IF;

    v_delta_cost := v_new_total_cost - v_old_total_cost;
    v_new_fruit_cost_per_kg := CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END;

    UPDATE lot_receipts
    SET price_per_carton = CASE WHEN COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN p_new_price ELSE price_per_carton END,
        fruit_cost_per_kg = v_new_fruit_cost_per_kg,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;

    -- Sync GL entries through sync_supplier_ledger_for_lot (creates adjustment JE and syncs supplier balance)
    IF v_lot.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(p_lot_id, 'UPDATE');
    END IF;

    -- Update stock batches if graded
    SELECT COALESCE(SUM(weight_kg), 0) INTO v_total_graded FROM lot_grading_results WHERE lot_id = p_lot_id;
    IF v_total_graded > 0 THEN
      v_effective_cost := v_new_total_cost / v_total_graded;
      FOR v_grading IN (SELECT stock_batch_id FROM lot_grading_results WHERE lot_id = p_lot_id AND stock_batch_id IS NOT NULL) LOOP
        UPDATE stock_batches
        SET purchase_cost = v_effective_cost, average_cost = v_effective_cost
        WHERE id = v_grading.stock_batch_id;
      END LOOP;
    END IF;

    -- Update station product batches (matched by product_code = lot_number) and cascade to packing orders
    FOR v_batch_record IN 
        SELECT id FROM station_product_batches 
        WHERE source_type = 'lot_receipt' AND product_code = v_lot.lot_number
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

    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;

COMMIT;
