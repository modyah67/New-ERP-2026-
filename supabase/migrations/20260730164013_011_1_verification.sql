-- Verification Script for Migration 011.1 Patch
-- Purpose: Confirm all patches were applied correctly and system is production ready

BEGIN;

DO $$
DECLARE
    v_check_count INTEGER;
    v_check_passed BOOLEAN := true;
    v_errors TEXT := '';
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Migration 011.1 Verification Report';
    RAISE NOTICE '================================================================';
    
    -- Check 1: rpc_post_journal function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ rpc_post_journal function exists';
    ELSE
        RAISE NOTICE '✗ rpc_post_journal function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'rpc_post_journal function missing; ';
    END IF;
    
    -- Check 2: account_ledger_entries.dimensions column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'dimensions') THEN
        RAISE NOTICE '✓ account_ledger_entries.dimensions column exists';
    ELSE
        RAISE NOTICE '✗ account_ledger_entries.dimensions column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'account_ledger_entries.dimensions missing; ';
    END IF;
    
    -- Check 3: account_ledger_entries.amount_in_base_currency column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'amount_in_base_currency') THEN
        RAISE NOTICE '✓ account_ledger_entries.amount_in_base_currency column exists';
    ELSE
        RAISE NOTICE '✗ account_ledger_entries.amount_in_base_currency column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'account_ledger_entries.amount_in_base_currency missing; ';
    END IF;
    
    -- Check 4: journal_entries.currency_snapshot column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'currency_snapshot') THEN
        RAISE NOTICE '✓ journal_entries.currency_snapshot column exists';
    ELSE
        RAISE NOTICE '✗ journal_entries.currency_snapshot column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'journal_entries.currency_snapshot missing; ';
    END IF;
    
    -- Check 5: journal_entries.idempotency_key column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'idempotency_key') THEN
        RAISE NOTICE '✓ journal_entries.idempotency_key column exists';
    ELSE
        RAISE NOTICE '✗ journal_entries.idempotency_key column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'journal_entries.idempotency_key missing; ';
    END IF;
    
    -- Check 6: tax_codes.posting_role_id column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tax_codes' AND column_name = 'posting_role_id') THEN
        RAISE NOTICE '✓ tax_codes.posting_role_id column exists';
    ELSE
        RAISE NOTICE '✗ tax_codes.posting_role_id column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'tax_codes.posting_role_id missing; ';
    END IF;
    
    -- Check 7: idx_journal_entries_idempotency index exists
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_journal_entries_idempotency') THEN
        RAISE NOTICE '✓ idx_journal_entries_idempotency index exists';
    ELSE
        RAISE NOTICE '✗ idx_journal_entries_idempotency index MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'idx_journal_entries_idempotency index missing; ';
    END IF;
    
    -- Check 8: journal_entries.company_id column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'company_id') THEN
        RAISE NOTICE '✓ journal_entries.company_id column exists';
    ELSE
        RAISE NOTICE '✗ journal_entries.company_id column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'journal_entries.company_id missing; ';
    END IF;
    
    -- Check 9: account_ledger_entries.company_id column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'company_id') THEN
        RAISE NOTICE '✓ account_ledger_entries.company_id column exists';
    ELSE
        RAISE NOTICE '✗ account_ledger_entries.company_id column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'account_ledger_entries.company_id missing; ';
    END IF;
    
    -- Check 10: accounts.company_id column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id') THEN
        RAISE NOTICE '✓ accounts.company_id column exists';
    ELSE
        RAISE NOTICE '✗ accounts.company_id column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'accounts.company_id missing; ';
    END IF;
    
    -- Check 11: accounts.is_leaf column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'is_leaf') THEN
        RAISE NOTICE '✓ accounts.is_leaf column exists';
    ELSE
        RAISE NOTICE '✗ accounts.is_leaf column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'accounts.is_leaf missing; ';
    END IF;
    
    -- Check 12: accounts.allow_posting column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'allow_posting') THEN
        RAISE NOTICE '✓ accounts.allow_posting column exists';
    ELSE
        RAISE NOTICE '✗ accounts.allow_posting column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'accounts.allow_posting missing; ';
    END IF;
    
    -- Check 13: accounts.account_category column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'account_category') THEN
        RAISE NOTICE '✓ accounts.account_category column exists';
    ELSE
        RAISE NOTICE '✗ accounts.account_category column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'accounts.account_category missing; ';
    END IF;
    
    -- Check 14: fiscal_years.company_id column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'fiscal_years' AND column_name = 'company_id') THEN
        RAISE NOTICE '✓ fiscal_years.company_id column exists';
    ELSE
        RAISE NOTICE '✗ fiscal_years.company_id column MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fiscal_years.company_id missing; ';
    END IF;
    
    -- Check 15: accounting_periods table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'accounting_periods') THEN
        RAISE NOTICE '✓ accounting_periods table exists';
    ELSE
        RAISE NOTICE '✗ accounting_periods table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'accounting_periods table missing; ';
    END IF;
    
    -- Check 16: sys_companies table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
        RAISE NOTICE '✓ sys_companies table exists';
    ELSE
        RAISE NOTICE '✗ sys_companies table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'sys_companies table missing; ';
    END IF;
    
    -- Check 17: sys_document_types table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_document_types') THEN
        RAISE NOTICE '✓ sys_document_types table exists';
    ELSE
        RAISE NOTICE '✗ sys_document_types table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'sys_document_types table missing; ';
    END IF;
    
    -- Check 18: posting_profiles table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profiles') THEN
        RAISE NOTICE '✓ posting_profiles table exists';
    ELSE
        RAISE NOTICE '✗ posting_profiles table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'posting_profiles table missing; ';
    END IF;
    
    -- Check 19: posting_profile_rules table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profile_rules') THEN
        RAISE NOTICE '✓ posting_profile_rules table exists';
    ELSE
        RAISE NOTICE '✗ posting_profile_rules table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'posting_profile_rules table missing; ';
    END IF;
    
    -- Check 20: posting_account_roles table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_account_roles') THEN
        RAISE NOTICE '✓ posting_account_roles table exists';
    ELSE
        RAISE NOTICE '✗ posting_account_roles table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'posting_account_roles table missing; ';
    END IF;
    
    -- Check 21: tax_codes table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_codes') THEN
        RAISE NOTICE '✓ tax_codes table exists';
    ELSE
        RAISE NOTICE '✗ tax_codes table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'tax_codes table missing; ';
    END IF;
    
    -- Check 22: tax_rates table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_rates') THEN
        RAISE NOTICE '✓ tax_rates table exists';
    ELSE
        RAISE NOTICE '✗ tax_rates table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'tax_rates table missing; ';
    END IF;
    
    -- Check 23: sys_sequences table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences') THEN
        RAISE NOTICE '✓ sys_sequences table exists';
    ELSE
        RAISE NOTICE '✗ sys_sequences table MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'sys_sequences table missing; ';
    END IF;
    
    -- Check 24: fn_validate_company_active function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_company_active' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_validate_company_active function exists';
    ELSE
        RAISE NOTICE '✗ fn_validate_company_active function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_validate_company_active function missing; ';
    END IF;
    
    -- Check 25: fn_validate_fiscal_year function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_fiscal_year' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_validate_fiscal_year function exists';
    ELSE
        RAISE NOTICE '✗ fn_validate_fiscal_year function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_validate_fiscal_year function missing; ';
    END IF;
    
    -- Check 26: fn_validate_period_open function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_period_open' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_validate_period_open function exists';
    ELSE
        RAISE NOTICE '✗ fn_validate_period_open function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_validate_period_open function missing; ';
    END IF;
    
    -- Check 27: fn_validate_document_type function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_document_type' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_validate_document_type function exists';
    ELSE
        RAISE NOTICE '✗ fn_validate_document_type function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_validate_document_type function missing; ';
    END IF;
    
    -- Check 28: fn_validate_posting_profile function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_posting_profile' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_validate_posting_profile function exists';
    ELSE
        RAISE NOTICE '✗ fn_validate_posting_profile function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_validate_posting_profile function missing; ';
    END IF;
    
    -- Check 29: fn_resolve_posting_accounts_bulk function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_resolve_posting_accounts_bulk' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_resolve_posting_accounts_bulk function exists';
    ELSE
        RAISE NOTICE '✗ fn_resolve_posting_accounts_bulk function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_resolve_posting_accounts_bulk function missing; ';
    END IF;
    
    -- Check 30: fn_raise_posting_error function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_raise_posting_error' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_raise_posting_error function exists';
    ELSE
        RAISE NOTICE '✗ fn_raise_posting_error function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_raise_posting_error function missing; ';
    END IF;
    
    -- Check 31: fn_get_next_sequence function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_get_next_sequence' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ fn_get_next_sequence function exists';
    ELSE
        RAISE NOTICE '✗ fn_get_next_sequence function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'fn_get_next_sequence function missing; ';
    END IF;
    
    -- Check 32: get_current_company_id function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_current_company_id' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ get_current_company_id function exists';
    ELSE
        RAISE NOTICE '✗ get_current_company_id function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'get_current_company_id function missing; ';
    END IF;
    
    -- Check 33: rebuild_chart_of_accounts_hierarchy function exists
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rebuild_chart_of_accounts_hierarchy' AND pronamespace = 'public'::regnamespace) THEN
        RAISE NOTICE '✓ rebuild_chart_of_accounts_hierarchy function exists';
    ELSE
        RAISE NOTICE '✗ rebuild_chart_of_accounts_hierarchy function MISSING';
        v_check_passed := false;
        v_errors := v_errors || 'rebuild_chart_of_accounts_hierarchy function missing; ';
    END IF;
    
    -- Check 34: Verify critical indexes exist
    SELECT COUNT(*) INTO v_check_count FROM pg_indexes 
    WHERE schemaname = 'public' 
    AND indexname IN (
        'idx_journal_entries_company_id',
        'idx_account_ledger_entries_company_id',
        'idx_accounts_company_id',
        'idx_fiscal_years_company_id',
        'idx_accounting_periods_dates',
        'idx_posting_profile_rules_profile_id',
        'idx_posting_profile_rules_role_id',
        'idx_tax_rates_tax_code_id'
    );
    
    IF v_check_count = 8 THEN
        RAISE NOTICE '✓ All 8 critical indexes exist';
    ELSE
        RAISE NOTICE '✗ Only % of 8 critical indexes exist', v_check_count;
        v_check_passed := false;
        v_errors := v_errors || 'Missing critical indexes; ';
    END IF;
    
    -- Check 35: Verify foreign keys exist
    SELECT COUNT(*) INTO v_check_count FROM information_schema.table_constraints 
    WHERE table_schema = 'public' 
    AND constraint_type = 'FOREIGN KEY'
    AND table_name IN ('account_ledger_entries', 'posting_profile_rules', 'tax_codes', 'accounting_periods');
    
    IF v_check_count >= 4 THEN
        RAISE NOTICE '✓ Foreign keys exist on dependent tables';
    ELSE
        RAISE NOTICE '✗ Missing foreign keys on dependent tables';
        v_check_passed := false;
        v_errors := v_errors || 'Missing foreign keys; ';
    END IF;
    
    RAISE NOTICE '================================================================';
    IF v_check_passed THEN
        RAISE NOTICE 'VERIFICATION RESULT: ✓ ALL CHECKS PASSED';
        RAISE NOTICE 'Migration 011.1 is production ready.';
    ELSE
        RAISE NOTICE 'VERIFICATION RESULT: ✗ CHECKS FAILED';
        RAISE NOTICE 'Errors: %', v_errors;
        RAISE EXCEPTION 'Verification failed. Please review errors above.';
    END IF;
    RAISE NOTICE '================================================================';
END $$;

ROLLBACK; -- Verification only, do not commit
