-- Migration 131: Add missing currency exchange document types
-- ============================================================================
-- Fixes "Document Type not found" errors when posting journal entries 
-- from currency exchange operations.

BEGIN;

INSERT INTO public.sys_document_types (code, name, prefix) VALUES
('currency_exchange', 'Currency Exchange', 'CEXC'),
('bank_currency_exchange', 'Bank Currency Exchange', 'BEXC')
ON CONFLICT (code) DO NOTHING;

COMMIT;
