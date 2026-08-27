BEGIN;

-- Fix missing source_id for purchase invoices
UPDATE journal_entries je
SET source_id = pi.id::TEXT
FROM purchase_invoices pi
WHERE pi.journal_entry_id = je.id
  AND je.source_id IS NULL;

-- Fix missing source_id for lot receipts
UPDATE journal_entries je
SET source_id = lr.id::TEXT
FROM lot_receipts lr
WHERE lr.journal_entry_id = je.id
  AND je.source_id IS NULL;

COMMIT;
