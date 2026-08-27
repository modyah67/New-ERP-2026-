-- Migration 110: Insert missing document types for new source_types
--
-- Fixes "Document Type not found" errors when post_journal_entry is called
-- with source_type values that don't exist in sys_document_types.

BEGIN;

INSERT INTO sys_document_types (code, name, prefix) VALUES
  ('purchase_price_adjustment', 'Purchase Price Adjustment', 'PPAD'),
  ('expense_reversal', 'Expense Reversal', 'EREV'),
  ('expense_payment', 'Expense Payment', 'EPAY'),
  ('bank_withdrawal', 'Bank Withdrawal', 'BWD'),
  ('bank_deposit', 'Bank Deposit', 'BDEP'),
  ('treasury_deposit', 'Treasury Deposit', 'TDEP'),
  ('treasury_withdraw', 'Treasury Withdrawal', 'TWD'),
  ('opening_balance', 'Opening Balance', 'OPBL'),
  ('packing_order', 'Packing Order', 'PACK'),
  ('export_shipment', 'Export Shipment', 'EXSH'),
  ('lot_receipt', 'Lot Receipt', 'LREC'),
  ('lot_return', 'Lot Return', 'LRET')
ON CONFLICT (code) DO NOTHING;

COMMIT;
