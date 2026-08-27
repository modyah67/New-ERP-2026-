-- Migration 030: Fix Builder Idempotency
-- Purpose: Remove runtime INSERTs into config tables from builder functions.
--          Replace with idempotent ON CONFLICT + lookup patterns.
--
-- Affected functions:
--   1. rpc_build_manual_journal  (was inserting into posting_profiles, posting_profile_rules)
--   2. rpc_build_multi_line_journal (was inserting into posting_profiles, posting_account_roles,
--      posting_profile_rules, document_posting_templates)

BEGIN;

-- =============================================================================
-- FIX 1: rpc_build_manual_journal
-- Problem: INSERT INTO posting_profiles without ON CONFLICT fails on second call
--          with same idempotency_key (duplicate key on company_id + code).
-- Fix: ON CONFLICT DO NOTHING + SELECT for profile, ON CONFLICT DO UPDATE for rules.
-- =============================================================================

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

    -- Idempotent profile provisioning: create if not exists, then lookup
    INSERT INTO public.posting_profiles (company_id, code, name, description, is_default, is_active)
    VALUES (v_company_id, 'MANUAL_' || v_idempotency_key, 'Manual Profile ' || v_idempotency_key, 'Dynamic profile for manual journal', false, true)
    ON CONFLICT (company_id, code) DO NOTHING;

    SELECT id INTO v_profile_id
    FROM public.posting_profiles
    WHERE company_id = v_company_id AND code = 'MANUAL_' || v_idempotency_key;

    -- Idempotent rule mapping: upsert to handle re-execution
    INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
    VALUES 
        (v_company_id, v_profile_id, v_role_debit, v_debit_account_id),
        (v_company_id, v_profile_id, v_role_credit, v_credit_account_id)
    ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;

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

-- =============================================================================
-- FIX 2: rpc_build_multi_line_journal
-- Problem: INSERT into posting_profiles, posting_account_roles,
--          posting_profile_rules, document_posting_templates at runtime
--          without ON CONFLICT. Fails on re-execution.
-- Fix: ON CONFLICT DO NOTHING/UPDATE + SELECT for all config INSERTs.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_build_multi_line_journal("payload" jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
    v_profile_id UUID;
    v_role_id UUID;
    v_lines JSONB;
    v_line JSONB;
    v_journal_lines JSONB := '[]'::jsonb;
    v_account_id UUID;
    v_debit NUMERIC;
    v_credit NUMERIC;
    v_description TEXT;
    v_index INT := 0;
    v_role_code TEXT;
    v_result JSONB;
    v_date TEXT;
    v_ref_id TEXT;
    v_ref_type TEXT;
    v_profile_code TEXT;
BEGIN
    v_company_id := public.get_current_company_id();
    
    -- Idempotent profile provisioning
    v_profile_id := gen_random_uuid();
    v_profile_code := 'MULTI_' || v_profile_id;

    INSERT INTO public.posting_profiles (
        id, company_id, code, name, is_default, valid_from
    ) VALUES (
        v_profile_id, v_company_id, v_profile_code, 'Multi Line Profile ' || v_profile_id, false, CURRENT_DATE
    ) ON CONFLICT (company_id, code) DO NOTHING;

    SELECT id INTO v_profile_id
    FROM public.posting_profiles
    WHERE company_id = v_company_id AND code = v_profile_code;

    v_lines := payload->'lines';
    v_date := payload->>'date';
    v_ref_id := payload->>'reference_id';
    v_ref_type := payload->>'reference_type';
    
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::UUID;
        v_debit := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_description := v_line->>'description';
        v_role_code := 'MULTI_ROLE_' || v_index;

        -- Idempotent role creation
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES (v_company_id, v_role_code, v_role_code, 'Dynamic Role for Multi Line', true)
        ON CONFLICT (company_id, code) DO NOTHING;

        SELECT id INTO v_role_id
        FROM public.posting_account_roles
        WHERE company_id = v_company_id AND code = v_role_code;

        -- Idempotent rule mapping
        INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
        VALUES (v_company_id, v_profile_id, v_role_id, v_account_id)
        ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;

        -- Idempotent template requirement
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES (v_company_id, 'MANUAL_JOURNAL', v_role_id, false, 1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- Append to journal lines
        v_journal_lines := v_journal_lines || jsonb_build_object(
            'role', v_role_code,
            'debit', v_debit,
            'credit', v_credit,
            'description', v_description
        );

        v_index := v_index + 1;
    END LOOP;

    -- Send to Post Journal
    v_result := public.rpc_post_journal(
        jsonb_build_object(
            'company_id', v_company_id,
            'document_type', 'MANUAL_JOURNAL',
            'posting_profile_id', v_profile_id,
            'posting_date', v_date,
            'reference', v_ref_type || '_' || v_ref_id,
            'description', payload->>'description',
            'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
            'idempotency_key', 'MULTI_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
            'lines', v_journal_lines
        )
    );

    RETURN v_result;
END;
$$;

COMMIT;
