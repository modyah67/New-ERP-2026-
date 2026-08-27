-- Migration 011 v2: Enterprise Unified Posting Engine (Production Ready)
-- Purpose: Orchestrator RPC for posting all financial journals.
-- Status: Schema-Driven, Idempotent, Backward Compatible, Enterprise Grade.

BEGIN;

-- =================================================================================
-- 1. SCHEMA EXTENSIONS (Backward Compatible)
-- =================================================================================
DO $$
BEGIN
    -- 1a. Preserve forward compatibility for dimensions
    ALTER TABLE IF EXISTS public.account_ledger_entries 
        ADD COLUMN IF NOT EXISTS dimensions JSONB DEFAULT '{}'::jsonb;
    
    ALTER TABLE IF EXISTS public.account_ledger_entries 
        ADD COLUMN IF NOT EXISTS amount_in_base_currency NUMERIC DEFAULT 0;

    -- 1b. Preserve historical exchange rates securely
    ALTER TABLE IF EXISTS public.journal_entries 
        ADD COLUMN IF NOT EXISTS currency_snapshot JSONB;

    -- 1c. Repair Tax Engine (Missing from 010)
    ALTER TABLE IF EXISTS public.tax_codes 
        ADD COLUMN IF NOT EXISTS posting_role_id UUID REFERENCES public.posting_account_roles(id) ON DELETE RESTRICT;

    -- 1d. Idempotency Layer
    ALTER TABLE IF EXISTS public.journal_entries 
        ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
    
    CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_idempotency 
        ON public.journal_entries(company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
END $$;

-- 1e. Seed VAT Roles
DO $$
DECLARE
    v_company_id UUID;
    v_vat_input_id UUID;
    v_vat_output_id UUID;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies ORDER BY created_at ASC LIMIT 1;
    IF v_company_id IS NOT NULL THEN
        -- Seed VAT Roles
        INSERT INTO public.posting_account_roles (company_id, code, name, is_system) 
        VALUES (v_company_id, 'VAT_INPUT', 'VAT Input', true) 
        ON CONFLICT (company_id, code) DO NOTHING RETURNING id INTO v_vat_input_id;
        
        INSERT INTO public.posting_account_roles (company_id, code, name, is_system) 
        VALUES (v_company_id, 'VAT_OUTPUT', 'VAT Output', true) 
        ON CONFLICT (company_id, code) DO NOTHING RETURNING id INTO v_vat_output_id;
    END IF;
END $$;


-- =================================================================================
-- 2. ERROR HANDLING (Enterprise Exceptions)
-- =================================================================================
CREATE OR REPLACE FUNCTION public.fn_raise_posting_error(
    p_code TEXT, 
    p_message TEXT, 
    p_details TEXT DEFAULT '{}', 
    p_hint TEXT DEFAULT '', 
    p_severity TEXT DEFAULT 'ERROR',
    p_request_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    RAISE EXCEPTION 'POSTING_ERROR' 
    USING ERRCODE = 'P0001', 
    DETAIL = jsonb_build_object(
        'success', false,
        'code', p_code, 
        'message', p_message, 
        'details', p_details,
        'hint', p_hint,
        'severity', p_severity,
        'timestamp', now(),
        'request_id', p_request_id,
        'transaction_id', txid_current()
    )::text;
END;
$$;


-- =================================================================================
-- 3. VALIDATION FUNCTIONS
-- =================================================================================

CREATE OR REPLACE FUNCTION public.fn_validate_company_active(p_company_id UUID, p_request_id TEXT DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE id = p_company_id) THEN
        PERFORM public.fn_raise_posting_error('COMPANY_INVALID', 'Company does not exist or is inactive.', '{}', 'Provide a valid company_id', 'ERROR', p_request_id);
    END IF;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_fiscal_year(p_company_id UUID, p_date DATE, p_request_id TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_fy RECORD;
BEGIN
    SELECT id, name, status INTO v_fy FROM public.fiscal_years 
    WHERE company_id = p_company_id AND p_date BETWEEN start_date AND end_date LIMIT 1;
    
    IF NOT FOUND THEN
        PERFORM public.fn_raise_posting_error('FY_MISSING', 'No fiscal year found for the posting date.', p_date::text, 'Check fiscal year dates', 'ERROR', p_request_id);
    END IF;
    
    IF v_fy.status IN ('CLOSED', 'ARCHIVED') THEN
        PERFORM public.fn_raise_posting_error('FY_CLOSED', 'The fiscal year is closed.', v_fy.name, 'Cannot post into a closed fiscal year', 'ERROR', p_request_id);
    END IF;
    
    RETURN jsonb_build_object('fiscal_year_id', v_fy.id, 'name', v_fy.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_period_open(p_company_id UUID, p_fy_id BIGINT, p_date DATE, p_request_id TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_period RECORD;
BEGIN
    SELECT id, period_name, status INTO v_period FROM public.accounting_periods 
    WHERE company_id = p_company_id AND fiscal_year_id = p_fy_id AND p_date BETWEEN start_date AND end_date LIMIT 1;
    
    IF NOT FOUND THEN
        PERFORM public.fn_raise_posting_error('PERIOD_MISSING', 'No accounting period found for the posting date.', p_date::text, 'Check accounting period dates', 'ERROR', p_request_id);
    END IF;
    
    IF v_period.status != 'OPEN' THEN
        PERFORM public.fn_raise_posting_error('PERIOD_CLOSED', 'Accounting Period is closed.', v_period.period_name, 'Open the period before posting', 'ERROR', p_request_id);
    END IF;
    
    RETURN jsonb_build_object('period_id', v_period.id, 'period_name', v_period.period_name);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_document_type(p_doc_type TEXT, p_request_id TEXT DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.sys_document_types WHERE code = p_doc_type AND is_active = true) THEN
        PERFORM public.fn_raise_posting_error('DOC_TYPE_INVALID', 'Document type is missing or inactive.', p_doc_type, 'Ensure document_type_code exists', 'ERROR', p_request_id);
    END IF;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_posting_profile(p_company_id UUID, p_profile_id UUID, p_request_id TEXT DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.posting_profiles 
        WHERE company_id = p_company_id AND id = p_profile_id AND is_active = true 
        ORDER BY id FOR SHARE
    ) THEN
        PERFORM public.fn_raise_posting_error('PROFILE_INVALID', 'Posting profile is missing or inactive.', p_profile_id::text, 'Check posting profile settings', 'ERROR', p_request_id);
    END IF;
    RETURN true;
END;
$$;


-- =================================================================================
-- 4. BULK RESOLUTION FUNCTIONS
-- =================================================================================

CREATE OR REPLACE FUNCTION public.fn_resolve_posting_accounts_bulk(p_company_id UUID, p_profile_id UUID, p_role_codes JSONB, p_request_id TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_missing TEXT;
    v_invalid_acc RECORD;
BEGIN
    -- Bulk resolve and lock configuration rows safely to prevent deadlocks
    WITH requested_roles AS (
        SELECT DISTINCT value::text AS role_code FROM jsonb_array_elements_text(p_role_codes) AS value
    ),
    resolved AS (
        SELECT rr.role_code, pr.account_id, a.is_active, a.allow_posting, a.is_leaf
        FROM requested_roles rr
        JOIN public.posting_account_roles r ON r.company_id = p_company_id AND r.code = rr.role_code
        JOIN public.posting_profile_rules pr ON pr.company_id = p_company_id AND pr.posting_profile_id = p_profile_id AND pr.role_id = r.id
        JOIN public.accounts a ON a.id = pr.account_id
        WHERE pr.valid_from <= CURRENT_DATE AND (pr.valid_to IS NULL OR pr.valid_to >= CURRENT_DATE)
        ORDER BY r.id, pr.id
        FOR SHARE OF r, pr
    )
    SELECT jsonb_object_agg(role_code, jsonb_build_object('account_id', account_id, 'is_active', is_active, 'allow_posting', allow_posting, 'is_leaf', is_leaf)) 
    INTO v_result FROM resolved;
    
    v_result := COALESCE(v_result, '{}'::jsonb);

    -- Check if any roles failed to resolve
    SELECT value::text INTO v_missing
    FROM jsonb_array_elements_text(p_role_codes) AS value
    WHERE NOT (v_result ? value::text)
    LIMIT 1;

    IF v_missing IS NOT NULL THEN
        PERFORM public.fn_raise_posting_error('ACCOUNT_RESOLUTION_FAILED', 'Could not resolve GL account for posting role.', v_missing, 'Add account rule for role', 'ERROR', p_request_id);
    END IF;

    -- Validate target accounts
    FOR v_invalid_acc IN 
        SELECT key AS role_code, value
        FROM jsonb_each(v_result)
        WHERE (value->>'is_active')::boolean = false 
           OR (value->>'is_leaf')::boolean = false 
           OR (value->>'allow_posting')::boolean = false
    LOOP
        PERFORM public.fn_raise_posting_error(
            'ACCOUNT_INVALID_STATE', 
            'Target account is not allowed for posting.', 
            'Role: ' || v_invalid_acc.role_code || ' Account ID: ' || (v_invalid_acc.value->>'account_id'),
            'Ensure target account is a leaf node, active, and allows posting',
            'ERROR',
            p_request_id
        );
    END LOOP;

    RETURN v_result;
END;
$$;


-- =================================================================================
-- 5. UNIFIED POSTING ENGINE (RPC)
-- =================================================================================

CREATE OR REPLACE FUNCTION public.rpc_post_journal(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Request Variables
    v_company_id UUID;
    v_profile_id UUID;
    v_doc_type TEXT;
    v_date DATE;
    v_ref TEXT;
    v_desc TEXT;
    v_currency TEXT;
    v_exchange_rate NUMERIC;
    v_currency_snapshot JSONB;
    v_dimensions JSONB;
    v_created_by UUID;
    v_idempotency_key TEXT;
    
    -- Engine State
    v_fy_info JSONB;
    v_period_info JSONB;
    v_journal_id BIGINT;
    v_entry_number TEXT;
    
    -- Processing
    v_lines JSONB;
    v_line JSONB;
    v_taxes JSONB;
    v_tax JSONB;
    
    v_norm_lines JSONB := '[]'::jsonb;
    v_roles_needed JSONB := '[]'::jsonb;
    v_resolved_accounts JSONB;
    
    v_total_debit NUMERIC := 0;
    v_total_credit NUMERIC := 0;
    
    v_role TEXT;
    v_debit NUMERIC;
    v_credit NUMERIC;
    v_acc_id BIGINT;
    
    -- Tax Resolution
    v_tax_rate NUMERIC;
    v_tax_role_id UUID;
    v_tax_role_code TEXT;
    v_tax_amount NUMERIC;
    
    -- Timing
    v_start_time TIMESTAMPTZ;
BEGIN
    v_start_time := clock_timestamp();

    -- 1. Extract Header
    v_company_id := (payload->>'company_id')::UUID;
    v_profile_id := (payload->>'posting_profile_id')::UUID;
    v_doc_type := payload->>'document_type';
    v_date := (payload->>'posting_date')::DATE;
    v_ref := payload->>'reference';
    v_desc := payload->>'description';
    v_currency := COALESCE(payload->'currency'->>'code', 'EGP');
    v_exchange_rate := COALESCE((payload->'currency'->>'exchange_rate')::NUMERIC, 1.0);
    v_currency_snapshot := COALESCE(payload->'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0));
    v_dimensions := COALESCE(payload->'dimensions', '{}'::jsonb);
    v_created_by := COALESCE((payload->>'created_by')::UUID, auth.uid());
    v_idempotency_key := payload->>'idempotency_key';
    
    v_lines := COALESCE(payload->'lines', '[]'::jsonb);
    v_taxes := COALESCE(payload->'taxes', '[]'::jsonb);

    -- 2. Idempotency Layer (Fast Exit)
    IF v_idempotency_key IS NOT NULL THEN
        SELECT id, entry_number INTO v_journal_id, v_entry_number
        FROM public.journal_entries
        WHERE company_id = v_company_id AND idempotency_key = v_idempotency_key 
        LIMIT 1;
        
        IF FOUND THEN
            RETURN jsonb_build_object(
                'success', true,
                'journal_id', v_journal_id,
                'journal_number', v_entry_number,
                'posting_status', 'POSTED_IDEMPOTENT',
                'warnings', '[]'::jsonb,
                'errors', '[]'::jsonb,
                'execution_time_ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))
            );
        END IF;
    END IF;

    IF jsonb_array_length(v_lines) = 0 THEN
        PERFORM public.fn_raise_posting_error('EMPTY_JOURNAL', 'A journal must contain at least one line.', '{}', 'Provide journal lines in payload', 'ERROR', v_idempotency_key);
    END IF;

    -- 3. Core Validation
    PERFORM public.fn_validate_company_active(v_company_id, v_idempotency_key);
    v_fy_info := public.fn_validate_fiscal_year(v_company_id, v_date, v_idempotency_key);
    v_period_info := public.fn_validate_period_open(v_company_id, (v_fy_info->>'fiscal_year_id')::BIGINT, v_date, v_idempotency_key);
    PERFORM public.fn_validate_document_type(v_doc_type, v_idempotency_key);
    PERFORM public.fn_validate_posting_profile(v_company_id, v_profile_id, v_idempotency_key);

    -- 4. Normalize Lines & Collect Roles
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_lines)
    LOOP
        v_role := v_line->>'role';
        v_debit := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit := COALESCE((v_line->>'credit')::NUMERIC, 0);
        
        IF v_role IS NULL THEN
            PERFORM public.fn_raise_posting_error('ROLE_MISSING', 'Journal line is missing a posting role code.', '{}', 'Specify a posting role for each line', 'ERROR', v_idempotency_key);
        END IF;

        -- Normalize neg values
        IF v_debit < 0 THEN
            v_credit := v_credit + abs(v_debit);
            v_debit := 0;
        END IF;
        IF v_credit < 0 THEN
            v_debit := v_debit + abs(v_credit);
            v_credit := 0;
        END IF;
        
        v_norm_lines := v_norm_lines || jsonb_build_object(
            'role', v_role, 
            'debit', v_debit, 
            'credit', v_credit, 
            'description', COALESCE(v_line->>'description', v_desc)
        );
        v_roles_needed := v_roles_needed || to_jsonb(v_role);
    END LOOP;

    -- 5. Historical Tax Engine (Timeline Aware)
    FOR v_tax IN SELECT * FROM jsonb_array_elements(v_taxes)
    LOOP
        SELECT tr.rate, tc.posting_role_id INTO v_tax_rate, v_tax_role_id
        FROM public.tax_codes tc
        JOIN public.tax_rates tr ON tr.tax_code_id = tc.id
        WHERE tc.company_id = v_company_id 
          AND tc.code = v_tax->>'tax_code' 
          AND tc.is_active = true
          AND v_date >= tr.effective_from 
          AND (tr.effective_to IS NULL OR v_date <= tr.effective_to)
        ORDER BY tc.id, tr.id FOR SHARE
        LIMIT 1;
        
        IF NOT FOUND THEN
            PERFORM public.fn_raise_posting_error('TAX_NOT_FOUND', 'Tax code or valid rate not found for the given date.', v_tax->>'tax_code', 'Ensure tax rate is effective on posting_date', 'ERROR', v_idempotency_key);
        END IF;
        IF v_tax_role_id IS NULL THEN
            PERFORM public.fn_raise_posting_error('TAX_ROLE_MISSING', 'Tax code missing posting role.', v_tax->>'tax_code', 'Link a posting role to the tax code', 'ERROR', v_idempotency_key);
        END IF;
        
        SELECT code INTO v_tax_role_code FROM public.posting_account_roles WHERE id = v_tax_role_id;
        
        v_tax_amount := (v_tax->>'base_amount')::NUMERIC * v_tax_rate;
        
        IF (v_tax->>'sign') = 'DEBIT' THEN
            v_norm_lines := v_norm_lines || jsonb_build_object('role', v_tax_role_code, 'debit', v_tax_amount, 'credit', 0, 'description', 'Tax ' || (v_tax->>'tax_code'));
        ELSE
            v_norm_lines := v_norm_lines || jsonb_build_object('role', v_tax_role_code, 'debit', 0, 'credit', v_tax_amount, 'description', 'Tax ' || (v_tax->>'tax_code'));
        END IF;
        
        v_roles_needed := v_roles_needed || to_jsonb(v_tax_role_code);
    END LOOP;

    -- 6. Bulk Resolve & Validate Accounts via Config Layer
    v_resolved_accounts := public.fn_resolve_posting_accounts_bulk(v_company_id, v_profile_id, v_roles_needed, v_idempotency_key);

    -- 7. Calculate Totals & Validate Balanced Journal BEFORE Inserts
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_norm_lines)
    LOOP
        v_total_debit := v_total_debit + (v_line->>'debit')::NUMERIC;
        v_total_credit := v_total_credit + (v_line->>'credit')::NUMERIC;
    END LOOP;

    IF ROUND(v_total_debit, 4) != ROUND(v_total_credit, 4) THEN
        PERFORM public.fn_raise_posting_error('JOURNAL_UNBALANCED', 'Total debits do not equal total credits.', 'Debit: ' || v_total_debit || ' Credit: ' || v_total_credit, 'Ensure debits equal credits before posting', 'ERROR', v_idempotency_key);
    END IF;

    -- 8. Generate Gapless Document Sequence (only if all validations pass)
    v_entry_number := public.fn_get_next_sequence(v_company_id, v_doc_type, (v_fy_info->>'fiscal_year_id')::INT, NULL);

    -- 9. Insert Header (Legacy Compat & Idempotent)
    INSERT INTO public.journal_entries (
        company_id, entry_number, entry_date, description, status, source_type, source_id, created_by, currency_snapshot, idempotency_key
    ) VALUES (
        v_company_id, v_entry_number, v_date, v_desc, 'posted', v_doc_type, v_ref, v_created_by, v_currency_snapshot, v_idempotency_key
    ) RETURNING id INTO v_journal_id;

    -- 10. Insert Ledger Lines (Absolute Amount in Base Currency)
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_norm_lines)
    LOOP
        v_role := v_line->>'role';
        v_debit := (v_line->>'debit')::NUMERIC;
        v_credit := (v_line->>'credit')::NUMERIC;
        v_acc_id := (v_resolved_accounts->v_role->>'account_id')::BIGINT;
        
        IF v_debit > 0 OR v_credit > 0 THEN
            INSERT INTO public.account_ledger_entries (
                company_id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, dimensions
            ) VALUES (
                v_company_id, v_journal_id, v_acc_id, v_debit, v_credit, v_currency, (v_debit + v_credit) * v_exchange_rate, v_line->>'description', v_dimensions
            );
        END IF;
    END LOOP;

    -- 11. Return Structured Enterprise Result
    RETURN jsonb_build_object(
        'success', true,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number,
        'posting_status', 'POSTED',
        'warnings', '[]'::jsonb,
        'errors', '[]'::jsonb,
        'execution_time_ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))
    );

EXCEPTION WHEN OTHERS THEN
    -- If it's our custom enterprise error (P0001), bubble it up intact
    IF SQLSTATE = 'P0001' THEN
        RAISE;
    END IF;
    
    -- Otherwise, wrap generic SQL errors in our enterprise format
    PERFORM public.fn_raise_posting_error('SYSTEM_ERROR', SQLERRM, SQLSTATE, 'Check database logs', 'FATAL', v_idempotency_key);
END;
$$;

COMMIT;
