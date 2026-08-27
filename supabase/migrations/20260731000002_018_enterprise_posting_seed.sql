-- Migration 018: Phase 1 - Enterprise Posting Seed and RPC Update
-- Purpose: Seeds the baseline configuration required to make the Enterprise Posting Engine deployable,
--          and updates rpc_post_journal to automatically resolve the posting profile.

BEGIN;

DO $$
DECLARE
    v_company record;
    v_profile_id uuid;
    
    v_role_ar uuid;
    v_role_ap uuid;
    v_role_revenue uuid;
    v_role_cogs uuid;
    v_role_vat_out uuid;
    v_role_vat_in uuid;
    v_role_cash uuid;
    v_role_bank uuid;
    v_role_inv uuid;
    v_role_discount uuid;
    
    v_acc_ar int;
    v_acc_ap int;
    v_acc_rev int;
    v_acc_cogs int;
    v_acc_cash int;
    v_acc_inv int;
BEGIN
    -- 1. Seed Missing Document Types (prefix is NOT NULL — must be provided)
    INSERT INTO public.sys_document_types (code, name, prefix, is_active) VALUES
    ('COST_ALLOCATION', 'Cost Allocation', 'CA', true),
    ('EXPORT_SHIPMENT', 'Export Shipment', 'EXP', true),
    ('CASH_PAYMENT', 'Cash Payment', 'CPAY', true),
    ('CASH_RECEIPT', 'Cash Receipt', 'CREC', true),
    ('PURCHASE_WORKFLOW', 'Purchase Workflow', 'PW', true)
    ON CONFLICT (code) DO NOTHING;

    -- 2. Iterate over all existing companies to seed their default configurations
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        -- Retrieve Role IDs
        SELECT id INTO v_role_ar FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AR';
        SELECT id INTO v_role_ap FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AP';
        SELECT id INTO v_role_revenue FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'REVENUE';
        SELECT id INTO v_role_cogs FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'COGS';
        SELECT id INTO v_role_cash FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'CASH';
        SELECT id INTO v_role_inv FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'INVENTORY';

        -- Dynamically resolve account IDs (based on legacy system conventions)
        SELECT id INTO v_acc_ap FROM public.accounts WHERE (account_code = '20101' OR name = 'الموردون') AND is_leaf = true AND allow_posting = true LIMIT 1;
        SELECT id INTO v_acc_inv FROM public.accounts WHERE (account_code = '10201' OR name = 'مخزن البضائع') AND is_leaf = true AND allow_posting = true LIMIT 1;
        SELECT id INTO v_acc_cash FROM public.accounts WHERE (account_code = '10101' OR name = 'الخزينة') AND is_leaf = true AND allow_posting = true LIMIT 1;
        
        -- Fallbacks if code lookup fails (find by type)
        IF v_acc_ap IS NULL THEN SELECT id INTO v_acc_ap FROM public.accounts WHERE account_type = 'liability' AND is_leaf = true AND allow_posting = true LIMIT 1; END IF;
        IF v_acc_inv IS NULL THEN SELECT id INTO v_acc_inv FROM public.accounts WHERE account_type = 'asset' AND is_leaf = true AND allow_posting = true LIMIT 1; END IF;
        IF v_acc_cash IS NULL THEN SELECT id INTO v_acc_cash FROM public.accounts WHERE account_type = 'asset' AND is_leaf = true AND allow_posting = true LIMIT 1; END IF;
        
        -- Assume similar for AR, REVENUE, COGS
        SELECT id INTO v_acc_ar FROM public.accounts WHERE account_type = 'asset' AND name LIKE '%عملاء%' AND is_leaf = true AND allow_posting = true LIMIT 1;
        SELECT id INTO v_acc_rev FROM public.accounts WHERE account_type = 'revenue' AND is_leaf = true AND allow_posting = true LIMIT 1;
        SELECT id INTO v_acc_cogs FROM public.accounts WHERE account_type = 'expense' AND is_leaf = true AND allow_posting = true LIMIT 1;

        -- Create Default Profile
        INSERT INTO public.posting_profiles (company_id, code, name, description, is_default, is_active)
        VALUES (v_company.id, 'DEFAULT', 'Standard Company Profile', 'Default fallback profile for all postings', true, true)
        ON CONFLICT (company_id, code) DO UPDATE SET is_default = true
        RETURNING id INTO v_profile_id;

        -- Create Profile Rules (Mappings)
        IF v_acc_ap IS NOT NULL AND v_role_ap IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            VALUES (v_company.id, v_profile_id, v_role_ap, v_acc_ap)
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;
        END IF;
        
        IF v_acc_inv IS NOT NULL AND v_role_inv IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            VALUES (v_company.id, v_profile_id, v_role_inv, v_acc_inv)
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;
        END IF;

        IF v_acc_cash IS NOT NULL AND v_role_cash IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            VALUES (v_company.id, v_profile_id, v_role_cash, v_acc_cash)
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;
        END IF;

        IF v_acc_ar IS NOT NULL AND v_role_ar IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            VALUES (v_company.id, v_profile_id, v_role_ar, v_acc_ar)
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;
        END IF;

        IF v_acc_rev IS NOT NULL AND v_role_revenue IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            VALUES (v_company.id, v_profile_id, v_role_revenue, v_acc_rev)
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;
        END IF;

        IF v_acc_cogs IS NOT NULL AND v_role_cogs IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            VALUES (v_company.id, v_profile_id, v_role_cogs, v_acc_cogs)
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO UPDATE SET account_id = EXCLUDED.account_id;
        END IF;

    END LOOP;
END $$;

-- =================================================================================
-- Ensure journal_entry_dimensions table exists (referenced by rpc_post_journal)
-- =================================================================================
CREATE TABLE IF NOT EXISTS public.journal_entry_dimensions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id UUID NOT NULL REFERENCES public.sys_companies(id),
    journal_entry_id BIGINT NOT NULL REFERENCES public.journal_entries(id) ON DELETE CASCADE,
    dimension_key TEXT NOT NULL,
    dimension_value TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_journal_entry_dimensions_journal_id ON public.journal_entry_dimensions(journal_entry_id);

-- =================================================================================
-- Update rpc_post_journal to make posting_profile_id optional and auto-resolve
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

    -- 1.5. Auto-Resolve Posting Profile
    IF v_profile_id IS NULL THEN
        -- Fallback to Company Default Profile
        SELECT id INTO v_profile_id
        FROM public.posting_profiles
        WHERE company_id = v_company_id AND is_default = true
        LIMIT 1;

        IF v_profile_id IS NULL THEN
            PERFORM public.fn_raise_posting_error('PROFILE_MISSING', 'No default posting profile found for company.', '{}', 'Seed a default posting profile for the company', 'ERROR', v_idempotency_key);
        END IF;
    END IF;

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
        
        -- Get resolved account id for this role
        v_acc_id := (v_resolved_accounts->v_role->>'account_id')::BIGINT;

        IF v_debit > 0 OR v_credit > 0 THEN
            INSERT INTO public.account_ledger_entries (
                company_id, journal_entry_id, account_id, debit, credit, description
            ) VALUES (
                v_company_id, v_journal_id, v_acc_id, v_debit, v_credit, v_line->>'description'
            );
        END IF;
    END LOOP;

    -- 11. Write Dimensions (if any)
    IF v_dimensions != '{}'::jsonb THEN
        INSERT INTO public.journal_entry_dimensions (
            company_id, journal_entry_id, dimension_key, dimension_value
        )
        SELECT v_company_id, v_journal_id, key, value#>>'{}'
        FROM jsonb_each(v_dimensions);
    END IF;

    -- 12. Return Success Payload
    RETURN jsonb_build_object(
        'success', true,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number,
        'posting_status', 'POSTED',
        'warnings', '[]'::jsonb,
        'errors', '[]'::jsonb,
        'execution_time_ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))
    );
EXCEPTION 
    WHEN OTHERS THEN
        -- If it's our custom enterprise error (P0001), bubble it up intact
        IF SQLSTATE = 'P0001' THEN
            RAISE;
        END IF;
        -- Otherwise, wrap generic SQL errors in our enterprise format
        PERFORM public.fn_raise_posting_error('SYSTEM_ERROR', SQLERRM, SQLSTATE, 'Check database logs', 'FATAL', v_idempotency_key);
END;
$$;

COMMIT;
