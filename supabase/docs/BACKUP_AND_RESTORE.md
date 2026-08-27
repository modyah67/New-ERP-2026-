# Backup and Restore Guide

## Backup

### Automated Backup

```powershell
.\scripts\backup.ps1
```

Creates a timestamped SQL dump in `db_backups/` directory.

### Manual Backup

```bash
supabase db dump > db_backups/custom_backup_$(date +%Y%m%d).sql
```

### What is Backed Up

- Complete schema (tables, functions, triggers, policies, indexes)
- All data (master data + transactional data)
- Extensions
- RLS policies

### What is NOT Backed Up

- Auth users (managed by Supabase)
- Storage files
- Edge functions
- Realtime subscriptions

## Restore

### From Backup

```powershell
.\scripts\restore.ps1 -BackupFile db_backups\backup_20260721_143000.sql
```

### Manual Restore

```bash
# Reset database
supabase db reset

# Apply backup
psql $SUPABASE_DB_URL -f db_backups/backup_20260721_143000.sql
```

### Restore to a Different Project

```bash
# Link to target project
supabase link <target-project-ref>

# Reset and restore
supabase db reset
psql <target-db-url> -f db_backups/backup_20260721_143000.sql
```

## Wipe Runtime Data

To reset a database to a clean state (remove all transactional data):

```bash
psql $SUPABASE_DB_URL -f supabase/scripts/wipe_runtime.sql
```

This preserves:
- Users & profiles
- Accounts & chart of accounts
- Currencies & exchange rates
- Settings & company profile
- Customers & suppliers (with zeroed balances)
- Products (with zeroed quantities)
- Fruit types
- Warehouses
- Stations
- Treasuries

## Backup Schedule Recommendation

| Environment | Frequency | Retention |
|------------|-----------|-----------|
| Development | On-demand | Last 5 backups |
| Staging | Daily | 30 days |
| Production | Daily + Weekly | 90 days |

## Disaster Recovery

1. Create new Supabase project
2. Link: `supabase link <new-project-ref>`
3. Push schema: `supabase db push`
4. Restore data: `psql <new-db-url> -f backup.sql`
5. Verify: `.\scripts\verify.ps1`
6. Update Flutter app configuration with new Supabase URL/keys
