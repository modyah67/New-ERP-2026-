# DATABASE DIFF REPORT

**Current Live Database** vs **supabase/schema.sql**
**Generated:** 2026-07-21
**Status:** CRITICAL DIFFERENCES

---

## METHODOLOGY

This report compares the final schema.sql (the canonical schema extracted from 300+ migrations) against what would exist in a fresh database built from that schema.sql.

Since we cannot connect to a live database in this environment, this diff is based on:
1. Analysis of `_COMBINED.sql` (the full migration execution history)
2. Analysis of all individual migration files
3. Analysis of Flutter Dart code references
4. Cross-referencing against `schema.sql`

---

## TABLES: schema.sql vs _COMBINED.sql

### Tables in _COMBINED.sql but MISSING from schema.sql (10)

| # | Table | _COMBINED.sql Line | In schema.sql | In Baseline Migration |
|---|-------|--------------------|---------------|----------------------|
| 1 | `export_invoices` | 86 | NO | NO |
| 2 | `shareholder_profit_distributions` | 34783 | NO | NO |
| 3 | `shipment_cost_allocations` | 12920 | NO | NO |
| 4 | `shipment_recipe_snapshots` | 13130 | NO | NO |
| 5 | `audit_logs_text` | 11949 | NO | NO |
| 6 | `raw_material_categories` | 25904 | NO | NO |
| 7 | `raw_material_transactions` | 20444 | NO | NO |
| 8 | `finished_goods` | 13297 | NO | NO |
| 9 | `finished_products` | 20340 | NO | NO |
| 10 | `crop_purchases` | 20381 | NO | NO |

### Tables NEVER defined in any migration (3)

| # | Table | Referenced By | Impact |
|---|-------|--------------|--------|
| 1 | **shareholders** | Functions, views, Flutter DAO | CRITICAL |
| 2 | **shareholder_transactions** | Trigger only | HIGH |
| 3 | **access** | Policy only | MEDIUM |

### Tables in schema.sql but NOT in _COMBINED.sql (0)

All 80 tables in schema.sql have corresponding CREATE TABLE in _COMBINED.sql.

---

## FUNCTIONS: schema.sql vs _COMBINED.sql

### Functions in _COMBINED.sql but MISSING from schema.sql (5)

| # | Function | Impact |
|---|----------|--------|
| 1 | `generate_next_customer_code` | Customer creation fails |
| 2 | `get_total_revenue` | Reports fail |
| 3 | `get_next_supplier_code` | Supplier creation fails |
| 4 | `get_next_shareholder_code` | Shareholder creation fails |
| 5 | `rpc_process_proforma_invoice_ledger` | Proforma processing fails |

### Functions with GRANT but no CREATE FUNCTION (1)

| Function | Issue |
|----------|-------|
| `get_inventory_summary` | GRANT exists, function does not |

---

## TRIGGERS: schema.sql vs _COMBINED.sql

### Triggers referencing non-existent tables in schema.sql (3)

| # | Trigger | Table | Issue |
|---|---------|-------|-------|
| 1 | `set_export_invoices_updated_at` | `export_invoices` | Table not created |
| 2 | `trg_check_fy_allows_sales` | `invoice_items` | Trigger on VIEW |
| 3 | `trg_check_fy_allows_shareholder` | `shareholder_transactions` | Table not created |

---

## POLICIES: schema.sql vs _COMBINED.sql

### Policies referencing non-existent tables in schema.sql (12)

All policies from _COMBINED.sql that target tables missing from schema.sql:

| # | Table | Policy Count |
|---|-------|-------------|
| 1 | `export_invoices` | 2 |
| 2 | `finished_goods` | 1 |
| 3 | `finished_products` | 1 |
| 4 | `crop_purchases` | 1 |
| 5 | `shareholder_profit_distributions` | 1 |
| 6 | `shipment_cost_allocations` | 1 |
| 7 | `shipment_recipe_snapshots` | 1 |
| 8 | `raw_material_categories` | 1 |
| 9 | `raw_material_transactions` | 1 |
| 10 | `fruit_varieties` | 1 |
| 11 | `access` | 1 |
| 12 | `company_addresses` | 1 |

---

## INDEXES: schema.sql vs _COMBINED.sql

### Indexes referencing non-existent tables in schema.sql (12)

Same 12 tables as above — indexes exist in _COMBINED.sql but their target tables are not in schema.sql.

---

## VIEWS: schema.sql vs _COMBINED.sql

### Views in schema.sql referencing non-existent tables (1)

| View | Missing Dependency |
|------|--------------------|
| `items` | References `finished_products` (not in schema.sql) |

---

## EXTENSIONS

| Extension | In schema.sql | In _COMBINED.sql | Match |
|-----------|---------------|------------------|-------|
| `uuid-ossp` | ✓ | ✓ | MATCH |
| `pg_trgm` | ✓ | ✓ | MATCH |

---

## GRANTS

### Duplicate GRANTs in schema.sql (11)

| Function | Count |
|----------|-------|
| `rpc_confirm_purchase` | 2x |
| `rpc_confirm_packing_order` | 2x |
| `exchange_bank_currency` | 2x |
| `delete_bank_account_transaction` | 2x |
| `delete_customer_safe` | 2x |
| `get_complete_dashboard_data` | 2x |
| `restore_station_batch_allocations` | 2x+ |
| `upsert_station_product_quantity` | 2x |
| `withdraw_bank_account` | 2x |
| `rpc_cancel_packing_order` | 3x |
| `rpc_process_lot_receipt` | 2x |

### GRANT on undefined function (1)

| Function | Issue |
|----------|-------|
| `get_inventory_summary` | No CREATE FUNCTION |

---

## SCHEMA COMPLETENESS SCORE

| Category | Count | Missing | Score |
|----------|-------|---------|-------|
| Tables | 91 needed | 13 missing | 86% |
| Functions | 196 defined | 6 missing | 97% |
| Triggers | 50 defined | 3 invalid | 94% |
| Policies | 96 defined | 12 invalid | 87% |
| Indexes | 229 defined | 12 invalid | 95% |
| Views | 9 defined | 1 broken | 89% |
| Extensions | 2 needed | 0 missing | 100% |
| **OVERALL** | | | **91%** |

---

## CONCLUSION

The schema.sql is missing **13 tables**, **6 functions**, and has **3 invalid triggers**, **12 invalid policies**, and **12 invalid indexes** that reference non-existent tables. The `items` view is broken because it depends on `finished_products` which is not in the schema.

**The schema.sql is NOT ready for production deployment until these gaps are remediated.**
