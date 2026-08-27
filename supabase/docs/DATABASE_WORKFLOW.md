# Database Workflow

## Overview

This ERP uses Supabase PostgreSQL with a single canonical schema (`schema.sql`) as the source of truth. All historical migrations have been archived. Future changes must be added as timestamped migrations.

## Directory Structure

```
supabase/
  schema.sql                          # Canonical schema (full database definition)
  migrations/
    20260721000000_initial_schema.sql  # Baseline migration (builds everything)
  migrations_archive/                  # Historical migrations (read-only)
  seeds/
    seed_required.sql                  # Mandatory master data
    seed_demo.sql                      # Optional demo data
  scripts/
    wipe_runtime.sql                   # Reset runtime data only
  docs/
    DATABASE_WORKFLOW.md               # This file
    CLIENT_DEPLOYMENT.md              # Client delivery guide
    BACKUP_AND_RESTORE.md             # Backup/restore procedures
    RELEASE_CHECKLIST.md              # Pre-release checklist
    DATABASE_RESTRUCTURE_REPORT.md    # Restructure audit report
    DATABASE_STRUCTURE.md             # Object inventory
```

## Local Development

### First Time Setup

```powershell
# 1. Clone the repository
git clone <repo-url>
cd <project>

# 2. Reset the database (builds from scratch)
.\scripts\reset_dev.ps1

# 3. Launch Flutter
flutter run -d windows
```

### Daily Development

```powershell
# Reset database to clean state
.\scripts\reset_dev.ps1

# Reset and launch Flutter
.\scripts\reset_dev.ps1 --launch
```

### Adding a New Feature

```powershell
# 1. Create a new migration
supabase migration new add_supplier_currency

# 2. Edit the migration file
# Write only the incremental SQL needed for your feature

# 3. Test locally
.\scripts\reset_dev.ps1

# 4. Verify everything works
.\scripts\verify.ps1

# 5. Commit
git add .
git commit -m "feat: add supplier currency support"
git push
```

### Naming Convention for Migrations

```
YYYYMMDDHHMMSS_description.sql

Examples:
  20260722093000_add_supplier_currency.sql
  20260723140000_add_product_images.sql
  20260725100000_fix_treasury_balance.sql
```

## Database Reset

```powershell
# Full reset (recommended for development)
.\scripts\reset_dev.ps1

# Or manually:
supabase db reset
supabase db push
supabase db seed --file supabase\seeds\seed_required.sql
```

## Backup & Restore

```powershell
# Create backup
.\scripts\backup.ps1

# Restore from backup
.\scripts\restore.ps1 -BackupFile db_backups\backup_20260721_143000.sql
```

## Deploying to a New Client

```powershell
# Two commands only:
supabase link <client-project-ref>
.\scripts\deploy_new_customer.ps1 -ProjectRef <client-project-ref>
```

## Updating an Existing Client

```powershell
# Link to client project
supabase link <client-project-ref>

# Push new migrations only
supabase db push
```

## Rules

1. **NEVER edit** `schema.sql` directly. All changes go through migrations.
2. **NEVER edit** `20260721000000_initial_schema.sql`. It is immutable.
3. **NEVER edit** files in `migrations_archive/`. They are read-only.
4. **ALWAYS use** `supabase migration new` for new changes.
5. **ALWAYS test** with `.\scripts\verify.ps1` before pushing.
6. **ALWAYS use** `ON CONFLICT` in seed files for idempotency.
