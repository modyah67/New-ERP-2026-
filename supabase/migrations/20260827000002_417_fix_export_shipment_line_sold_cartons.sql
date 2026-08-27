-- Migration 417: Fix export shipment line-level carton tracking (sold_cartons) and accurate cost retrieval

-- 1. Match any historical export_shipment_items to packing_order_lines if line ID is missing
UPDATE export_shipment_items esi
SET packing_order_line_id = (
    SELECT pol.id 
    FROM packing_order_lines pol 
    WHERE pol.packing_order_id = esi.packing_order_id 
      AND (pol.product_name = esi.product_name OR pol.product_name = esi.invoice_product_name)
    LIMIT 1
)
WHERE esi.packing_order_line_id IS NULL AND esi.packing_order_id IS NOT NULL;

-- 2. Recalculate and synchronize sold_cartons for all packing_order_lines and packing_orders
UPDATE packing_order_lines pol
SET sold_cartons = COALESCE((
    SELECT SUM(esi.quantity)
    FROM export_shipment_items esi
    JOIN export_shipments es ON es.id = esi.shipment_id
    WHERE esi.packing_order_line_id = pol.id
      AND es.status != 'cancelled'
), 0);

UPDATE packing_orders po
SET sold_cartons = COALESCE((
    SELECT SUM(esi.quantity)
    FROM export_shipment_items esi
    JOIN export_shipments es ON es.id = esi.shipment_id
    WHERE esi.packing_order_id = po.id
      AND es.status != 'cancelled'
), 0);

-- 3. Upgrade rpc_save_export_shipment to track packing_order_line_id and update sold_cartons per line
CREATE OR REPLACE FUNCTION rpc_save_export_shipment(p_shipment jsonb, p_items jsonb)
RETURNS jsonb AS $$
DECLARE
    v_shipment_id bigint;
    v_packing_order_ids bigint[];
    v_item jsonb;
    v_old_item RECORD;
    v_packing_order RECORD;
    v_packing_line RECORD;
    v_line_id bigint;
    v_requested_cartons int;
    v_available_cartons int;
BEGIN
    v_shipment_id := (p_shipment->>'id')::bigint;

    -- Step 1: Collect all packing order IDs to lock
    SELECT array_agg(DISTINCT id ORDER BY id) INTO v_packing_order_ids
    FROM (
        SELECT packing_order_id AS id FROM export_shipment_items WHERE shipment_id = v_shipment_id
        UNION
        SELECT (value->>'packingOrderId')::bigint AS id FROM jsonb_array_elements(p_items) WHERE (value->>'packingOrderId') IS NOT NULL
    ) t;

    -- Step 2: Lock all involved packing orders in ascending order to prevent deadlocks
    IF v_packing_order_ids IS NOT NULL AND array_length(v_packing_order_ids, 1) > 0 THEN
        PERFORM id FROM packing_orders WHERE id = ANY(v_packing_order_ids) ORDER BY id FOR UPDATE;
    END IF;

    -- Step 3: Restore sold_cartons from existing items if this is an update
    IF v_shipment_id IS NOT NULL THEN
        FOR v_old_item IN SELECT * FROM export_shipment_items WHERE shipment_id = v_shipment_id
        LOOP
            UPDATE packing_orders 
            SET sold_cartons = GREATEST(0, COALESCE(sold_cartons, 0) - COALESCE(v_old_item.quantity, 0))
            WHERE id = v_old_item.packing_order_id;

            IF v_old_item.packing_order_line_id IS NOT NULL THEN
                UPDATE packing_order_lines
                SET sold_cartons = GREATEST(0, COALESCE(sold_cartons, 0) - COALESCE(v_old_item.quantity, 0))
                WHERE id = v_old_item.packing_order_line_id;
            END IF;
        END LOOP;
        
        -- Delete old items
        DELETE FROM export_shipment_items WHERE shipment_id = v_shipment_id;
    END IF;

    -- Step 4: Upsert the Shipment
    IF v_shipment_id IS NOT NULL THEN
        UPDATE export_shipments SET
            shipment_no = p_shipment->>'shipment_no',
            invoice_id = (p_shipment->>'invoice_id')::bigint,
            invoice_number = p_shipment->>'invoice_number',
            customer_id = (p_shipment->>'customer_id')::bigint,
            customer_name = p_shipment->>'customer_name',
            customer_code = p_shipment->>'customer_code',
            clearing_agent_id = (p_shipment->>'clearing_agent_id')::bigint,
            clearing_agent_name = p_shipment->>'clearing_agent_name',
            contact_person = p_shipment->>'contact_person',
            destination_country = p_shipment->>'destination_country',
            country_of_origin = p_shipment->>'country_of_origin',
            destination_address = p_shipment->>'destination_address',
            container_number = p_shipment->>'container_number',
            container_type = p_shipment->>'container_type',
            bl_number = p_shipment->>'bl_number',
            vessel_name = p_shipment->>'vessel_name',
            shipping_company = p_shipment->>'shipping_company',
            data_logger_no = p_shipment->>'data_logger_no',
            port_of_loading = p_shipment->>'port_of_loading',
            port_of_destination = p_shipment->>'port_of_destination',
            transport_mode = COALESCE(p_shipment->>'transport_mode', 'sea'),
            pallet_count = COALESCE((p_shipment->>'pallet_count')::int, 0),
            carton_count = COALESCE((p_shipment->>'carton_count')::int, 0),
            net_weight = COALESCE((p_shipment->>'net_weight')::numeric, 0),
            gross_weight = COALESCE((p_shipment->>'gross_weight')::numeric, 0),
            incoterm = p_shipment->>'incoterm',
            payment_terms = p_shipment->>'payment_terms',
            currency = p_shipment->>'currency',
            terms_conditions = p_shipment->>'terms_conditions',
            internal_notes = p_shipment->>'notes',
            status = p_shipment->>'status',
            packing_recipe_id = (p_shipment->>'packing_recipe_id')::bigint,
            freight_cost = COALESCE((p_shipment->>'freight_cost')::numeric, 0),
            insurance_cost = COALESCE((p_shipment->>'insurance_cost')::numeric, 0),
            clearance_cost = COALESCE((p_shipment->>'clearance_cost')::numeric, 0),
            other_costs = COALESCE((p_shipment->>'other_costs')::numeric, 0),
            total_landed_cost = COALESCE((p_shipment->>'total_landed_cost')::numeric, 0),
            cost_per_carton = COALESCE((p_shipment->>'cost_per_carton')::numeric, 0),
            export_price_per_carton = COALESCE((p_shipment->>'export_price_per_carton')::numeric, 0),
            currency_code = p_shipment->>'currency_code',
            exchange_rate = COALESCE((p_shipment->>'exchange_rate')::numeric, 1.0),
            total_revenue_foreign = COALESCE((p_shipment->>'total_revenue_foreign')::numeric, 0),
            total_revenue_egp = COALESCE((p_shipment->>'total_revenue_egp')::numeric, 0),
            net_profit_egp = COALESCE((p_shipment->>'net_profit_egp')::numeric, 0),
            total_fruit_cost = COALESCE((p_shipment->>'total_fruit_cost')::numeric, 0),
            total_packing_material_cost = COALESCE((p_shipment->>'total_packing_material_cost')::numeric, 0),
            gross_profit = COALESCE((p_shipment->>'gross_profit')::numeric, 0),
            net_profit = COALESCE((p_shipment->>'net_profit')::numeric, 0),
            discount_amount = COALESCE((p_shipment->>'discount_amount')::numeric, 0),
            discount_reason = p_shipment->>'discount_reason',
            applied_discount_amount = COALESCE((p_shipment->>'applied_discount_amount')::numeric, 0),
            paid_amount = COALESCE((p_shipment->>'paid_amount')::numeric, 0),
            payment_source_type = p_shipment->>'payment_source_type',
            payment_treasury_id = p_shipment->>'payment_treasury_id',
            payment_bank_account_id = (p_shipment->>'payment_bank_account_id')::bigint,
            is_confirmed = COALESCE((p_shipment->>'is_confirmed')::boolean, false)
        WHERE id = v_shipment_id;
    ELSE
        INSERT INTO export_shipments (
            shipment_no, invoice_id, invoice_number, customer_id, customer_name, customer_code,
            clearing_agent_id, clearing_agent_name, contact_person, destination_country, country_of_origin,
            destination_address, container_number, container_type, bl_number, vessel_name, shipping_company,
            data_logger_no, port_of_loading, port_of_destination, transport_mode, pallet_count, carton_count,
            net_weight, gross_weight, incoterm, payment_terms, currency, terms_conditions, internal_notes, status,
            packing_recipe_id, freight_cost, insurance_cost, clearance_cost, other_costs, total_landed_cost,
            cost_per_carton, export_price_per_carton, currency_code, exchange_rate, total_revenue_foreign,
            total_revenue_egp, net_profit_egp, total_fruit_cost, total_packing_material_cost, gross_profit,
            net_profit, discount_amount, discount_reason, applied_discount_amount, paid_amount,
            payment_source_type, payment_treasury_id, payment_bank_account_id, is_confirmed
        ) VALUES (
            p_shipment->>'shipment_no', (p_shipment->>'invoice_id')::bigint, p_shipment->>'invoice_number', (p_shipment->>'customer_id')::bigint, p_shipment->>'customer_name', p_shipment->>'customer_code',
            (p_shipment->>'clearing_agent_id')::bigint, p_shipment->>'clearing_agent_name', p_shipment->>'contact_person', p_shipment->>'destination_country', p_shipment->>'country_of_origin',
            p_shipment->>'destination_address', p_shipment->>'container_number', p_shipment->>'container_type', p_shipment->>'bl_number', p_shipment->>'vessel_name', p_shipment->>'shipping_company',
            p_shipment->>'data_logger_no', p_shipment->>'port_of_loading', p_shipment->>'port_of_destination', COALESCE(p_shipment->>'transport_mode', 'sea'), COALESCE((p_shipment->>'pallet_count')::int, 0), COALESCE((p_shipment->>'carton_count')::int, 0),
            COALESCE((p_shipment->>'net_weight')::numeric, 0), COALESCE((p_shipment->>'gross_weight')::numeric, 0), p_shipment->>'incoterm', p_shipment->>'payment_terms', p_shipment->>'currency', p_shipment->>'terms_conditions', p_shipment->>'notes', p_shipment->>'status',
            (p_shipment->>'packing_recipe_id')::bigint, COALESCE((p_shipment->>'freight_cost')::numeric, 0), COALESCE((p_shipment->>'insurance_cost')::numeric, 0), COALESCE((p_shipment->>'clearance_cost')::numeric, 0), COALESCE((p_shipment->>'other_costs')::numeric, 0), COALESCE((p_shipment->>'total_landed_cost')::numeric, 0),
            COALESCE((p_shipment->>'cost_per_carton')::numeric, 0), COALESCE((p_shipment->>'export_price_per_carton')::numeric, 0), p_shipment->>'currency_code', COALESCE((p_shipment->>'exchange_rate')::numeric, 1.0), COALESCE((p_shipment->>'total_revenue_foreign')::numeric, 0),
            COALESCE((p_shipment->>'total_revenue_egp')::numeric, 0), COALESCE((p_shipment->>'net_profit_egp')::numeric, 0), COALESCE((p_shipment->>'total_fruit_cost')::numeric, 0), COALESCE((p_shipment->>'total_packing_material_cost')::numeric, 0), COALESCE((p_shipment->>'gross_profit')::numeric, 0),
            COALESCE((p_shipment->>'net_profit')::numeric, 0), COALESCE((p_shipment->>'discount_amount')::numeric, 0), p_shipment->>'discount_reason', COALESCE((p_shipment->>'applied_discount_amount')::numeric, 0), COALESCE((p_shipment->>'paid_amount')::numeric, 0),
            p_shipment->>'payment_source_type', p_shipment->>'payment_treasury_id', (p_shipment->>'payment_bank_account_id')::bigint, COALESCE((p_shipment->>'is_confirmed')::boolean, false)
        ) RETURNING id INTO v_shipment_id;
    END IF;

    -- Step 5: Insert new items and update sold_cartons
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_requested_cartons := COALESCE((v_item->>'qty')::int, 0);
            v_line_id := COALESCE(
                (v_item->>'packing_order_line_id')::bigint,
                (v_item->>'lineId')::bigint
            );
            
            IF (v_item->>'packingOrderId') IS NOT NULL THEN
                -- Check available cartons
                SELECT * INTO v_packing_order
                FROM packing_orders
                WHERE id = (v_item->>'packingOrderId')::bigint;

                IF v_line_id IS NOT NULL THEN
                    SELECT * INTO v_packing_line
                    FROM packing_order_lines
                    WHERE id = v_line_id;

                    IF FOUND THEN
                        v_available_cartons := COALESCE(v_packing_line.carton_count, 0) - COALESCE(v_packing_line.sold_cartons, 0);
                        IF v_requested_cartons > v_available_cartons THEN
                            RAISE EXCEPTION 'الكمية المطلوبة (%) تتجاوز الكراتين المتاحة (%) في بند أمر التعبئة %', v_requested_cartons, v_available_cartons, v_packing_line.product_name;
                        END IF;

                        UPDATE packing_order_lines
                        SET sold_cartons = COALESCE(sold_cartons, 0) + v_requested_cartons
                        WHERE id = v_line_id;
                    END IF;
                ELSE
                    v_available_cartons := COALESCE(v_packing_order.carton_count, 0) - COALESCE(v_packing_order.sold_cartons, 0);
                    IF v_requested_cartons > v_available_cartons THEN
                        RAISE EXCEPTION 'الكمية المطلوبة (%) تتجاوز الكراتين المتاحة (%) في أمر التعبئة %', v_requested_cartons, v_available_cartons, v_packing_order.order_number;
                    END IF;
                END IF;

                -- Update packing order header sold_cartons
                UPDATE packing_orders 
                SET sold_cartons = COALESCE(sold_cartons, 0) + v_requested_cartons
                WHERE id = v_packing_order.id;
            END IF;

            -- Insert shipment item with packing_order_line_id
            INSERT INTO export_shipment_items (
                shipment_id, 
                packing_order_id, 
                packing_order_line_id,
                product_name, 
                invoice_product_name,
                finished_product_id,
                grade, 
                country_of_origin,
                hs_code,
                quantity,
                price, 
                export_price_per_carton,
                weight_per_carton,
                net_weight, 
                gross_weight,
                amount,
                pallets
            ) VALUES (
                v_shipment_id, 
                (v_item->>'packingOrderId')::bigint, 
                v_line_id,
                COALESCE(v_item->>'name', ''),
                COALESCE(v_item->>'product_name', ''),
                (v_item->>'productId')::int,
                v_item->>'grade', 
                v_item->>'countryOfOrigin',
                v_item->>'hsCode',
                v_requested_cartons,
                COALESCE((v_item->>'price')::numeric, 0), 
                COALESCE((v_item->>'exportPricePerCarton')::numeric, 0), 
                COALESCE((v_item->>'weightPerCarton')::numeric, 15),
                COALESCE((v_item->>'netWt')::numeric, 0), 
                COALESCE((v_item->>'grossWt')::numeric, 0), 
                COALESCE((v_item->>'amount')::numeric, 0),
                COALESCE((v_item->>'pallets')::int, 0)
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true, 'id', v_shipment_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Upgrade rpc_cancel_export_shipment to restore line-level sold_cartons
CREATE OR REPLACE FUNCTION public.rpc_cancel_export_shipment("p_shipment_id" bigint, "p_user_id" uuid DEFAULT auth.uid())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_old_item RECORD;
BEGIN
    SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
    END IF;

    -- Restore sold_cartons on packing orders and packing order lines
    FOR v_old_item IN SELECT * FROM export_shipment_items WHERE shipment_id = p_shipment_id
    LOOP
        UPDATE packing_orders 
        SET sold_cartons = GREATEST(0, COALESCE(sold_cartons, 0) - COALESCE(v_old_item.quantity, 0))
        WHERE id = v_old_item.packing_order_id;

        IF v_old_item.packing_order_line_id IS NOT NULL THEN
            UPDATE packing_order_lines
            SET sold_cartons = GREATEST(0, COALESCE(sold_cartons, 0) - COALESCE(v_old_item.quantity, 0))
            WHERE id = v_old_item.packing_order_line_id;
        END IF;
    END LOOP;

    UPDATE export_shipments
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = p_shipment_id;
    
    RETURN jsonb_build_object('success', true, 'shipment_id', p_shipment_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_export_shipment(jsonb, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_export_shipment(bigint, uuid) TO authenticated, service_role;
