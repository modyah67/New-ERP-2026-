-- Migration 128: Add missing payment document types
-- ============================================================================
-- Fixes "Document Type not found" errors when posting journal entries 
-- from spend_custody and receive_custody for the new entity types.

BEGIN;

INSERT INTO public.sys_document_types (code, name, prefix) VALUES
-- From receive_custody
('supplier_payment_received', 'Supplier Payment Received', 'SPR'),
('clearing_agent_payment_received', 'Clearing Agent Payment Received', 'CAPR'),
('shipping_company_payment_received', 'Shipping Company Payment Received', 'SCPR'),
('shareholder_payment_received', 'Shareholder Payment Received', 'SHPR'),

-- From spend_custody
('purchase_payment', 'Purchase Payment', 'PP'),
('customer_refund', 'Customer Refund', 'CR'),
('clearing_agent_payment', 'Clearing Agent Payment', 'CAP'),
('shipping_company_payment', 'Shipping Company Payment', 'SCP'),
('shareholder_withdrawal', 'Shareholder Withdrawal', 'SHW'),
('expense_payment', 'Expense Payment', 'EXP')
ON CONFLICT (code) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';
