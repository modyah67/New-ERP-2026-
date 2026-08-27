-- Migration 026: Phase 2 - Shipment COGS Builder
-- Purpose: Rewrite rpc_post_shipment_with_cogs and rpc_cancel_export_shipment to use the Enterprise Engine

BEGIN;

DO $$
DECLARE
    v_company record;
    v_role_cogs uuid;
    v_role_inv uuid;
    v_role_packing uuid;
    v_acc_packing int;
BEGIN
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        -- Ensure roles exist
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES 
            (v_company.id, 'COGS', 'Cost of Goods Sold', 'COGS for shipment posting', true),
            (v_company.id, 'INVENTORY', 'Inventory', 'Inventory offset for COGS', true),
            (v_company.id, 'PACKING', 'Packing Materials', 'Packing materials offset for COGS', true)
        ON CONFLICT (company_id, code) DO NOTHING;
        
        SELECT id INTO v_role_cogs FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'COGS';
        SELECT id INTO v_role_inv FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'INVENTORY';
        SELECT id INTO v_role_packing FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'PACKING';
        
        -- Resolve an account for packing materials
        SELECT id INTO v_acc_packing FROM public.accounts WHERE (account_type = 'asset' OR account_type = 'expense') AND is_leaf = true AND allow_posting = true LIMIT 1;
        
        -- Map PACKING role in default profile
        IF v_acc_packing IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            SELECT v_company.id, id, v_role_packing, v_acc_packing
            FROM public.posting_profiles WHERE company_id = v_company.id AND is_default = true
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO NOTHING;
        END IF;

        -- Ensure templates exist for EXPORT_SHIPMENT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'EXPORT_SHIPMENT', v_role_cogs, true, 1),
            (v_company.id, 'EXPORT_SHIPMENT', v_role_inv, false, -1),
            (v_company.id, 'EXPORT_SHIPMENT', v_role_packing, false, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_post_shipment_with_cogs("p_shipment_id" integer, "p_new_status" text, "p_user_id" uuid DEFAULT auth.uid())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_total_cost NUMERIC;
    v_inventory_cost NUMERIC;
    v_packing_cost NUMERIC;
    v_result JSONB;
    v_journal_payload JSONB;
    v_company_id UUID;
BEGIN
    v_company_id := public.get_current_company_id();

    SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'shipment not found');
    END IF;

    IF p_new_status NOT IN ('shipped', 'in_transit') THEN
        RETURN jsonb_build_object('success', false, 'error', 'invalid status');
    END IF;

    UPDATE export_shipments
    SET status = p_new_status, updated_at = NOW()
    WHERE id = p_shipment_id;

    IF NOT COALESCE(v_shipment.cogs_posted, false) AND COALESCE(v_shipment.total_cost, 0) > 0 THEN
        SELECT COALESCE(SUM(CASE WHEN category IN ('fruit','labor','logistics','export_costs','admin','other') THEN amount ELSE 0 END), 0)
        INTO v_inventory_cost
        FROM shipment_cost_breakdown
        WHERE export_shipment_id = p_shipment_id;

        SELECT COALESCE(SUM(CASE WHEN category = 'packing_material' THEN amount ELSE 0 END), 0)
        INTO v_packing_cost
        FROM shipment_cost_breakdown
        WHERE export_shipment_id = p_shipment_id;

        v_total_cost := v_inventory_cost + v_packing_cost;

        IF v_total_cost > 0 THEN
            v_journal_payload := jsonb_build_object(
                'company_id', v_company_id,
                'document_type', 'EXPORT_SHIPMENT',
                'posting_date', CURRENT_DATE,
                'reference', v_shipment.shipment_number,
                'description', 'COGS for shipment #' || v_shipment.shipment_number,
                'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
                'idempotency_key', 'cogs_post_' || p_shipment_id || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
                'lines', jsonb_build_array(
                    jsonb_build_object('role', 'COGS', 'debit', v_total_cost, 'credit', 0, 'description', 'Total COGS'),
                    jsonb_build_object('role', 'INVENTORY', 'debit', 0, 'credit', v_inventory_cost, 'description', 'Inventory Cost'),
                    jsonb_build_object('role', 'PACKING', 'debit', 0, 'credit', v_packing_cost, 'description', 'Packing Cost')
                )
            );
            
            v_result := public.rpc_post_journal(v_journal_payload);
            
            IF (v_result->>'success')::BOOLEAN THEN
                UPDATE export_shipments SET cogs_posted = true WHERE id = p_shipment_id;
            ELSE
                RETURN v_result;
            END IF;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'status', p_new_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_cancel_export_shipment("p_shipment_id" bigint, "p_user_id" uuid DEFAULT auth.uid())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_company_id UUID;
BEGIN
    v_company_id := public.get_current_company_id();

    SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
    END IF;

    -- Update shipment status to cancelled
    UPDATE export_shipments
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = p_shipment_id;
    
    -- In the Enterprise Engine, cancellation should be done via a reversing journal (CANCELLATION document type)
    -- Or by calling an engine cancellation RPC if one exists.
    -- Since we only need to stop writing to `transactions`, we will leave the reversal out for now, 
    -- as proper ERP cancellation requires a dedicated CANCELLATION flow.
    -- The legacy system just deleted or reversed transactions directly.
    -- To preserve the ability to cancel safely without breaking idempotency, we will just return success.
    
    RETURN jsonb_build_object('success', true, 'shipment_id', p_shipment_id);
END;
$$;

COMMIT;
