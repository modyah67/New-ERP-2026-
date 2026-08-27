-- Migration 171: Fix get_ledger_page_rpc missing RECURSIVE and add currency support
-- 1. Fix Syntax Error: Added RECURSIVE to WITH target_accounts CTE which caused the RPC to fail
-- 2. Multi-currency support: Added p_currency parameter and filtering logic
-- 3. Base currency amounts: When p_currency IS NULL (All Currencies), return amount_in_base_currency
--    to ensure EGP-equivalent amounts are shown for non-EGP transactions.

DROP FUNCTION IF EXISTS public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION public.get_ledger_page_rpc(
  p_account_id TEXT DEFAULT NULL,
  p_from_date TEXT DEFAULT NULL,
  p_to_date TEXT DEFAULT NULL,
  p_cursor_date TEXT DEFAULT NULL,
  p_cursor_id TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_currency TEXT DEFAULT NULL
)
RETURNS TABLE(
  id TEXT,
  date TEXT,
  entry_number TEXT,
  account_id TEXT,
  account_code TEXT,
  account_name TEXT,
  description TEXT,
  debit NUMERIC,
  credit NUMERIC,
  reference_type TEXT,
  reference_id TEXT,
  next_cursor_date TEXT,
  next_cursor_id TEXT,
  has_more BOOLEAN,
  opening_balance_debit NUMERIC,
  opening_balance_credit NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_cursor_ts TIMESTAMPTZ;
  v_ob_debit NUMERIC := 0;
  v_ob_credit NUMERIC := 0;
  v_cursor_entry_id BIGINT;
BEGIN
  -- Parse cursor
  IF p_cursor_date IS NOT NULL AND p_cursor_id IS NOT NULL AND p_cursor_date != '' AND p_cursor_id != '' THEN
    v_cursor_ts := p_cursor_date::TIMESTAMPTZ;
    v_cursor_entry_id := p_cursor_id::BIGINT;
  END IF;

  -- Compute opening balance
  IF v_cursor_ts IS NOT NULL THEN
    SELECT
      COALESCE(SUM(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.debit
        END
      ), 0),
      COALESCE(SUM(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.credit
        END
      ), 0)
    INTO v_ob_debit, v_ob_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    WHERE (p_account_id IS NULL OR ale.account_id IN (
      WITH RECURSIVE target_accounts AS (
        SELECT acc0.id FROM accounts acc0 WHERE p_account_id IS NOT NULL AND (acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id)
        UNION ALL
        SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
      )
      SELECT target_accounts.id FROM target_accounts
    ))
      AND (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND je.entry_date < (v_cursor_ts AT TIME ZONE 'UTC')::DATE
      AND (p_currency IS NULL OR ale.currency = p_currency);
  ELSE
    IF p_from_date IS NOT NULL AND p_from_date != '' THEN
      SELECT
        COALESCE(SUM(
          CASE
            WHEN p_currency IS NULL THEN CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
            ELSE ale.debit
          END
        ), 0),
        COALESCE(SUM(
          CASE
            WHEN p_currency IS NULL THEN CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
            ELSE ale.credit
          END
        ), 0)
      INTO v_ob_debit, v_ob_credit
      FROM account_ledger_entries ale
      INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
      WHERE (p_account_id IS NULL OR ale.account_id IN (
        WITH RECURSIVE target_accounts AS (
          SELECT acc0.id FROM accounts acc0 WHERE p_account_id IS NOT NULL AND (acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id)
          UNION ALL
          SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
        )
        SELECT target_accounts.id FROM target_accounts
      ))
        AND (je.deleted_at IS NULL)
        AND (ale.deleted_at IS NULL)
        AND je.entry_date < p_from_date::DATE
        AND (p_currency IS NULL OR ale.currency = p_currency);
    END IF;
  END IF;

  RETURN QUERY
  WITH RECURSIVE target_accounts AS (
    SELECT acc0.id FROM accounts acc0 WHERE p_account_id IS NOT NULL AND (acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  ),
  raw_page AS (
    SELECT
      ale.id::TEXT AS r_id,
      je.entry_date::TEXT AS r_date,
      COALESCE(je.entry_number, '')::TEXT AS r_entry_number,
      ale.account_id::TEXT AS r_account_id,
      COALESCE(a.account_code, '')::TEXT AS r_account_code,
      COALESCE(a.account_name, a.name, '')::TEXT AS r_account_name,
      COALESCE(NULLIF(ale.description, ''), NULLIF(je.description, ''), '')::TEXT AS r_description,
      COALESCE(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.debit
        END, 0
      ) AS r_debit,
      COALESCE(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.credit
        END, 0
      ) AS r_credit,
      COALESCE(je.source_type, '')::TEXT AS r_reference_type,
      COALESCE(je.source_id, '')::TEXT AS r_reference_id,
      ale.id AS ale_order_id,
      je.entry_date AS je_order_date
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    LEFT JOIN accounts a ON a.id = ale.account_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_account_id IS NULL OR ale.account_id IN (SELECT target_accounts.id FROM target_accounts))
      AND (p_from_date IS NULL OR p_from_date = '' OR je.entry_date >= p_from_date::DATE)
      AND (p_to_date IS NULL OR p_to_date = '' OR je.entry_date <= p_to_date::DATE)
      AND (p_currency IS NULL OR ale.currency = p_currency)
      AND (
        v_cursor_ts IS NULL
        OR je.entry_date > (v_cursor_ts AT TIME ZONE 'UTC')::DATE
        OR (je.entry_date = (v_cursor_ts AT TIME ZONE 'UTC')::DATE
            AND ale.id > v_cursor_entry_id)
      )
    ORDER BY je.entry_date ASC, ale.id ASC
    LIMIT (p_limit + 1)
  ),
  page_data AS (
    SELECT * FROM raw_page LIMIT p_limit
  ),
  has_more_val AS (
    SELECT (COUNT(*) > p_limit) AS hm FROM raw_page
  )
  SELECT
    pd.r_id AS id,
    pd.r_date AS date,
    pd.r_entry_number AS entry_number,
    pd.r_account_id AS account_id,
    pd.r_account_code AS account_code,
    pd.r_account_name AS account_name,
    pd.r_description AS description,
    pd.r_debit AS debit,
    pd.r_credit AS credit,
    pd.r_reference_type AS reference_type,
    pd.r_reference_id AS reference_id,
    (SELECT p2.r_date FROM page_data p2 ORDER BY p2.je_order_date DESC, p2.ale_order_id DESC LIMIT 1)::TEXT AS next_cursor_date,
    (SELECT p2.r_id FROM page_data p2 ORDER BY p2.je_order_date DESC, p2.ale_order_id DESC LIMIT 1)::TEXT AS next_cursor_id,
    COALESCE((SELECT hm FROM has_more_val), false) AS has_more,
    v_ob_debit AS opening_balance_debit,
    v_ob_credit AS opening_balance_credit
  FROM page_data pd;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated, anon, service_role;
