-- ============================================================
-- WIPE ALL TRANSACTIONAL DATA — Keep master/seed data intact
-- ============================================================
-- Run this in Supabase SQL Editor to reset all business data.
-- Does NOT touch: accounts, customers, suppliers, treasuries,
-- bank_accounts, products, raw_materials, stations, settings, etc.
--
-- WARNING: This is irreversible. Backup first if needed.
-- ============================================================

BEGIN;

-- ─── Step 1: Disable triggers temporarily to avoid side effects ───
SET session_replication_role = 'replica';

-- ─── Step 2: Wipe all transactional data in dependency order ───

-- Financial / Accounting
DELETE FROM transactions;
DELETE FROM ledger_entries;
DELETE FROM treasury_transactions;
DELETE FROM bank_account_transactions;
DELETE FROM cashbox_transactions;
DELETE FROM cash_receipts;
DELETE FROM cash_payments;
DELETE FROM cheques;

-- Fiscal year operations
DELETE FROM fiscal_year_closing_entries;
DELETE FROM fiscal_year_inventory_snapshot;
DELETE FROM fiscal_year_closing_progress;
DELETE FROM fiscal_year_backup_metadata;
DELETE FROM fiscal_year_closing_lock;
DELETE FROM fiscal_year_audit_log;

-- Purchases
DELETE FROM purchase_invoice_items;
DELETE FROM purchase_invoices;

-- Sales / Exports
DELETE FROM sales_invoice_items;
DELETE FROM sales_invoices;
DELETE FROM export_invoices;
DELETE FROM export_shipment_items;
DELETE FROM export_shipments;
DELETE FROM proforma_invoice_items;
DELETE FROM proforma_invoices;

-- Production / Packing
DELETE FROM packing_order_cost_items;
DELETE FROM packing_order_sortings;
DELETE FROM packing_order_items;
DELETE FROM packing_orders;

-- Inventory / Stock
DELETE FROM stock_movements;
DELETE FROM stock_batches;
DELETE FROM stock_transfers;
DELETE FROM finished_goods;
DELETE FROM finished_products;
DELETE FROM raw_material_transactions;

-- Lots
DELETE FROM lot_grading_results;
DELETE FROM lot_returns;
DELETE FROM lot_receipts;

-- Shipment costs / profitability
DELETE FROM shipment_cost_breakdown;
DELETE FROM shipment_cost_allocations;
DELETE FROM shipment_recipe_snapshots;
DELETE FROM shipment_profitability_snapshots;
DELETE FROM supplier_settlements;
DELETE FROM prep_center_cost_items;
DELETE FROM general_cost_items;
DELETE FROM cost_report_items;

-- Crop purchases
DELETE FROM crop_purchases;

-- Profit distribution
DELETE FROM shareholder_profit_distributions;

-- Audit / logs / system
DELETE FROM statement_notes;
DELETE FROM approval_history;
DELETE FROM notifications;
DELETE FROM backup_history;
DELETE FROM invoice_edits;
DELETE FROM audit_logs;
DELETE FROM audit_logs_text;
DELETE FROM financial_audit_log;
DELETE FROM _supplier_balance_log;

-- ─── Step 3: Reset master data balances to zero ───
UPDATE customers SET balance = 0, updated_at = now();
UPDATE suppliers SET outstanding_balance = 0, updated_at = now();
UPDATE treasuries SET updated_at = now();
UPDATE bank_accounts SET balance = 0, updated_at = now();
UPDATE raw_materials SET quantity = 0, updated_at = now();

-- Reset treasury_balances to zero
UPDATE treasury_balances SET balance = 0;

-- ─── Step 4: Reset station product quantities ───
UPDATE station_products SET quantity = 0, updated_at = now() WHERE quantity > 0;

-- ─── Step 5: Re-enable triggers ───
SET session_replication_role = 'origin';

-- ─── Step 6: Reset sequences ───
DO $$
DECLARE
  seq RECORD;
BEGIN
  FOR seq IN
    SELECT sequencename FROM pg_sequences
    WHERE schemaname = 'public'
      AND sequencename LIKE '%seq%'
  LOOP
    EXECUTE 'ALTER SEQUENCE ' || seq.sequencename || ' RESTART WITH 1';
  END LOOP;
END $$;

COMMIT;

-- Verify
SELECT 'Wipe complete!' AS status;
