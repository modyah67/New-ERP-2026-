-- Migration 139: Add exchange_currency document type
-- ============================================================================
-- Fixes "Document Type exchange_currency not found" error during bank currency exchange.

BEGIN;

INSERT INTO public.sys_document_types (code, name, prefix) VALUES
('exchange_currency', 'Bank Currency Exchange', 'EXCH')
ON CONFLICT (code) DO NOTHING;

COMMIT;
