-- ============================================================================
-- Migration 422: Fix Ledger Opening Balance Multi-Currency Support
-- ============================================================================
-- 1. Updates get_balance_before_date_rpc:
--    - Accepts p_currency text DEFAULT NULL::text.
--    - When p_currency IS NULL OR p_currency = 'ALL':
--        Uses amount_in_base_currency so opening balance in unified EGP mode
--        is 100% accurate.
--    - When p_currency is specified (e.g. 'USD', 'EUR'):
--        Filters by ale.currency = p_currency and sums debit/credit.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_balance_before_date_rpc(text, date);

CREATE OR REPLACE FUNCTION public.get_balance_before_date_rpc(
    p_account_id text,
    p_before_date date,
    p_currency text DEFAULT NULL::text
)
RETURNS TABLE(debit numeric, credit numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
  WITH RECURSIVE target_accounts AS (
    SELECT id FROM accounts WHERE (p_account_id IS NULL OR p_account_id = '' OR id::TEXT = p_account_id OR account_code = p_account_id OR code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  )
  SELECT
    COALESCE(SUM(
      CASE 
        WHEN p_currency IS NULL OR p_currency = 'ALL' THEN
          CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
        ELSE ale.debit
      END
    ), 0)::numeric AS debit,
    COALESCE(SUM(
      CASE 
        WHEN p_currency IS NULL OR p_currency = 'ALL' THEN
          CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
        ELSE ale.credit
      END
    ), 0)::numeric AS credit
  FROM account_ledger_entries ale
  INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE ale.account_id IN (SELECT id FROM target_accounts)
    AND (je.deleted_at IS NULL)
    AND (ale.deleted_at IS NULL)
    AND je.entry_date < p_before_date
    AND (p_currency IS NULL OR p_currency = 'ALL' OR ale.currency = p_currency);
$function$;

GRANT EXECUTE ON FUNCTION public.get_balance_before_date_rpc(text, date, text) TO authenticated, anon, service_role;

COMMIT;
