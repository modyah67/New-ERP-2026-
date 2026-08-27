-- Migration: Export Shipment Integrity, Atomic RPC, and Packing Order Protection
-- Enforces data integrity for packing orders and atomic shipment creation.

-- 1. Database Trigger: Protect Completed Packing Orders
CREATE OR REPLACE FUNCTION protect_completed_packing_order()
RETURNS trigger AS $$
BEGIN
  -- If both old and new status are 'completed', prevent modification of inventory-affecting fields
  IF OLD.status = 'completed' AND NEW.status = 'completed' THEN
    IF OLD.carton_count IS DISTINCT FROM NEW.carton_count OR
       OLD.net_weight_per_carton IS DISTINCT FROM NEW.net_weight_per_carton OR
       OLD.gross_weight_per_carton IS DISTINCT FROM NEW.gross_weight_per_carton OR
       OLD.total_net_weight IS DISTINCT FROM NEW.total_net_weight OR
       OLD.total_gross_weight IS DISTINCT FROM NEW.total_gross_weight OR
       OLD.fruit_type_id IS DISTINCT FROM NEW.fruit_type_id OR
       OLD.batch_id IS DISTINCT FROM NEW.batch_id OR
       OLD.packing_cost_per_carton IS DISTINCT FROM NEW.packing_cost_per_carton OR
       OLD.total_packing_cost IS DISTINCT FROM NEW.total_packing_cost THEN
      
      RAISE EXCEPTION 'Cannot modify inventory-affecting fields of a completed packing order (ID: %). Must change status to draft first.', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_protect_completed_packing_order ON public.packing_orders;
CREATE TRIGGER trg_protect_completed_packing_order
  BEFORE UPDATE ON public.packing_orders
  FOR EACH ROW
  EXECUTE FUNCTION protect_completed_packing_order();


-- 2. Atomic RPC for Saving Export Shipment
CREATE OR REPLACE FUNCTION rpc_save_export_shipment(p_shipment jsonb, p_items jsonb)
RETURNS jsonb AS $$
DECLARE
    v_shipment_id bigint;
    v_packing_order_ids bigint[];
    v_item jsonb;
    v_old_item RECORD;
    v_packing_order RECORD;
    v_requested_cartons int;
    v_available_cartons int;
BEGIN
    v_shipment_id := (p_shipment->>'id')::bigint;

    -- Step 1: Collect all packing order IDs to lock (both from existing shipment items and new items)
    SELECT array_agg(DISTINCT id ORDER BY id) INTO v_packing_order_ids
    FROM (
        SELECT packing_order_id AS id FROM export_shipment_items WHERE export_shipment_id = v_shipment_id
        UNION
        SELECT (value->>'packingOrderId')::bigint AS id FROM jsonb_array_elements(p_items) WHERE (value->>'packingOrderId') IS NOT NULL
    ) t;

    -- Step 2: Lock all involved packing orders in ascending order to prevent deadlocks
    IF v_packing_order_ids IS NOT NULL AND array_length(v_packing_order_ids, 1) > 0 THEN
        PERFORM id FROM packing_orders WHERE id = ANY(v_packing_order_ids) ORDER BY id FOR UPDATE;
    END IF;

    -- Step 3: Restore sold_cartons from existing items if this is an update
    IF v_shipment_id IS NOT NULL THEN
        FOR v_old_item IN SELECT * FROM export_shipment_items WHERE export_shipment_id = v_shipment_id
        LOOP
            UPDATE packing_orders 
            SET sold_cartons = GREATEST(0, COALESCE(sold_cartons, 0) - v_old_item.cartons)
            WHERE id = v_old_item.packing_order_id;
        END LOOP;
        
        -- Delete old items
        DELETE FROM export_shipment_items WHERE export_shipment_id = v_shipment_id;
    END IF;

    -- Step 4: Upsert the Shipment
    IF v_shipment_id IS NOT NULL THEN
        UPDATE export_shipments SET
            shipment_number = p_shipment->>'shipment_number',
            customer_name = p_shipment->>'customer_name',
            customer_code = p_shipment->>'customer_code',
            destination = p_shipment->>'destination',
            expected_date = (p_shipment->>'expected_date')::timestamp,
            status = p_shipment->>'status',
            notes = p_shipment->>'notes',
            discount_amount = COALESCE((p_shipment->>'discount_amount')::numeric, 0),
            discount_reason = p_shipment->>'discount_reason',
            freight_cost = COALESCE((p_shipment->>'freight_cost')::numeric, 0),
            clearance_cost = COALESCE((p_shipment->>'clearance_cost')::numeric, 0),
            other_costs = COALESCE((p_shipment->>'other_costs')::numeric, 0),
            total_amount = COALESCE((p_shipment->>'total_amount')::numeric, 0),
            net_amount = COALESCE((p_shipment->>'net_amount')::numeric, 0),
            payment_status = p_shipment->>'payment_status',
            paid_amount = COALESCE((p_shipment->>'paid_amount')::numeric, 0),
            remaining_amount = COALESCE((p_shipment->>'remaining_amount')::numeric, 0),
            total_cost = COALESCE((p_shipment->>'total_cost')::numeric, 0),
            estimated_profit = COALESCE((p_shipment->>'estimated_profit')::numeric, 0),
            profit_margin = COALESCE((p_shipment->>'profit_margin')::numeric, 0),
            total_cartons = COALESCE((p_shipment->>'total_cartons')::int, 0),
            total_net_weight = COALESCE((p_shipment->>'total_net_weight')::numeric, 0),
            total_gross_weight = COALESCE((p_shipment->>'total_gross_weight')::numeric, 0),
            currency = COALESCE(p_shipment->>'currency', 'EGP'),
            exchange_rate = COALESCE((p_shipment->>'exchange_rate')::numeric, 1.0),
            total_foreign = COALESCE((p_shipment->>'total_foreign')::numeric, 0),
            is_confirmed = COALESCE((p_shipment->>'is_confirmed')::boolean, false),
            payment_source_type = p_shipment->>'payment_source_type',
            payment_treasury_id = (p_shipment->>'payment_treasury_id')::bigint,
            payment_bank_account_id = (p_shipment->>'payment_bank_account_id')::bigint
        WHERE id = v_shipment_id;
    ELSE
        INSERT INTO export_shipments (
            shipment_number, customer_name, customer_code, destination, expected_date, status, notes,
            discount_amount, discount_reason, freight_cost, clearance_cost, other_costs,
            total_amount, net_amount, payment_status, paid_amount, remaining_amount,
            total_cost, estimated_profit, profit_margin, total_cartons, total_net_weight, total_gross_weight,
            currency, exchange_rate, total_foreign, is_confirmed, payment_source_type, payment_treasury_id, payment_bank_account_id
        ) VALUES (
            p_shipment->>'shipment_number', p_shipment->>'customer_name', p_shipment->>'customer_code', p_shipment->>'destination', (p_shipment->>'expected_date')::timestamp, p_shipment->>'status', p_shipment->>'notes',
            COALESCE((p_shipment->>'discount_amount')::numeric, 0), p_shipment->>'discount_reason', COALESCE((p_shipment->>'freight_cost')::numeric, 0), COALESCE((p_shipment->>'clearance_cost')::numeric, 0), COALESCE((p_shipment->>'other_costs')::numeric, 0),
            COALESCE((p_shipment->>'total_amount')::numeric, 0), COALESCE((p_shipment->>'net_amount')::numeric, 0), p_shipment->>'payment_status', COALESCE((p_shipment->>'paid_amount')::numeric, 0), COALESCE((p_shipment->>'remaining_amount')::numeric, 0),
            COALESCE((p_shipment->>'total_cost')::numeric, 0), COALESCE((p_shipment->>'estimated_profit')::numeric, 0), COALESCE((p_shipment->>'profit_margin')::numeric, 0), COALESCE((p_shipment->>'total_cartons')::int, 0), COALESCE((p_shipment->>'total_net_weight')::numeric, 0), COALESCE((p_shipment->>'total_gross_weight')::numeric, 0),
            COALESCE(p_shipment->>'currency', 'EGP'), COALESCE((p_shipment->>'exchange_rate')::numeric, 1.0), COALESCE((p_shipment->>'total_foreign')::numeric, 0), COALESCE((p_shipment->>'is_confirmed')::boolean, false), p_shipment->>'payment_source_type', (p_shipment->>'payment_treasury_id')::bigint, (p_shipment->>'payment_bank_account_id')::bigint
        ) RETURNING id INTO v_shipment_id;
    END IF;

    -- Step 5: Insert new items and update sold_cartons
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_requested_cartons := (v_item->>'cartons')::int;
            
            IF (v_item->>'packingOrderId') IS NOT NULL THEN
                -- Check available cartons
                SELECT * INTO v_packing_order
                FROM packing_orders
                WHERE id = (v_item->>'packingOrderId')::bigint;

                v_available_cartons := v_packing_order.carton_count - COALESCE(v_packing_order.sold_cartons, 0);

                IF v_requested_cartons > v_available_cartons THEN
                    RAISE EXCEPTION 'Insufficient available cartons in packing order %. Requested: %, Available: %', v_packing_order.id, v_requested_cartons, v_available_cartons;
                END IF;

                -- Update packing order sold_cartons
                UPDATE packing_orders 
                SET sold_cartons = COALESCE(sold_cartons, 0) + v_requested_cartons
                WHERE id = v_packing_order.id;
            END IF;

            -- Insert shipment item
            INSERT INTO export_shipment_items (
                export_shipment_id, packing_order_id, product_name, grade, cartons,
                net_weight_per_carton, total_net_weight, price, total_amount, cost, total_cost,
                currency, exchange_rate, total_foreign, price_foreign
            ) VALUES (
                v_shipment_id, (v_item->>'packingOrderId')::bigint, v_item->>'productName', v_item->>'grade', v_requested_cartons,
                (v_item->>'netWeightPerCarton')::numeric, (v_item->>'totalNetWeight')::numeric, (v_item->>'price')::numeric, (v_item->>'totalAmount')::numeric, (v_item->>'cost')::numeric, (v_item->>'totalCost')::numeric,
                COALESCE(v_item->>'currency', 'EGP'), COALESCE((v_item->>'exchangeRate')::numeric, 1.0), COALESCE((v_item->>'totalForeign')::numeric, 0), COALESCE((v_item->>'priceForeign')::numeric, 0)
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object('id', v_shipment_id);
END;
$$ LANGUAGE plpgsql;
