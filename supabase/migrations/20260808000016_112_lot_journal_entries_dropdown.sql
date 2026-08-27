-- Migration 112: rpc_get_lot_journal_entries — all GL entries for a lot

CREATE OR REPLACE FUNCTION public.rpc_get_lot_journal_entries(
  p_lot_id TEXT
)
RETURNS TABLE (
  journal_entry_id BIGINT,
  entry_number     TEXT,
  entry_date       DATE,
  description      TEXT,
  source_type      TEXT,
  source_id        TEXT,
  total_debit      NUMERIC,
  total_credit     NUMERIC,
  currency         TEXT,
  created_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot_number TEXT;
BEGIN
  SELECT lot_number INTO v_lot_number
  FROM lot_receipts WHERE id::TEXT = p_lot_id;

  RETURN QUERY
  SELECT DISTINCT ON (je.id)
    je.id AS journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.source_type,
    je.source_id,
    COALESCE(SUM(ale.debit) OVER (PARTITION BY je.id), 0) AS total_debit,
    COALESCE(SUM(ale.credit) OVER (PARTITION BY je.id), 0) AS total_credit,
    (SELECT ale2.currency FROM public.account_ledger_entries ale2
     WHERE ale2.journal_entry_id = je.id AND ale2.currency IS NOT NULL
     ORDER BY ale2.id LIMIT 1) AS currency,
    je.created_at
  FROM public.journal_entries je
  INNER JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id
  WHERE je.deleted_at IS NULL
    AND ale.deleted_at IS NULL
    AND (
      -- Match by source_id (lot_receipt entries from sync_supplier_ledger_for_lot)
      (je.source_id = p_lot_id AND je.source_type = 'lot_receipt')
      OR
      -- Match by description containing lot number (payment entries from spend_custody/withdraw_bank_account)
      (v_lot_number IS NOT NULL AND v_lot_number != ''
       AND je.description LIKE '%لوت رقم ' || v_lot_number || '%'
       AND je.source_type IN ('custody_expense', 'bank_expense'))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_lot_journal_entries(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
