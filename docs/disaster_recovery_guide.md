# Disaster Recovery Guide

**Version:** 1.0.0  
**Last Updated:** 2026-06-20  
**Severity Levels:** P1 (Critical), P2 (High), P3 (Medium), P4 (Low)

---

## 1. Recovery Objectives

| Metric | Target |
|---|---|
| RPO (Recovery Point Objective) | 24 hours (daily backup) |
| RTO (Recovery Time Objective) | 4 hours |
| Data Loss Tolerance | < 1 day of transactions |

---

## 2. Disaster Scenarios

### Scenario 1: Database Corruption (P1)

**Symptoms:**
- Application fails to load data
- Query errors in Supabase logs
- Referential integrity violations

**Response:**
1. **Stop application** — Prevent further writes
2. **Identify corruption scope** — Check Supabase Dashboard → Database → Health
3. **Restore from latest backup:**
   ```bash
   # Via Supabase Dashboard
   Database → Backups → Select latest → Restore
   ```
4. **Verify data integrity:**
   ```sql
   SELECT rpc_validate_backup_readiness();
   ```
5. **Resume application** — Confirm normal operation
6. **Post-mortem** — Determine root cause, prevent recurrence

**RTO:** ~2 hours (backup size dependent)

---

### Scenario 2: Application Crash (P2)

**Symptoms:**
- App freezes or crashes on startup
- Windows error dialog on launch

**Response:**
1. **Check logs:**
   - Windows Event Viewer → Windows Logs → Application
   - Flutter crash logs in `%APPDATA%\ERP System\logs\`
2. **Re-install application** (keep settings)
3. **If persists**, rollback to previous version
4. **Notify users** via email/WhatsApp

**RTO:** ~1 hour

---

### Scenario 3: Data Loss (P1)

**Symptoms:**
- Missing transactions/invoices
- User reports missing data

**Response:**
1. **Isolate scope** — Which data is missing? When was it last seen?
2. **Check audit logs:**
   ```sql
   SELECT * FROM audit_logs_text
   WHERE created_at > NOW() - INTERVAL '7 days'
   AND action LIKE '%delete%';
   ```
3. **Restore specific table:**
   ```bash
   # Extract table from backup
   pg_restore -d temp_db backup.dump -t <table_name>
   # Export and re-import
   pg_dump -d temp_db -t <table_name> > restored_table.sql
   psql -d production_db -f restored_table.sql
   ```
4. **Verify data completeness**

**RTO:** ~4 hours

---

### Scenario 4: User/Auth Issue (P2)

**Symptoms:**
- User cannot login
- MFA failures
- Suspicious login attempts

**Response:**
1. **Check user status:**
   ```sql
   SELECT * FROM auth.users WHERE email = 'user@example.com';
   ```
2. **Reset password** via Supabase Auth dashboard
3. **Revoke suspicious sessions:**
   ```sql
   SELECT auth.revoke_sessions('<user_id>');
   ```
4. **Enable MFA** if not already enabled

**RTO:** ~30 minutes

---

### Scenario 5: Network/Connectivity (P3)

**Symptoms:**
- Cannot connect to Supabase
- Timeout errors in application

**Response:**
1. **Check Supabase status** — [status.supabase.com](https://status.supabase.com)
2. **Check network** — Firewall, proxy settings
3. **Check DNS** — `nslookup <project>.supabase.co`
4. **Wait for Supabase resolution** (usually < 15 minutes)
5. **If prolonged**, switch to backup Supabase project (if configured)

**RTO:** Dependent on external service

---

## 3. Backup Verification

### Daily Verification
```sql
-- Check backup exists for today
SELECT EXISTS (
  SELECT 1 FROM backup_history
  WHERE created_at::date = CURRENT_DATE
  AND status = 'completed'
);
```

### Weekly Integrity Check
```bash
# Restore to temp database
createdb erp_verify
pg_restore -d erp_verify latest_backup.dump

# Run validation queries
psql -d erp_verify -c "SELECT count(*) FROM export_shipments"
psql -d erp_verify -c "SELECT count(*) FROM transactions"

# Clean up
dropdb erp_verify
```

---

## 4. Communication Plan

| Severity | Notify | Method | Timeframe |
|---|---|---|---|
| P1 | All users | Email + WhatsApp | Immediate |
| P2 | Affected users | Email | Within 1 hour |
| P3 | Admin team | Slack/Email | Within 2 hours |
| P4 | Dev team | Ticket | Next business day |

---

## 5. Post-Recovery Checklist

- [ ] All critical data restored and verified
- [ ] Application functioning normally
- [ ] Users can login and access data
- [ ] Audit logs reflect recovery actions
- [ ] Backup schedule resumed
- [ ] Root cause identified and documented
- [ ] Prevention measures implemented
