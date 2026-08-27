-- Migration 041: Phase E — Recreate Treasury Accounts & Linkage
--
-- Issues Fixed:
-- 1. Treasury accounts (11101-11104) were partially deleted
-- 2. Only 11101 (EGP) remained, but needs to be recreated properly
-- 3. treasury_balances linkage was missing
--
-- Solution:
-- 1. Delete remaining treasury account (11101)
-- 2. Recreate all 4 treasury accounts (11101-11104) with proper structure
-- 3. Create linkage in treasury_balances with correct account_id

-- ============================================================================
-- SECTION 1: DELETE REMAINING TREASURY ACCOUNT
-- ============================================================================

-- Delete the remaining treasury account (11101 - EGP)
-- This will cascade delete any ledger entries using this account

-- First, delete any references in posting_profile_rules
DELETE FROM posting_profile_rules 
WHERE account_id IN (SELECT id FROM accounts WHERE account_code = '11101' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

DELETE FROM account_ledger_entries 
WHERE account_id IN (SELECT id FROM accounts WHERE account_code = '11101');

DELETE FROM accounts 
WHERE account_code = '11101' 
AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';


-- ============================================================================
-- SECTION 2: RECREATE ALL 4 TREASURY ACCOUNTS PROPERLY
-- ============================================================================

DO $$
DECLARE
    v_parent_id BIGINT;
    v_company_id UUID := 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';
BEGIN
    SELECT id INTO v_parent_id 
    FROM accounts 
    WHERE account_code = '1000' AND company_id = v_company_id;
    
    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Parent account 1000 (Cash) not found';
    END IF;
    
    -- 11101: Main Treasury - EGP
    INSERT INTO accounts (
        account_code, name, account_name, account_type, parent_id, 
        is_leaf, is_system, allow_posting, normal_balance, company_id
    ) VALUES (
        '11101', 'Main Treasury - EGP', 'الخزينة الرئيسية - جنيه', 'asset',
        v_parent_id, true, false, true, 'Debit', v_company_id
    ) ON CONFLICT (account_code, company_id) DO NOTHING;
    
    -- 11102: Main Treasury - USD
    INSERT INTO accounts (
        account_code, name, account_name, account_type, parent_id, 
        is_leaf, is_system, allow_posting, normal_balance, company_id
    ) VALUES (
        '11102', 'Main Treasury - USD', 'الخزينة الرئيسية - دولار', 'asset',
        v_parent_id, true, false, true, 'Debit', v_company_id
    ) ON CONFLICT (account_code, company_id) DO NOTHING;
    
    -- 11103: Main Treasury - EUR
    INSERT INTO accounts (
        account_code, name, account_name, account_type, parent_id, 
        is_leaf, is_system, allow_posting, normal_balance, company_id
    ) VALUES (
        '11103', 'Main Treasury - EUR', 'الخزينة الرئيسية - يورو', 'asset',
        v_parent_id, true, false, true, 'Debit', v_company_id
    ) ON CONFLICT (account_code, company_id) DO NOTHING;
    
    -- 11104: Main Treasury - GBP
    INSERT INTO accounts (
        account_code, name, account_name, account_type, parent_id, 
        is_leaf, is_system, allow_posting, normal_balance, company_id
    ) VALUES (
        '11104', 'Main Treasury - GBP', 'الخزينة الرئيسية - جنيه إسترليني', 'asset',
        v_parent_id, true, false, true, 'Debit', v_company_id
    ) ON CONFLICT (account_code, company_id) DO NOTHING;
END $$;


-- ============================================================================
-- SECTION 3: CREATE PROPER LINKAGE IN treasury_balances
-- ============================================================================

-- Clear existing treasury_balances (if any)
DELETE FROM treasury_balances;

-- Recreate treasury_balances with proper account_id linkage
-- For each treasury, create 4 currency entries with correct account_id
INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
SELECT 
    t.id AS treasury_id,
    'EGP' AS currency,
    0.00 AS balance,
    (SELECT id FROM accounts WHERE account_code = '11101' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5') AS account_id
FROM treasuries t
WHERE t.company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';

INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
SELECT 
    t.id AS treasury_id,
    'USD' AS currency,
    0.00 AS balance,
    (SELECT id FROM accounts WHERE account_code = '11102' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5') AS account_id
FROM treasuries t
WHERE t.company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';

INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
SELECT 
    t.id AS treasury_id,
    'EUR' AS currency,
    0.00 AS balance,
    (SELECT id FROM accounts WHERE account_code = '11103' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5') AS account_id
FROM treasuries t
WHERE t.company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';

INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
SELECT 
    t.id AS treasury_id,
    'GBP' AS currency,
    0.00 AS balance,
    (SELECT id FROM accounts WHERE account_code = '11104' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5') AS account_id
FROM treasuries t
WHERE t.company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';


-- ============================================================================
-- VERIFICATION QUERY (for manual check)
-- ============================================================================
-- Run this after migration to verify:
-- SELECT 
--     tb.id,
--     tb.treasury_id,
--     tb.currency,
--     tb.balance,
--     tb.account_id,
--     a.account_code,
--     a.account_name
-- FROM treasury_balances tb
-- JOIN accounts a ON tb.account_id = a.id
-- ORDER BY tb.treasury_id, tb.currency;
