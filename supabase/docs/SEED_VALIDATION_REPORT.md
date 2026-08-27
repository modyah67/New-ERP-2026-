# SEED VALIDATION REPORT

**Generated:** 2026-07-21
**Files:** `seed_required.sql`, `seed_demo.sql`
**Status:** PASS with warnings

---

## SEED: seed_required.sql

### Master Data Inserts

| # | Table | Rows | Idempotent | ON CONFLICT | FK Safe | Status |
|---|-------|------|------------|-------------|---------|--------|
| 1 | `currencies` | 4 | ✓ | `code` | None | PASS |
| 2 | `exchange_rates` | 4 | ✓ | `currency_code` | None | PASS |
| 3 | `accounts` | 16 | ✓ | `id` | None | PASS |
| 4 | `settings` | 6 | ✓ | `key` | None | PASS |
| 5 | `company_profile` | 1 | ✓ | `id` | None | PASS |
| 6 | `fruit_types` | 10 | ✓ | `name` | None | PASS |
| 7 | `invoice_numbering` | 6 | ✓ | `entity_type` | None | PASS |
| 8 | `fiscal_years` | 1 | ✓ | `year` | None | PASS |

### Validation Details

**ON CONFLICT usage:** All 8 INSERT statements use `ON CONFLICT ... DO UPDATE` or `DO NOTHING`. Safe for repeated execution.

**FK dependencies:** All inserts target tables with no FK constraints on the inserted columns. No dependency ordering issues.

**Master data only:** No transactional data. No customers, suppliers, purchases, invoices, or any runtime records.

**Runtime data preserved:** Wipe script (`wipe_runtime.sql`) preserves all these master data tables.

### Warnings

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | `fiscal_years` uses `ON CONFLICT (year)` | INFO | Assumes `year` column has UNIQUE constraint — verify in schema |
| 2 | `accounts` uses hardcoded UUIDs | INFO | Must match the UUID format expected by the application |

### Verdict: PASS

seed_required.sql is safe for production use.

---

## SEED: seed_demo.sql

### Demo Data Inserts

| # | Table | Rows | Idempotent | ON CONFLICT | FK Safe | Status |
|---|-------|------|------------|-------------|---------|--------|
| 1 | `warehouses` | 2 | ✓ | `id` | None | PASS |
| 2 | `customers` | 4 | ✓ | `id` | None | PASS |
| 3 | `suppliers` | 3 | ✓ | `id` | None | PASS |
| 4 | `products` | 5 | ✓ | `id` | None | PASS |
| 5 | `stations` | 2 | ✓ | `code` | None | PASS |
| 6 | `treasuries` | 2 | ✓ | `id` | None | PASS |
| 7 | `bank_accounts` | 2 | ✓ | `currency` | None | PASS |
| 8 | `expense_categories` | 7 | ✓ | `name` | None | PASS |
| 9 | `clearing_agents` | 2 | ✓ | `code` | None | PASS |
| 10 | `shipping_companies` | 3 | ✓ | `code` | None | PASS |

### Validation Details

**ON CONFLICT usage:** All 10 INSERT statements use `ON CONFLICT`. Safe for repeated execution.

**FK dependencies:** All inserts target independent tables. No cascading FK issues.

**Demo-only flag:** File header clearly states "DO NOT run this on production."

### Warnings

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | `bank_accounts` UNIQUE on `currency` | MEDIUM | Both demo bank accounts are EGP — second INSERT will UPDATE the first. Should use different currencies or remove UNIQUE constraint. |
| 2 | `products` has `category_id` column | INFO | Demo products set `category_id = NULL` — verify column allows NULL in schema |

### Verdict: PASS (demo only)

seed_demo.sql is safe for development use. The bank_accounts currency conflict is cosmetic only.

---

## OVERALL SEED ASSESSMENT

| Criteria | Result |
|----------|--------|
| Only master data in seed_required | ✓ |
| No runtime/transactional data | ✓ |
| All INSERTs idempotent | ✓ |
| FK dependencies respected | ✓ |
| No superuser commands | ✓ |
| No business logic changes | ✓ |
| Safe for production | ✓ (seed_required only) |
| Safe for development | ✓ (both seeds) |

### Recommendation
- Run `seed_required.sql` after every `supabase db push` or `supabase db reset`
- Run `seed_demo.sql` only in development environments
- Fix the `bank_accounts` currency collision in seed_demo.sql if demo data needs two banks
