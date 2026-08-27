-- Migration 088: Fix backfill for missing journal_entry_id in treasury_transactions
-- The previous backfill failed because the descriptions differed slightly.
UPDATE treasury_transactions tt
SET journal_entry_id = je.id
FROM journal_entries je
WHERE tt.type = 'supplier_payment'
  AND tt.description LIKE 'دفعة نقدية للمورد - فاتورة رقم %'
  AND je.source_type = 'purchase_payment'
  AND je.description = REPLACE(tt.description, 'دفعة نقدية للمورد', 'دفعة للمورد')
  AND tt.journal_entry_id IS NULL;
