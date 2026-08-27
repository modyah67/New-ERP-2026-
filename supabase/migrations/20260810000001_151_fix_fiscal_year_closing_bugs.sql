-- Migration: 151_fix_fiscal_year_closing_bugs
-- Description: Updates get_account_balances_for_fy and get_account_balances_with_currency to read from account_ledger_entries instead of transactions. Also adds SECURITY DEFINER to release_closing_lock.

-- 1. Fix get_account_balances_for_fy
CREATE OR REPLACE FUNCTION "public"."get_account_balances_for_fy"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(jsonb_object_agg(
    account_code,
    jsonb_build_object('debit', debit, 'credit', credit)
  ), '{}'::jsonb)
  FROM (
    SELECT
      a.account_code,
      COALESCE(SUM(t.debit), 0)::numeric AS debit,
      COALESCE(SUM(t.credit), 0)::numeric AS credit
    FROM public.account_ledger_entries t
    JOIN public.accounts a ON t.account_id = a.id
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE t.created_at::date BETWEEN fy.start_date AND fy.end_date
    GROUP BY a.account_code
  ) totals;
$$;

-- 2. Fix get_account_balances_with_currency
CREATE OR REPLACE FUNCTION "public"."get_account_balances_with_currency"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(jsonb_object_agg(
    account_code,
    jsonb_build_object('debit', debit, 'credit', credit, 'balance', balance)
  ), '{}'::jsonb)
  FROM (
    SELECT
      a.account_code,
      COALESCE(SUM(t.debit), 0)::numeric AS debit,
      COALESCE(SUM(t.credit), 0)::numeric AS credit,
      (COALESCE(SUM(t.debit), 0) - COALESCE(SUM(t.credit), 0))::numeric AS balance
    FROM public.account_ledger_entries t
    JOIN public.accounts a ON t.account_id = a.id
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE t.created_at::date BETWEEN fy.start_date AND fy.end_date
    GROUP BY a.account_code
  ) totals;
$$;

-- 3. Fix release_closing_lock (Add SECURITY DEFINER)
CREATE OR REPLACE FUNCTION "public"."release_closing_lock"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = NULL,
      released_at = now(),
      status = 'FREE'
  WHERE id = 1;
END;
$$;
