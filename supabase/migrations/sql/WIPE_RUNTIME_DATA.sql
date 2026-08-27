-- ============================================================================
-- WIPE_RUNTIME_DATA.sql — Reset ERP to Fresh State
-- ============================================================================
-- Safely deletes all transactional/business data while preserving
-- master/reference data, users, roles, settings, and chart of accounts.
--
-- WARNING: This is irreversible. Use only before delivering to a new client.
--
-- Safe | Idempotent | Transactional (BEGIN/COMMIT)
-- ============================================================================

BEGIN;

-- ── Begin safe cleanup ──
-- Use a temporary log table to track deletions and updates
CREATE TEMP TABLE IF NOT EXISTS tmp_cleanup_log (
    table_name text,
    rows_deleted bigint
);

-- ============================================================================
-- 1-11. DELETE TRANSACTIONAL DATA WITH LOGGING
-- ============================================================================
DO $$
DECLARE
    v_table text;
    v_cnt bigint;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'transactions','ledger_entries','treasury_transactions','bank_account_transactions','cashbox_transactions','cash_receipts','cash_payments','cheques',
        'fiscal_year_closing_entries','fiscal_year_inventory_snapshot','fiscal_year_closing_progress','fiscal_year_backup_metadata','fiscal_year_closing_lock','fiscal_year_audit_log',
        'purchase_invoice_items','purchase_invoices',
        'sales_invoice_items','sales_invoices','export_invoices','export_shipment_items','export_shipments','proforma_invoice_items','proforma_invoices',
        'packing_order_cost_items','packing_order_sortings','packing_order_items','packing_orders',
        'stock_movements','stock_batches','stock_transfers','finished_goods','raw_material_transactions',
        'lot_grading_results','lot_returns','lot_receipts',
        'shipment_cost_breakdown','shipment_cost_allocations','shipment_recipe_snapshots','shipment_profitability_snapshots','supplier_settlements','prep_center_cost_items','general_cost_items','cost_report_items',
        'crop_purchases',
        'shareholder_profit_distributions',
        'statement_notes','approval_history','notifications','backup_history','invoice_edits','audit_logs','audit_logs_text','financial_audit_log','_supplier_balance_log'
    ] LOOP
        BEGIN
            EXECUTE format('DELETE FROM %I', v_table);
            GET DIAGNOSTICS v_cnt = ROW_COUNT;
        EXCEPTION WHEN undefined_table THEN
            RAISE NOTICE 'Table % does not exist, skipping delete', v_table;
            v_cnt := 0;
        END;
        INSERT INTO tmp_cleanup_log VALUES (v_table, v_cnt);
    END LOOP;
END $$;


-- ============================================================================
-- 12. RESET MASTER DATA BALANCES TO ZERO
-- ============================================================================

-- ============================================================================
-- 12. RESET MASTER DATA BALANCES TO ZERO WITH LOGGING
-- ============================================================================
DO $$
DECLARE v_cnt bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='customers' AND column_name='balance') THEN
        UPDATE customers SET balance = 0, current_balance = 0, outstanding_balance = 0, updated_at = now();
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('customers', v_cnt);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='suppliers' AND column_name='outstanding_balance') THEN
        UPDATE suppliers SET outstanding_balance = 0, total_purchases = 0, updated_at = now();
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('suppliers', v_cnt);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='treasury_balances' AND column_name='balance') THEN
        UPDATE treasury_balances SET balance = 0;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('treasury_balances', v_cnt);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bank_accounts' AND column_name='balance') THEN
        UPDATE bank_accounts SET balance = 0, updated_at = now();
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('bank_accounts', v_cnt);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='raw_materials' AND column_name='quantity') THEN
        UPDATE raw_materials SET quantity = 0, updated_at = now();
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('raw_materials', v_cnt);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='station_products' AND column_name='quantity') THEN
        UPDATE station_products SET quantity = 0, updated_at = now() WHERE quantity > 0;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('station_products', v_cnt);
    END IF;
END $$;

-- Station product batch remaining quantities (guarded & logged)
DO $$
DECLARE v_cnt bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='station_product_batches' AND column_name='remaining_quantity') THEN
        UPDATE station_product_batches SET remaining_quantity = 0, updated_at = now() WHERE remaining_quantity > 0;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        INSERT INTO tmp_cleanup_log VALUES ('station_product_batches', v_cnt);
    END IF;
END $$;

-- ============================================================================
-- 13. RESET SEQUENCES
-- ============================================================================
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT sequencename FROM pg_sequences
    WHERE schemaname = 'public'
  LOOP
    BEGIN
      EXECUTE 'ALTER SEQUENCE ' || quote_ident(r.sequencename) || ' RESTART WITH 1';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not reset sequence %: %', r.sequencename, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================================================
-- 14. END OF CLEANUP
-- ============================================================================
-- No need to re‑enable triggers; cleanup runs with default permissions.


-- ============================================================================
-- 15. VERIFICATION
-- ============================================================================
DO $$
DECLARE
  v_count BIGINT;
  v_tables TEXT[] := ARRAY[
    'transactions', 'ledger_entries', 'treasury_transactions',
    'purchase_invoices', 'purchase_invoice_items',
    'export_shipments', 'export_shipment_items',
    'packing_orders', 'stock_batches', 'stock_movements',
    'cash_payments', 'cash_receipts', 'cheques'
  ];
  v_table TEXT;
  v_has_data BOOLEAN := FALSE;
BEGIN
  FOREACH v_table IN ARRAY v_tables
  LOOP
    BEGIN
      EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(v_table) INTO v_count;
    EXCEPTION WHEN undefined_table THEN
      RAISE NOTICE 'Verification: table % does not exist, skipping', v_table;
      CONTINUE;
    END;
    IF v_count > 0 THEN
      RAISE WARNING '⚠️  % still has % rows', v_table, v_count;
      v_has_data := TRUE;
    END IF;
  END LOOP;

  IF NOT v_has_data THEN
    RAISE NOTICE '✅ All transactional tables are empty';
  END IF;

  -- Check customer balances (guard columns)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='customers' AND column_name='balance') THEN
    SELECT COUNT(*) INTO v_count FROM customers WHERE balance != 0 OR current_balance != 0;
    IF v_count > 0 THEN
      RAISE WARNING '⚠️  % customers still have non-zero balances', v_count;
    ELSE
      RAISE NOTICE '✅ All customer balances are zero';
    END IF;
  END IF;

  -- Check supplier balances (guard columns)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='suppliers' AND column_name='outstanding_balance') THEN
    SELECT COUNT(*) INTO v_count FROM suppliers WHERE outstanding_balance != 0;
    IF v_count > 0 THEN
      RAISE WARNING '⚠️  % suppliers still have non-zero balances', v_count;
    ELSE
      RAISE NOTICE '✅ All supplier balances are zero';
    END IF;
  END IF;
END $$;

COMMIT;

SELECT '✅ WIPE COMPLETE — System reset to fresh state' AS result;
