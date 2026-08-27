-- Migration 082: Fix journal entry view, general ledger RPC, and fiscal year uniqueness

-- 1. Upgrade v_journal_entry_lines with journal_entry_id, accounts info and source identifiers
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
    je.source_type,
    je.source_id,
    je.status
FROM account_ledger_entries ale
JOIN journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN accounts a ON a.id = ale.account_id
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;

-- 2. Fix get_ledger_page_rpc (resolve ambiguous column reference "id")
DROP FUNCTION IF EXISTS public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.get_ledger_page_rpc(
  p_account_id TEXT DEFAULT NULL,
  p_from_date TEXT DEFAULT NULL,
  p_to_date TEXT DEFAULT NULL,
  p_cursor_date TEXT DEFAULT NULL,
  p_cursor_id TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
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
      COALESCE(SUM(ale.debit), 0),
      COALESCE(SUM(ale.credit), 0)
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
      AND je.entry_date < (v_cursor_ts AT TIME ZONE 'UTC')::DATE;
  ELSE
    IF p_from_date IS NOT NULL AND p_from_date != '' THEN
      SELECT
        COALESCE(SUM(ale.debit), 0),
        COALESCE(SUM(ale.credit), 0)
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
        AND je.entry_date < p_from_date::DATE;
    END IF;
  END IF;

  RETURN QUERY
  WITH target_accounts AS (
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
      COALESCE(ale.debit, 0) AS r_debit,
      COALESCE(ale.credit, 0) AS r_credit,
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

GRANT EXECUTE ON FUNCTION public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated, anon, service_role;

-- 3. Add rpc_get_journal_entry for clean and fast single entry retrieval
CREATE OR REPLACE FUNCTION public.rpc_get_journal_entry(
  p_entry_number TEXT DEFAULT NULL,
  p_journal_entry_id BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_je RECORD;
  v_lines JSONB;
BEGIN
  SELECT * INTO v_je
  FROM journal_entries
  WHERE deleted_at IS NULL
    AND (
      (p_journal_entry_id IS NOT NULL AND id = p_journal_entry_id)
      OR (p_entry_number IS NOT NULL AND entry_number = p_entry_number)
      OR (p_entry_number IS NOT NULL AND id::TEXT = p_entry_number)
      OR (p_entry_number IS NOT NULL AND source_id = p_entry_number)
    )
  ORDER BY id DESC
  LIMIT 1;

  IF v_je.id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ale.id,
      'account_id', ale.account_id,
      'account_code', COALESCE(a.account_code, ''),
      'account_name', COALESCE(a.account_name, a.name, ''),
      'debit', COALESCE(ale.debit, 0),
      'credit', COALESCE(ale.credit, 0),
      'type', CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END,
      'amount', CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END,
      'description', ale.description
    )
  ), '[]'::jsonb) INTO v_lines
  FROM account_ledger_entries ale
  LEFT JOIN accounts a ON a.id = ale.account_id
  WHERE ale.journal_entry_id = v_je.id
    AND ale.deleted_at IS NULL;

  RETURN jsonb_build_object(
    'id', v_je.id,
    'entry_number', v_je.entry_number,
    'entry_date', v_je.entry_date,
    'description', v_je.description,
    'source_type', v_je.source_type,
    'source_id', v_je.source_id,
    'created_by', v_je.created_by,
    'created_at', v_je.created_at,
    'lines', v_lines
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_journal_entry(TEXT, BIGINT) TO authenticated, anon, service_role;

-- 4. Clean up duplicate is_current fiscal years (safe wrapper)
DO $$
BEGIN
  UPDATE fiscal_years SET is_current = false WHERE id != 2 AND is_current = true;
  UPDATE fiscal_years SET is_current = true WHERE id = 2;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Fiscal year cleanup skipped: %', SQLERRM;
END $$;
