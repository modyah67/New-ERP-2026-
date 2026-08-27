-- ============================================================================
-- 097_insert_missing_document_types.sql
--
-- Inserts missing document types for purchase inventory, payments, lot operations,
-- and other types to prevent "Document Type not found" in post_journal_entry.
-- ============================================================================

BEGIN;

INSERT INTO sys_document_types (code, name, prefix) VALUES
  ('purchase_inventory', 'Purchase Inventory', 'PINV'),
  ('purchase_payment', 'Purchase Payment', 'PPAY'),
  ('purchase', 'Purchase Invoice', 'PURC'),
  ('lot_return', 'Lot Return', 'LRET'),
  ('lot_receipt', 'Lot Receipt', 'LREC'),
  ('supplier_payment', 'Supplier Payment', 'SPAY'),
  ('employee_payment', 'Employee Payment', 'EMP'),
  ('general_expense', 'General Expense', 'GEXP')
ON CONFLICT (code) DO NOTHING;

COMMIT;
