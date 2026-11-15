-- ==============================================================================
-- Migration: 20261114000001_cost_centers_and_financial_records_indexes.sql
-- Description: High-performance B-tree indexes on financial transactions,
--              journal entries, ledger lines, cost centers, packing orders,
--              and shipments for rapid cost report queries and UI non-blocking.
-- Note: 'journal_entry_lines' is a view over 'account_ledger_entries'.
--       All indexes are placed directly on the underlying base tables.
-- ==============================================================================

-- 1. Account Ledger Entries (الأستاذ العام وحركات الحسابات والقيود ومراكز التكلفة)
CREATE INDEX IF NOT EXISTS idx_ale_cost_center_id 
  ON public.account_ledger_entries USING btree (cost_center_id) 
  WHERE cost_center_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ale_account_cost_center 
  ON public.account_ledger_entries USING btree (account_id, cost_center_id);

CREATE INDEX IF NOT EXISTS idx_ale_journal_entry_id 
  ON public.account_ledger_entries USING btree (journal_entry_id);

CREATE INDEX IF NOT EXISTS idx_ale_created_at_desc 
  ON public.account_ledger_entries USING btree (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ale_account_date 
  ON public.account_ledger_entries USING btree (account_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ale_company_cost_center 
  ON public.account_ledger_entries USING btree (company_id, cost_center_id) 
  WHERE company_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ale_deleted_at 
  ON public.account_ledger_entries USING btree (deleted_at) 
  WHERE deleted_at IS NULL;

-- 2. Journal Entries (دفتر القيود اليومية)
CREATE INDEX IF NOT EXISTS idx_je_entry_date 
  ON public.journal_entries USING btree (entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_je_status_date 
  ON public.journal_entries USING btree (status, entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_je_company_status 
  ON public.journal_entries USING btree (company_id, status) 
  WHERE company_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_je_deleted_at 
  ON public.journal_entries USING btree (deleted_at) 
  WHERE deleted_at IS NULL;

-- 3. Cost Centers & Categories (مراكز التكلفة والتصنيفات)
CREATE INDEX IF NOT EXISTS idx_cost_centers_code 
  ON public.cost_centers USING btree (code);

CREATE INDEX IF NOT EXISTS idx_cost_centers_is_closed 
  ON public.cost_centers USING btree (is_closed);

CREATE INDEX IF NOT EXISTS idx_cost_centers_season 
  ON public.cost_centers USING btree (season);

CREATE INDEX IF NOT EXISTS idx_cost_centers_company_id 
  ON public.cost_centers USING btree (company_id) 
  WHERE company_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_crc_account_id 
  ON public.cost_report_categories USING btree (account_id) 
  WHERE account_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_crc_cost_center_id 
  ON public.cost_report_categories USING btree (cost_center_id) 
  WHERE cost_center_id IS NOT NULL;

-- 4. Operations & Shipments underlying vw_cost_details_live (أوامر التعبئة والشحنات والمحاصيل)
CREATE INDEX IF NOT EXISTS idx_po_export_shipment_id 
  ON public.packing_orders USING btree (export_shipment_id);

CREATE INDEX IF NOT EXISTS idx_po_status 
  ON public.packing_orders USING btree (status);

CREATE INDEX IF NOT EXISTS idx_po_lot_id 
  ON public.packing_orders USING btree (lot_id);

CREATE INDEX IF NOT EXISTS idx_po_packed_at 
  ON public.packing_orders USING btree (packed_at DESC);

CREATE INDEX IF NOT EXISTS idx_export_shipments_date 
  ON public.export_shipments USING btree (shipment_date DESC);

CREATE INDEX IF NOT EXISTS idx_export_shipments_customer 
  ON public.export_shipments USING btree (customer_name);

CREATE INDEX IF NOT EXISTS idx_export_shipments_shipment_no 
  ON public.export_shipments USING btree (shipment_no);

CREATE INDEX IF NOT EXISTS idx_lr_confirmed_receipt_date 
  ON public.lot_receipts USING btree (is_confirmed, receipt_date DESC);

CREATE INDEX IF NOT EXISTS idx_lr_supplier_id 
  ON public.lot_receipts USING btree (supplier_id);

CREATE INDEX IF NOT EXISTS idx_lot_returns_receipt_id 
  ON public.lot_returns USING btree (lot_receipt_id);
