-- Migration 089: Fix Chart of Accounts Classifications & Duplicates
-- ====================================================================

BEGIN;

DO $$
DECLARE
  v_fuel_old_id BIGINT;
  v_fuel_new_id BIGINT;
  v_engineer_fees_id BIGINT;
  v_export_fees_id BIGINT;
  v_suspense_id BIGINT;
BEGIN

  -- 1. Merge Duplicate Fuel Expense Accounts (1568 -> 6160)
  SELECT id INTO v_fuel_old_id FROM accounts WHERE account_code = '1568' LIMIT 1;
  SELECT id INTO v_fuel_new_id FROM accounts WHERE account_code = '6160' LIMIT 1;

  IF v_fuel_old_id IS NOT NULL AND v_fuel_new_id IS NOT NULL THEN
    -- Move journal entries
    UPDATE account_ledger_entries SET account_id = v_fuel_new_id WHERE account_id = v_fuel_old_id;
    -- Move treasury balances
    UPDATE treasury_balances SET account_id = v_fuel_new_id WHERE account_id = v_fuel_old_id;
    -- Move legacy transactions
    UPDATE transactions SET account_id = v_fuel_new_id WHERE account_id = v_fuel_old_id;
    -- Update expense categories or related
    UPDATE expense_categories SET default_account_id = v_fuel_new_id WHERE default_account_id = v_fuel_old_id;
    
    -- Delete the old account
    DELETE FROM accounts WHERE id = v_fuel_old_id;
  END IF;

  -- 2. Fix Engineer Fees (112001) - Should be an expense
  SELECT id INTO v_engineer_fees_id FROM accounts WHERE account_code = '112001' LIMIT 1;
  IF v_engineer_fees_id IS NOT NULL THEN
    UPDATE accounts 
    SET account_code = '6170', 
        account_type = 'expense', 
        parent_id = (SELECT id FROM accounts WHERE account_code = '6000' LIMIT 1),
        updated_at = now()
    WHERE id = v_engineer_fees_id;
  END IF;

  -- 3. Fix Export Expenses (1050) - Should be an expense
  SELECT id INTO v_export_fees_id FROM accounts WHERE account_code = '1050' LIMIT 1;
  IF v_export_fees_id IS NOT NULL THEN
    UPDATE accounts 
    SET account_code = '6180', 
        account_type = 'expense', 
        parent_id = (SELECT id FROM accounts WHERE account_code = '6000' LIMIT 1),
        updated_at = now()
    WHERE id = v_export_fees_id;
  END IF;

  -- 4. Fix Suspense Account (9000) - Should not be Equity
  SELECT id INTO v_suspense_id FROM accounts WHERE account_code = '9000' LIMIT 1;
  IF v_suspense_id IS NOT NULL THEN
    UPDATE accounts 
    SET account_type = 'liability',
        updated_at = now()
    WHERE id = v_suspense_id;
  END IF;

END;
$$;

COMMIT;
