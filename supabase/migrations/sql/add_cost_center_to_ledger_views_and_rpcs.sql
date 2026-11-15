-- ==============================================================================
-- Migration: Add Cost Center Name & Code to v_journal_entry_lines and get_ledger_page_rpc
-- ==============================================================================

-- 1. Drop dependent function and view first to prevent Postgres 42P16
DROP FUNCTION IF EXISTS public.rpc_get_journal_history(text, date, date, int);
DROP VIEW IF EXISTS public.journal_entry_lines CASCADE;
DROP VIEW IF EXISTS public.v_journal_entry_lines CASCADE;

-- 2. Recreate v_journal_entry_lines with cost_center_name and cost_center_code
CREATE OR REPLACE VIEW public.v_journal_entry_lines AS
SELECT
    ale.id,
    ale.journal_entry_id,
    je.id AS entry_id,
    je.entry_number,
    je.entry_date AS transaction_date,
    ale.account_id,
    COALESCE(NULLIF(a.account_code, ''), NULLIF(a.code, ''), '') AS account_code,
    COALESCE(NULLIF(a.account_name, ''), NULLIF(a.name, ''), '') AS account_name,
    CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END AS type,
    (CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END) AS amount,
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
    je.status,
    ale.cost_center_id,
    COALESCE(cc.name_ar, cc.name, cc.code, ale.cost_center_id, '') AS cost_center_name,
    COALESCE(cc.code, ale.cost_center_id, '') AS cost_center_code,
    ale.entity_type,
    ale.entity_id,
    ale.branch_id,
    st.name AS branch_name,
    st.code AS branch_code
FROM public.account_ledger_entries ale
JOIN public.journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN public.accounts a ON a.id = ale.account_id
LEFT JOIN public.stations st ON st.id = ale.branch_id
LEFT JOIN public.cost_centers cc ON (
    cc.code = ale.cost_center_id 
    OR cc.code = 'CC-' || UPPER(ale.cost_center_id)
    OR (ale.cost_center_id = 'general_admin' AND cc.code = 'CC-ADMIN')
    OR (ale.cost_center_id = 'packing_station' AND cc.code = 'CC-PACKING')
    OR (ale.cost_center_id = 'freight_logistics' AND cc.code = 'CC-LOGISTICS')
    OR (ale.cost_center_id = 'customs_clearance' AND cc.code = 'CC-CUSTOMS')
    OR cc.id::TEXT = ale.cost_center_id
)
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;

-- 3. Recreate compatibility view
CREATE OR REPLACE VIEW public.journal_entry_lines AS
SELECT * FROM public.v_journal_entry_lines;

GRANT SELECT ON public.journal_entry_lines TO authenticated, service_role, anon;

-- 4. Recreate rpc_get_journal_history with matching composite return type
CREATE OR REPLACE FUNCTION public.rpc_get_journal_history(
    p_search text DEFAULT NULL,
    p_from_date date DEFAULT NULL,
    p_to_date date DEFAULT NULL,
    p_limit int DEFAULT 300
)
RETURNS SETOF v_journal_entry_lines AS $$
BEGIN
  IF p_search IS NULL OR p_search = '' THEN
    RETURN QUERY
    WITH latest AS (
      SELECT id 
      FROM journal_entries 
      WHERE deleted_at IS NULL
        AND (p_from_date IS NULL OR entry_date >= p_from_date)
        AND (p_to_date IS NULL OR entry_date <= p_to_date)
      ORDER BY created_at DESC, id DESC 
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN latest l ON l.id = v.entry_id
    ORDER BY v.created_at DESC, v.entry_id DESC, v.id ASC;
  ELSE
    RETURN QUERY
    WITH matched_entries AS (
      SELECT entry_id
      FROM v_journal_entry_lines
      WHERE (p_from_date IS NULL OR transaction_date >= p_from_date)
        AND (p_to_date IS NULL OR transaction_date <= p_to_date)
        AND (
          entry_number ILIKE '%' || p_search || '%'
          OR account_name ILIKE '%' || p_search || '%'
          OR account_code ILIKE '%' || p_search || '%'
          OR description ILIKE '%' || p_search || '%'
          OR cost_center_name ILIKE '%' || p_search || '%'
          OR branch_name ILIKE '%' || p_search || '%'
        )
      GROUP BY entry_id
      ORDER BY MAX(created_at) DESC, entry_id DESC
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN matched_entries m ON m.entry_id = v.entry_id
    ORDER BY v.created_at DESC, v.entry_id DESC, v.id ASC;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.rpc_get_journal_history(text, date, date, int) TO authenticated, service_role, anon;

-- 5. Drop and recreate get_ledger_page_rpc with cost_center_id and cost_center_name
DROP FUNCTION IF EXISTS public.get_ledger_page_rpc(text, text, text, text, text, integer, text);

CREATE OR REPLACE FUNCTION public.get_ledger_page_rpc(
  p_account_id text DEFAULT NULL::text,
  p_from_date text DEFAULT NULL::text,
  p_to_date text DEFAULT NULL::text,
  p_cursor_date text DEFAULT NULL::text,
  p_cursor_id text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_currency text DEFAULT NULL::text
)
RETURNS TABLE(
  id text,
  date text,
  entry_number text,
  account_id text,
  account_code text,
  account_name text,
  cost_center_id text,
  cost_center_name text,
  description text,
  debit numeric,
  credit numeric,
  reference_type text,
  reference_id text,
  next_cursor_date text,
  next_cursor_id text,
  has_more boolean,
  opening_balance_debit numeric,
  opening_balance_credit numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
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
        SELECT acc0.id FROM accounts acc0 
        WHERE (p_account_id IS NULL OR p_account_id = '' OR acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id OR acc0.code = p_account_id)
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
          SELECT acc0.id FROM accounts acc0 
          WHERE (p_account_id IS NULL OR p_account_id = '' OR acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id OR acc0.code = p_account_id)
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
    SELECT acc0.id FROM accounts acc0 
    WHERE (p_account_id IS NULL OR p_account_id = '' OR acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id OR acc0.code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  ),
  raw_page AS (
    SELECT
      ale.id::TEXT AS r_id,
      je.entry_date::TEXT AS r_date,
      COALESCE(je.entry_number, '')::TEXT AS r_entry_number,
      ale.account_id::TEXT AS r_account_id,
      COALESCE(a.account_code, a.code, '')::TEXT AS r_account_code,
      COALESCE(a.account_name, a.name, '')::TEXT AS r_account_name,
      ale.cost_center_id::TEXT AS r_cost_center_id,
      COALESCE(cc.name_ar, cc.name, cc.code, ale.cost_center_id, '')::TEXT AS r_cost_center_name,
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
    LEFT JOIN public.cost_centers cc ON (
        cc.code = ale.cost_center_id 
        OR cc.code = 'CC-' || UPPER(ale.cost_center_id)
        OR (ale.cost_center_id = 'general_admin' AND cc.code = 'CC-ADMIN')
        OR (ale.cost_center_id = 'packing_station' AND cc.code = 'CC-PACKING')
        OR (ale.cost_center_id = 'freight_logistics' AND cc.code = 'CC-LOGISTICS')
        OR (ale.cost_center_id = 'customs_clearance' AND cc.code = 'CC-CUSTOMS')
        OR cc.id::TEXT = ale.cost_center_id
    )
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
    pd.r_cost_center_id AS cost_center_id,
    pd.r_cost_center_name AS cost_center_name,
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
$function$;

GRANT EXECUTE ON FUNCTION public.get_ledger_page_rpc(text, text, text, text, text, integer, text) TO authenticated, anon, service_role;
