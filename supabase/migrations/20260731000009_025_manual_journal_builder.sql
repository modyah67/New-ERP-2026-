-- Migration 025: Phase 2 - Manual Journal Builder
-- Purpose: SQL Builder for arbitrary Account-to-Account Manual Journals.
-- It dynamically provisions a Manual Posting Profile to satisfy rpc_post_journal's role requirement.

BEGIN;

DO $$
DECLARE
    v_company record;
BEGIN
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        -- Ensure MANUAL_DEBIT and MANUAL_CREDIT roles exist
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES 
            (v_company.id, 'MANUAL_DEBIT', 'Manual Debit', 'Dynamic role for manual debit', true),
            (v_company.id, 'MANUAL_CREDIT', 'Manual Credit', 'Dynamic role for manual credit', true)
        ON CONFLICT (company_id, code) DO NOTHING;
        
        -- Seed MANUAL_JOURNAL document type
        INSERT INTO public.sys_document_types (code, prefix, name, is_active)
        VALUES ('MANUAL_JOURNAL', 'MJ', 'Manual Journal Entry', true)
        ON CONFLICT (code) DO NOTHING;

        -- Add templates for MANUAL_JOURNAL
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        SELECT v_company.id, 'MANUAL_JOURNAL', id, true, 1
        FROM public.posting_account_roles 
        WHERE company_id = v_company.id AND code IN ('MANUAL_DEBIT', 'MANUAL_CREDIT')
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_build_manual_journal(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
    v_date DATE;
    v_amount NUMERIC;
    v_debit_account_id BIGINT;
    v_credit_account_id BIGINT;
    v_description TEXT;
    
    v_journal_payload JSONB;
    v_role_debit UUID;
    v_role_credit UUID;
    v_profile_id UUID;
    v_idempotency_key TEXT;
BEGIN
    v_company_id := COALESCE((payload->>'company_id')::UUID, public.get_current_company_id());
    v_date := (payload->>'date')::DATE;
    v_amount := (payload->>'amount')::NUMERIC;
    v_debit_account_id := (payload->>'debit_account_id')::BIGINT;
    v_credit_account_id := (payload->>'credit_account_id')::BIGINT;
    v_description := payload->>'description';
    v_idempotency_key := COALESCE(payload->>'idempotency_key', 'man_jnl_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT);
    
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Could not resolve company_id for Manual Journal.';
    END IF;

    SELECT id INTO v_role_debit FROM public.posting_account_roles WHERE company_id = v_company_id AND code = 'MANUAL_DEBIT';
    SELECT id INTO v_role_credit FROM public.posting_account_roles WHERE company_id = v_company_id AND code = 'MANUAL_CREDIT';

    -- Create a dynamic profile for this specific manual journal
    INSERT INTO public.posting_profiles (company_id, code, name, description, is_default, is_active)
    VALUES (v_company_id, 'MANUAL_' || v_idempotency_key, 'Manual Profile ' || v_idempotency_key, 'Dynamic profile for manual journal', false, true)
    RETURNING id INTO v_profile_id;

    -- Map the requested accounts to the roles in this dynamic profile
    INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
    VALUES 
        (v_company_id, v_profile_id, v_role_debit, v_debit_account_id),
        (v_company_id, v_profile_id, v_role_credit, v_credit_account_id);

    -- Generate Journal Payload
    v_journal_payload := jsonb_build_object(
        'company_id', v_company_id,
        'posting_profile_id', v_profile_id,
        'document_type', 'MANUAL_JOURNAL',
        'posting_date', v_date,
        'reference', 'MANUAL',
        'description', v_description,
        'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
        'idempotency_key', v_idempotency_key,
        'lines', jsonb_build_array(
            jsonb_build_object('role', 'MANUAL_DEBIT', 'debit', v_amount, 'credit', 0, 'description', v_description),
            jsonb_build_object('role', 'MANUAL_CREDIT', 'debit', 0, 'credit', v_amount, 'description', v_description)
        )
    );
    
    RETURN public.rpc_post_journal(v_journal_payload);
END;
$$;

COMMIT;
