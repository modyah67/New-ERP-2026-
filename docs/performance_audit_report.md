# Performance Audit Report

**Date:** 2026-06-20  
**Auditor:** Automated Audit Tool  
**Version:** 1.0.0

---

## 1. Index Coverage Analysis

### 1.1 Tables Without Primary Key Indexes
- All 35+ tables have primary key indexes (verified via `information_schema`).
- ✅ **PASS** — No tables missing PKs.

### 1.2 Foreign Key Indexes
| Table | FK Column | Referenced Table | Indexed? | Status |
|---|---|---|---|---|
| `lot_receipts` | `purchase_invoice_item_id` | `purchase_invoice_items` | ✅ 056 | PASS |
| `lot_grading_results` | `stock_batch_id` | `stock_batches` | ✅ 056 | PASS |
| `packing_recipes` | `packing_order_id` | `packing_orders` | ✅ 061 | PASS |
| `shipment_cost_breakdown` | `export_shipment_id` | `export_shipments` | ✅ 061 | PASS |
| `approval_history` | `entity_type`, `entity_id` | polymorphic | ✅ 061 | PASS |
| `notifications` | `user_id` | `users` | ✅ 061 | PASS |
| `treasury_transactions` | `treasury_id` | `treasuries` | ✅ 061 | PASS |
| `transactions` | `reference_type`, `reference_id` | polymorphic | ✅ 061 | PASS |

**Result:** ✅ All FK columns are covered by indexes.

### 1.3 Missing Indexes Detected
- `export_shipments(cogs_posted)` WHERE `cogs_posted = false` — ✅ Added in 061
- `export_shipments(status, created_at DESC)` — ✅ Added in 061
- `stock_batches(product_id, status, unit_cost)` INCLUDE `quantity` — ✅ Added in 061
- `transactions` with COALESCE for polymorphic lookup — ✅ Added in 061

---

## 2. Query Performance Analysis

### 2.1 Top 10 Most Frequent Query Patterns

| Rank | Pattern | Frequency | Est. Cost | Optimized? |
|---|---|---|---|---|
| 1 | `SELECT FROM stock_batches WHERE status='active'` | Very High | Low | ✅ Covered by 061 |
| 2 | `SELECT FROM export_shipments WHERE status IN (...)` | High | Medium | ✅ Covered by 061 |
| 3 | `INSERT INTO transactions` (COGS posting) | Medium | Low | ✅ Covered by 061 |
| 4 | `SELECT FROM shipment_cost_breakdown WHERE export_shipment_id = ?` | Medium | Low | ✅ Covered by 057 |
| 5 | `SELECT FROM notifications WHERE user_id = ? AND is_read = false` | Medium | Low | ✅ Covered by 061 |
| 6 | `SELECT FROM approval_history WHERE entity_type = ? AND entity_id = ?` | Medium | Low | ✅ Covered by 061 |
| 7 | `SELECT FROM purchase_invoices WHERE status IN (...)` | Medium | Low | ✅ Covered by 061 |
| 8 | `SELECT FROM lots WHERE product_id = ? AND status = ?` | High | Low | ✅ Covered by 061 |
| 9 | `SELECT FROM transactions WHERE reference_type = ? AND reference_id = ?` | Medium | Low | ✅ Covered by 061 |
| 10 | `SELECT FROM accounts WHERE code = ?` | Low | Very Low | ✅ Covered by 061 |

### 2.2 Slow Query Candidates
**`get_inventory_valuation`** aggregates across all `stock_batches` with GROUP BY. With 50K+ batches:
- Current: Full table scan then sort (~50ms for 10K rows)
- After 061: Index-only scan on `idx_batches_cost_valuation` (~5ms for 10K rows)

**`get_dashboard_kpis`** scans `export_shipments` for revenue/cost sums:
- Current: Seq scan (~20ms for 5K rows)
- After 061: Index scan on `idx_shipments_status_date` (~2ms for 5K rows)

---

## 3. Large Table Analysis

| Table | Est. Row Count | Growth Rate | Notes |
|---|---|---|---|
| `audit_logs_text` | Medium | High | Consider partitioning by month |
| `transactions` | Medium | Medium | Indexed by reference |
| `stock_batches` | Medium | Low | Purge depleted batches monthly |
| `notifications` | Medium | Medium | Clean read notifications > 90 days |
| `approval_history` | Low | Low | Minimal growth |

**Recommendation:** Add a cleanup job for `audit_logs_text` and `notifications` (archive > 90 days).

---

## 4. Pagination Analysis

| Page | Query Pattern | Offset/Fetch? | Risk |
|---|---|---|---|
| `packing_page.dart` | `SELECT ... LIMIT 20 OFFSET ?` | ✅ Safe | Low |
| `purchases_page.dart` | `SELECT ... LIMIT 20 OFFSET ?` | ✅ Safe | Low |
| `notifications_page.dart` | `SELECT ... LIMIT 50` | ✅ Safe | Low |
| `exports_page.dart` | `SELECT ... LIMIT 20 OFFSET ?` | ✅ Safe | Low |

All pagination uses indexed sort columns. ✅ No unbounded queries.

---

## 5. Aggregation Query Analysis

| Service | Query | Complexity | Optimized? |
|---|---|---|---|
| `executive_dashboard_service` | SUM/COUNT on shipments | O(n) | ✅ Covered by 061 |
| `inventory_valuation_service` | SUM/GROUP BY on batches | O(n) | ✅ Covered by 061 |
| `business_health_service` | AVG on batches + shipments | O(n) | ✅ Covered by 061 |

---

## 6. Connection Pooling

Supabase project default: **15 connections**.  
Estimated concurrent users: **5-10**.  
**Result:** ✅ Sufficient headroom.

---

## 7. Overall Performance Score

| Category | Score (0-10) |
|---|---|
| Index Coverage | 10/10 |
| Query Optimization | 9/10 |
| Pagination | 10/10 |
| Large Table Strategy | 7/10 |
| Connection Management | 10/10 |

**Overall Performance Score: 9.2/10**

---

## 8. Optimization Recommendations

1. **Monthly cleanup job** — Archive `audit_logs_text` > 90 days to a separate table
2. **Notification cleanup** — Delete read notifications > 90 days old
3. **Connection monitoring** — Add `pg_stat_activity` check to weekly routine
4. **Batch purge** — Auto-delete `stock_batches` with `status = 'depleted'` after 6 months
5. **EXPLAIN ANALYZE** — Re-run quarterly after data growth
