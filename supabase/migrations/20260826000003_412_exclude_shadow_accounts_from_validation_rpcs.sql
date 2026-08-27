-- Migration 412: Exclude 2100 branch, sub-accounts (2101, 2102, 2105) and 5210 from financial validation RPCs

CREATE OR REPLACE FUNCTION public.validate_trial_balance_rpc(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(total_debit numeric, total_credit numeric, is_balanced boolean, difference numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  WITH totals AS (
    SELECT
      COALESCE(SUM(ale.debit), 0)::numeric AS total_debit,
      COALESCE(SUM(ale.credit), 0)::numeric AS total_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    INNER JOIN accounts a ON a.id = ale.account_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_from IS NULL OR je.entry_date >= p_from)
      AND (p_to IS NULL OR je.entry_date <= p_to)
      AND COALESCE(a.account_code, a.code) NOT IN ('2100', '2101', '2102', '2105', '5210')
  )
  SELECT
    t.total_debit,
    t.total_credit,
    ABS(t.total_debit - t.total_credit) < 0.01 AS is_balanced,
    t.total_debit - t.total_credit AS difference
  FROM totals t;
$function$;

CREATE OR REPLACE FUNCTION public.validate_balance_sheet_rpc(p_as_of_date date DEFAULT NULL::date)
 RETURNS TABLE(total_assets numeric, total_liabilities numeric, total_equity numeric, total_liabilities_and_equity numeric, is_balanced boolean, difference numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  WITH account_balances AS (
    SELECT
      ale.account_id,
      COALESCE(SUM(ale.debit), 0) AS total_debit,
      COALESCE(SUM(ale.credit), 0) AS total_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    INNER JOIN accounts a ON a.id = ale.account_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_as_of_date IS NULL OR je.entry_date <= p_as_of_date)
      AND COALESCE(a.account_code, a.code) NOT IN ('2100', '2101', '2102', '2105', '5210')
    GROUP BY ale.account_id
  ),
  classified AS (
    SELECT
      ab.total_debit,
      ab.total_credit,
      CASE
        WHEN a.account_type = 'asset' THEN 'asset'
        WHEN a.account_type = 'liability' THEN 'liability'
        WHEN a.account_type = 'equity' THEN 'equity'
        ELSE 'other'
      END AS classification,
      CASE
        WHEN a.account_type = 'asset' THEN ab.total_debit - ab.total_credit
        ELSE ab.total_credit - ab.total_debit
      END AS net_balance
    FROM account_balances ab
    INNER JOIN accounts a ON a.id = ab.account_id
    WHERE a.account_type IN ('asset', 'liability', 'equity')
  ),
  summed AS (
    SELECT
      COALESCE(SUM(CASE WHEN classification = 'asset' THEN net_balance ELSE 0 END), 0) AS total_assets,
      COALESCE(SUM(CASE WHEN classification = 'liability' THEN net_balance ELSE 0 END), 0) AS total_liabilities,
      COALESCE(SUM(CASE WHEN classification = 'equity' THEN net_balance ELSE 0 END), 0) AS total_equity
    FROM classified
  )
  SELECT
    s.total_assets,
    s.total_liabilities,
    s.total_equity,
    (s.total_liabilities + s.total_equity) AS total_liabilities_and_equity,
    ABS(s.total_assets - (s.total_liabilities + s.total_equity)) < 0.01 AS is_balanced,
    s.total_assets - (s.total_liabilities + s.total_equity) AS difference
  FROM summed s;
$function$;
