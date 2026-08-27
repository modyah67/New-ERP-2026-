-- Migration 111: Fix rpc_get_purchase_journal_entries to find inventory & payment entries
--
-- Problem: rpc_confirm_purchase calls post_journal_entry WITHOUT p_source_id,
-- so source_id is NULL for inventory/payment entries.
-- The RPC only matched by source_id = p_purchase_id, missing those entries.
-- Fix: Also match by description containing the purchase invoice_number.

DROP FUNCTION IF EXISTS public.rpc_get_purchase_journal_entries(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_get_purchase_journal_entries(
  p_purchase_id TEXT
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
  v_invoice_number TEXT;
BEGIN
  -- Get the invoice number to match entries by description
  SELECT invoice_number INTO v_invoice_number
  FROM purchase_invoices WHERE id::TEXT = p_purchase_id;

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
      -- Match by source_id (for price_adjustment entries created by rpc_edit_purchase_item_price)
      (je.source_id = p_purchase_id AND je.source_type IN ('purchase_inventory', 'purchase_payment', 'purchase_price_adjustment'))
      OR
      -- Match by description containing invoice number (for entries created by rpc_confirm_purchase without source_id)
      (v_invoice_number IS NOT NULL AND v_invoice_number != ''
       AND je.description LIKE '%' || v_invoice_number || '%'
       AND je.source_type IN ('purchase_inventory', 'purchase_payment'))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_purchase_journal_entries(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
