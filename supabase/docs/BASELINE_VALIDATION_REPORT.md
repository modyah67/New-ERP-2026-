# BASELINE MIGRATION VALIDATION REPORT

**File:** `supabase/migrations/20260721000000_initial_schema.sql`
**Generated:** 2026-07-21
**Status:** FAIL — Multiple critical issues

---

## EXECUTIVE SUMMARY

| Check | Result | Details |
|-------|--------|---------|
| Duplicate Tables | PASS | 80 unique CREATE TABLE statements |
| Duplicate Functions | WARNING | 10 functions defined twice (5 are overloads, 5 are duplicates) |
| Duplicate Triggers | PASS | No duplicate trigger names on same table |
| Duplicate Policies | WARNING | 1 invalid policy on non-existent table |
| Duplicate Indexes | PASS | No duplicate index names |
| Ordering | PASS | All CREATE TABLE before CREATE TRIGGER/INDEX/GRANT |
| Syntax | PASS | Balanced parentheses, proper semicolons |
| Extensions | PASS | uuid-ossp and pg_trgm present |
| **Missing Tables** | **FAIL** | 12 tables referenced in triggers/policies/indexes are never created |
| **Missing Function** | **FAIL** | 1 GRANT on undefined function |

---

## CRITICAL ISSUES

### 1. TRIGGERS ON NON-EXISTENT TABLES (3)

The migration will fail at runtime when PostgreSQL encounters these triggers:

```sql
-- Line 1583: Triggers on export_invoices (table never created)
create trigger set_export_invoices_updated_at before update on public.export_invoices
for each row execute function public.set_updated_at();

-- Line 1661: Trigger on invoice_items (this is a VIEW, not a table)
create trigger trg_check_fy_allows_sales before insert or update on public.invoice_items
for each row execute function public.check_fiscal_year_allows_financial();

-- Line 1671: Trigger on shareholder_transactions (table never created)
create trigger trg_check_fy_allows_shareholder before insert or update on public.shareholder_transactions
for each row execute function public.check_fiscal_year_allows_financial();
```

### 2. POLICIES ON NON-EXISTENT TABLES (12)

The migration will fail at PostgreSQL when these policies target tables that don't exist:

| # | Table | Policy Name |
|---|-------|-------------|
| 1 | `access` | "Allow all anon access" |
| 2 | `export_invoices` | Multiple policies |
| 3 | `finished_goods` | "Allow all authenticated" |
| 4 | `finished_products` | "Allow all authenticated" |
| 5 | `crop_purchases` | "Allow all authenticated" |
| 6 | `shareholder_profit_distributions` | "All authenticated" |
| 7 | `shipment_cost_allocations` | "Allow all authenticated" |
| 8 | `shipment_recipe_snapshots` | "Allow all authenticated" |
| 9 | `raw_material_categories` | "Allow all authenticated" |
| 10 | `raw_material_transactions` | "Allow all authenticated" |
| 11 | `fruit_varieties` | "Allow all authenticated" |
| 12 | `company_addresses` | (referenced in index) |

### 3. INDEXES ON NON-EXISTENT TABLES (12)

The migration will fail when creating indexes on tables that don't exist:

| # | Table |
|---|-------|
| 1 | `audit_logs_text` |
| 2 | `company_addresses` |
| 3 | `crop_purchases` |
| 4 | `export_invoices` |
| 5 | `financial_audit_log` |
| 6 | `finished_goods` |
| 7 | `finished_products` |
| 8 | `lots` |
| 9 | `raw_material_transactions` |
| 10 | `shareholder_profit_distributions` |
| 11 | `shipment_cost_allocations` |
| 12 | `shipment_recipe_snapshots` |

### 4. DUPLICATE FUNCTION DEFINITIONS (5)

These functions are defined twice with the same signature — last definition wins:

| Function | Line 1 | Line 2 | Impact |
|----------|--------|--------|--------|
| `audit_trigger_func()` | ~2398 | ~2454 | Second overwrites first (different implementations) |
| `update_updated_at()` | ~11993 | ~12003 | Second overwrites first |
| `deduct_station_batch_allocations()` | ~4053 | ~4173 | Second overwrites first |
| `restore_station_batch_allocations()` | ~4310 | ~4430 | Second overwrites first |
| `rpc_cancel_export_shipment()` | ~6190 | ~6270 | Second overwrites first |

### 5. GRANT ON UNDEFINED FUNCTION (1)

```sql
-- This GRANT references a function that is never created
GRANT EXECUTE ON FUNCTION public.get_inventory_summary() TO authenticated;
```

---

## WARNING ISSUES

### Duplicate Functions (Intentional Overloads — 5)

| Function | Signatures | Valid? |
|----------|-----------|--------|
| `calculate_packing_cost` | 2 different param sets | YES (overload) |
| `rpc_confirm_packing_order` | 2 different param sets | YES (overload) |
| `rpc_confirm_purchase` | 2 different param sets | YES (overload) |
| `rpc_process_lot_receipt` | 2 different param sets | YES (overload) |
| `update_weighted_avg_cost` | 2 different param sets | YES (overload) |

### Duplicate GRANT Statements (12)

Harmless but messy — same GRANT executed twice:

| Function | Duplicate Count |
|----------|----------------|
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

---

## PASS CHECKS

| Check | Result |
|-------|--------|
| No duplicate CREATE TABLE | PASS — 80 unique tables |
| No duplicate CREATE TRIGGER per table | PASS |
| No duplicate CREATE INDEX names | PASS |
| Extensions present | PASS — uuid-ossp, pg_trgm |
| Statement ordering correct | PASS |
| SQL syntax valid | PASS — balanced parentheses, semicolons |

---

## CONCLUSION

**The baseline migration CANNOT build a working database from zero.**

It will fail at:
1. Line ~1583: Trigger on `export_invoices` (table not created)
2. Line ~1661: Trigger on `invoice_items` (VIEW, not table)
3. Line ~1671: Trigger on `shareholder_transactions` (table not created)
4. Various lines: 12 policy creation statements on non-existent tables
5. Various lines: 12 index creation statements on non-existent tables

### Required Fixes
1. Add 12 missing CREATE TABLE statements before their triggers/policies/indexes
2. Fix or remove trigger on `invoice_items` (cannot trigger on VIEW)
3. Fix or remove trigger on `shareholder_transactions`
4. Remove duplicate function definitions (keep latest)
5. Remove duplicate GRANT statements
6. Add missing `get_inventory_summary` function or remove its GRANT
