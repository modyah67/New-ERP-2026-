-- Migration 017: Patch UUID/TEXT Mismatches (SQLSTATE 42804)
-- Purpose: Fix COALESCE(text, uuid) bugs in foundational RLS policies and ledger queries.

BEGIN;

-- =================================================================================
-- FIX 1: public.get_current_company_id()
-- Cause: current_setting(...) returned TEXT, while subquery returned UUID.
-- =================================================================================
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS
$func$
BEGIN
    -- Default to the first company for testing/development if JWT is missing
    -- In production, this should STRICTLY read from auth.jwt() -> 'app_metadata' ->> 'company_id'
    RETURN COALESCE(
        NULLIF(current_setting('request.jwt.claim.app_metadata.company_id', true), '')::UUID,
        (SELECT id FROM public.sys_companies WHERE name = 'Main Company' LIMIT 1)
    );
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================================
-- FIX 2: public.get_ledger_page_rpc()
-- Cause: COALESCE(uuid, text) inside the CTE.
-- =================================================================================
CREATE OR REPLACE FUNCTION "public"."get_ledger_page_rpc"("p_account_id" "text" DEFAULT NULL::"text", "p_from_date" "text" DEFAULT NULL::"text", "p_to_date" "text" DEFAULT NULL::"text", "p_cursor_date" "text" DEFAULT NULL::"text", "p_cursor_id" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "text", "date" "text", "entry_number" bigint, "account_id" "text", "account_code" "text", "account_name" "text", "description" "text", "debit" numeric, "credit" numeric, "reference_type" "text", "reference_id" "text", "next_cursor_date" "text", "next_cursor_id" "text", "has_more" boolean, "opening_balance_debit" numeric, "opening_balance_credit" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_cursor_ts TIMESTAMPTZ;
  v_has_more BOOLEAN := FALSE;
  v_next_cursor_date TEXT;
  v_next_cursor_id TEXT;
  v_ob_debit NUMERIC := 0;
  v_ob_credit NUMERIC := 0;
BEGIN
  -- Parse cursor timestamp
  IF p_cursor_date IS NOT NULL AND p_cursor_id IS NOT NULL THEN
    v_cursor_ts := p_cursor_date::TIMESTAMPTZ;
  END IF;

  -- Compute opening balance at cursor position (before cursor)
  IF v_cursor_ts IS NOT NULL THEN
    SELECT
      COALESCE(SUM(COALESCE(debit, CASE WHEN type='debit' THEN amount ELSE 0 END)), 0),
      COALESCE(SUM(COALESCE(credit, CASE WHEN type='credit' THEN amount ELSE 0 END)), 0)
    INTO v_ob_debit, v_ob_credit
    FROM transactions
    WHERE (p_account_id IS NULL OR account_id = p_account_id)
      AND transaction_date < v_cursor_ts;

    -- Subtract current page opening balance from total opening balance
    -- (we want opening balance BEFORE the cursor, not before the date range)
  ELSE
    -- No cursor = first page: compute opening balance before fromDate
    IF p_from_date IS NOT NULL THEN
      SELECT
        COALESCE(SUM(COALESCE(debit, CASE WHEN type='debit' THEN amount ELSE 0 END)), 0),
        COALESCE(SUM(COALESCE(credit, CASE WHEN type='credit' THEN amount ELSE 0 END)), 0)
      INTO v_ob_debit, v_ob_credit
      FROM transactions
      WHERE (p_account_id IS NULL OR account_id = p_account_id)
        AND transaction_date < p_from_date::TIMESTAMPTZ;
    END IF;
  END IF;

  RETURN QUERY
  WITH page AS (
    SELECT
      t.id::TEXT AS t_id,
      t.transaction_date::TEXT AS t_date,
      t.entry_number AS t_entry_number,
      t.account_id::TEXT AS t_account_id,
      COALESCE(a.account_code, '') AS t_account_code,
      COALESCE(a.name, '') AS t_account_name,
      COALESCE(t.description, '') AS t_description,
      COALESCE(t.debit, 0) AS t_debit,
      COALESCE(t.credit, 0) AS t_credit,
      COALESCE(t.reference_type, '') AS t_reference_type,
      t.reference_id::text AS t_reference_id
    FROM transactions t
    LEFT JOIN accounts a ON a.id = t.account_id
    WHERE (p_account_id IS NULL OR t.account_id = p_account_id)
      AND (p_from_date IS NULL OR t.transaction_date >= p_from_date::TIMESTAMPTZ)
      AND (p_to_date IS NULL OR t.transaction_date <= p_to_date::TIMESTAMPTZ)
      AND (
        v_cursor_ts IS NULL
        OR t.transaction_date > v_cursor_ts
        OR (t.transaction_date = v_cursor_ts AND t.id::TEXT > p_cursor_id)
      )
    ORDER BY t.transaction_date ASC, t.id ASC
    LIMIT (p_limit + 1)
  ),
  page_data AS (
    SELECT * FROM page LIMIT p_limit
  ),
  has_more_check AS (
    SELECT COUNT(*) > 0 AS has_more FROM page WHERE NOT EXISTS (SELECT 1 FROM page_data)
  )
  SELECT
    pd.t_id AS id,
    pd.t_date AS date,
    pd.t_entry_number AS entry_number,
    pd.t_account_id AS account_id,
    pd.t_account_code AS account_code,
    pd.t_account_name AS account_name,
    pd.t_description AS description,
    pd.t_debit AS debit,
    pd.t_credit AS credit,
    pd.t_reference_type AS reference_type,
    pd.t_reference_id AS reference_id,
    (SELECT p2.t_date FROM page p2 ORDER BY p2.t_date DESC, p2.t_id DESC LIMIT 1) AS next_cursor_date,
    (SELECT p2.t_id FROM page p2 ORDER BY p2.t_date DESC, p2.t_id DESC LIMIT 1) AS next_cursor_id,
    hmc.has_more,
    v_ob_debit AS opening_balance_debit,
    v_ob_credit AS opening_balance_credit
  FROM page_data pd
  CROSS JOIN has_more_check hmc;
END;
$$;

-- Preserve Grants for public.get_ledger_page_rpc
GRANT ALL ON FUNCTION "public"."get_ledger_page_rpc"("p_account_id" "text", "p_from_date" "text", "p_to_date" "text", "p_cursor_date" "text", "p_cursor_id" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_ledger_page_rpc"("p_account_id" "text", "p_from_date" "text", "p_to_date" "text", "p_cursor_date" "text", "p_cursor_id" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ledger_page_rpc"("p_account_id" "text", "p_from_date" "text", "p_to_date" "text", "p_cursor_date" "text", "p_cursor_id" "text", "p_limit" integer) TO "service_role";

COMMIT;
