-- Migration 087: Fix multi-currency balance display
--
-- 1. Recalculate amount_in_base_currency from exchange_rates for all
--    account_ledger_entries where it is 0 or NULL but currency != 'EGP'
-- 2. Backfill currency on existing account_ledger_entries where currency is NULL
--
-- NOTE ON EXCHANGE RATE ACCURACY:
-- ─────────────────────────────────────────────────────────────────────
-- amount_in_base_currency is calculated using the CURRENT exchange rate
-- from the exchange_rates table (rate_to_egp as of today's date), NOT
-- the historical rate at the time the journal entry was originally posted.
--
-- This is because the system does NOT store per-entry historical exchange
-- rates — only the latest rate per currency is available via
-- exchange_rates.updated_at.
--
-- This is a KNOWN and ACCEPTED approximation for the delivery scope.
-- For full accuracy, a per-entry historical rate column would need to
-- be added to account_ledger_entries in a future phase.
-- ─────────────────────────────────────────────────────────────────────

-- ── 1. Recalculate amount_in_base_currency ──────────────────────────────────
UPDATE public.account_ledger_entries ale
SET amount_in_base_currency = CASE
    WHEN ale.currency = 'EGP' OR ale.currency IS NULL THEN COALESCE(ale.debit, 0) + COALESCE(ale.credit, 0)
    ELSE (COALESCE(ale.debit, 0) + COALESCE(ale.credit, 0)) * COALESCE(
        (SELECT rate_to_egp FROM public.exchange_rates er
         WHERE er.currency_code = ale.currency
         ORDER BY er.updated_at DESC LIMIT 1),
        1.0
    )
END
WHERE ale.amount_in_base_currency = 0
   OR ale.amount_in_base_currency IS NULL;

-- ── 2. Backfill currency on NULL currency entries ───────────────────────────
UPDATE public.account_ledger_entries
SET currency = 'EGP'
WHERE currency IS NULL OR currency = '';

-- ── 3. Ensure view v_journal_entry_lines exposes currency column ────────────
DROP VIEW IF EXISTS public.v_journal_entry_lines;
CREATE OR REPLACE VIEW public.v_journal_entry_lines AS
SELECT
    ale.id,
    ale.journal_entry_id,
    je.id AS entry_id,
    je.entry_number,
    je.entry_date AS transaction_date,
    ale.account_id,
    COALESCE(a.account_code, '') AS account_code,
    COALESCE(a.account_name, a.name, '') AS account_name,
    CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END AS type,
    CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END AS amount,
    ale.description,
    je.created_by,
    je.created_at,
    je.company_id,
    ale.debit,
    ale.credit,
    ale.currency,
    ale.amount_in_base_currency,
    je.source_type,
    je.source_id,
    je.status
FROM account_ledger_entries ale
JOIN journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN accounts a ON a.id = ale.account_id
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;
