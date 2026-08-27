BEGIN;

-- 1. Fix the unique index to allow soft-deleted records to coexist
DROP INDEX IF EXISTS idx_spd_unique_dist;
CREATE UNIQUE INDEX idx_spd_unique_dist ON public.shareholder_profit_distributions (shipment_id, shareholder_id, person_index) WHERE deleted_at IS NULL;

-- 2. Update v_shareholders to include profit distributions (which increase the balance / act as a deposit of equity)
DROP VIEW IF EXISTS public.v_shareholders;
CREATE OR REPLACE VIEW public.v_shareholders AS
SELECT 
  s.*,
  (
    CASE WHEN COALESCE(s.initial_balance_egp, 0) > 0 THEN COALESCE(s.initial_balance_egp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'deposit' AND currency = 'EGP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP'), 0)
    + COALESCE((SELECT SUM(converted_amount) FROM shareholder_profit_distributions WHERE shareholder_id = s.id AND currency = 'EGP' AND deleted_at IS NULL), 0)
  ) AS total_deposits_egp,
  (
    CASE WHEN COALESCE(s.initial_balance_egp, 0) < 0 THEN ABS(COALESCE(s.initial_balance_egp, 0)) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'expense' AND currency = 'EGP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP'), 0)
  ) AS total_withdrawals_egp,

  (
    CASE WHEN COALESCE(s.initial_balance_usd, 0) > 0 THEN COALESCE(s.initial_balance_usd, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'deposit' AND currency = 'USD' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD'), 0)
    + COALESCE((SELECT SUM(converted_amount) FROM shareholder_profit_distributions WHERE shareholder_id = s.id AND currency = 'USD' AND deleted_at IS NULL), 0)
  ) AS total_deposits_usd,
  (
    CASE WHEN COALESCE(s.initial_balance_usd, 0) < 0 THEN ABS(COALESCE(s.initial_balance_usd, 0)) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'expense' AND currency = 'USD' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD'), 0)
  ) AS total_withdrawals_usd,

  (
    CASE WHEN COALESCE(s.initial_balance_eur, 0) > 0 THEN COALESCE(s.initial_balance_eur, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'deposit' AND currency = 'EUR' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR'), 0)
    + COALESCE((SELECT SUM(converted_amount) FROM shareholder_profit_distributions WHERE shareholder_id = s.id AND currency = 'EUR' AND deleted_at IS NULL), 0)
  ) AS total_deposits_eur,
  (
    CASE WHEN COALESCE(s.initial_balance_eur, 0) < 0 THEN ABS(COALESCE(s.initial_balance_eur, 0)) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'expense' AND currency = 'EUR' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR'), 0)
  ) AS total_withdrawals_eur,

  (
    CASE WHEN COALESCE(s.initial_balance_gbp, 0) > 0 THEN COALESCE(s.initial_balance_gbp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'deposit' AND currency = 'GBP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP'), 0)
    + COALESCE((SELECT SUM(converted_amount) FROM shareholder_profit_distributions WHERE shareholder_id = s.id AND currency = 'GBP' AND deleted_at IS NULL), 0)
  ) AS total_deposits_gbp,
  (
    CASE WHEN COALESCE(s.initial_balance_gbp, 0) < 0 THEN ABS(COALESCE(s.initial_balance_gbp, 0)) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type = 'expense' AND currency = 'GBP' AND shareholder_id = s.id), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP'), 0)
  ) AS total_withdrawals_gbp
FROM public.shareholders s;

COMMIT;
