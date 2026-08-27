-- Migration 282: Fix Export Shipment Payment Journal Linking & Prevent Duplicate Payment Journals
-- 1. Updates rpc_get_export_shipment_journal_entries to include all bank and treasury payment source types.
-- 2. Safely removes duplicate manual journal entry (JE #9) created by legacy code and links JE #8 to shipment.

-- 1. Update rpc_get_export_shipment_journal_entries
CREATE OR REPLACE FUNCTION public.rpc_get_export_shipment_journal_entries(
  p_shipment_id BIGINT
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
  v_shipment_no TEXT;
BEGIN
  SELECT shipment_no INTO v_shipment_no
  FROM export_shipments WHERE id = p_shipment_id;

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
      -- Match by source_id (all export-related shipment, discount, and payment types)
      (je.source_id = p_shipment_id::text
       AND je.source_type IN (
         'export_shipment', 'export_discount',
         'bank_deposit', 'customer_bank_deposit',
         'customer_treasury_deposit', 'customer_treasury_withdrawal',
         'export_payment'
       ))
      OR
      -- Match by description containing shipment number
      (v_shipment_no IS NOT NULL AND v_shipment_no != ''
       AND je.description LIKE '%' || v_shipment_no || '%'
       AND je.source_type IN (
         'export_shipment', 'export_discount',
         'bank_deposit', 'customer_bank_deposit',
         'customer_treasury_deposit', 'customer_treasury_withdrawal',
         'export_payment'
       ))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_export_shipment_journal_entries(BIGINT) TO authenticated;

-- 2. Link existing payment entry (JE #8 / BKD-00001) to shipment 1
UPDATE public.journal_entries
SET source_id = '1'
WHERE id = 8 AND (source_id IS NULL OR source_id = 'null');

-- 3. Clean up the duplicate manual journal entry (JE #9) created by legacy code
DELETE FROM public.account_ledger_entries
WHERE journal_entry_id = 9;

DELETE FROM public.journal_entries
WHERE id = 9 AND source_type = 'MANUAL_JOURNAL' AND source_id = 'MANUAL';

-- Adjust balance of Account 10 if affected
UPDATE public.accounts
SET balance = COALESCE((
  SELECT SUM(COALESCE(debit, 0) - COALESCE(credit, 0))
  FROM public.account_ledger_entries
  WHERE account_id = 10 AND deleted_at IS NULL
), 0)
WHERE id = 10;
