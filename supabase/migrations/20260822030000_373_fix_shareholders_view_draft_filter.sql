-- ============================================================================
-- Migration 373: Exclude Draft Transactions from Shareholder Balances & View
-- ============================================================================
-- Description:
-- Fixes public.v_shareholders view so that draft transactions (status = 'draft')
-- in treasury_transactions and bank_account_transactions are NOT included in
-- shareholder balances, deposits, or withdrawals. Only confirmed transactions count.
-- ============================================================================

DROP VIEW IF EXISTS public.v_shareholders CASCADE;

CREATE OR REPLACE VIEW public.v_shareholders AS
SELECT 
  s.*,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_egp, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_egp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'EGP' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'incoming' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'EGP'), 0)
  ) AS total_deposits_egp,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_egp, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_egp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'EGP' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EGP' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'outgoing' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'EGP'), 0)
  ) AS total_withdrawals_egp,

  (
    CASE WHEN COALESCE(s.initial_balance_direction_usd, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_usd, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'USD' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'incoming' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'USD'), 0)
  ) AS total_deposits_usd,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_usd, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_usd, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'USD' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'USD' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'outgoing' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'USD'), 0)
  ) AS total_withdrawals_usd,

  (
    CASE WHEN COALESCE(s.initial_balance_direction_eur, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_eur, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'EUR' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'incoming' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'EUR'), 0)
  ) AS total_deposits_eur,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_eur, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_eur, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'EUR' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'EUR' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'outgoing' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'EUR'), 0)
  ) AS total_withdrawals_eur,

  (
    CASE WHEN COALESCE(s.initial_balance_direction_gbp, 'CREDIT') = 'CREDIT' THEN COALESCE(s.initial_balance_gbp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('deposit', 'shareholder_deposit') AND currency = 'GBP' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'deposit' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'incoming' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'GBP'), 0)
  ) AS total_deposits_gbp,
  (
    CASE WHEN COALESCE(s.initial_balance_direction_gbp, 'CREDIT') = 'DEBIT' THEN COALESCE(s.initial_balance_gbp, 0) ELSE 0 END 
    + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE type IN ('expense', 'shareholder_withdrawal') AND currency = 'GBP' AND shareholder_id = s.id AND (status = 'confirmed' OR status IS NULL)), 0) 
    + COALESCE((SELECT SUM(bat.amount) FROM bank_account_transactions bat JOIN bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type = 'withdraw' AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::TEXT AND ba.currency = 'GBP' AND (bat.status = 'confirmed' OR bat.status IS NULL)), 0)
    + COALESCE((SELECT SUM(amount) FROM cheques WHERE type = 'outgoing' AND status = 'cleared' AND shareholder_id = s.id AND currency = 'GBP'), 0)
  ) AS total_withdrawals_gbp
FROM public.shareholders s;

GRANT ALL ON TABLE public.v_shareholders TO authenticated;
GRANT ALL ON TABLE public.v_shareholders TO service_role;
GRANT ALL ON TABLE public.v_shareholders TO anon;

NOTIFY pgrst, 'reload_schema';
