-- ============================================================================
-- VERIFY_DATABASE.sql — Comprehensive ERP Database Health Check (60 Tests)
-- ============================================================================
-- Run this AFTER applying migrations to verify everything is correct.
-- Returns a table with PASS/FAIL report for each check.
--
-- Usage:
--   SELECT * FROM verify_database();
--   SELECT * FROM verify_database() WHERE NOT passed;
--   SELECT count(*) FILTER (WHERE NOT passed) AS failures FROM verify_database();
--
-- Safe | Read-only | No data modification
-- ============================================================================

CREATE OR REPLACE FUNCTION verify_database()
RETURNS TABLE (
    test_id INT,
    test_name TEXT,
    passed BOOLEAN,
    details TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_count BIGINT;
  v_count2 BIGINT;
  v_pass BOOLEAN;
  v_detail TEXT;
  v_def TEXT;
  r RECORD;
BEGIN

  -- ============================================================================
  -- SECTION A: SCHEMA INTEGRITY (Tests 1-12)
  -- ============================================================================

  -- 1. CRITICAL FUNCTIONS EXIST
  v_pass := TRUE; v_detail := '';
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_confirm_purchase') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_confirm_purchase MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_cancel_purchase') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_cancel_purchase MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'create_balanced_entry') THEN
    v_pass := FALSE; v_detail := v_detail || 'create_balanced_entry MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_account_totals_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_account_totals_rpc MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_cancel_export_shipment') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_cancel_export_shipment MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_process_export_shipment_ledger') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_process_export_shipment_ledger MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_balance_before_date_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_balance_before_date_rpc MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_account_total_by_id_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_account_total_by_id_rpc MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_latest_exchange_rates_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_latest_exchange_rates_rpc MISSING; '; END IF;
  IF v_pass THEN v_detail := 'All 9 critical functions exist'; END IF;
  test_id := 1; test_name := 'Critical Functions Exist'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 2. SECURITY DEFINER on critical functions
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT p.proname FROM pg_proc p
    WHERE p.proname IN ('rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry',
                         'get_account_totals_rpc','rpc_cancel_export_shipment')
  LOOP
    v_def := (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = r.proname LIMIT 1);
    IF v_def NOT LIKE '%SECURITY DEFINER%' THEN
      v_pass := FALSE; v_detail := v_detail || r.proname || ' missing SEC DEF; ';
    END IF;
  END LOOP;
  IF v_pass THEN v_detail := 'All checked functions have SECURITY DEFINER'; END IF;
  test_id := 2; test_name := 'SECURITY DEFINER Present'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 3. search_path set on critical functions
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT p.proname FROM pg_proc p
    WHERE p.proname IN ('rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry',
                         'get_account_totals_rpc','rpc_cancel_export_shipment')
  LOOP
    v_def := (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = r.proname LIMIT 1);
    IF v_def NOT LIKE '%search_path%' THEN
      v_pass := FALSE; v_detail := v_detail || r.proname || ' missing search_path; ';
    END IF;
  END LOOP;
  IF v_pass THEN v_detail := 'All checked functions have search_path'; END IF;
  test_id := 3; test_name := 'search_path Set'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 4. NO DUPLICATE OVERLOADS
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT proname, COUNT(*) AS cnt FROM pg_proc
    WHERE proname IN ('rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry')
    GROUP BY proname HAVING COUNT(*) > 1
  LOOP
    v_pass := FALSE; v_detail := v_detail || r.proname || ' has ' || r.cnt || ' overloads; ';
  END LOOP;
  IF v_pass THEN v_detail := 'No duplicate overloads'; END IF;
  test_id := 4; test_name := 'No Duplicate Overloads'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 5. GRANT EXECUTE to authenticated
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT proname FROM pg_proc WHERE proname IN (
      'rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry',
      'get_account_totals_rpc','rpc_cancel_export_shipment',
      'rpc_process_export_shipment_ledger','get_balance_before_date_rpc',
      'get_account_total_by_id_rpc','get_latest_exchange_rates_rpc'
    )
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.proname = r.proname
        AND p.proacl IS NOT NULL
        AND EXISTS (SELECT 1 FROM unnest(p.proacl) a WHERE a::TEXT LIKE '%authenticated%')
    ) THEN
      v_pass := FALSE; v_detail := v_detail || r.proname || ' missing GRANT; ';
    END IF;
  END LOOP;
  IF v_pass THEN v_detail := 'GRANTs verified for all critical RPCs'; END IF;
  test_id := 5; test_name := 'GRANT EXECUTE to authenticated'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 6. accounts.id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'accounts' AND column_name = 'id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'accounts.id is not UUID (expected UUID)'; ELSE v_detail := 'accounts.id is UUID'; END IF;
  test_id := 6; test_name := 'accounts.id Type = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 7. purchase_invoices.id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'purchase_invoices' AND column_name = 'id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'purchase_invoices.id is not UUID (expected UUID)'; ELSE v_detail := 'purchase_invoices.id is UUID'; END IF;
  test_id := 7; test_name := 'purchase_invoices.id Type = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 8. customers.id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'customers' AND column_name = 'id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'customers.id is not UUID (expected UUID)'; ELSE v_detail := 'customers.id is UUID'; END IF;
  test_id := 8; test_name := 'customers.id Type = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 9. suppliers.id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'suppliers' AND column_name = 'id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'suppliers.id is not UUID'; ELSE v_detail := 'suppliers.id is UUID'; END IF;
  test_id := 9; test_name := 'suppliers.id Type = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 10. stock_batches.supplier_id TYPE = UUID (must match suppliers.id)
  v_pass := TRUE;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_batches' AND column_name = 'supplier_id' AND table_schema = 'public'
  ) THEN
    v_pass := FALSE; v_detail := 'stock_batches.supplier_id MISSING';
  ELSE
    SELECT data_type INTO v_detail FROM information_schema.columns
    WHERE table_name = 'stock_batches' AND column_name = 'supplier_id' AND table_schema = 'public';
    IF v_detail != 'uuid' THEN
      v_pass := FALSE; v_detail := 'stock_batches.supplier_id is ' || v_detail || ' (expected UUID)';
    ELSE
      v_detail := 'stock_batches.supplier_id is UUID';
    END IF;
  END IF;
  test_id := 10; test_name := 'stock_batches.supplier_id = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 11. cash_payments.supplier_id TYPE = UUID
  v_pass := TRUE;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cash_payments' AND column_name = 'supplier_id' AND table_schema = 'public'
  ) THEN
    v_pass := FALSE; v_detail := 'cash_payments.supplier_id MISSING';
  ELSE
    SELECT data_type INTO v_detail FROM information_schema.columns
    WHERE table_name = 'cash_payments' AND column_name = 'supplier_id' AND table_schema = 'public';
    IF v_detail != 'uuid' THEN
      v_pass := FALSE; v_detail := 'cash_payments.supplier_id is ' || v_detail || ' (expected UUID)';
    ELSE
      v_detail := 'cash_payments.supplier_id is UUID';
    END IF;
  END IF;
  test_id := 11; test_name := 'cash_payments.supplier_id = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 12. stock_batches.purchase_invoice_id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'stock_batches' AND column_name = 'purchase_invoice_id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'purchase_invoice_id is not UUID (expected UUID)'; ELSE v_detail := 'stock_batches.purchase_invoice_id is UUID'; END IF;
  test_id := 12; test_name := 'purchase_invoice_id = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION B: REFERENTIAL INTEGRITY (Tests 13-22)
  -- ============================================================================

  -- 13. FK: purchase_invoice_items -> purchase_invoices
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoice_items pii
  WHERE NOT EXISTS (SELECT 1 FROM purchase_invoices pi WHERE pi.id = pii.invoice_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 13; test_name := 'FK: purchase_invoice_items->purchase_invoices'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 14. FK: export_shipment_items -> export_shipments
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM export_shipment_items esi
  WHERE NOT EXISTS (SELECT 1 FROM export_shipments es WHERE es.id = esi.shipment_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 14; test_name := 'FK: export_shipment_items->export_shipments'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 15. FK: sales_invoice_items -> sales_invoices
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM sales_invoice_items sii
  WHERE NOT EXISTS (SELECT 1 FROM sales_invoices si WHERE si.id = sii.invoice_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 15; test_name := 'FK: sales_invoice_items->sales_invoices'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 16. FK: packing_order_sortings -> packing_orders
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM packing_order_sortings pos
  WHERE NOT EXISTS (SELECT 1 FROM packing_orders po WHERE po.id = pos.packing_order_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 16; test_name := 'FK: packing_order_sortings->packing_orders'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 17. FK: packing_order_cost_items -> packing_orders
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM packing_order_cost_items poci
  WHERE NOT EXISTS (SELECT 1 FROM packing_orders po WHERE po.id = poci.packing_order_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 17; test_name := 'FK: packing_order_cost_items->packing_orders'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 18. FK: lot_grading_results -> lot_receipts
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM lot_grading_results lgr
  WHERE NOT EXISTS (SELECT 1 FROM lot_receipts lr WHERE lr.id = lgr.lot_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 18; test_name := 'FK: lot_grading_results->lot_receipts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 19. FK: transactions -> accounts
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions t
  WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.id = t.account_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 19; test_name := 'FK: transactions->accounts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 20. FK: ledger_entries -> customers
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM ledger_entries le
  WHERE le.entity_type = 'customer'
    AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.id::TEXT = le.entity_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 20; test_name := 'FK: ledger_entries->customers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 21. No NULL invoice_id in purchase_invoice_items
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoice_items WHERE invoice_id IS NULL;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' items with NULL invoice_id'; ELSE v_detail := 'All items have invoice_id'; END IF;
  test_id := 21; test_name := 'No NULL invoice_id'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 22. purchase_invoices has payment columns
  v_pass := TRUE; v_detail := '';
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='payment_treasury_id') THEN
    v_pass := FALSE; v_detail := v_detail || 'payment_treasury_id MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='payment_source_type') THEN
    v_pass := FALSE; v_detail := v_detail || 'payment_source_type MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='payment_bank_account_id') THEN
    v_pass := FALSE; v_detail := v_detail || 'payment_bank_account_id MISSING; '; END IF;
  IF v_pass THEN v_detail := 'All payment columns present'; END IF;
  test_id := 22; test_name := 'Purchase Payment Columns'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION C: FINANCIAL INTEGRITY (Tests 23-35)
  -- ============================================================================

  -- 23. Trial Balance = 0
  v_pass := TRUE;
  SELECT COALESCE(SUM(debit - credit), 0) INTO v_count FROM transactions;
  IF v_count != 0 THEN v_pass := FALSE; v_detail := 'Difference: ' || v_count; ELSE v_detail := 'Balanced (sum = 0)'; END IF;
  test_id := 23; test_name := 'Trial Balance = 0'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 24. General Ledger Balanced
  v_pass := TRUE;
  SELECT COALESCE(SUM(debit), 0) INTO v_count FROM transactions;
  SELECT COALESCE(SUM(credit), 0) INTO v_count2 FROM transactions;
  IF v_count != v_count2 THEN
    v_pass := FALSE; v_detail := 'Debits=' || v_count || ' Credits=' || v_count2;
  ELSE
    v_detail := 'GL balanced: debits=' || v_count || ' credits=' || v_count2;
  END IF;
  test_id := 24; test_name := 'General Ledger Balanced'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 25. No Empty Journal Entries
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions WHERE debit = 0 AND credit = 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' empty entries'; ELSE v_detail := 'No empty entries'; END IF;
  test_id := 25; test_name := 'No Empty Journal Entries'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 26. No Negative Debit/Credit
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions WHERE debit < 0 OR credit < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative entries'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 26; test_name := 'No Negative Debit/Credit'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 27. Ledger Entries Positive Amounts
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM ledger_entries WHERE amount <= 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' non-positive'; ELSE v_detail := 'All positive'; END IF;
  test_id := 27; test_name := 'Ledger Entries Positive'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 28. Customer Balance vs Ledger
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM customers c
  WHERE c.balance != 0 AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le WHERE le.entity_type = 'customer' AND le.entity_id = c.id::TEXT
  );
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' customers with balance but no ledger'; ELSE v_detail := 'Consistent'; END IF;
  test_id := 28; test_name := 'Customer Balance vs Ledger'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 29. Treasury Amounts Non-Negative
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM treasury_transactions WHERE amount < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative treasury amounts'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 29; test_name := 'Treasury Amounts Non-Negative'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 30. No Treasury Transactions Without Journal
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM treasury_transactions tt
  WHERE tt.type = 'expense' AND tt.amount > 0
    AND NOT EXISTS (
      SELECT 1 FROM transactions t
      WHERE t.description LIKE '%' || COALESCE(tt.description, '') || '%'
        AND t.debit > 0
    );
  IF v_count > 0 THEN v_detail := v_count || ' treasury txs without matching journal (soft check)'; ELSE v_detail := 'All treasury txs have journal entries'; END IF;
  test_id := 30; test_name := 'Treasury vs Journal (soft)'; passed := TRUE; details := v_detail;
  RETURN NEXT;

  -- 31. Supplier Outstanding Balance Consistency
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM suppliers s
  WHERE s.outstanding_balance != 0 AND NOT EXISTS (
    SELECT 1 FROM purchase_invoices pi
    WHERE pi.supplier_id = s.id AND pi.status = 'confirmed'
  );
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' suppliers with balance but no confirmed purchases'; ELSE v_detail := 'Consistent'; END IF;
  test_id := 31; test_name := 'Supplier Balance Consistency'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 32. Key Views Exist
  v_pass := TRUE; v_detail := '';
  FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'public'
    AND table_name IN ('invoices','invoice_items','purchases','purchase_items','cashbox')
  LOOP
    v_detail := v_detail || r.table_name || ' OK; ';
  END LOOP;
  IF v_detail = '' THEN v_pass := FALSE; v_detail := 'No views found'; END IF;
  test_id := 32; test_name := 'Key Views Exist'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 33. Key Sequences Exist
  v_pass := TRUE; v_detail := '';
  IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE sequencename = 'entry_number_seq') THEN
    v_pass := FALSE; v_detail := 'entry_number_seq MISSING; ';
  END IF;
  IF v_pass THEN v_detail := 'Key sequences exist'; END IF;
  test_id := 33; test_name := 'Key Sequences Exist'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 34. Triggers Valid
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = 'public' AND NOT t.tgisinternal
    AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = t.tgfoid);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' broken triggers'; ELSE v_detail := 'All triggers valid'; END IF;
  test_id := 34; test_name := 'Triggers Valid'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 35. No Fake UUID Functions
  v_pass := TRUE; v_detail := '';
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_int_to_uuid') THEN
    v_pass := FALSE; v_detail := v_detail || '_int_to_uuid exists (fake UUID); ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_uuid_to_int') THEN
    v_pass := FALSE; v_detail := v_detail || '_uuid_to_int exists; ';
  END IF;
  IF v_pass THEN v_detail := 'No fake UUID functions found'; END IF;
  test_id := 35; test_name := 'No Fake UUID Functions'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION D: INVENTORY INTEGRITY (Tests 36-40)
  -- ============================================================================

  -- 36. Inventory Quantities Non-Negative
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM raw_materials WHERE quantity < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative quantities'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 36; test_name := 'Inventory Quantities Non-Negative'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 37. Stock Batch Quantities Consistent
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stock_batches WHERE remaining_quantity > quantity;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' inconsistent batches'; ELSE v_detail := 'All consistent'; END IF;
  test_id := 37; test_name := 'Stock Batch Quantities'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 38. No Batches Without Purchase
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stock_batches sb
  WHERE sb.purchase_invoice_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM purchase_invoices pi WHERE pi.id = sb.purchase_invoice_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphan batches'; ELSE v_detail := 'All batches have valid purchase'; END IF;
  test_id := 38; test_name := 'No Orphan Stock Batches'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 39. No Duplicate Batches
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM (
    SELECT batch_number, COUNT(*) AS cnt FROM stock_batches GROUP BY batch_number HAVING COUNT(*) > 1
  ) d;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' duplicate batch numbers'; ELSE v_detail := 'No duplicates'; END IF;
  test_id := 39; test_name := 'No Duplicate Batches'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 40. Station Product Quantities Non-Negative
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM station_products WHERE quantity < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 40; test_name := 'Station Product Quantities'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION E: MASTER DATA (Tests 41-48)
  -- ============================================================================

  -- 41. Accounts Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM accounts;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO accounts'; ELSE v_detail := v_count || ' accounts'; END IF;
  test_id := 41; test_name := 'Master: Accounts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 42. Customers Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM customers;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO customers'; ELSE v_detail := v_count || ' customers'; END IF;
  test_id := 42; test_name := 'Master: Customers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 43. Suppliers Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM suppliers;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO suppliers'; ELSE v_detail := v_count || ' suppliers'; END IF;
  test_id := 43; test_name := 'Master: Suppliers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 44. Treasuries Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM treasuries;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO treasuries'; ELSE v_detail := v_count || ' treasuries'; END IF;
  test_id := 44; test_name := 'Master: Treasuries'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 45. Raw Materials Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM raw_materials;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO raw materials'; ELSE v_detail := v_count || ' raw materials'; END IF;
  test_id := 45; test_name := 'Master: Raw Materials'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 46. Stations Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stations;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO stations'; ELSE v_detail := v_count || ' stations'; END IF;
  test_id := 46; test_name := 'Master: Stations'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 47. User Roles Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM user_roles;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO user roles'; ELSE v_detail := v_count || ' user roles'; END IF;
  test_id := 47; test_name := 'Master: User Roles'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 48. Bank Accounts Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM bank_accounts;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO bank accounts'; ELSE v_detail := v_count || ' bank accounts'; END IF;
  test_id := 48; test_name := 'Master: Bank Accounts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION F: CURRENCY / EXCHANGE (Tests 49-52)
  -- ============================================================================

  -- 49. Currencies Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM currencies;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO currencies'; ELSE v_detail := v_count || ' currencies'; END IF;
  test_id := 49; test_name := 'Master: Currencies'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 50. Exchange Rates Exist
  v_pass := TRUE;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'exchange_rates') THEN
    SELECT COUNT(*) INTO v_count FROM exchange_rates;
    IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO exchange rates'; ELSE v_detail := v_count || ' exchange rates'; END IF;
  ELSE
    v_detail := 'exchange_rates table not found (soft check)';
  END IF;
  test_id := 50; test_name := 'Exchange Rates'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 51. Treasury Balances Exist
  v_pass := TRUE;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'treasury_balances') THEN
    SELECT COUNT(*) INTO v_count FROM treasury_balances;
    v_detail := v_count || ' treasury balances';
  ELSE
    v_detail := 'treasury_balances table not found';
  END IF;
  test_id := 51; test_name := 'Treasury Balances'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 52. No NULL currency on transactions
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions WHERE currency_snapshot IS NULL AND (debit > 0 OR credit > 0);
  v_detail := v_count || ' transactions without currency snapshot';
  test_id := 52; test_name := 'Currency Snapshot (soft)'; passed := TRUE; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION G: SECURITY (Tests 53-54)
  -- ============================================================================

  -- 53. No functions with unexpected search_path
  v_pass := TRUE; v_detail := '';
  SELECT COUNT(*) INTO v_count FROM pg_proc p
  WHERE p.proconfig IS NOT NULL
    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%' AND c != 'search_path=public, extensions' AND c != 'search_path=public');
  IF v_count > 0 THEN
    v_pass := FALSE; v_detail := v_count || ' functions with unexpected search_path';
  ELSE
    v_detail := 'All search_paths OK';
  END IF;
  test_id := 53; test_name := 'search_path Safe'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 54. RLS / Grants (soft check)
  v_pass := TRUE; v_detail := '';
  v_detail := 'Soft check -- review RLS policies separately';
  test_id := 54; test_name := 'RLS / Grants (soft)'; passed := TRUE; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION H: COMPREHENSIVE (Tests 55-60)
  -- ============================================================================

  -- 55. No confirmed invoices with zero items
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoices pi
  WHERE pi.status = 'confirmed'
    AND NOT EXISTS (SELECT 1 FROM purchase_invoice_items pii WHERE pii.invoice_id = pi.id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' confirmed invoices without items'; ELSE v_detail := 'All confirmed invoices have items'; END IF;
  test_id := 55; test_name := 'Confirmed Invoices Have Items'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 56. No duplicate invoice numbers
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM (
    SELECT invoice_number, COUNT(*) FROM purchase_invoices
    WHERE invoice_number IS NOT NULL
    GROUP BY invoice_number HAVING COUNT(*) > 1
  ) d;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' duplicate invoice numbers'; ELSE v_detail := 'No duplicates'; END IF;
  test_id := 56; test_name := 'No Duplicate Invoice Numbers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 57. No purchase invoices with mismatched totals
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoices pi
  WHERE pi.status = 'confirmed'
    AND ABS(pi.total_amount - (
      SELECT COALESCE(SUM(pii.quantity * pii.unit_cost), 0)
      FROM purchase_invoice_items pii WHERE pii.invoice_id = pi.id
    )) > 0.01;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' invoices with mismatched totals'; ELSE v_detail := 'All totals match'; END IF;
  test_id := 57; test_name := 'Invoice Totals Match Items'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 58. No cancelled invoices with stock batches
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stock_batches sb
  WHERE EXISTS (SELECT 1 FROM purchase_invoices pi WHERE pi.id = sb.purchase_invoice_id AND pi.status = 'cancelled');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' batches for cancelled invoices'; ELSE v_detail := 'Clean'; END IF;
  test_id := 58; test_name := 'No Stock for Cancelled Invoices'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 59. No duplicate supplier codes
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM (
    SELECT code, COUNT(*) FROM suppliers WHERE code IS NOT NULL GROUP BY code HAVING COUNT(*) > 1
  ) d;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' duplicate supplier codes'; ELSE v_detail := 'No duplicates'; END IF;
  test_id := 59; test_name := 'No Duplicate Supplier Codes'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 60. All export shipments have valid statuses
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM export_shipments
  WHERE status NOT IN ('preparing','ready','shipped','in_transit','arrived','delivered','cancelled');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' invalid statuses'; ELSE v_detail := 'All valid'; END IF;
  test_id := 60; test_name := 'Valid Shipment Statuses'; passed := v_pass; details := v_detail;
  RETURN NEXT;

END;
$$;
