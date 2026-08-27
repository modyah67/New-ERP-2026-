-- Migration 185: Fix Shareholder Deposits and Withdrawals Display
-- Ensure that total_deposits and total_withdrawals ONLY sum the actual transactions
-- and DO NOT include the initial balance. 
-- This fixes the UI bug where "إيداع" and "صرف" incorrectly included the opening balances.

BEGIN;

DROP VIEW IF EXISTS public.v_shareholders;
CREATE OR REPLACE VIEW public.v_shareholders AS
SELECT 
  s.*,
  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'EGP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP'), 0)
  ) AS total_deposits_egp,
  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'EGP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP'), 0)
  ) AS total_withdrawals_egp,

  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'USD' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD'), 0)
  ) AS total_deposits_usd,
  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'USD' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD'), 0)
  ) AS total_withdrawals_usd,

  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'EUR' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR'), 0)
  ) AS total_deposits_eur,
  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'EUR' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR'), 0)
  ) AS total_withdrawals_eur,

  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'GBP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP'), 0)
  ) AS total_deposits_gbp,
  (
    COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'GBP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP'), 0)
  ) AS total_withdrawals_gbp

FROM public.shareholders s;

COMMIT;
