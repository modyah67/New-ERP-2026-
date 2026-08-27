-- Migration 029: Phase 2 - Multi Line Journal Builder
-- Purpose: Provide a generic builder for legacy multi-line journals (like Fiscal Year Closing)

BEGIN;

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
BEGIN
    v_company_id := public.get_current_company_id();
    
    -- Dynamically provision a Posting Profile for this specific manual entry
    v_profile_id := gen_random_uuid();
    
    INSERT INTO public.posting_profiles (
        id, company_id, code, name, is_default, valid_from
    ) VALUES (
        v_profile_id, v_company_id, 'MULTI_' || v_profile_id, 'Multi Line Profile ' || v_profile_id, false, CURRENT_DATE
    );

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

        -- Create Role
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES (v_company_id, v_role_code, v_role_code, 'Dynamic Role for Multi Line', true)
        RETURNING id INTO v_role_id;

        -- Map Role to Account in the specific profile
        INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
        VALUES (v_company_id, v_profile_id, v_role_id, v_account_id);

        -- Add Template requirement
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES (v_company_id, 'MANUAL_JOURNAL', v_role_id, false, 1);

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
