BEGIN;

CREATE OR REPLACE FUNCTION public.reverse_journal_entry(
  p_journal_entry_id BIGINT,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- This function is called by several export shipment migrations before hard-deleting journal entries.
  -- Since the journal entries and ledger entries are immediately deleted in those migrations,
  -- this function is intentionally left as a no-op to prevent the "function does not exist" error
  -- without interfering with the hard-delete and recreate logic.
  RETURN;
END;
$$;

COMMIT;
