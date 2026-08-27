-- Migration 011.2: Production Hardening for Enterprise Posting Engine
-- Purpose: Fix security, validation, and concurrency issues in rpc_post_journal
-- Status: Idempotent, Backward Compatible, Production Ready

BEGIN;

-- =================================================================================
-- PATCH: Hardening Fixes for rpc_post_journal
-- =================================================================================

-- Fix 1: Remove created_by spoofing (Line 81)
-- Fix 2: Add exchange rate validation (Line 78)
-- Fix 3: Add empty journal protection (Lines 214-220)
-- Fix 4: Add idempotency race condition handling in EXCEPTION (Lines 234-242)

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
    v_acc_id INTEGER;
    
    -- Tax Resolution
    v_tax_rate NUMERIC;
    v_tax_role_id UUID;
    v_tax_role_code TEXT;
    v_tax_amount NUMERIC;
    
    -- Empty Journal Protection
    v_lines_inserted INTEGER := 0;
    
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
    
    -- FIX 1: Remove created_by spoofing - always use auth.uid()
    v_created_by := auth.uid();
    
    v_idempotency_key := payload->>'idempotency_key';
    
    v_lines := COALESCE(payload->'lines', '[]'::jsonb);
    v_taxes := COALESCE(payload->'taxes', '[]'::jsonb);

    -- FIX 2: Validate exchange rate before any calculations
    IF v_exchange_rate <= 0 THEN
        PERFORM public.fn_raise_posting_error('INVALID_EXCHANGE_RATE', 'Exchange rate must be greater than zero.', v_exchange_rate::text, 'Provide a positive exchange rate', 'ERROR', v_idempotency_key);
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
    v_period_info := public.fn_validate_period_open(v_company_id, (v_fy_info->>'fiscal_year_id')::INT, v_date, v_idempotency_key);
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
        v_acc_id := (v_resolved_accounts->>v_role->>'account_id')::INTEGER;
        
        IF v_debit > 0 OR v_credit > 0 THEN
            INSERT INTO public.account_ledger_entries (
                company_id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, dimensions
            ) VALUES (
                v_company_id, v_journal_id, v_acc_id, v_debit, v_credit, v_currency, (v_debit + v_credit) * v_exchange_rate, v_line->>'description', v_dimensions
            );
            v_lines_inserted := v_lines_inserted + 1;
        END IF;
    END LOOP;

    -- FIX 3: Empty Journal Protection - prevent posting journals with zero ledger entries
    IF v_lines_inserted = 0 THEN
        -- Rollback the header insert
        DELETE FROM public.journal_entries WHERE id = v_journal_id;
        PERFORM public.fn_raise_posting_error('EMPTY_LEDGER', 'Journal has no valid ledger lines after normalization.', '{}', 'Ensure at least one line has non-zero debit or credit', 'ERROR', v_idempotency_key);
    END IF;

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
    -- FIX 4: Idempotency Race Condition Handling - intercept 23505 (unique_violation)
    IF SQLSTATE = '23505' AND v_idempotency_key IS NOT NULL THEN
        -- Re-read the journal using (company_id, idempotency_key)
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
    
    -- If it's our custom enterprise error (P0001), bubble it up intact
    IF SQLSTATE = 'P0001' THEN
        RAISE;
    END IF;
    
    -- Otherwise, wrap generic SQL errors in our enterprise format
    PERFORM public.fn_raise_posting_error('SYSTEM_ERROR', SQLERRM, SQLSTATE, 'Check database logs', 'FATAL', v_idempotency_key);
END;
$$;

COMMIT;
