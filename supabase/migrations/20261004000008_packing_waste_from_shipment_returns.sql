-- ============================================================================
-- Migration: 20261004000008_packing_waste_from_shipment_returns.sql
-- Description: Connect packaging material waste from airport shipment returns
--              directly to the packing order waste tracking and settlement cycle
-- ============================================================================

-- 1. Enhanced rpc_get_packing_waste_settlements
CREATE OR REPLACE FUNCTION public.rpc_get_packing_waste_settlements(p_packing_order_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order RECORD;
    v_notes JSONB;
    v_mat_waste_pct NUMERIC := 0;
    v_tot_pkg_drawn NUMERIC := 0;
    v_tot_pkg_waste NUMERIC := 0;
    v_return_pkg_waste NUMERIC := 0;
    v_return_damaged_cartons NUMERIC := 0;
    v_return_details JSONB := '[]'::jsonb;
    v_settled NUMERIC := 0;
    v_unsettled NUMERIC := 0;
    v_status TEXT;
    v_settlements JSONB := '[]'::jsonb;
    v_mat_array JSONB := '[]'::jsonb;
    v_m_el JSONB;
BEGIN
    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    -- Check packaging waste from shipment returns (الهالك من رجوع الشحنة من المطار)
    SELECT 
        COALESCE(SUM(
            COALESCE((item->>'damaged_cartons')::numeric, 0) * COALESCE((item->>'carton_unit_cost')::numeric, 0)
        ), 0),
        COALESCE(SUM(COALESCE((item->>'damaged_cartons')::numeric, 0)), 0),
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'return_id', esr.id,
                'return_number', esr.return_number,
                'return_date', esr.return_date,
                'shipment_id', esr.shipment_id,
                'shipment_no', COALESCE(es.shipment_no, ''),
                'damaged_cartons', COALESCE((item->>'damaged_cartons')::int, 0),
                'carton_unit_cost', COALESCE((item->>'carton_unit_cost')::numeric, 0),
                'waste_cost', COALESCE((item->>'damaged_cartons')::numeric, 0) * COALESCE((item->>'carton_unit_cost')::numeric, 0),
                'product_name', item->>'product_name',
                'carton_product_name', item->>'carton_product_name'
            )
        ) FILTER (WHERE (COALESCE((item->>'damaged_cartons')::numeric, 0) * COALESCE((item->>'carton_unit_cost')::numeric, 0)) > 0), '[]'::jsonb)
    INTO v_return_pkg_waste, v_return_damaged_cartons, v_return_details
    FROM public.export_shipment_returns esr
    JOIN public.export_shipments es ON es.id = esr.shipment_id
    LEFT JOIN LATERAL jsonb_array_elements(COALESCE(esr.raw_data->'items', '[]'::jsonb)) AS item ON true
    WHERE (
        (item->>'packing_order_id')::bigint = p_packing_order_id
        OR (
            (item->>'packing_order_id') IS NULL 
            AND esr.shipment_id IN (
                SELECT shipment_id FROM public.export_shipment_items WHERE packing_order_id = p_packing_order_id
            )
        )
    );

    IF v_return_pkg_waste > 0 THEN
        v_tot_pkg_waste := v_return_pkg_waste;
    ELSE
        BEGIN
            v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
            IF jsonb_typeof(v_notes) = 'string' THEN
                v_notes := (v_notes #>> '{}')::jsonb;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_notes := '{}'::jsonb;
        END;

        -- Extract or compute packaging waste cost from order notes
        v_tot_pkg_waste := COALESCE((v_notes->'workflow_stages'->'packaging'->>'pkg_waste_cost')::numeric, 0);

        IF v_tot_pkg_waste = 0 THEN
            v_mat_waste_pct := COALESCE(
                (v_notes->>'material_waste_percent')::numeric, 
                (v_notes->>'waste_percentage')::numeric, 
                0
            );

            IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
                v_mat_array := v_notes->'materials';
            ELSIF v_notes ? 'material_items' AND jsonb_typeof(v_notes->'material_items') = 'array' THEN
                v_mat_array := v_notes->'material_items';
            END IF;

            IF jsonb_array_length(v_mat_array) > 0 THEN
                FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_mat_array) LOOP
                    v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE(
                        (v_m_el->>'total')::numeric,
                        (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) *
                         COALESCE((v_m_el->>'unit_cost')::numeric, 0))
                    );
                END LOOP;
            END IF;

            IF v_tot_pkg_drawn = 0 THEN
                v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
                IF v_mat_waste_pct > 0 THEN
                    v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 4);
                END IF;
            END IF;

            v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 4);
        END IF;
    END IF;

    -- Sum settlements
    SELECT COALESCE(SUM(amount), 0) INTO v_settled
    FROM public.packing_order_waste_settlements
    WHERE packing_order_id = p_packing_order_id;

    v_unsettled := GREATEST(0, ROUND(v_tot_pkg_waste - v_settled, 4));

    IF v_tot_pkg_waste <= 0 THEN
        v_status := 'no_waste';
    ELSIF v_settled <= 0 THEN
        v_status := 'unsettled';
    ELSIF v_unsettled <= 0.001 THEN
        v_status := 'fully_settled';
    ELSE
        v_status := 'partially_settled';
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', s.id,
            'packing_order_id', s.packing_order_id,
            'amount', s.amount,
            'settlement_date', s.settlement_date,
            'notes', s.notes,
            'created_by', s.created_by,
            'created_at', s.created_at
        ) ORDER BY s.id DESC
    ), '[]'::jsonb) INTO v_settlements
    FROM public.packing_order_waste_settlements s
    WHERE s.packing_order_id = p_packing_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'total_waste_cost', v_tot_pkg_waste,
        'settled_waste_cost', v_settled,
        'unsettled_waste_cost', v_unsettled,
        'status', v_status,
        'settlements', v_settlements,
        'packaging_journal_entry_id', v_order.packaging_journal_entry_id,
        'return_packaging_waste_cost', v_return_pkg_waste,
        'return_damaged_cartons', v_return_damaged_cartons,
        'return_details', v_return_details,
        'is_from_return', (v_return_pkg_waste > 0)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_packing_waste_settlements(BIGINT) 
    TO authenticated, anon, service_role;


-- 2. Enhanced rpc_settle_packing_material_waste
CREATE OR REPLACE FUNCTION public.rpc_settle_packing_material_waste(
    p_packing_order_id BIGINT,
    p_amount NUMERIC,
    p_notes TEXT DEFAULT NULL,
    p_settlement_date DATE DEFAULT CURRENT_DATE,
    p_settled_by TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order RECORD;
    v_notes JSONB;
    v_mat_waste_pct NUMERIC := 0;
    v_tot_pkg_drawn NUMERIC := 0;
    v_tot_pkg_waste NUMERIC := 0;
    v_return_pkg_waste NUMERIC := 0;
    v_return_damaged_cartons NUMERIC := 0;
    v_already_settled NUMERIC := 0;
    v_unsettled NUMERIC := 0;
    v_new_settled NUMERIC := 0;
    v_new_unsettled NUMERIC := 0;
    v_status TEXT;
    v_settlement_id BIGINT;
    v_uid UUID;
    v_company_id UUID;
    v_mat_array JSONB := '[]'::jsonb;
    v_m_el JSONB;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'قيمة التسوية يجب أن تكون أكبر من الصفر');
    END IF;

    -- Lock the packing order row
    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    -- Prerequisite check: Packaging stage must be confirmed first
    IF v_order.packaging_confirmed_at IS NULL 
       AND v_order.packaging_journal_entry_id IS NULL 
       AND v_order.status NOT IN ('packaging_confirmed', 'costs_confirmed', 'final_approved', 'completed') THEN
        RETURN jsonb_build_object('success', false, 'error', 'يجب تأكيد وصرف مواد التعبئة أولاً قبل تسجيل تسوية الهالك');
    END IF;

    -- Check packaging waste from shipment returns first
    SELECT 
        COALESCE(SUM(
            COALESCE((item->>'damaged_cartons')::numeric, 0) * COALESCE((item->>'carton_unit_cost')::numeric, 0)
        ), 0),
        COALESCE(SUM(COALESCE((item->>'damaged_cartons')::numeric, 0)), 0)
    INTO v_return_pkg_waste, v_return_damaged_cartons
    FROM public.export_shipment_returns esr
    LEFT JOIN LATERAL jsonb_array_elements(COALESCE(esr.raw_data->'items', '[]'::jsonb)) AS item ON true
    WHERE (
        (item->>'packing_order_id')::bigint = p_packing_order_id
        OR (
            (item->>'packing_order_id') IS NULL 
            AND esr.shipment_id IN (
                SELECT shipment_id FROM public.export_shipment_items WHERE packing_order_id = p_packing_order_id
            )
        )
    );

    IF v_return_pkg_waste > 0 THEN
        v_tot_pkg_waste := v_return_pkg_waste;
    ELSE
        BEGIN
            v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
            IF jsonb_typeof(v_notes) = 'string' THEN
                v_notes := (v_notes #>> '{}')::jsonb;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_notes := '{}'::jsonb;
        END;

        -- Extract or compute packaging waste cost
        v_tot_pkg_waste := COALESCE((v_notes->'workflow_stages'->'packaging'->>'pkg_waste_cost')::numeric, 0);

        IF v_tot_pkg_waste = 0 THEN
            v_mat_waste_pct := COALESCE(
                (v_notes->>'material_waste_percent')::numeric, 
                (v_notes->>'waste_percentage')::numeric, 
                0
            );

            IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
                v_mat_array := v_notes->'materials';
            ELSIF v_notes ? 'material_items' AND jsonb_typeof(v_notes->'material_items') = 'array' THEN
                v_mat_array := v_notes->'material_items';
            END IF;

            IF jsonb_array_length(v_mat_array) > 0 THEN
                FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_mat_array) LOOP
                    v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE(
                        (v_m_el->>'total')::numeric,
                        (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) *
                         COALESCE((v_m_el->>'unit_cost')::numeric, 0))
                    );
                END LOOP;
            END IF;

            IF v_tot_pkg_drawn = 0 THEN
                v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
                IF v_mat_waste_pct > 0 THEN
                    v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 4);
                END IF;
            END IF;

            v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 4);
        END IF;
    END IF;

    IF v_tot_pkg_waste <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'لا يوجد هالك مواد تعبئة مسجل لهذا الأمر للتسوية');
    END IF;

    -- Calculate already settled waste
    SELECT COALESCE(SUM(amount), 0) INTO v_already_settled
    FROM public.packing_order_waste_settlements
    WHERE packing_order_id = p_packing_order_id;

    v_unsettled := GREATEST(0, ROUND(v_tot_pkg_waste - v_already_settled, 4));

    -- Ceiling validation
    IF p_amount > (v_unsettled + 0.001) THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'قيمة التسوية المطلوبة (' || p_amount || ' ج.م) تتجاوز الهالك غير المسوّى المتبقي (' || v_unsettled || ' ج.م)',
            'unsettled_amount', v_unsettled,
            'total_waste', v_tot_pkg_waste,
            'already_settled', v_already_settled
        );
    END IF;

    IF p_settled_by IS NOT NULL AND p_settled_by <> '' THEN
        BEGIN
            v_uid := p_settled_by::uuid;
        EXCEPTION WHEN OTHERS THEN
            v_uid := auth.uid();
        END;
    ELSE
        v_uid := auth.uid();
    END IF;
    v_company_id := v_order.company_id;
    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM public.journal_entries WHERE id = v_order.packaging_journal_entry_id LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- Insert settlement record
    INSERT INTO public.packing_order_waste_settlements (
        packing_order_id, amount, settlement_date, notes, created_by, created_at, company_id
    ) VALUES (
        p_packing_order_id, p_amount, COALESCE(p_settlement_date, CURRENT_DATE), p_notes, v_uid, now(), v_company_id
    ) RETURNING id INTO v_settlement_id;

    -- Compute new settlement totals
    v_new_settled := v_already_settled + p_amount;
    v_new_unsettled := GREATEST(0, ROUND(v_tot_pkg_waste - v_new_settled, 4));

    IF v_new_unsettled <= 0.001 THEN
        v_status := 'fully_settled';
    ELSE
        v_status := 'partially_settled';
    END IF;

    -- Update order notes metadata
    BEGIN
        v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
        IF jsonb_typeof(v_notes) = 'string' THEN
            v_notes := (v_notes #>> '{}')::jsonb;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_notes := '{}'::jsonb;
    END;

    v_notes := jsonb_set(v_notes, '{waste_settlement_summary}', jsonb_build_object(
        'total_waste_cost', v_tot_pkg_waste,
        'settled_waste_cost', v_new_settled,
        'unsettled_waste_cost', v_new_unsettled,
        'status', v_status,
        'is_from_return', (v_return_pkg_waste > 0),
        'return_damaged_cartons', v_return_damaged_cartons,
        'last_settled_at', now(),
        'settlements_count', (SELECT COUNT(*) FROM public.packing_order_waste_settlements WHERE packing_order_id = p_packing_order_id)
    ), true);

    UPDATE public.packing_orders
    SET notes = v_notes::text,
        updated_at = now()
    WHERE id = p_packing_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'settlement_id', v_settlement_id,
        'settled_amount', p_amount,
        'total_waste_cost', v_tot_pkg_waste,
        'total_settled', v_new_settled,
        'remaining_unsettled', v_new_unsettled,
        'status', v_status,
        'is_from_return', (v_return_pkg_waste > 0),
        'packaging_journal_entry_id', v_order.packaging_journal_entry_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_material_waste(BIGINT, NUMERIC, TEXT, DATE, TEXT) 
    TO authenticated, anon, service_role;
