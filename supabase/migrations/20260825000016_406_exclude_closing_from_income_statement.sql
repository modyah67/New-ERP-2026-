-- ============================================================================
-- Migration 406: Support Excluding Closing Entries from Operational Reports
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_account_totals_rpc(
  p_from DATE DEFAULT NULL,
  p_to DATE DEFAULT NULL,
  p_currency TEXT DEFAULT NULL,
  p_exclude_closing BOOLEAN DEFAULT FALSE
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
          CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END
        ELSE
          ale.debit
      END
    ), 0)::numeric AS debit,
    COALESCE(SUM(
      CASE
        WHEN p_currency IS NULL THEN
          CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END
        ELSE
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
    AND (p_exclude_closing IS NOT TRUE OR je.source_type != 'fiscal_year_closing')
  GROUP BY ale.account_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_account_totals_rpc(DATE, DATE, TEXT, BOOLEAN) TO authenticated, anon, service_role;

COMMIT;
