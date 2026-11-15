-- ==============================================================================
-- Migration: Add branch_id and branch details to v_journal_entry_lines
-- Exposes branch_id, branch_name, branch_code for analytical expense reporting
-- ==============================================================================

-- 1. Drop dependent function and views in correct order
DROP FUNCTION IF EXISTS public.rpc_get_journal_history(text, date, date, int);
DROP VIEW IF EXISTS public.journal_entry_lines CASCADE;
DROP VIEW IF EXISTS public.v_journal_entry_lines CASCADE;

-- 2. Recreate v_journal_entry_lines with branch_id, branch_name, branch_code
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
    ale.branch_id,
    st.name AS branch_name,
    st.code AS branch_code
FROM account_ledger_entries ale
JOIN journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN accounts a ON a.id = ale.account_id
LEFT JOIN stations st ON st.id = ale.branch_id
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;

-- 3. Recreate compatibility view journal_entry_lines
CREATE OR REPLACE VIEW public.journal_entry_lines AS
SELECT * FROM public.v_journal_entry_lines;

GRANT SELECT ON public.journal_entry_lines TO authenticated, service_role, anon;

-- 4. Recreate rpc_get_journal_history with matching return type
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
