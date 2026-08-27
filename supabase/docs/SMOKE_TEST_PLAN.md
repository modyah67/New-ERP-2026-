# ERP SMOKE TEST PLAN

**Generated:** 2026-07-21
**Status:** BLOCKED — Cannot generate PowerShell script until missing objects are remediated
**Script:** `scripts/erp_smoke_test.ps1`

---

## STATUS: BLOCKED

The smoke test script **cannot be generated** because:

1. 12 tables referenced by Flutter are missing from schema.sql
2. 5 RPCs called by Flutter have no implementation
3. The baseline migration will fail at runtime

**Generating a smoke test against a broken schema would produce false positives for every module.**

---

## WHAT THE SMOKE TEST WILL COVER (once schema is fixed)

### Phase 1: Database Connectivity
- [ ] Supabase connection
- [ ] Auth session
- [ ] RLS enforcement

### Phase 2: Module CRUD Operations

For EACH module, the test will:
1. **CREATE** — Insert a test record
2. **READ** — Select the created record
3. **UPDATE** — Modify the record
4. **DELETE** — Remove the record
5. **RPC** — Call the module's primary RPC
6. **Verify** — Confirm no exceptions

| # | Module | Table(s) | Primary RPC |
|---|--------|----------|-------------|
| 1 | Auth | profiles, users | — |
| 2 | Dashboard | — | get_complete_dashboard_data, get_dashboard_stats |
| 3 | Customers | customers | generate_next_customer_code, delete_customer_safe |
| 4 | Suppliers | suppliers | get_next_supplier_code |
| 5 | Warehouses | warehouses | — |
| 6 | Products | products | — |
| 7 | Inventory | stock_batches, stock_movements | create_batch_from_purchase, deduct_stock_fifo |
| 8 | Purchases | purchase_invoices, purchase_invoice_items | create_purchase, rpc_confirm_purchase |
| 9 | Purchase Confirmation | — | rpc_confirm_purchase |
| 10 | Packing Orders | packing_orders | rpc_confirm_packing_order |
| 11 | Packing Confirmation | — | rpc_confirm_packing_order |
| 12 | Export Shipments | export_shipments, export_shipment_items | rpc_cancel_export_shipment |
| 13 | Shipment Confirmation | — | rpc_process_export_shipment_ledger |
| 14 | Treasury | treasuries, treasury_transactions | create_treasury, deposit_treasury |
| 15 | Cash | cashbox_transactions | get_cashbox_balance |
| 16 | Banks | bank_accounts | deposit_bank_account, withdraw_bank_account |
| 17 | Cheques | cheques | create_cheque, clear_cheque, cancel_cheque |
| 18 | Accounting | accounts, transactions | create_balanced_entry |
| 19 | Journal Entries | transactions | get_next_entry_number |
| 20 | Profit Distribution | shareholder_profit_distributions | distribute_shipment_profit |
| 21 | Reports | — | get_total_revenue, get_inventory_summary |
| 22 | Notifications | notifications | — |
| 23 | Fiscal Years | fiscal_years | — |
| 24 | Settings | settings, system_settings | — |
| 25 | Currencies | currencies | — |
| 26 | Exchange Rates | exchange_rates | — |
| 27 | Audit Log | audit_logs, audit_logs_text | — |

### Phase 3: RPC Exhaustive Test

For EACH of the 70 RPCs, call with test parameters and verify no exception.

### Phase 4: Trigger Test

For EACH trigger, perform the triggering action and verify the effect.

### Phase 5: Policy Test

For EACH RLS-enabled table, test with authenticated and unauthenticated contexts.

---

## AUTOMATED TEST OUTPUT FORMAT

```
[PASS] Module: Customers — CREATE/READ/UPDATE/DELETE
[PASS] RPC: generate_next_customer_code — returns string
[FAIL] Module: Shareholders — CREATE failed: relation "shareholders" does not exist
  FAILED MODULE: Shareholders
  FAILED TABLE: shareholders
  FAILED RPC: get_next_shareholder_code
  FAILED FUNCTION: None
  FAILED TRIGGER: None
  FAILED POLICY: None
  FAILED QUERY: INSERT INTO shareholders (code, name) VALUES ('SH-001', 'Test')
  FAILED EXCEPTION: relation "public.shareholders" does not exist
```

---

## RECOMMENDATION

1. **First:** Fix the 13 missing tables and 6 missing functions in schema.sql and baseline migration
2. **Then:** Regenerate schema.sql
3. **Then:** Run `supabase db reset` to verify the baseline builds cleanly
4. **Then:** Generate and run this smoke test
