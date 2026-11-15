-- ============================================================================
-- Migration: Fix and Enhance rpc_apply_packing_order_item_debit_note
-- Supports explicit or auto-resolved supplier_id, updates packing_orders costs,
-- and posts supplier debit note journal entries to double-entry ledger.
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, BIGINT, NUMERIC, TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT);
DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, BIGINT, UUID);
DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, BIGINT, UUID, TEXT);

CREATE OR REPLACE FUNCTION public.rpc_apply_packing_order_item_debit_note(
    p_order_id BIGINT,
    p_item_type TEXT,                -- 'material' or 'crop'
    p_batch_id BIGINT DEFAULT 0,     -- station_product_batch_id or lot_id
    p_discount_amount NUMERIC DEFAULT 0, -- Total discount amount in EGP (base currency)
    p_supplier_id UUID DEFAULT NULL, -- Explicit supplier UUID (or auto-resolved)
    p_reason TEXT DEFAULT 'تسوية سعر / إشعار خصم مورد',
    p_item_id BIGINT DEFAULT NULL,   -- Optional
    p_user_id UUID DEFAULT auth.uid(),
    p_item_name TEXT DEFAULT NULL
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
    v_source_account_id BIGINT;
    v_dest_account_id BIGINT;
    v_dest_account_code TEXT := '1031';
    v_is_shipped BOOLEAN := false;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_entry_date DATE;
    v_old_mat_cost NUMERIC;
    v_new_mat_cost NUMERIC;
    v_new_fruit_cost NUMERIC;
    v_new_total_pkg_cost NUMERIC;
    v_new_cost_per_carton NUMERIC;
    v_carton_count INT;
    v_supplier_uuid UUID := p_supplier_id;
    v_supplier_name TEXT := '';
    v_supplier_currency TEXT := 'EGP';
    v_exchange_rate NUMERIC := 1.0;
    v_foreign_discount NUMERIC;
    v_applied NUMERIC;
    v_old_total NUMERIC;
    v_new_total NUMERIC;
    v_qty NUMERIC;
    v_cost_center_id TEXT;
    v_cost_center_name TEXT;
    v_cost_center_type TEXT := 'operational';
    v_item_name TEXT := 'بند أمر تعبئة';
    v_category TEXT := 'مواد التعبئة';
BEGIN
    -- 1. Validate & Lock Packing Order
    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    IF p_discount_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'مبلغ الخصم يجب أن يكون أكبر من الصفر');
    END IF;

    -- 2. Check Profit Distribution Lock
    IF EXISTS (
        SELECT 1 
        FROM public.export_shipment_items esi
        JOIN public.shareholder_profit_distributions spd ON spd.shipment_id = esi.shipment_id
        WHERE esi.packing_order_id = p_order_id
          AND spd.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'تم توزيع أرباح الشحنة المرتبطة بهذا الأمر على المساهمين - لا يمكن تعديل الأسعار أو التكاليف');
    END IF;

    v_company_id := v_order.company_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 3. Auto-resolve Supplier UUID if not explicitly provided
    IF v_supplier_uuid IS NULL THEN
        IF p_item_type = 'material' AND p_batch_id > 0 THEN
            SELECT supplier_id INTO v_supplier_uuid
            FROM public.station_product_batches
            WHERE id = p_batch_id;

            IF v_supplier_uuid IS NULL THEN
                SELECT pi.supplier_id INTO v_supplier_uuid
                FROM public.station_product_batches spb
                JOIN public.purchase_invoices pi ON pi.id = spb.purchase_invoice_id
                WHERE spb.id = p_batch_id;
            END IF;
        END IF;

        -- Fallback to lot supplier linked to this packing order
        IF v_supplier_uuid IS NULL AND v_order.lot_id IS NOT NULL THEN
            SELECT supplier_id INTO v_supplier_uuid
            FROM public.lot_receipts
            WHERE id = v_order.lot_id;

            IF v_supplier_uuid IS NULL THEN
                SELECT supplier_id INTO v_supplier_uuid
                FROM public.lots
                WHERE id = v_order.lot_id;
            END IF;
        END IF;

        -- Fallback to system default supplier if only one exists
        IF v_supplier_uuid IS NULL THEN
            SELECT id INTO v_supplier_uuid FROM public.suppliers LIMIT 1;
        END IF;
    END IF;

    -- 4. Load Supplier details
    IF v_supplier_uuid IS NOT NULL THEN
        SELECT name, COALESCE(currency, 'EGP')
        INTO v_supplier_name, v_supplier_currency
        FROM public.suppliers
        WHERE id = v_supplier_uuid;

        v_exchange_rate := COALESCE(public.fn_get_exchange_rate(v_supplier_currency), 1.0);
    END IF;

    IF v_supplier_name IS NULL OR v_supplier_name = '' THEN
        v_supplier_name := 'المورد المرتبط';
    END IF;

    -- 5. Identify Accounts
    -- Source: Supplier Payable Account
    BEGIN
        SELECT account_id INTO v_source_account_id
        FROM public.suppliers
        WHERE id = v_supplier_uuid;
    EXCEPTION WHEN OTHERS THEN
        v_source_account_id := NULL;
    END;

    IF v_source_account_id IS NULL THEN
        v_source_account_id := public.resolve_gl_account('2001', v_company_id);
    END IF;
    IF v_source_account_id IS NULL THEN
        v_source_account_id := public.resolve_gl_account('2000', v_company_id);
    END IF;
    IF v_source_account_id IS NULL THEN
        v_source_account_id := public.resolve_gl_account('2112', v_company_id);
    END IF;
    IF v_source_account_id IS NULL THEN
        SELECT id INTO v_source_account_id FROM public.accounts WHERE account_code IN ('2112', '2001', '2000') LIMIT 1;
    END IF;
    IF v_source_account_id IS NULL THEN
        SELECT id INTO v_source_account_id FROM public.accounts WHERE account_type = 'liability' LIMIT 1;
    END IF;

    -- Destination Account: COGS (3111/5000) if shipped, Packaging Inventory (12411/1040) or Crop Inventory (12412/1030) or Finished Goods (12413/1031) if not
    SELECT EXISTS (
        SELECT 1 FROM public.export_shipment_items WHERE packing_order_id = p_order_id
    ) INTO v_is_shipped;

    IF v_is_shipped THEN
        v_dest_account_id := public.resolve_gl_account('3111', v_company_id);
        IF v_dest_account_id IS NULL THEN
            v_dest_account_id := public.resolve_gl_account('5000', v_company_id);
        END IF;
        IF v_dest_account_id IS NULL THEN
            SELECT id INTO v_dest_account_id FROM public.accounts WHERE account_code IN ('3111', '5000', '5101', '3110') LIMIT 1;
        END IF;
        IF v_dest_account_id IS NULL THEN
            SELECT id INTO v_dest_account_id FROM public.accounts WHERE account_type IN ('cost_of_goods_sold', 'expense') LIMIT 1;
        END IF;
    ELSE
        IF p_item_type = 'material' THEN
            v_dest_account_id := public.resolve_gl_account('12411', v_company_id);
            IF v_dest_account_id IS NULL THEN
                v_dest_account_id := public.resolve_gl_account('1040', v_company_id);
            END IF;
        ELSE
            v_dest_account_id := public.resolve_gl_account('12412', v_company_id);
            IF v_dest_account_id IS NULL THEN
                v_dest_account_id := public.resolve_gl_account('1030', v_company_id);
            END IF;
        END IF;

        IF v_dest_account_id IS NULL THEN
            v_dest_account_id := public.resolve_gl_account('12413', v_company_id);
        END IF;
        IF v_dest_account_id IS NULL THEN
            v_dest_account_id := public.resolve_gl_account('1031', v_company_id);
        END IF;
        IF v_dest_account_id IS NULL THEN
            SELECT id INTO v_dest_account_id FROM public.accounts WHERE account_code IN ('12413', '1031', '12411', '1040', '12412', '1030') LIMIT 1;
        END IF;
        IF v_dest_account_id IS NULL THEN
            SELECT id INTO v_dest_account_id FROM public.accounts WHERE account_type = 'asset' LIMIT 1;
        END IF;
    END IF;

    IF v_source_account_id IS NULL OR v_dest_account_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'تعذر تحديد حسابات اليومية (حساب المورد أو حساب المخزون/التكلفة)');
    END IF;

    -- 6. Resolve Cost Center & Item Details
    BEGIN
        v_notes := v_order.notes::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_notes := '{}'::jsonb;
    END;

    IF p_item_type = 'material' THEN
        v_category := 'مواد التعبئة';
        v_cost_center_type := 'operational';
        
        IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
            FOR v_elem IN SELECT * FROM jsonb_array_elements(v_notes->'materials')
            LOOP
                IF (p_batch_id > 0 AND COALESCE((v_elem->>'batch_id')::bigint, 0) = p_batch_id) OR
                   (p_item_id IS NOT NULL AND (v_elem->>'id')::text = p_item_id::text) OR
                   (p_item_name IS NOT NULL AND p_item_name <> '' AND (
                       COALESCE(v_elem->>'product_name', v_elem->>'name', v_elem->>'item_name') = p_item_name
                   )) OR
                   (jsonb_array_length(v_notes->'materials') = 1) THEN
                    v_cost_center_id := NULLIF(v_elem->>'cost_center_id', '');
                    v_cost_center_name := NULLIF(v_elem->>'cost_center_name', '');
                    v_item_name := COALESCE(NULLIF(v_elem->>'product_name', ''), NULLIF(v_elem->>'item_name', ''), NULLIF(v_elem->>'name', ''), p_item_name, 'مواد تعبئة');
                    EXIT;
                END IF;
            END LOOP;
        END IF;

        IF v_cost_center_id IS NULL THEN
            SELECT code, COALESCE(name_ar, name)
            INTO v_cost_center_id, v_cost_center_name
            FROM public.cost_centers
            WHERE code = 'CC-PACKING' OR code = 'packing_station'
            LIMIT 1;
        END IF;

        IF v_cost_center_id IS NULL THEN
            v_cost_center_id := 'CC-PACKING';
            v_cost_center_name := 'محطة التعبئة والتجهيز';
        END IF;
    ELSIF p_item_type = 'crop' THEN
        v_category := 'تكلفة المحاصيل';
        v_cost_center_type := 'variety';
        v_item_name := COALESCE(v_order.product_name, 'محصول');

        SELECT code, COALESCE(name_ar, name)
        INTO v_cost_center_id, v_cost_center_name
        FROM public.cost_centers
        WHERE (product_id = v_order.fruit_type_id OR name_ar = v_order.product_name OR crop_name = v_order.product_name)
          AND cost_center_type = 'variety'
        LIMIT 1;

        IF v_cost_center_id IS NULL THEN
            SELECT code, COALESCE(name_ar, name)
            INTO v_cost_center_id, v_cost_center_name
            FROM public.cost_centers
            WHERE cost_center_type = 'variety'
            LIMIT 1;
        END IF;

        IF v_cost_center_id IS NULL THEN
            v_cost_center_id := 'CC-CROP';
            v_cost_center_name := 'تكلفة المحاصيل';
        END IF;
    END IF;

    -- 7. Generate Journal Entry
    v_foreign_discount := ROUND(p_discount_amount / GREATEST(v_exchange_rate, 0.0001), 2);

    INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
    ) VALUES (
        'PENDING',
        v_entry_date,
        'إشعار خصم مورد على أمر تعبئة رقم ' || p_order_id::text || ' - مورد: ' || COALESCE(v_supplier_name, '') || ' - ' || COALESCE(p_reason, ''),
        'posted', true, 'packing_debit_note', p_order_id::text, v_company_id,
        COALESCE(p_user_id, auth.uid()), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_debit_note', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'DN-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    -- DR: Supplier account (decreases payable)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id, cost_center_id
    ) VALUES (
        v_je_id, v_source_account_id, v_foreign_discount, 0, v_supplier_currency, p_discount_amount,
        'إشعار خصم من المورد ' || COALESCE(v_supplier_name, '') || ' لأمر تعبئة #' || p_order_id::text,
        v_company_id, v_cost_center_id
    );

    -- CR: Inventory or COGS (reduces cost)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id, cost_center_id
    ) VALUES (
        v_je_id, v_dest_account_id, 0, p_discount_amount, 'EGP', p_discount_amount,
        'تخفيض تكلفة الإنتاج لأمر تعبئة #' || p_order_id::text || ' بإشعار خصم مورد ' || COALESCE(v_supplier_name, ''),
        v_company_id, v_cost_center_id
    );

    -- 7. Update Supplier Subledger & Account Statement (ledger_entries and supplier balance)
    IF v_supplier_uuid IS NOT NULL THEN
        UPDATE public.suppliers
        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - p_discount_amount),
            current_balances_by_currency = jsonb_set(
                COALESCE(current_balances_by_currency, '{}'::jsonb),
                array[v_supplier_currency],
                to_jsonb(COALESCE((current_balances_by_currency->>v_supplier_currency)::numeric, 0) - v_foreign_discount)
            ),
            updated_at = now()
        WHERE id = v_supplier_uuid;

        INSERT INTO public.ledger_entries (
            entity_type,
            entity_id,
            entry_type,
            amount,
            currency,
            reference_type,
            reference_id,
            reference_text,
            description,
            created_by,
            created_at
        ) VALUES (
            'supplier',
            v_supplier_uuid::text,
            'debit',
            v_foreign_discount,
            v_supplier_currency,
            'packing_order_debit_note',
            p_order_id,
            v_entry_num,
            'إشعار خصم وتسوية أمر تعبئة #' || p_order_id::text || ' - مورد: ' || COALESCE(v_supplier_name, '') || ' (' || COALESCE(p_reason, '') || ')',
            COALESCE(p_user_id, auth.uid()),
            now()
        );
    END IF;

    -- 8. Sync into Cost Center Transactions (Reduces Cost Center Expenses)
    IF v_cost_center_id IS NOT NULL THEN
        INSERT INTO public.cost_center_transactions (
            cost_center_id,
            cost_center_name,
            cost_center_type,
            source_type,
            source_id,
            transaction_date,
            supplier_id,
            supplier_name,
            item_name,
            category,
            quantity,
            unit_price,
            currency,
            exchange_rate,
            total_in_currency,
            amount,
            notes,
            is_confirmed
        ) VALUES (
            v_cost_center_id,
            v_cost_center_name,
            v_cost_center_type,
            'packing_debit_note',
            'pkdn_' || p_order_id::text || '_' || v_je_id::text,
            v_entry_date,
            v_supplier_uuid::text,
            v_supplier_name,
            'إشعار خصم تسوية - ' || v_item_name,
            v_category,
            0,
            0,
            v_supplier_currency,
            v_exchange_rate,
            -v_foreign_discount,
            -p_discount_amount,
            'إشعار خصم وتسوية أمر تعبئة #' || p_order_id::text || ' - مورد: ' || COALESCE(v_supplier_name, '') || ' (' || COALESCE(p_reason, '') || ')',
            true
        ) ON CONFLICT (source_type, source_id) DO UPDATE SET
            cost_center_id = EXCLUDED.cost_center_id,
            cost_center_name = EXCLUDED.cost_center_name,
            cost_center_type = EXCLUDED.cost_center_type,
            supplier_id = EXCLUDED.supplier_id,
            supplier_name = EXCLUDED.supplier_name,
            item_name = EXCLUDED.item_name,
            category = EXCLUDED.category,
            currency = EXCLUDED.currency,
            exchange_rate = EXCLUDED.exchange_rate,
            total_in_currency = EXCLUDED.total_in_currency,
            amount = EXCLUDED.amount,
            notes = EXCLUDED.notes,
            updated_at = now();
    END IF;

    -- 9. Recalculate Packing Order Costs & Update JSON Notes
    v_carton_count := GREATEST(1, COALESCE(v_order.carton_count, 1));
    v_new_total_pkg_cost := GREATEST(0, COALESCE(v_order.total_packing_cost, 0) - p_discount_amount);
    v_new_cost_per_carton := ROUND(v_new_total_pkg_cost / v_carton_count, 2);

    BEGIN
        v_notes := v_order.notes::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_notes := '{}'::jsonb;
    END;

    IF p_item_type = 'material' THEN
        v_new_mat_cost := GREATEST(0, COALESCE(v_order.actual_material_cost, 0) - p_discount_amount);
        
        -- Update materials array in notes
        IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
            FOR v_elem IN SELECT * FROM jsonb_array_elements(v_notes->'materials')
            LOOP
                IF NOT v_found AND (
                    (p_batch_id > 0 AND COALESCE((v_elem->>'batch_id')::bigint, 0) = p_batch_id) OR
                    (p_item_id IS NOT NULL AND (v_elem->>'id')::text = p_item_id::text) OR
                    (p_item_name IS NOT NULL AND p_item_name <> '' AND (
                        COALESCE(v_elem->>'product_name', v_elem->>'name', v_elem->>'item_name') = p_item_name
                    )) OR
                    (jsonb_array_length(v_notes->'materials') = 1)
                ) THEN
                    v_found := true;
                    v_applied := COALESCE(NULLIF(v_elem->>'discount_applied', '')::numeric, 0) + p_discount_amount;
                    v_qty := GREATEST(1, COALESCE(
                        NULLIF(v_elem->>'used_qty', '')::numeric,
                        NULLIF(v_elem->>'quantity', '')::numeric,
                        1
                    ));
                    v_old_total := COALESCE(
                        NULLIF(v_elem->>'total', '')::numeric,
                        NULLIF(v_elem->>'total_cost', '')::numeric,
                        ROUND(v_qty * COALESCE(NULLIF(v_elem->>'unit_cost', '')::numeric, NULLIF(v_elem->>'cost', '')::numeric, 0), 2)
                    );
                    v_new_total := GREATEST(0, v_old_total - p_discount_amount);
                    
                    v_elem := v_elem || jsonb_build_object(
                        'discount_applied', v_applied,
                        'total', v_new_total,
                        'total_cost', v_new_total,
                        'unit_cost', ROUND(v_new_total / v_qty, 3),
                        'cost', ROUND(v_new_total / v_qty, 3),
                        'supplier_name', v_supplier_name,
                        'supplier_id', v_supplier_uuid
                    );
                END IF;
                v_new_materials := v_new_materials || jsonb_build_array(v_elem);
            END LOOP;
            v_notes := v_notes || jsonb_build_object('materials', v_new_materials);
        END IF;

        UPDATE public.packing_orders
        SET actual_material_cost = v_new_mat_cost,
            total_packing_cost = v_new_total_pkg_cost,
            packing_cost_per_carton = v_new_cost_per_carton,
            notes = v_notes::text
        WHERE id = p_order_id;

        -- Keep packing_order_lines in sync with new cost per carton
        UPDATE public.packing_order_lines
        SET final_cost = ROUND(v_new_cost_per_carton * carton_count, 2),
            final_unit_cost = v_new_cost_per_carton
        WHERE packing_order_id = p_order_id;

    ELSIF p_item_type = 'crop' THEN
        v_new_fruit_cost := GREATEST(0, COALESCE(v_order.fruit_cost_allocated, 0) - p_discount_amount);

        UPDATE public.packing_orders
        SET fruit_cost_allocated = v_new_fruit_cost,
            fruit_cost_base = GREATEST(0, COALESCE(fruit_cost_base, 0) - p_discount_amount),
            total_packing_cost = v_new_total_pkg_cost,
            packing_cost_per_carton = v_new_cost_per_carton
        WHERE id = p_order_id;

        -- Keep packing_order_lines in sync with new cost per carton
        UPDATE public.packing_order_lines
        SET final_cost = ROUND(v_new_cost_per_carton * carton_count, 2),
            final_unit_cost = v_new_cost_per_carton
        WHERE packing_order_id = p_order_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_num,
        'discount_amount', p_discount_amount,
        'new_packing_cost_per_carton', v_new_cost_per_carton,
        'new_total_packing_cost', v_new_total_pkg_cost,
        'new_actual_material_cost', v_new_mat_cost,
        'supplier_name', v_supplier_name,
        'cost_center_id', v_cost_center_id,
        'cost_center_name', v_cost_center_name
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, BIGINT, UUID, TEXT) TO authenticated, anon, service_role;

-- ============================================================================
-- 10. Retroactive Sync: Pull any existing packing debit notes into:
--     1) ledger_entries (Supplier Statement & Outstanding Balance)
--     2) cost_center_transactions (Cost Centers & Cost Reports)
-- ============================================================================
DO $$
DECLARE
    r RECORD;
    v_order_id BIGINT;
    v_supplier_id UUID;
    v_supplier_name TEXT;
    v_cur TEXT;
    v_amt NUMERIC;
    v_base_amt NUMERIC;
    v_cc_id TEXT;
    v_cc_name TEXT;
    v_cc_type TEXT := 'operational';
    v_item_name TEXT;
    v_category TEXT := 'مواد التعبئة';
    v_ex_rate NUMERIC;
BEGIN
    FOR r IN 
        SELECT je.id AS je_id, je.entry_number, je.source_id, je.description, je.created_at, je.created_by,
               ale.account_id, ale.debit, ale.currency, ale.amount_in_base_currency, ale.cost_center_id
        FROM public.journal_entries je
        JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id AND ale.debit > 0
        WHERE je.source_type = 'packing_debit_note'
    LOOP
        v_order_id := (r.source_id)::bigint;
        v_amt := r.debit;
        v_cur := COALESCE(r.currency, 'EGP');
        v_base_amt := r.amount_in_base_currency;

        -- Find supplier by matching suppliers.account_id with r.account_id
        SELECT id, name INTO v_supplier_id, v_supplier_name
        FROM public.suppliers
        WHERE account_id = r.account_id
        LIMIT 1;

        -- Fallback to lot supplier
        IF v_supplier_id IS NULL THEN
            SELECT lr.supplier_id INTO v_supplier_id
            FROM public.packing_orders po
            LEFT JOIN public.lot_receipts lr ON lr.id = po.lot_id
            WHERE po.id = v_order_id;

            IF v_supplier_id IS NOT NULL THEN
                SELECT name INTO v_supplier_name FROM public.suppliers WHERE id = v_supplier_id;
            END IF;
        END IF;

        IF v_supplier_id IS NULL THEN
            SELECT id, name INTO v_supplier_id, v_supplier_name FROM public.suppliers LIMIT 1;
        END IF;

        -- 1. Sync into ledger_entries (Supplier Statement)
        IF v_supplier_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.ledger_entries
                WHERE entity_type = 'supplier'
                  AND reference_type = 'packing_order_debit_note'
                  AND reference_id = v_order_id
            ) THEN
                INSERT INTO public.ledger_entries (
                    entity_type, entity_id, entry_type, amount, currency,
                    reference_type, reference_id, reference_text, description, created_by, created_at
                ) VALUES (
                    'supplier', v_supplier_id::text, 'debit', v_amt, v_cur,
                    'packing_order_debit_note', v_order_id, r.entry_number,
                    r.description, r.created_by, r.created_at
                );

                UPDATE public.suppliers
                SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - v_base_amt),
                    current_balances_by_currency = jsonb_set(
                        COALESCE(current_balances_by_currency, '{}'::jsonb),
                        array[v_cur],
                        to_jsonb(COALESCE((current_balances_by_currency->>v_cur)::numeric, 0) - v_amt)
                    ),
                    updated_at = now()
                WHERE id = v_supplier_id;
            END IF;
        END IF;

        -- 2. Sync into cost_center_transactions (Cost Center Reports)
        v_cc_id := r.cost_center_id;
        IF v_cc_id IS NULL OR v_cc_id = '' THEN
            SELECT cc.code, COALESCE(cc.name_ar, cc.name), cc.cost_center_type
            INTO v_cc_id, v_cc_name, v_cc_type
            FROM public.packing_orders po
            JOIN public.cost_centers cc ON (cc.product_id = po.fruit_type_id OR cc.name_ar = po.product_name)
            WHERE po.id = v_order_id
            LIMIT 1;
        END IF;

        IF v_cc_id IS NULL OR v_cc_id = '' THEN
            v_cc_id := 'CC-PACKING';
            v_cc_name := 'محطة التعبئة والتجهيز';
            v_cc_type := 'operational';
        ELSE
            SELECT COALESCE(name_ar, name), cost_center_type
            INTO v_cc_name, v_cc_type
            FROM public.cost_centers
            WHERE code = v_cc_id OR id::text = v_cc_id
            LIMIT 1;
        END IF;

        IF v_cc_type = 'variety' THEN
            v_category := 'تكلفة المحاصيل';
        ELSE
            v_category := 'مواد التعبئة';
        END IF;

        v_ex_rate := CASE WHEN v_amt > 0 THEN ROUND(v_base_amt / v_amt, 4) ELSE 1.0 END;

        INSERT INTO public.cost_center_transactions (
            cost_center_id,
            cost_center_name,
            cost_center_type,
            source_type,
            source_id,
            transaction_date,
            supplier_id,
            supplier_name,
            item_name,
            category,
            quantity,
            unit_price,
            currency,
            exchange_rate,
            total_in_currency,
            amount,
            notes,
            is_confirmed
        ) VALUES (
            v_cc_id,
            v_cc_name,
            v_cc_type,
            'packing_debit_note',
            'pkdn_' || v_order_id::text || '_' || r.je_id::text,
            (r.created_at AT TIME ZONE 'Africa/Cairo')::DATE,
            v_supplier_id::text,
            v_supplier_name,
            'إشعار خصم تسوية',
            v_category,
            0,
            0,
            v_cur,
            v_ex_rate,
            -v_amt,
            -v_base_amt,
            r.description,
            true
        ) ON CONFLICT (source_type, source_id) DO UPDATE SET
            cost_center_id = EXCLUDED.cost_center_id,
            cost_center_name = EXCLUDED.cost_center_name,
            cost_center_type = EXCLUDED.cost_center_type,
            supplier_id = EXCLUDED.supplier_id,
            supplier_name = EXCLUDED.supplier_name,
            amount = EXCLUDED.amount,
            total_in_currency = EXCLUDED.total_in_currency,
            notes = EXCLUDED.notes,
            updated_at = now();

    END LOOP;
END;
$$;
