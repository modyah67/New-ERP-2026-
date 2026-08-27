-- Migration 183: Fix Shareholder View Treasury Transaction Types
-- The previous views were checking type = 'expense' and type = 'deposit'.
-- Treasury spend_custody and receive_custody now use 'shareholder_withdrawal' and 'shareholder_deposit'.

BEGIN;

DROP VIEW IF EXISTS public.v_shareholders;
CREATE OR REPLACE VIEW public.v_shareholders AS
SELECT 
  s.*,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_egp, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_egp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'EGP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP'), 0)
  ) AS total_deposits_egp,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_egp, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_egp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'EGP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP'), 0)
  ) AS total_withdrawals_egp,

  (
    CASE WHEN COALESCE(s.initial_balance_direction_usd, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_usd, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'USD' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD'), 0)
  ) AS total_deposits_usd,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_usd, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_usd, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'USD' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD'), 0)
  ) AS total_withdrawals_usd,

  (
    CASE WHEN COALESCE(s.initial_balance_direction_eur, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_eur, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'EUR' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR'), 0)
  ) AS total_deposits_eur,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_eur, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_eur, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'EUR' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR'), 0)
  ) AS total_withdrawals_eur,

  (
    CASE WHEN COALESCE(s.initial_balance_direction_gbp, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_gbp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'GBP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP'), 0)
  ) AS total_deposits_gbp,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_gbp, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_gbp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'GBP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP'), 0)
  ) AS total_withdrawals_gbp
FROM public.shareholders s;

COMMIT;
