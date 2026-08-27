-- Migration 088: Fix journal entry navigation by cleaning up duplicate rpc_get_journal_entry
-- and ensuring a single, reliable function exists.

-- Step 1: Drop ALL existing overloads of rpc_get_journal_entry
DROP FUNCTION IF EXISTS public.rpc_get_journal_entry(TEXT, BIGINT);
DROP FUNCTION IF EXISTS public.rpc_get_journal_entry(BIGINT, TEXT);

-- Step 2: Recreate as a single canonical function
CREATE OR REPLACE FUNCTION public.rpc_get_journal_entry(
  p_journal_entry_id BIGINT DEFAULT NULL,
  p_entry_number TEXT DEFAULT NULL
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
  -- Resolve the journal entry: try id first, then entry_number, then id::text, then source_id
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

  IF v_je IS NULL OR v_je.id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ale.id,
      'account_id', ale.account_id,
      'account_code', COALESCE(a.account_code, a.code, ''),
      'account_name', COALESCE(a.account_name, a.name, 'حساب غير معروف'),
      'debit', COALESCE(ale.debit, 0),
      'credit', COALESCE(ale.credit, 0),
      'currency', COALESCE(ale.currency, 'EGP'),
      'description', ale.description
    ) ORDER BY ale.id ASC
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
    'status', v_je.status,
    'created_at', v_je.created_at,
    'lines', v_lines
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_journal_entry(BIGINT, TEXT) TO authenticated, anon, service_role;
