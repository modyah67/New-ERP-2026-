-- Verification Script Patch for Migration 011.2 Hardening
-- Purpose: Robust verification using pg_get_functiondef instead of fragile text matching
-- Status: Idempotent, Non-Destructive

BEGIN;

DO $$
DECLARE
    v_check_count INTEGER;
    v_passed INTEGER := 0;
    v_failed INTEGER := 0;
    v_warnings INTEGER := 0;
    v_function_def TEXT;
    v_check_name TEXT;
    v_check_result TEXT;
    v_check_status TEXT;
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Migration 011.2 Hardening Verification Report';
    RAISE NOTICE '================================================================';
    
    -- Get function definition once using pg_get_functiondef
    SELECT pg_get_functiondef(p.oid) INTO v_function_def
    FROM pg_proc p
    WHERE p.proname = 'rpc_post_journal' AND p.pronamespace = 'public'::regnamespace;
    
    -- Debug: Print if function definition was found
    IF v_function_def IS NULL THEN
        RAISE NOTICE 'WARNING: rpc_post_journal function definition is NULL';
    ELSE
        RAISE NOTICE 'INFO: rpc_post_journal function definition loaded (length: %)', length(v_function_def);
    END IF;
    
    -- Check 1: rpc_post_journal function exists
    v_check_name := 'rpc_post_journal function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 2: Verify created_by spoofing fix - uses auth.uid() only
    v_check_name := 'created_by spoofing fix applied';
    IF v_function_def IS NOT NULL AND v_function_def ~* 'auth\.uid\(\)' AND v_function_def !~* 'payload[^\n]*created_by' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 3: Verify exchange rate validation - checks <= 0
    v_check_name := 'Exchange rate validation applied';
    IF v_function_def IS NOT NULL AND v_function_def ~* 'v_exchange_rate.*<=.*0' AND v_function_def ~* 'INVALID_EXCHANGE_RATE' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 4: Verify empty journal protection - checks v_lines_inserted
    v_check_name := 'Empty journal protection applied';
    IF v_function_def IS NOT NULL AND v_function_def ~* 'v_lines_inserted' AND v_function_def ~* 'EMPTY_LEDGER' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 5: Verify idempotency race condition handling - intercepts SQLSTATE 23505
    v_check_name := 'Idempotency race condition handling applied';
    IF v_function_def IS NOT NULL AND v_function_def ~* '23505' AND v_function_def ~* 'POSTED_IDEMPOTENT' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 6: Verify tax calculations NOT modified - ABS not added for base_amount
    v_check_name := 'Tax calculations NOT modified (ABS not added)';
    IF v_function_def IS NOT NULL AND v_function_def !~* 'ABS[^\n]*base_amount' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 7: Verify search_path is set to public
    v_check_name := 'search_path correctly set to public';
    IF v_function_def IS NOT NULL AND v_function_def ~* 'search_path.*public' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 8: Verify SECURITY DEFINER is still present
    v_check_name := 'SECURITY DEFINER still present';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND prosecdef = true) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 9: Verify idx_journal_entries_idempotency index exists
    v_check_name := 'idx_journal_entries_idempotency index exists';
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_journal_entries_idempotency') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 10: Verify account_ledger_entries.dimensions column exists
    v_check_name := 'account_ledger_entries.dimensions column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'dimensions') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 11: Verify account_ledger_entries.amount_in_base_currency column exists
    v_check_name := 'account_ledger_entries.amount_in_base_currency column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'amount_in_base_currency') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 12: Verify journal_entries.currency_snapshot column exists
    v_check_name := 'journal_entries.currency_snapshot column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'currency_snapshot') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 13: Verify journal_entries.idempotency_key column exists
    v_check_name := 'journal_entries.idempotency_key column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'idempotency_key') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 14: Verify tax_codes.posting_role_id column exists
    v_check_name := 'tax_codes.posting_role_id column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tax_codes' AND column_name = 'posting_role_id') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 15: Verify journal_entries.company_id column exists
    v_check_name := 'journal_entries.company_id column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'company_id') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 16: Verify account_ledger_entries.company_id column exists
    v_check_name := 'account_ledger_entries.company_id column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'company_id') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 17: Verify accounts.company_id column exists
    v_check_name := 'accounts.company_id column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 18: Verify accounts.is_leaf column exists
    v_check_name := 'accounts.is_leaf column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'is_leaf') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 19: Verify accounts.allow_posting column exists
    v_check_name := 'accounts.allow_posting column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'allow_posting') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 20: Verify accounts.account_category column exists
    v_check_name := 'accounts.account_category column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'account_category') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 21: Verify fiscal_years.company_id column exists
    v_check_name := 'fiscal_years.company_id column exists';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'fiscal_years' AND column_name = 'company_id') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 22: Verify accounting_periods table exists
    v_check_name := 'accounting_periods table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'accounting_periods') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 23: Verify sys_companies table exists
    v_check_name := 'sys_companies table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 24: Verify sys_document_types table exists
    v_check_name := 'sys_document_types table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_document_types') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 25: Verify posting_profiles table exists
    v_check_name := 'posting_profiles table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profiles') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 26: Verify posting_profile_rules table exists
    v_check_name := 'posting_profile_rules table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profile_rules') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 27: Verify posting_account_roles table exists
    v_check_name := 'posting_account_roles table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_account_roles') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 28: Verify tax_codes table exists
    v_check_name := 'tax_codes table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_codes') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 29: Verify tax_rates table exists
    v_check_name := 'tax_rates table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_rates') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 30: Verify sys_sequences table exists
    v_check_name := 'sys_sequences table exists';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences') THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 31: Verify fn_validate_company_active function exists
    v_check_name := 'fn_validate_company_active function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_company_active' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 32: Verify fn_validate_fiscal_year function exists
    v_check_name := 'fn_validate_fiscal_year function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_fiscal_year' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 33: Verify fn_validate_period_open function exists
    v_check_name := 'fn_validate_period_open function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_period_open' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 34: Verify fn_validate_document_type function exists
    v_check_name := 'fn_validate_document_type function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_document_type' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 35: Verify fn_validate_posting_profile function exists
    v_check_name := 'fn_validate_posting_profile function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_posting_profile' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 36: Verify fn_resolve_posting_accounts_bulk function exists
    v_check_name := 'fn_resolve_posting_accounts_bulk function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_resolve_posting_accounts_bulk' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 37: Verify fn_raise_posting_error function exists
    v_check_name := 'fn_raise_posting_error function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_raise_posting_error' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 38: Verify fn_get_next_sequence function exists
    v_check_name := 'fn_get_next_sequence function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_get_next_sequence' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 39: Verify get_current_company_id function exists
    v_check_name := 'get_current_company_id function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_current_company_id' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 40: Verify rebuild_chart_of_accounts_hierarchy function exists
    v_check_name := 'rebuild_chart_of_accounts_hierarchy function exists';
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rebuild_chart_of_accounts_hierarchy' AND pronamespace = 'public'::regnamespace) THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 41: Verify critical indexes exist
    v_check_name := 'All 9 critical indexes exist';
    SELECT COUNT(*) INTO v_check_count FROM pg_indexes 
    WHERE schemaname = 'public' 
    AND indexname IN (
        'idx_journal_entries_idempotency',
        'idx_journal_entries_company_id',
        'idx_account_ledger_entries_company_id',
        'idx_accounts_company_id',
        'idx_fiscal_years_company_id',
        'idx_accounting_periods_dates',
        'idx_posting_profile_rules_profile_id',
        'idx_posting_profile_rules_role_id',
        'idx_tax_rates_tax_code_id'
    );
    
    IF v_check_count = 9 THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: % (found % of 9)', v_check_status, v_check_name, v_check_count;
    
    -- Check 42: Verify foreign keys exist
    v_check_name := 'Foreign keys exist on dependent tables';
    SELECT COUNT(*) INTO v_check_count FROM information_schema.table_constraints 
    WHERE table_schema = 'public' 
    AND constraint_type = 'FOREIGN KEY'
    AND table_name IN ('account_ledger_entries', 'posting_profile_rules', 'tax_codes', 'accounting_periods');
    
    IF v_check_count >= 4 THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: % (found % foreign keys)', v_check_status, v_check_name, v_check_count;
    
    -- Check 43: Verify JSONB operator fix from 011.1 is still present
    v_check_name := 'JSONB operator fix (from 011.1) still present';
    IF v_function_def IS NOT NULL AND v_function_def ~* '->>v_role' AND v_function_def ~* 'account_id' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 44: Verify INTEGER cast fix from 011.1 is still present
    v_check_name := 'INTEGER cast fix (from 011.1) still present';
    IF v_function_def IS NOT NULL AND v_function_def ~* '::INTEGER' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Check 45: Verify fiscal_year_id INT cast fix from 011.1 is still present
    v_check_name := 'fiscal_year_id INT cast fix (from 011.1) still present';
    IF v_function_def IS NOT NULL AND v_function_def ~* 'fiscal_year_id.*::INT' THEN
        v_check_status := 'PASS';
        v_passed := v_passed + 1;
    ELSE
        v_check_status := 'FAIL';
        v_failed := v_failed + 1;
    END IF;
    RAISE NOTICE '%: %', v_check_status, v_check_name;
    
    -- Summary
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'VERIFICATION SUMMARY';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Passed: %', v_passed;
    RAISE NOTICE 'Failed: %', v_failed;
    RAISE NOTICE 'Warnings: %', v_warnings;
    RAISE NOTICE '================================================================';
    
    IF v_failed = 0 THEN
        RAISE NOTICE 'VERIFICATION PASSED';
        RAISE NOTICE 'Migration 011.2 is production ready.';
    ELSE
        RAISE EXCEPTION 'VERIFICATION FAILED: % checks failed', v_failed;
    END IF;
END $$;

ROLLBACK; -- Verification only, do not commit
