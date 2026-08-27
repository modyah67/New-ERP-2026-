-- Diagnostic Verification Script for Migration 011.2
-- Purpose: Identify which checks are failing using result sets
-- Status: Diagnostic only - no exceptions raised

BEGIN;

DO $$
DECLARE
    v_function_def TEXT;
BEGIN
    -- Create temporary table for results
    DROP TABLE IF EXISTS temp_verification_results;
    CREATE TEMP TABLE temp_verification_results (
        check_number INTEGER,
        check_name TEXT,
        expected TEXT,
        actual TEXT,
        passed BOOLEAN,
        function_def TEXT
    );
    
    -- Get function definition
    SELECT pg_get_functiondef(p.oid) INTO v_function_def
    FROM pg_proc p
    WHERE p.proname = 'rpc_post_journal' AND p.pronamespace = 'public'::regnamespace;
    
    -- Store function definition in temp table for later access
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed, function_def)
    VALUES (0, 'Function Definition', 'Loaded', CASE WHEN v_function_def IS NULL THEN 'NULL' ELSE 'LOADED' END, v_function_def IS NOT NULL, v_function_def);
    
    -- Check 1: rpc_post_journal function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed, function_def)
    SELECT 
        1,
        'rpc_post_journal function exists',
        'Function exists in pg_proc',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND pronamespace = 'public'::regnamespace),
        v_function_def;
    
    -- Check 2: created_by spoofing fix
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        2,
        'created_by spoofing fix applied',
        'Uses auth.uid() and no payload override',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* 'auth\.uid\(\)' AND v_function_def !~* 'payload.*created_by' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* 'auth\.uid\(\)' AND v_function_def !~* 'payload.*created_by';
    
    -- Check 3: Exchange rate validation
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        3,
        'Exchange rate validation applied',
        'Contains v_exchange_rate <= 0 and INVALID_EXCHANGE_RATE',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* 'v_exchange_rate.*<=.*0' AND v_function_def ~* 'INVALID_EXCHANGE_RATE' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* 'v_exchange_rate.*<=.*0' AND v_function_def ~* 'INVALID_EXCHANGE_RATE';
    
    -- Check 4: Empty journal protection
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        4,
        'Empty journal protection applied',
        'Contains v_lines_inserted and EMPTY_LEDGER',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* 'v_lines_inserted' AND v_function_def ~* 'EMPTY_LEDGER' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* 'v_lines_inserted' AND v_function_def ~* 'EMPTY_LEDGER';
    
    -- Check 5: Idempotency race condition handling
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        5,
        'Idempotency race condition handling applied',
        'Contains 23505 and POSTED_IDEMPOTENT',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* '23505' AND v_function_def ~* 'POSTED_IDEMPOTENT' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* '23505' AND v_function_def ~* 'POSTED_IDEMPOTENT';
    
    -- Check 6: Tax calculations NOT modified
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        6,
        'Tax calculations NOT modified (ABS not added)',
        'Does NOT contain ABS.*base_amount',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def !~* 'ABS.*base_amount' THEN 'NO ABS FOUND'
            ELSE 'ABS FOUND'
        END,
        v_function_def IS NOT NULL AND v_function_def !~* 'ABS.*base_amount';
    
    -- Check 7: search_path set to public
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        7,
        'search_path correctly set to public',
        'Contains search_path.*public',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* 'search_path.*public' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* 'search_path.*public';
    
    -- Check 8: SECURITY DEFINER present
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        8,
        'SECURITY DEFINER still present',
        'prosecdef = true',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND prosecdef = true) THEN 'TRUE' ELSE 'FALSE' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_post_journal' AND prosecdef = true);
    
    -- Check 9: idx_journal_entries_idempotency index exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        9,
        'idx_journal_entries_idempotency index exists',
        'Index exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_journal_entries_idempotency') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_journal_entries_idempotency');
    
    -- Check 10: account_ledger_entries.dimensions column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        10,
        'account_ledger_entries.dimensions column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'dimensions') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'dimensions');
    
    -- Check 11: account_ledger_entries.amount_in_base_currency column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        11,
        'account_ledger_entries.amount_in_base_currency column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'amount_in_base_currency') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'amount_in_base_currency');
    
    -- Check 12: journal_entries.currency_snapshot column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        12,
        'journal_entries.currency_snapshot column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'currency_snapshot') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'currency_snapshot');
    
    -- Check 13: journal_entries.idempotency_key column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        13,
        'journal_entries.idempotency_key column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'idempotency_key') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'idempotency_key');
    
    -- Check 14: tax_codes.posting_role_id column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        14,
        'tax_codes.posting_role_id column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tax_codes' AND column_name = 'posting_role_id') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tax_codes' AND column_name = 'posting_role_id');
    
    -- Check 15: journal_entries.company_id column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        15,
        'journal_entries.company_id column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'company_id') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'company_id');
    
    -- Check 16: account_ledger_entries.company_id column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        16,
        'account_ledger_entries.company_id column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'company_id') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger_entries' AND column_name = 'company_id');
    
    -- Check 17: accounts.company_id column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        17,
        'accounts.company_id column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id');
    
    -- Check 18: accounts.is_leaf column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        18,
        'accounts.is_leaf column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'is_leaf') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'is_leaf');
    
    -- Check 19: accounts.allow_posting column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        19,
        'accounts.allow_posting column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'allow_posting') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'allow_posting');
    
    -- Check 20: accounts.account_category column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        20,
        'accounts.account_category column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'account_category') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'account_category');
    
    -- Check 21: fiscal_years.company_id column exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        21,
        'fiscal_years.company_id column exists',
        'Column exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'fiscal_years' AND column_name = 'company_id') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'fiscal_years' AND column_name = 'company_id');
    
    -- Check 22: accounting_periods table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        22,
        'accounting_periods table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'accounting_periods') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'accounting_periods');
    
    -- Check 23: sys_companies table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        23,
        'sys_companies table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies');
    
    -- Check 24: sys_document_types table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        24,
        'sys_document_types table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_document_types') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_document_types');
    
    -- Check 25: posting_profiles table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        25,
        'posting_profiles table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profiles') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profiles');
    
    -- Check 26: posting_profile_rules table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        26,
        'posting_profile_rules table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profile_rules') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_profile_rules');
    
    -- Check 27: posting_account_roles table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        27,
        'posting_account_roles table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_account_roles') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'posting_account_roles');
    
    -- Check 28: tax_codes table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        28,
        'tax_codes table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_codes') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_codes');
    
    -- Check 29: tax_rates table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        29,
        'tax_rates table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_rates') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tax_rates');
    
    -- Check 30: sys_sequences table exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        30,
        'sys_sequences table exists',
        'Table exists',
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences') THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences');
    
    -- Check 31: fn_validate_company_active function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        31,
        'fn_validate_company_active function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_company_active' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_company_active' AND pronamespace = 'public'::regnamespace);
    
    -- Check 32: fn_validate_fiscal_year function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        32,
        'fn_validate_fiscal_year function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_fiscal_year' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_fiscal_year' AND pronamespace = 'public'::regnamespace);
    
    -- Check 33: fn_validate_period_open function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        33,
        'fn_validate_period_open function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_period_open' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_period_open' AND pronamespace = 'public'::regnamespace);
    
    -- Check 34: fn_validate_document_type function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        34,
        'fn_validate_document_type function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_document_type' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_document_type' AND pronamespace = 'public'::regnamespace);
    
    -- Check 35: fn_validate_posting_profile function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        35,
        'fn_validate_posting_profile function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_posting_profile' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validate_posting_profile' AND pronamespace = 'public'::regnamespace);
    
    -- Check 36: fn_resolve_posting_accounts_bulk function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        36,
        'fn_resolve_posting_accounts_bulk function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_resolve_posting_accounts_bulk' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_resolve_posting_accounts_bulk' AND pronamespace = 'public'::regnamespace);
    
    -- Check 37: fn_raise_posting_error function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        37,
        'fn_raise_posting_error function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_raise_posting_error' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_raise_posting_error' AND pronamespace = 'public'::regnamespace);
    
    -- Check 38: fn_get_next_sequence function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        38,
        'fn_get_next_sequence function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_get_next_sequence' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_get_next_sequence' AND pronamespace = 'public'::regnamespace);
    
    -- Check 39: get_current_company_id function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        39,
        'get_current_company_id function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_current_company_id' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_current_company_id' AND pronamespace = 'public'::regnamespace);
    
    -- Check 40: rebuild_chart_of_accounts_hierarchy function exists
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        40,
        'rebuild_chart_of_accounts_hierarchy function exists',
        'Function exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rebuild_chart_of_accounts_hierarchy' AND pronamespace = 'public'::regnamespace) THEN 'EXISTS' ELSE 'NOT FOUND' END,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rebuild_chart_of_accounts_hierarchy' AND pronamespace = 'public'::regnamespace);
    
    -- Check 41: All 9 critical indexes exist
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        41,
        'All 9 critical indexes exist',
        '9 indexes found',
        (SELECT COUNT(*)::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ('idx_journal_entries_idempotency', 'idx_journal_entries_company_id', 'idx_account_ledger_entries_company_id', 'idx_accounts_company_id', 'idx_fiscal_years_company_id', 'idx_accounting_periods_dates', 'idx_posting_profile_rules_profile_id', 'idx_posting_profile_rules_role_id', 'idx_tax_rates_tax_code_id')),
        (SELECT COUNT(*) = 9 FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ('idx_journal_entries_idempotency', 'idx_journal_entries_company_id', 'idx_account_ledger_entries_company_id', 'idx_accounts_company_id', 'idx_fiscal_years_company_id', 'idx_accounting_periods_dates', 'idx_posting_profile_rules_profile_id', 'idx_posting_profile_rules_role_id', 'idx_tax_rates_tax_code_id'));
    
    -- Check 42: Foreign keys exist
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        42,
        'Foreign keys exist on dependent tables',
        '>= 4 foreign keys',
        (SELECT COUNT(*)::TEXT FROM information_schema.table_constraints WHERE table_schema = 'public' AND constraint_type = 'FOREIGN KEY' AND table_name IN ('account_ledger_entries', 'posting_profile_rules', 'tax_codes', 'accounting_periods')),
        (SELECT COUNT(*) >= 4 FROM information_schema.table_constraints WHERE table_schema = 'public' AND constraint_type = 'FOREIGN KEY' AND table_name IN ('account_ledger_entries', 'posting_profile_rules', 'tax_codes', 'accounting_periods'));
    
    -- Check 43: JSONB operator fix from 011.1
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        43,
        'JSONB operator fix (from 011.1) still present',
        'Contains ->>v_role and account_id',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* '->>v_role' AND v_function_def ~* 'account_id' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* '->>v_role' AND v_function_def ~* 'account_id';
    
    -- Check 44: INTEGER cast fix from 011.1
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        44,
        'INTEGER cast fix (from 011.1) still present',
        'Contains ::INTEGER',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* '::INTEGER' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* '::INTEGER';
    
    -- Check 45: fiscal_year_id INT cast fix from 011.1
    INSERT INTO temp_verification_results (check_number, check_name, expected, actual, passed)
    SELECT 
        45,
        'fiscal_year_id INT cast fix (from 011.1) still present',
        'Contains fiscal_year_id.*::INT',
        CASE 
            WHEN v_function_def IS NULL THEN 'Function definition NULL'
            WHEN v_function_def ~* 'fiscal_year_id.*::INT' THEN 'MATCH'
            ELSE 'NO MATCH'
        END,
        v_function_def IS NOT NULL AND v_function_def ~* 'fiscal_year_id.*::INT';
END $$;

-- Return ONLY failed checks
SELECT 
    check_number AS "Check Number",
    check_name AS "Check Name",
    expected AS "Expected",
    actual AS "Actual",
    CASE WHEN NOT passed THEN 'FAILED' END AS "Reason",
    function_def AS "Source snippet from pg_get_functiondef()"
FROM temp_verification_results
WHERE NOT passed
ORDER BY check_number;

ROLLBACK;
