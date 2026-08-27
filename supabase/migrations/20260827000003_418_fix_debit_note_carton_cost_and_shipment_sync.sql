-- ============================================================================
-- Migration 418: Fix Debit Note Carton Cost Calculation and Export Shipment Sync
-- ============================================================================
-- 1. Corrects rpc_apply_packing_order_item_debit_note to:
--    a. Fix account_ledger_entries columns (remove nonexistent foreign_amount / exchange_rate).
--    b. Apply line-specific crop and material debit notes directly to the target line in multi-product orders.
--    c. Update packing_orders total_packing_cost and packing_cost_per_carton.
--    d. Update packing_order_lines final_cost and final_unit_cost accurately.
--    e. Update linked export_shipment_items.price to the exact new carton cost.
--    f. Return new_packing_cost_per_carton and new_total_packing_cost in JSONB.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_apply_packing_order_item_debit_note(
    p_order_id BIGINT,
    p_item_type TEXT,                -- 'material' or 'crop'
    p_batch_id BIGINT,               -- station_product_batch_id or line_id / lot_id
    p_discount_amount NUMERIC,       -- Total discount amount in EGP (base currency)
    p_supplier_id UUID DEFAULT NULL,
    p_reason TEXT DEFAULT 'تسوية سعر / إشعار خصم مورد',
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order RECORD;
    v_notes JSONB;
    v_materials JSONB;
    v_fruit_alloc JSONB;
    v_new_materials JSONB := '[]'::jsonb;
    v_elem JSONB;
    v_found BOOLEAN := false;
    v_company_id UUID;
    v_source_account_id BIGINT;
    v_dest_account_id BIGINT;
    v_dest_account_code TEXT := '1031';
    v_is_shipped BOOLEAN := false;
    v_shipment_id BIGINT;
    v_shipment_no TEXT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_old_mat_cost NUMERIC;
    v_new_mat_cost NUMERIC;
    v_old_fruit_cost NUMERIC;
    v_new_fruit_cost NUMERIC;
    v_old_total_pkg_cost NUMERIC;
    v_new_total_pkg_cost NUMERIC;
    v_new_cost_per_carton NUMERIC;
    v_carton_count INT;
    v_item_used_qty NUMERIC;
    v_item_old_total NUMERIC;
    v_item_new_total NUMERIC;
    v_item_new_unit_cost NUMERIC;
    v_line RECORD;
    v_target_line_id BIGINT := NULL;
    v_target_line_new_cost NUMERIC;
    v_target_line_new_unit_cost NUMERIC;
    v_new_raw NUMERIC;
    v_new_cost_per_kg NUMERIC;
    v_new_sorting_cost NUMERIC;
    v_new_waste_cost NUMERIC;
    v_mat_apply_to TEXT := 'all';
    v_supplier_uuid UUID := p_supplier_id;
    v_supplier_name TEXT;
    v_item_name TEXT := '';
    v_target_desc TEXT;
    v_supplier_currency TEXT := 'EGP';
    v_exchange_rate NUMERIC := 1.0;
    v_foreign_discount NUMERIC;
    r_ship RECORD;
BEGIN
    -- ── A. Validate & Lock Packing Order ──
    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    IF p_discount_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'مبلغ الخصم يجب أن يكون أكبر من الصفر');
    END IF;

    -- ── Check Profit Distribution Lock ──
    IF EXISTS (
        SELECT 1 
        FROM public.export_shipment_items esi
        JOIN public.shareholder_profit_distributions spd ON spd.shipment_id = esi.shipment_id
        WHERE esi.packing_order_id = p_order_id
          AND spd.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'تم توزيع أرباح الشحنة المرتبطة بهذا الأمر على المساهمين - لا يمكن تعديل الأسعار أو التكاليف');
    END IF;

    v_notes := CASE 
        WHEN v_order.notes IS NULL OR v_order.notes = '' THEN '{}'::jsonb
        ELSE v_order.notes::jsonb
    END;

    v_carton_count := COALESCE(v_order.carton_count, 1);
    IF v_carton_count <= 0 THEN v_carton_count := 1; END IF;

    v_old_mat_cost := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_old_fruit_cost := COALESCE(v_order.fruit_cost_allocated, v_order.fruit_cost_base, 0);
    v_old_total_pkg_cost := COALESCE(v_order.total_packing_cost, 0);

    -- ── B. Process Item Type & Update Notes JSON ──
    IF p_item_type = 'material' THEN
        v_materials := COALESCE(v_notes->'materials', '[]'::jsonb);
        IF jsonb_typeof(v_materials) = 'array' THEN
            FOR v_elem IN SELECT * FROM jsonb_array_elements(v_materials) LOOP
                IF (v_elem->>'batch_id')::bigint = p_batch_id OR (p_batch_id = 0 AND NOT v_found) THEN
                    v_found := true;
                    v_item_name := COALESCE(v_elem->>'product_name', 'خامة تعبئة');
                    v_supplier_name := v_elem->>'supplier_name';
                    v_mat_apply_to := COALESCE(v_elem->>'apply_to', 'all');
                    v_item_used_qty := COALESCE((v_elem->>'used_qty')::numeric, 1);
                    IF v_item_used_qty <= 0 THEN v_item_used_qty := 1; END IF;
                    v_item_old_total := COALESCE((v_elem->>'total')::numeric, (v_elem->>'unit_cost')::numeric * v_item_used_qty, 0);
                    v_item_new_total := GREATEST(0, v_item_old_total - p_discount_amount);
                    v_item_new_unit_cost := v_item_new_total / v_item_used_qty;

                    v_elem := v_elem || jsonb_build_object(
                        'total', v_item_new_total,
                        'unit_cost', v_item_new_unit_cost,
                        'discount_applied', COALESCE((v_elem->>'discount_applied')::numeric, 0) + p_discount_amount,
                        'last_debit_note_at', now()
                    );
                END IF;
                v_new_materials := v_new_materials || jsonb_build_array(v_elem);
            END LOOP;
        END IF;

        IF NOT v_found THEN
            v_notes := v_notes || jsonb_build_object('last_material_discount', p_discount_amount);
        ELSE
            v_notes := v_notes || jsonb_build_object('materials', v_new_materials);
        END IF;

        -- Resolve target line if material is applied to a specific line
        IF v_mat_apply_to LIKE 'line:%' THEN
            SELECT id INTO v_target_line_id
            FROM public.packing_order_lines
            WHERE packing_order_id = p_order_id
            ORDER BY id
            OFFSET (SUBSTRING(v_mat_apply_to FROM 6)::int)
            LIMIT 1;
        ELSIF v_mat_apply_to ~ '^[0-9]+$' THEN
            SELECT id INTO v_target_line_id
            FROM public.packing_order_lines
            WHERE packing_order_id = p_order_id
            ORDER BY id
            OFFSET (v_mat_apply_to::int)
            LIMIT 1;
        END IF;

        v_new_mat_cost := GREATEST(0, v_old_mat_cost - p_discount_amount);
        v_new_fruit_cost := v_old_fruit_cost;
    ELSE
        -- Crop / Fruit allocation adjustment
        IF p_batch_id > 0 THEN
            SELECT id, product_name INTO v_target_line_id, v_item_name
            FROM public.packing_order_lines
            WHERE packing_order_id = p_order_id
              AND (id = p_batch_id OR batch_id::text = p_batch_id::text OR source_lot_id::text = p_batch_id::text)
            LIMIT 1;
        END IF;

        IF v_target_line_id IS NULL AND p_supplier_id IS NOT NULL THEN
            SELECT pol.id, pol.product_name INTO v_target_line_id, v_item_name
            FROM public.packing_order_lines pol
            JOIN public.lot_receipts lr ON lr.id::text = pol.source_lot_id::text
            WHERE pol.packing_order_id = p_order_id
              AND lr.supplier_id = p_supplier_id
            LIMIT 1;
        END IF;

        IF v_target_line_id IS NULL AND (SELECT COUNT(*) FROM public.packing_order_lines WHERE packing_order_id = p_order_id) = 1 THEN
            SELECT id, product_name INTO v_target_line_id, v_item_name
            FROM public.packing_order_lines
            WHERE packing_order_id = p_order_id
            LIMIT 1;
        END IF;

        IF v_item_name IS NULL OR v_item_name = '' THEN
            v_item_name := COALESCE(v_order.product_name, 'محصول');
        END IF;

        v_new_fruit_cost := GREATEST(0, v_old_fruit_cost - p_discount_amount);
        v_new_mat_cost := v_old_mat_cost;
        v_notes := v_notes || jsonb_build_object(
            'fruit_discount_applied', COALESCE((v_notes->>'fruit_discount_applied')::numeric, 0) + p_discount_amount,
            'last_fruit_debit_note_at', now()
        );
    END IF;

    -- Recalculate Total Packing Cost & Cost per Carton
    v_new_total_pkg_cost := GREATEST(0, v_old_total_pkg_cost - p_discount_amount);
    v_new_cost_per_carton := ROUND(v_new_total_pkg_cost / v_carton_count, 4);

    -- ── C. Update Packing Order Record ──
    UPDATE public.packing_orders
    SET notes = v_notes::text,
        actual_material_cost = v_new_mat_cost,
        material_cost_base = v_new_mat_cost,
        fruit_cost_allocated = v_new_fruit_cost,
        fruit_cost_base = v_new_fruit_cost,
        total_packing_cost = v_new_total_pkg_cost,
        packing_cost_per_carton = v_new_cost_per_carton,
        updated_at = now()
    WHERE id = p_order_id;

    -- ── Update Packing Order Lines ──
    IF v_target_line_id IS NOT NULL THEN
        -- Line-specific discount: Deduct full discount from target line ONLY
        SELECT * INTO v_line FROM public.packing_order_lines WHERE id = v_target_line_id;

        IF p_item_type = 'crop' THEN
            -- Recalculate sorting_cost & waste_cost based on new cost_per_kg
            -- This mirrors the Dart packing_calculation_service formula:
            --   productCostPerKg = rawMaterialCost / quantity
            --   sortingCost = sorted_weight_kg × productCostPerKg
            --   wasteCost = waste_weight_kg × productCostPerKg
            --   finalCost = (rawMaterialCost - sortingCost) + wasteCost + packaging + costItems
            v_new_raw := GREATEST(0, COALESCE(v_line.raw_material_cost, 0) - p_discount_amount);
            v_new_cost_per_kg := CASE
                WHEN COALESCE(v_line.quantity, 0) > 0 THEN v_new_raw / v_line.quantity
                ELSE 0
            END;
            v_new_sorting_cost := COALESCE(v_line.sorted_weight_kg, 0) * v_new_cost_per_kg;
            -- In Dart, wasteCost = totalPurchaseCost * (wastePercent / 100).
            -- In carton mode, waste_weight_kg is 0, but waste_cost scales proportionally with raw_material_cost.
            v_new_waste_cost := CASE
                WHEN COALESCE(v_line.raw_material_cost, 0) > 0 AND COALESCE(v_line.waste_cost, 0) > 0 THEN
                    ROUND(v_new_raw * (v_line.waste_cost / v_line.raw_material_cost), 4)
                WHEN COALESCE(v_line.waste_weight_kg, 0) > 0 THEN
                    ROUND(v_line.waste_weight_kg * v_new_cost_per_kg, 4)
                ELSE 0
            END;

            -- Recompute final_cost from all components (same formula as Dart service)
            v_target_line_new_cost := (v_new_raw - v_new_sorting_cost)
                + v_new_waste_cost
                + COALESCE(v_line.specific_packaging_cost, 0)
                + COALESCE(v_line.allocated_shared_packaging, 0)
                + COALESCE(v_line.allocated_cost_items, 0);
            v_target_line_new_cost := GREATEST(0, v_target_line_new_cost);

            v_target_line_new_unit_cost := CASE
                WHEN COALESCE(v_line.total_net_weight, 0) > 0 THEN v_target_line_new_cost / v_line.total_net_weight
                WHEN COALESCE(v_line.carton_count, 0) > 0 THEN v_target_line_new_cost / v_line.carton_count
                ELSE v_line.final_unit_cost
            END;

            UPDATE public.packing_order_lines
            SET raw_material_cost = v_new_raw,
                sorting_cost = v_new_sorting_cost,
                waste_cost = v_new_waste_cost,
                final_cost = v_target_line_new_cost,
                final_unit_cost = v_target_line_new_unit_cost,
                updated_at = now()
            WHERE id = v_target_line_id;
        ELSE
            -- Material discount: simple deduction from final_cost
            v_target_line_new_cost := GREATEST(0, COALESCE(v_line.final_cost, 0) - p_discount_amount);
            v_target_line_new_unit_cost := CASE
                WHEN COALESCE(v_line.total_net_weight, 0) > 0 THEN v_target_line_new_cost / v_line.total_net_weight
                WHEN COALESCE(v_line.carton_count, 0) > 0 THEN v_target_line_new_cost / v_line.carton_count
                ELSE v_line.final_unit_cost
            END;

            UPDATE public.packing_order_lines
            SET specific_packaging_cost = GREATEST(0, COALESCE(specific_packaging_cost, 0) - p_discount_amount),
                final_cost = v_target_line_new_cost,
                final_unit_cost = v_target_line_new_unit_cost,
                updated_at = now()
            WHERE id = v_target_line_id;
        END IF;

        -- Sync linked shipment items for this specific line
        IF COALESCE(v_line.carton_count, 0) > 0 THEN
            UPDATE public.export_shipment_items
            SET price = ROUND(v_target_line_new_cost / v_line.carton_count, 4)
            WHERE packing_order_line_id = v_target_line_id;
        END IF;
    ELSE
        -- Shared discount: update all lines proportionally
        FOR v_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_order_id LOOP
            IF p_item_type = 'crop' THEN
                DECLARE
                    v_line_disc NUMERIC := p_discount_amount * (COALESCE(v_line.carton_count, 1)::numeric / v_carton_count);
                BEGIN
                    v_new_raw := GREATEST(0, COALESCE(v_line.raw_material_cost, 0) - v_line_disc);
                    v_new_cost_per_kg := CASE
                        WHEN COALESCE(v_line.quantity, 0) > 0 THEN v_new_raw / v_line.quantity
                        ELSE 0
                    END;
                    v_new_sorting_cost := COALESCE(v_line.sorted_weight_kg, 0) * v_new_cost_per_kg;
                    v_new_waste_cost := CASE
                        WHEN COALESCE(v_line.raw_material_cost, 0) > 0 AND COALESCE(v_line.waste_cost, 0) > 0 THEN
                            ROUND(v_new_raw * (v_line.waste_cost / v_line.raw_material_cost), 4)
                        WHEN COALESCE(v_line.waste_weight_kg, 0) > 0 THEN
                            ROUND(v_line.waste_weight_kg * v_new_cost_per_kg, 4)
                        ELSE 0
                    END;
                    v_target_line_new_cost := GREATEST(0, (v_new_raw - v_new_sorting_cost)
                        + v_new_waste_cost
                        + COALESCE(v_line.specific_packaging_cost, 0)
                        + COALESCE(v_line.allocated_shared_packaging, 0)
                        + COALESCE(v_line.allocated_cost_items, 0));
                    v_target_line_new_unit_cost := CASE
                        WHEN COALESCE(v_line.total_net_weight, 0) > 0 THEN v_target_line_new_cost / v_line.total_net_weight
                        WHEN COALESCE(v_line.carton_count, 0) > 0 THEN v_target_line_new_cost / v_line.carton_count
                        ELSE v_line.final_unit_cost
                    END;

                    UPDATE public.packing_order_lines
                    SET raw_material_cost = v_new_raw,
                        sorting_cost = v_new_sorting_cost,
                        waste_cost = v_new_waste_cost,
                        final_cost = v_target_line_new_cost,
                        final_unit_cost = v_target_line_new_unit_cost,
                        updated_at = now()
                    WHERE id = v_line.id;
                END;
            ELSE
                v_target_line_new_cost := GREATEST(0, COALESCE(v_line.final_cost, 0) - (p_discount_amount * (COALESCE(v_line.carton_count, 1)::numeric / v_carton_count)));
                v_target_line_new_unit_cost := CASE 
                    WHEN COALESCE(v_line.total_net_weight, 0) > 0 THEN v_target_line_new_cost / v_line.total_net_weight
                    WHEN COALESCE(v_line.carton_count, 0) > 0 THEN v_target_line_new_cost / v_line.carton_count
                    ELSE v_line.final_unit_cost 
                END;

                UPDATE public.packing_order_lines
                SET final_cost = v_target_line_new_cost,
                    final_unit_cost = v_target_line_new_unit_cost,
                    updated_at = now()
                WHERE id = v_line.id;
            END IF;

            IF COALESCE(v_line.carton_count, 0) > 0 THEN
                UPDATE public.export_shipment_items
                SET price = ROUND(v_target_line_new_cost / v_line.carton_count, 4)
                WHERE packing_order_line_id = v_line.id;
            END IF;
        END LOOP;
    END IF;

    -- Re-aggregate total_packing_cost from all lines' final_cost
    -- (necessary because crop debit notes trigger sorting/waste recalculation
    --  which may change the effective discount differently from p_discount_amount)
    SELECT COALESCE(SUM(final_cost), 0) INTO v_new_total_pkg_cost
    FROM public.packing_order_lines
    WHERE packing_order_id = p_order_id;

    v_new_cost_per_carton := ROUND(v_new_total_pkg_cost / v_carton_count, 4);

    UPDATE public.packing_orders
    SET total_packing_cost = v_new_total_pkg_cost,
        packing_cost_per_carton = v_new_cost_per_carton,
        updated_at = now()
    WHERE id = p_order_id;

    -- ── D. Check if Order is Linked to Confirmed/Active Shipment ──
    SELECT es.id, es.shipment_no
    INTO v_shipment_id, v_shipment_no
    FROM public.export_shipments es
    LEFT JOIN public.export_shipment_items esi ON esi.shipment_id = es.id
    WHERE (es.id = v_order.export_shipment_id OR esi.packing_order_id = p_order_id)
      AND es.status != 'cancelled'
    ORDER BY es.created_at DESC
    LIMIT 1;

    IF v_shipment_id IS NOT NULL THEN
        v_is_shipped := true;
        v_dest_account_code := '5000'; -- COGS (تكلفة البضاعة المباعة)
        v_target_desc := 'تخفيض تكلفة بضاعة مباعة لشحنة رقم ' || COALESCE(v_shipment_no, '') || ' عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text);
    ELSE
        v_is_shipped := false;
        v_dest_account_code := '1031'; -- Finished Goods Inventory (مخزون الإنتاج التام)
        v_target_desc := 'تخفيض تكلفة أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text) || ' بإشعار خصم المورد';
    END IF;

    -- ── E. Resolve Supplier, Currency, Exchange Rate & COA Accounts ──
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1031' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    -- 1. Identify Supplier UUID
    IF v_supplier_uuid IS NULL AND p_batch_id > 0 AND p_item_type = 'material' THEN
        SELECT pi.supplier_id INTO v_supplier_uuid
        FROM public.station_product_batches spb
        LEFT JOIN public.purchase_invoices pi ON pi.id = spb.purchase_invoice_id
        WHERE spb.id = p_batch_id;
    END IF;

    IF v_supplier_uuid IS NULL AND p_item_type = 'crop' AND v_target_line_id IS NOT NULL THEN
        SELECT lr.supplier_id INTO v_supplier_uuid
        FROM public.packing_order_lines pol
        JOIN public.lot_receipts lr ON lr.id::text = pol.source_lot_id::text
        WHERE pol.id = v_target_line_id;
    END IF;

    IF v_supplier_uuid IS NULL AND p_item_type = 'crop' AND v_order.lot_id IS NOT NULL THEN
        SELECT supplier_id INTO v_supplier_uuid FROM public.lot_receipts WHERE id::text = v_order.lot_id::text;
    END IF;

    -- 2. Resolve Source Account (Supplier Account if supplier exists, or Opening Balances / Equity 3000 if opening balance without supplier)
    IF v_supplier_uuid IS NOT NULL THEN
        SELECT account_id, COALESCE(currency, 'EGP')
        INTO v_source_account_id, v_supplier_currency
        FROM public.suppliers WHERE id = v_supplier_uuid;

        IF v_source_account_id IS NULL THEN
            v_source_account_id := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSE
        -- Opening balance material without supplier -> Debit Opening Balance Equity - EGP (3901)
        v_supplier_currency := 'EGP';
        v_source_account_id := public.resolve_gl_account('3901', v_company_id);
        IF v_source_account_id IS NULL THEN
            v_source_account_id := public.resolve_gl_account('3900', v_company_id);
        END IF;
        IF v_source_account_id IS NULL THEN
            v_source_account_id := public.resolve_gl_account('3000', v_company_id);
        END IF;
    END IF;

    -- 3. Resolve Batch/Lot Historical Exchange Rate
    IF p_batch_id > 0 AND p_item_type = 'material' THEN
        SELECT COALESCE(exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.station_product_batches
        WHERE id = p_batch_id;
    ELSIF p_item_type = 'crop' AND v_target_line_id IS NOT NULL THEN
        SELECT COALESCE(lr.exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.packing_order_lines pol
        JOIN public.lot_receipts lr ON lr.id::text = pol.source_lot_id::text
        WHERE pol.id = v_target_line_id;
    ELSIF p_item_type = 'crop' AND v_order.lot_id IS NOT NULL THEN
        SELECT COALESCE(exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.lot_receipts
        WHERE id::text = v_order.lot_id::text;
    END IF;

    IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN
        v_exchange_rate := 1.0;
    END IF;

    v_foreign_discount := ROUND(p_discount_amount / v_exchange_rate, 4);

    -- 4. Destination Account (5000 COGS if shipped, 1031 Finished Goods if unshipped)
    v_dest_account_id := public.resolve_gl_account(v_dest_account_code, v_company_id);

    -- ── F. Post Adjustment Journal Entry (Debit Note) ──
    INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
    ) VALUES (
        'PENDING',
        CURRENT_DATE,
        COALESCE(NULLIF(p_reason, ''), 
            CASE 
                WHEN v_supplier_uuid IS NOT NULL THEN 'إشعار تسوية مورد (' || COALESCE(v_item_name, '') || ') - أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text)
                ELSE 'تسوية تكلفة رصيد افتتاحي (' || COALESCE(v_item_name, '') || ') - أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text)
            END
        ),
        'posted', true, 'packing_order_debit_note', p_order_id::text, v_company_id,
        COALESCE(p_user_id, auth.uid()), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order_debit_note', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'PKDN-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    -- 1. DEBIT: Source Account (Supplier Account 2000 or Equity/Opening Balances 3000)
    IF v_source_account_id IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_source_account_id,
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END,
            0,
            v_supplier_currency,
            p_discount_amount,
            COALESCE(NULLIF(p_reason, ''), 
                CASE 
                    WHEN v_supplier_uuid IS NOT NULL THEN 'تسوية سعر / إشعار خصم مورد عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text)
                    ELSE 'تسوية تكلفة رصيد افتتاحي عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text)
                END
            ),
            v_company_id
        );
    END IF;

    -- 2. CREDIT: Destination Account (5000 COGS or 1031 Finished Goods in EGP)
    IF v_dest_account_id IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_dest_account_id, 0, p_discount_amount, 'EGP', p_discount_amount,
            COALESCE(NULLIF(p_reason, ''), v_target_desc),
            v_company_id
        );
    END IF;

    -- Update Supplier Outstanding Balance (in supplier currency) & Insert into Sub-ledger (كشف حساب المورد)
    IF v_supplier_uuid IS NOT NULL THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - 
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END
        WHERE id = v_supplier_uuid;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, description, created_by
        ) VALUES (
            'supplier',
            v_supplier_uuid::TEXT,
            'debit',
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END,
            v_supplier_currency,
            'packing_order_debit_note',
            v_je_id,
            COALESCE(NULLIF(p_reason, ''), 'إشعار خصم وتسوية مورد (' || COALESCE(v_item_name, '') || ') عن أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text)),
            COALESCE(p_user_id, auth.uid())
        );
    END IF;

    -- ── G. Auto-sync linked shipments profitability and carton cost ──
    UPDATE public.export_shipment_items
    SET price = v_new_cost_per_carton
    WHERE packing_order_id = p_order_id
      AND (packing_order_line_id IS NULL OR packing_order_line_id NOT IN (SELECT id FROM public.packing_order_lines WHERE packing_order_id = p_order_id));

    FOR v_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_order_id LOOP
        IF COALESCE(v_line.carton_count, 0) > 0 THEN
            UPDATE public.export_shipment_items
            SET price = ROUND(v_line.final_cost / v_line.carton_count, 4)
            WHERE packing_order_line_id = v_line.id;
        END IF;
    END LOOP;

    FOR r_ship IN 
        SELECT DISTINCT es.id
        FROM public.export_shipment_items esi
        JOIN public.export_shipments es ON es.id = esi.shipment_id
        WHERE esi.packing_order_id = p_order_id
          AND es.status != 'cancelled'
    LOOP
        UPDATE public.export_shipments es
        SET net_profit_egp = COALESCE(es.total_revenue_egp, 0) - COALESCE(es.total_landed_cost, 0) - COALESCE(es.allocated_admin_expenses, 0) - COALESCE(es.allocated_taxes, 0),
            net_profit = COALESCE(es.total_revenue_egp, 0) - COALESCE(es.total_landed_cost, 0) - COALESCE(es.allocated_admin_expenses, 0) - COALESCE(es.allocated_taxes, 0),
            updated_at = now()
        WHERE es.id = r_ship.id;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_num,
        'old_packing_cost_per_carton', ROUND(v_old_total_pkg_cost / v_carton_count, 4),
        'new_packing_cost_per_carton', v_new_cost_per_carton,
        'old_total_packing_cost', v_old_total_pkg_cost,
        'new_total_packing_cost', v_new_total_pkg_cost,
        'discount_amount', p_discount_amount,
        'foreign_discount_amount', v_foreign_discount,
        'supplier_currency', v_supplier_currency
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, UUID) TO authenticated, anon, service_role;

COMMIT;
