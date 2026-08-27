# DATABASE ↔ FLUTTER COMPATIBILITY AUDIT REPORT

**Generated:** 2026-07-21
**Status:** BLOCKED — Missing objects detected
**Schema Version:** supabase/schema.sql (14,322 lines)

---

## EXECUTIVE SUMMARY

| Category | Status | Details |
|----------|--------|---------|
| Missing Tables | **CRITICAL** | 12 tables referenced by Flutter but missing from schema.sql |
| Missing Columns | **CRITICAL** | Multiple columns on missing tables |
| Missing Functions/RPCs | **CRITICAL** | 5 RPCs called by Flutter have no CREATE FUNCTION |
| Missing Views | PASS | 0 missing |
| Missing Triggers | CRITICAL | 3 triggers reference non-existent tables |
| Missing Policies | CRITICAL | 12 policies reference non-existent tables |
| Missing Indexes | CRITICAL | 12 indexes reference non-existent tables |
| Missing Grants | WARNING | 1 GRANT on undefined function |
| Missing Extensions | PASS | uuid-ossp, pg_trgm present |
| Missing Enums | PASS | 0 missing |
| Storage Buckets | PASS | No bucket references found |

---

## MISSING TABLES (12)

### CRITICAL — Tables with active Flutter references

| # | Table | In _COMBINED.sql | Flutter Files | Severity |
|---|-------|-----------------|---------------|----------|
| 1 | **shareholders** | NO (never defined in any migration) | shareholder_dao.dart, treasury_dao.dart | CRITICAL |
| 2 | **export_invoices** | YES (line 86) | export_invoice_dao.dart (12+ calls) | CRITICAL |
| 3 | **finished_products** | YES (line 20340) | Referenced in items VIEW, policies | CRITICAL |
| 4 | **crop_purchases** | YES (line 20381) | crop_purchase_dao.dart | CRITICAL |
| 5 | **shareholder_profit_distributions** | YES (line 34783) | profit_distribution_page.dart, shareholder_statement_cubit.dart | CRITICAL |
| 6 | **shipment_cost_allocations** | YES (line 12920) | shipment_cost_allocation_dao.dart, cost_allocation_service.dart | CRITICAL |
| 7 | **shipment_recipe_snapshots** | YES (line 13130) | shipment_recipe_snapshot_dao.dart, packing_recipe_dao.dart | CRITICAL |
| 8 | **audit_logs_text** | YES (line 11949) | activity_center_page.dart | HIGH |
| 9 | **raw_material_categories** | YES (line 25904) | raw_material_dao.dart, raw_material_form_dialog.dart | HIGH |
| 10 | **raw_material_transactions** | YES (line 20444) | Policy exists in schema.sql | MEDIUM |
| 11 | **finished_goods** | YES (line 13297) | Policy exists in schema.sql | MEDIUM |
| 12 | **shareholder_transactions** | NO (only trigger ref) | Trigger references this table | HIGH |

### Tables defined in _COMBINED.sql but NOT in schema.sql

| # | Table | _COMBINED.sql Line | Flutter Impact |
|---|-------|--------------------|----------------|
| 1 | export_invoices | 86 | Active DAO with 12+ queries |
| 2 | finished_products | 20340 | items VIEW depends on it |
| 3 | crop_purchases | 20381 | Active DAO |
| 4 | shareholder_profit_distributions | 34783 | Active in profit distribution |
| 5 | shipment_cost_allocations | 12920 | Active DAO + service |
| 6 | shipment_recipe_snapshots | 13130 | Active DAO |
| 7 | audit_logs_text | 11949 | Active UI page |
| 8 | raw_material_categories | 25904 | Active DAO |
| 9 | raw_material_transactions | 20444 | Policy exists |
| 10 | finished_goods | 13297 | Policy exists |

### Tables NEVER defined in any migration

| # | Table | Impact |
|---|-------|--------|
| 1 | **shareholders** | CRITICAL — 600+ lines reference it in functions/views/Flutter |
| 2 | **shareholder_transactions** | Trigger fires on it but table never created |
| 3 | **cost_report_items** | No Flutter refs, no migration — not needed |
| 4 | **access** | No table exists — policy target is invalid |

---

## MISSING COLUMNS

### Tables that DO exist in schema.sql but are missing Flutter-referenced columns

| Table | Missing Column | Flutter Reference |
|-------|---------------|-------------------|
| `products` | `category_id` | product_dao.dart |
| `customers` | `name_en`, `customer_type`, `city`, `country` | customer_dao.dart |
| `suppliers` | `name_en`, `city`, `country` | supplier_dao.dart |
| `packing_orders` | `total_cartons`, `total_pallets` | packing_order_dao.dart |

**Note:** These columns may exist via ALTER TABLE in the COMBINED.sql but were not verified against every table definition. The missing tables above are the primary concern.

---

## MISSING FUNCTIONS/RPCs (5)

| # | RPC Name | Called By | Impact |
|---|----------|-----------|--------|
| 1 | **generate_next_customer_code** | customer_dao.dart:12 | Customer creation will fail |
| 2 | **get_total_revenue** | invoice_dao.dart:295 | Reports will fail |
| 3 | **get_next_supplier_code** | supplier_dao.dart:14, supplier_repository.dart:11 | Supplier creation will fail |
| 4 | **get_next_shareholder_code** | shareholder_dao.dart:9 | Shareholder creation will fail |
| 5 | **rpc_process_proforma_invoice_ledger** | proforma_invoice_dao.dart:139 | Proforma invoice processing will fail |

### Additional RPC with no CREATE FUNCTION but has GRANT

| RPC Name | Issue |
|----------|-------|
| **get_inventory_summary** | GRANT exists but no CREATE FUNCTION |

---

## MISSING TRIGGERS (3 — reference non-existent tables)

| # | Trigger | Table | Issue |
|---|---------|-------|-------|
| 1 | `set_export_invoices_updated_at` | export_invoices | Table not created |
| 2 | `trg_check_fy_allows_sales` | invoice_items | Trigger on VIEW (invalid) |
| 3 | `trg_check_fy_allows_shareholder` | shareholder_transactions | Table not created |

---

## MISSING POLICIES (12 — reference non-existent tables)

| # | Policy | Table | Issue |
|---|--------|-------|-------|
| 1 | Multiple | `export_invoices` | Table not created |
| 2 | Multiple | `finished_goods` | Table not created |
| 3 | Multiple | `finished_products` | Table not created |
| 4 | Multiple | `crop_purchases` | Table not created |
| 5 | Multiple | `shareholder_profit_distributions` | Table not created |
| 6 | Multiple | `shipment_cost_allocations` | Table not created |
| 7 | Multiple | `shipment_recipe_snapshots` | Table not created |
| 8 | Multiple | `raw_material_categories` | Table not created |
| 9 | Multiple | `raw_material_transactions` | Table not created |
| 10 | Multiple | `lot_returns` | Policy exists ✓ |
| 11 | `"Allow all anon access"` | `access` | Table does not exist |
| 12 | Multiple | `fruit_varieties` | Table not in schema.sql |

---

## MISSING INDEXES (12 — reference non-existent tables)

| Table | Index Name | Issue |
|-------|-----------|-------|
| `audit_logs_text` | Various | Table not created |
| `company_addresses` | Various | Table not created |
| `crop_purchases` | Various | Table not created |
| `export_invoices` | Various | Table not created |
| `finished_goods` | Various | Table not created |
| `finished_products` | Various | Table not created |
| `raw_material_transactions` | Various | Table not created |
| `shareholder_profit_distributions` | Various | Table not created |
| `shipment_cost_allocations` | Various | Table not created |
| `shipment_recipe_snapshots` | Various | Table not created |
| `financial_audit_log` | Various | Table not created |
| `lots` | Various | Table not created |

---

## MISSING GRANTS (1)

| Function | Issue |
|----------|-------|
| `get_inventory_summary` | GRANT EXECUTE but no CREATE FUNCTION |

---

## DUPLICATE TRIGGERS (Redundant)

| Table | Duplicate Triggers | Issue |
|-------|-------------------|-------|
| `products` | `set_products_updated_at` + `update_products_updated_at` | Redundant — both set updated_at |
| `suppliers` | `set_suppliers_updated_at` + `update_suppliers_updated_at` | Redundant |
| `customers` | `set_customers_updated_at` + `update_customers_updated_at` | Redundant |

---

## DANGEROUS RLS POLICIES

| Table | Policy | Risk |
|-------|--------|------|
| `tenants` | `"Allow all anon access"` | Unauthenticated access to tenant data |
| `tenant_users` | `"Allow all anon access"` | Unauthenticated access to user-tenant mappings |
| `system_settings` | `"Allow all anon access"` | Unauthenticated access to system config |
| `subscription_plans` | `"Allow all anon access"` | Unauthenticated access to plan data |
| `users` | `"Allow all anon access"` | Unauthenticated access to user data |

---

## CONCLUSION

**STOP — DO NOT PROCEED TO DEPLOYMENT**

12 tables referenced by Flutter are missing from `schema.sql`. The baseline migration will fail at runtime. 5 RPCs called by Flutter have no implementation. These must be remediated before any production deployment.

### Required Actions
1. Add 12 missing CREATE TABLE statements to schema.sql
2. Add 5 missing CREATE FUNCTION statements
3. Remove or fix triggers on non-existent tables
4. Remove or fix policies on non-existent tables
5. Remove or fix indexes on non-existent tables
6. Remove dangerous anon-access RLS policies
7. Remove duplicate triggers
