BEGIN;

CREATE OR REPLACE FUNCTION rpc_get_journal_history(p_search text DEFAULT NULL, p_from_date date DEFAULT NULL, p_to_date date DEFAULT NULL, p_limit int DEFAULT 300)
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
      ORDER BY entry_number DESC 
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN latest l ON l.id = v.entry_id
    ORDER BY v.entry_number DESC;
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
      ORDER BY MAX(entry_number) DESC
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN matched_entries m ON m.entry_id = v.entry_id
    ORDER BY v.entry_number DESC;
  END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION rpc_get_journal_history(text, date, date, int) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_get_journal_history(text, date, date, int) TO service_role;

COMMIT;
