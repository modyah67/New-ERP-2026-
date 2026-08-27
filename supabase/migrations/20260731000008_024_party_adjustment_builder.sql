-- Migration 024: Phase 2 - Party Adjustment Builder
-- Purpose: SQL Builder for Supplier and Customer Adjustments.

BEGIN;

DO $$
DECLARE
    v_company record;
    v_role_adjustment uuid;
    v_role_ar uuid;
    v_role_ap uuid;
    v_acc_adjustment int;
BEGIN
    -- Ensure ADJUSTMENT role exists
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES (v_company.id, 'ADJUSTMENT', 'General Adjustment', 'General offset for manual party adjustments', true)
        ON CONFLICT (company_id, code) DO NOTHING;
        
        SELECT id INTO v_role_adjustment FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'ADJUSTMENT';
        SELECT id INTO v_role_ar FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AR';
        SELECT id INTO v_role_ap FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AP';
        
        -- Resolve an expense/suspense account for default mapping
        SELECT id INTO v_acc_adjustment FROM public.accounts WHERE (account_type = 'expense' OR account_type = 'equity') AND is_leaf = true AND allow_posting = true LIMIT 1;
        
        -- Map ADJUSTMENT role in default profile
        IF v_acc_adjustment IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            SELECT v_company.id, id, v_role_adjustment, v_acc_adjustment
            FROM public.posting_profiles WHERE company_id = v_company.id AND is_default = true
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO NOTHING;
        END IF;

        -- Seed PARTY_ADJUSTMENT document type
        INSERT INTO public.sys_document_types (code, prefix, name, is_active)
        VALUES ('PARTY_ADJUSTMENT', 'PA', 'Party Manual Adjustment', true)
        ON CONFLICT (code) DO NOTHING;

        -- Add templates for PARTY_ADJUSTMENT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'PARTY_ADJUSTMENT', v_role_adjustment, true, 1),
            (v_company.id, 'PARTY_ADJUSTMENT', v_role_ar, false, 1),
            (v_company.id, 'PARTY_ADJUSTMENT', v_role_ap, false, 1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_build_party_adjustment_journal(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
    v_date DATE;
    v_amount NUMERIC;
    v_party_type TEXT;
    v_party_id UUID;
    v_is_debit BOOLEAN;
    v_description TEXT;
    
    v_journal_payload JSONB;
    v_party_role TEXT;
    v_party_code TEXT;
    
    v_ar_debit NUMERIC := 0;
    v_ar_credit NUMERIC := 0;
    v_ap_debit NUMERIC := 0;
    v_ap_credit NUMERIC := 0;
    v_adj_debit NUMERIC := 0;
    v_adj_credit NUMERIC := 0;
BEGIN
    v_company_id := COALESCE((payload->>'company_id')::UUID, public.get_current_company_id());
    v_date := (payload->>'date')::DATE;
    v_amount := (payload->>'amount')::NUMERIC;
    v_party_type := payload->>'party_type';
    v_party_id := (payload->>'party_id')::UUID;
    v_is_debit := (payload->>'is_debit')::BOOLEAN;
    v_description := payload->>'description';
    
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Could not resolve company_id for Adjustment.';
    END IF;

    IF v_party_type = 'customer' THEN
        v_party_role := 'AR';
        SELECT code INTO v_party_code FROM public.customers WHERE id = v_party_id;
        
        IF v_is_debit THEN
            -- Debit Customer (AR increases), Credit Adjustment
            v_ar_debit := v_amount;
            v_adj_credit := v_amount;
            -- Customer owes us more (balance increases)
            UPDATE public.customers SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amount WHERE id = v_party_id;
        ELSE
            -- Credit Customer (AR decreases), Debit Adjustment
            v_ar_credit := v_amount;
            v_adj_debit := v_amount;
            -- Customer owes us less (balance decreases)
            UPDATE public.customers SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_amount WHERE id = v_party_id;
        END IF;
        
        v_journal_payload := jsonb_build_object(
            'company_id', v_company_id,
            'document_type', 'PARTY_ADJUSTMENT',
            'posting_date', v_date,
            'reference', v_party_code,
            'description', v_description,
            'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
            'idempotency_key', 'adj_cust_' || v_party_code || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
            'lines', jsonb_build_array(
                jsonb_build_object('role', 'AR', 'debit', v_ar_debit, 'credit', v_ar_credit, 'description', v_description),
                jsonb_build_object('role', 'ADJUSTMENT', 'debit', v_adj_debit, 'credit', v_adj_credit, 'description', v_description)
            )
        );
        
    ELSIF v_party_type = 'supplier' THEN
        v_party_role := 'AP';
        SELECT code INTO v_party_code FROM public.suppliers WHERE id = v_party_id;
        
        IF v_is_debit THEN
            -- Debit Supplier (AP decreases), Credit Adjustment
            v_ap_debit := v_amount;
            v_adj_credit := v_amount;
            -- We owe supplier less (balance decreases)
            UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_amount WHERE id = v_party_id;
        ELSE
            -- Credit Supplier (AP increases), Debit Adjustment
            v_ap_credit := v_amount;
            v_adj_debit := v_amount;
            -- We owe supplier more (balance increases)
            UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amount WHERE id = v_party_id;
        END IF;
        
        v_journal_payload := jsonb_build_object(
            'company_id', v_company_id,
            'document_type', 'PARTY_ADJUSTMENT',
            'posting_date', v_date,
            'reference', v_party_code,
            'description', v_description,
            'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
            'idempotency_key', 'adj_sup_' || v_party_code || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
            'lines', jsonb_build_array(
                jsonb_build_object('role', 'AP', 'debit', v_ap_debit, 'credit', v_ap_credit, 'description', v_description),
                jsonb_build_object('role', 'ADJUSTMENT', 'debit', v_adj_debit, 'credit', v_adj_credit, 'description', v_description)
            )
        );
    END IF;
    
    RETURN public.rpc_post_journal(v_journal_payload);
END;
$$;

COMMIT;
