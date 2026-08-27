-- ============================================================================
-- 040b_insert_missing_document_types.sql
--
-- Inserts missing document types into sys_document_types for all source_type
-- values used by SQL functions calling post_journal_entry → fn_get_next_sequence.
--
-- Each document type gets a unique code + prefix for journal numbering:
--   opening_balance → OB-00001
--   treasury_deposit → TD-00001
--   bank_deposit → BKD-00001
--   bank_withdraw → BKW-00001
--   expense_payment → EP-00001
--   disbursement → DISB-00001
--   customer_payment → CPM-00001
--   supplier_payment_received → SPR-00001
--   clearing_agent_payment_received → CAP-00001
--   shipping_company_payment_received → SCP-00001
--   shareholder_payment_received → SHP-00001
--   treasury_withdrawal → TW-00001
-- ============================================================================

BEGIN;

INSERT INTO sys_document_types (code, name, prefix) VALUES
  ('opening_balance', 'Opening Balance', 'OB'),
  ('treasury_deposit', 'Treasury Deposit', 'TD'),
  ('treasury_withdrawal', 'Treasury Withdrawal', 'TW'),
  ('bank_deposit', 'Bank Deposit', 'BKD'),
  ('bank_withdraw', 'Bank Withdrawal', 'BKW'),
  ('expense_payment', 'Expense Payment', 'EP'),
  ('disbursement', 'Disbursement', 'DISB'),
  ('customer_payment', 'Customer Payment', 'CPM'),
  ('supplier_payment_received', 'Supplier Payment Received', 'SPR'),
  ('clearing_agent_payment_received', 'Clearing Agent Payment', 'CAP'),
  ('shipping_company_payment_received', 'Shipping Company Payment', 'SCP'),
  ('shareholder_payment_received', 'Shareholder Payment', 'SHP')
ON CONFLICT (code) DO NOTHING;

COMMIT;
