-- Migration 114: Fix rpc_get_lot_journal_entries — correct source_types
--
-- Problem: spend_custody uses source_type='purchase_payment' or 'expense_payment'
-- (NOT 'custody_expense'/'bank_expense'). The RPC filter was wrong.
-- Also need to match by description for payment entries (no source_id=lot_id).

DROP FUNCTION IF EXISTS public.rpc_get_lot_journal_entries(TEXT);

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
      -- 1. lot_receipt entries (source_id set via UPDATE after post_journal_entry)
      (je.source_id = p_lot_id AND je.source_type = 'lot_receipt')
      OR
      -- 2. lot_price_adjustment entries (source_id set directly)
      (je.source_id = p_lot_id AND je.source_type = 'lot_price_adjustment')
      OR
      -- 3. Payment entries — matched by description containing lot number
      --    source_type is 'purchase_payment' (supplier) or 'expense_payment' (expense)
      --    from spend_custody / withdraw_bank_account
      (v_lot_number IS NOT NULL AND v_lot_number != ''
       AND je.description LIKE '%' || v_lot_number || '%'
       AND je.source_type IN ('purchase_payment', 'expense_payment',
                              'custody_expense', 'bank_expense',
                              'supplier_payment'))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_lot_journal_entries(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
