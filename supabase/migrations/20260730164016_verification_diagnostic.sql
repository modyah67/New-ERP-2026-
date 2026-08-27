-- Diagnostic Verification Script for Migration 011.2
-- Purpose: Identify which checks are failing and why
-- Status: Diagnostic only

BEGIN;

DO $$
DECLARE
    v_function_def TEXT;
    v_check_name TEXT;
    v_pattern TEXT;
    v_match BOOLEAN;
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Migration 011.2 Diagnostic Verification';
    RAISE NOTICE '================================================================';
    
    -- Get function definition
    SELECT pg_get_functiondef(p.oid) INTO v_function_def
    FROM pg_proc p
    WHERE p.proname = 'rpc_post_journal' AND p.pronamespace = 'public'::regnamespace;
    
    IF v_function_def IS NULL THEN
        RAISE NOTICE 'ERROR: Function definition is NULL';
        RETURN;
    END IF;
    
    RAISE NOTICE 'Function definition length: %', length(v_function_def);
    RAISE NOTICE '================================================================';
    
    -- Test each pattern individually
    
    -- Check 2: created_by spoofing
    v_check_name := 'Check 2: created_by spoofing fix';
    v_pattern := 'auth\.uid\(\)';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    v_pattern := 'payload.*created_by';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: % (should be false)', v_check_name, v_pattern, v_match;
    
    -- Check 3: Exchange rate validation
    v_check_name := 'Check 3: Exchange rate validation';
    v_pattern := 'v_exchange_rate.*<=.*0';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    v_pattern := 'INVALID_EXCHANGE_RATE';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Check 4: Empty journal protection
    v_check_name := 'Check 4: Empty journal protection';
    v_pattern := 'v_lines_inserted';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    v_pattern := 'EMPTY_LEDGER';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Check 5: Idempotency race condition
    v_check_name := 'Check 5: Idempotency race condition';
    v_pattern := '23505';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    v_pattern := 'POSTED_IDEMPOTENT';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Check 6: Tax calculations NOT modified
    v_check_name := 'Check 6: Tax calculations NOT modified';
    v_pattern := 'ABS.*base_amount';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: % (should be false)', v_check_name, v_pattern, v_match;
    
    -- Check 7: search_path
    v_check_name := 'Check 7: search_path';
    v_pattern := 'search_path.*public';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Check 43: JSONB operator fix
    v_check_name := 'Check 43: JSONB operator fix';
    v_pattern := '->>v_role';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    v_pattern := 'account_id';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Check 44: INTEGER cast fix
    v_check_name := 'Check 44: INTEGER cast fix';
    v_pattern := '::INTEGER';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Check 45: fiscal_year_id INT cast fix
    v_check_name := 'Check 45: fiscal_year_id INT cast fix';
    v_pattern := 'fiscal_year_id.*::INT';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: %', v_check_name, v_pattern, v_match;
    
    -- Also check for ::BIGINT which should NOT be present
    v_pattern := '::BIGINT';
    v_match := v_function_def ~* v_pattern;
    RAISE NOTICE '%: Pattern "%" matched: % (should be false)', v_check_name, v_pattern, v_match;
    
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Diagnostic complete. Review pattern matches above.';
    RAISE NOTICE '================================================================';
END $$;

ROLLBACK;
