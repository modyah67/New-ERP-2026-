-- Migration 088: Use amount_in_base_currency for default (all-currencies) report totals
--
-- PROBLEM:
--   get_account_totals_rpc summed raw ale.debit / ale.credit which are in
--   the entry's original currency. When multiple currencies exist, this
--   produced meaningless totals (e.g. 1000 USD + 5000 EGP = 6000).
--
-- FIX:
--   When no currency filter is applied (p_currency = NULL), sum
--   amount_in_base_currency instead of raw debit/credit. This gives
--   consistent EGP-equivalent totals across all reports (Trial Balance,
--   Balance Sheet, Income Statement, Cash Flow).
--
--   When a specific currency is requested (p_currency = 'USD'), still
--   sum raw debit/credit filtered to that currency.
--
-- IMPORTANT NOTE ON EXCHANGE RATES (documented for client delivery):
-- ─────────────────────────────────────────────────────────────────────
-- amount_in_base_currency uses the CURRENT exchange rate from the
-- exchange_rates table (rate_to_egp as of today), NOT the historical
-- rate at the time the journal entry was posted.
--
-- This is because the system does NOT store historical exchange rates
-- per-entry — only the latest rate per currency is available in
-- exchange_rates.updated_at.
--
-- This is a KNOWN and ACCEPTED approximation for the delivery scope.
-- For full accuracy, a per-entry historical rate column would need to
-- be added to account_ledger_entries in a future phase.
-- ─────────────────────────────────────────────────────────────────────

-- ── 1. Upgrade get_account_totals_rpc ────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_account_totals_rpc(DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_account_totals_rpc(
  p_from DATE DEFAULT NULL,
  p_to DATE DEFAULT NULL,
  p_currency TEXT DEFAULT NULL
)
RETURNS TABLE(account_id TEXT, debit NUMERIC, credit NUMERIC)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    ale.account_id::text AS account_id,
    COALESCE(SUM(
      CASE
        WHEN p_currency IS NULL THEN
          -- DEFAULT (all currencies): use amount_in_base_currency
          -- to get consistent EGP-equivalent totals.
          -- In a journal entry line, either debit or credit is non-zero,
          -- so amount_in_base_currency = (debit + credit) * rate ≈ the
          -- single-side amount in EGP.
          CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
        ELSE
          -- SPECIFIC CURRENCY: use raw debit (in that currency)
          ale.debit
      END
    ), 0)::numeric AS debit,
    COALESCE(SUM(
      CASE
        WHEN p_currency IS NULL THEN
          -- DEFAULT (all currencies): use amount_in_base_currency
          CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
        ELSE
          -- SPECIFIC CURRENCY: use raw credit (in that currency)
          ale.credit
      END
    ), 0)::numeric AS credit
  FROM account_ledger_entries ale
  INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE (je.deleted_at IS NULL)
    AND (ale.deleted_at IS NULL)
    AND (p_from IS NULL OR je.entry_date >= p_from)
    AND (p_to IS NULL OR je.entry_date <= p_to)
    AND (p_currency IS NULL OR ale.currency = p_currency)
  GROUP BY ale.account_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_account_totals_rpc(DATE, DATE, TEXT) TO authenticated, anon, service_role;
