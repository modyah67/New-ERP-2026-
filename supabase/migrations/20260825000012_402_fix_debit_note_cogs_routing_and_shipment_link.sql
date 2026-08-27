-- ============================================================================
-- Migration 402: Fix Debit Note Routing to COGS (5000) vs Finished Goods (1031)
-- ============================================================================
-- 1. Checks both packing_orders.export_shipment_id and export_shipment_items
--    to accurately detect if the order belongs to a confirmed/active shipment.
-- 2. Routes credit line to 5000 (تكلفة البضاعة المباعة) when linked to an active shipment,
--    and to 1031 (مخزون الإنتاج التام) only if unshipped/unassigned.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_apply_packing_order_item_debit_note(
    p_order_id BIGINT,
    p_item_type TEXT,                -- 'material' or 'crop'
    p_batch_id BIGINT,               -- station_product_batch_id or 0 for main lot
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
    v_new_materials JSONB := '[]'::jsonb;
    v_elem JSONB;
    v_found BOOLEAN := false;
    v_company_id UUID;
    v_supplier_account_id BIGINT;
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
        FROM public.export_shipments es
        LEFT JOIN public.export_shipment_items esi ON esi.shipment_id = es.id
        JOIN public.shareholder_profit_distributions spd ON spd.shipment_id = es.id
        WHERE (es.id = v_order.export_shipment_id OR esi.packing_order_id = p_order_id)
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

        v_new_mat_cost := GREATEST(0, v_old_mat_cost - p_discount_amount);
        v_new_fruit_cost := v_old_fruit_cost;
    ELSE
        -- Crop / Fruit allocation adjustment
        v_item_name := COALESCE(v_order.product_name, 'محصول');
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

    -- Update packing order lines proportionally
    FOR v_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_order_id LOOP
        IF v_order.total_packing_cost > 0 THEN
            UPDATE public.packing_order_lines
            SET final_cost = GREATEST(0, final_cost - (p_discount_amount * (carton_count::numeric / v_carton_count))),
                final_unit_cost = CASE WHEN carton_count > 0 THEN (final_cost - (p_discount_amount * (carton_count::numeric / v_carton_count))) / carton_count ELSE final_unit_cost END,
                updated_at = now()
            WHERE id = v_line.id;
        END IF;
    END LOOP;

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
        v_target_desc := 'تخفيض تكلفة بضاعة مباعة (5000) لشحنة رقم ' || COALESCE(v_shipment_no, '') || ' عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text);
    ELSE
        v_dest_account_code := '1031'; -- Finished Goods Inventory (مخزون الإنتاج التام)
        v_target_desc := 'تخفيض تكلفة مخزون الإنتاج التام (1031) لأمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text) || ' بإشعار خصم المورد';
    END IF;

    -- ── E. Resolve Supplier, Currency, Exchange Rate & COA Accounts ──
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1030' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    -- 1. Identify Supplier UUID
    IF v_supplier_uuid IS NULL AND p_batch_id > 0 THEN
        SELECT pi.supplier_id INTO v_supplier_uuid
        FROM public.station_product_batches spb
        LEFT JOIN public.purchase_invoices pi ON pi.id = spb.purchase_invoice_id
        WHERE spb.id = p_batch_id;
    END IF;

    IF v_supplier_uuid IS NULL AND p_item_type = 'crop' AND v_order.lot_id IS NOT NULL THEN
        SELECT supplier_id INTO v_supplier_uuid FROM public.lot_receipts WHERE id = v_order.lot_id;
    END IF;

    -- 2. Resolve Supplier Account & Currency
    IF v_supplier_uuid IS NOT NULL THEN
        SELECT account_id, COALESCE(currency, 'EGP')
        INTO v_supplier_account_id, v_supplier_currency
        FROM public.suppliers WHERE id = v_supplier_uuid;
    END IF;

    -- 3. Resolve Batch/Lot Historical Exchange Rate
    IF p_batch_id > 0 THEN
        SELECT COALESCE(exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.station_product_batches
        WHERE id = p_batch_id;
    ELSIF p_item_type = 'crop' AND v_order.lot_id IS NOT NULL THEN
        SELECT COALESCE(exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.lot_receipts
        WHERE id = v_order.lot_id;
    END IF;

    IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN
        v_exchange_rate := 1.0;
    END IF;

    v_foreign_discount := ROUND(p_discount_amount / v_exchange_rate, 4);

    -- Fallback supplier account
    IF v_supplier_account_id IS NULL THEN
        v_supplier_account_id := public.resolve_gl_account('2000', v_company_id);
    END IF;

    -- 4. Destination Account (5000 if linked to shipment, 1031 if unshipped)
    v_dest_account_id := public.resolve_gl_account(v_dest_account_code, v_company_id);

    -- ── F. Post Adjustment Journal Entry (Debit Note) ──
    v_je_id := public.post_journal_entry(
        'packing_order_debit_note',
        'إشعار تسوية مورد (' || COALESCE(v_item_name, '') || ') - أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text) || ' - ' || p_reason,
        (NOW() AT TIME ZONE 'Africa/Cairo')::date,
        v_company_id,
        COALESCE(p_user_id, auth.uid()),
        jsonb_build_array(
            jsonb_build_object(
                'account_id', v_supplier_account_id,
                'debit', CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END,
                'credit', 0,
                'base_debit', p_discount_amount,
                'base_credit', 0,
                'currency', v_supplier_currency,
                'description', 'تسوية سعر / إشعار خصم مورد عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text)
            ),
            jsonb_build_object(
                'account_id', v_dest_account_id,
                'debit', 0,
                'credit', p_discount_amount,
                'base_debit', 0,
                'base_credit', p_discount_amount,
                'currency', 'EGP',
                'description', v_target_desc
            )
        ),
        p_order_id::text
    );

    SELECT entry_number INTO v_entry_num FROM public.journal_entries WHERE id = v_je_id;

    -- Update Supplier Outstanding Balance (in supplier currency)
    IF v_supplier_uuid IS NOT NULL THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - 
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END,
            updated_at = now()
        WHERE id = v_supplier_uuid;
    END IF;

    -- ── G. Auto-sync linked shipments cost & profitability ──
    FOR r_ship IN 
        SELECT DISTINCT es.id
        FROM public.export_shipments es
        LEFT JOIN public.export_shipment_items esi ON esi.shipment_id = es.id
        WHERE (es.id = v_order.export_shipment_id OR esi.packing_order_id = p_order_id)
          AND es.status != 'cancelled'
    LOOP
        UPDATE public.export_shipments es
        SET total_fruit_cost = GREATEST(0, COALESCE(es.total_fruit_cost, 0) - CASE WHEN p_item_type = 'crop' THEN p_discount_amount ELSE 0 END),
            total_packing_material_cost = GREATEST(0, COALESCE(es.total_packing_material_cost, 0) - CASE WHEN p_item_type = 'material' THEN p_discount_amount ELSE 0 END),
            total_landed_cost = GREATEST(0, COALESCE(es.total_landed_cost, 0) - p_discount_amount),
            net_profit_egp = COALESCE(es.total_revenue_egp, 0) - GREATEST(0, COALESCE(es.total_landed_cost, 0) - p_discount_amount) - COALESCE(es.allocated_admin_expenses, 0) - COALESCE(es.allocated_taxes, 0),
            net_profit = COALESCE(es.total_revenue_egp, 0) - GREATEST(0, COALESCE(es.total_landed_cost, 0) - p_discount_amount) - COALESCE(es.allocated_admin_expenses, 0) - COALESCE(es.allocated_taxes, 0),
            updated_at = now()
        WHERE es.id = r_ship.id;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_num,
        'destination_account', v_dest_account_code,
        'is_shipped', v_is_shipped,
        'supplier_currency', v_supplier_currency,
        'exchange_rate', v_exchange_rate,
        'foreign_discount', v_foreign_discount,
        'discount_applied_egp', p_discount_amount,
        'new_packing_cost_per_carton', v_new_cost_per_carton
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, UUID) TO authenticated;

COMMIT;
