# Administrator Manual

**Version:** 1.0.0  
**Last Updated:** 2026-06-20

---

## 1. User Management

### 1.1 Create User
1. Go to **إدارة المستخدمين** (User Management)
2. Click **إضافة مستخدم** (Add User)
3. Enter email, name, role
4. System sends invitation email

### 1.2 Roles & Permissions

| Role | Permissions |
|---|---|
| `admin` | Full access: approve, post COGS, manage users, settings |
| `manager` | Create/edit entities, view reports, submit for approval |
| `user` | Create/edit own entities, view assigned data |

### 1.3 Deactivate User
1. Find user in management list
2. Click **تعطيل** (Deactivate)
3. User can no longer login

---

## 2. Database Administration

### 2.1 Access Supabase Dashboard
- URL: `https://supabase.com/dashboard/project/<your-ref>`
- Use admin credentials (not app credentials)

### 2.2 Common Admin Queries
```sql
-- Check database size
SELECT pg_size_pretty(pg_database_size(current_database()));

-- Active connections
SELECT count(*) FROM pg_stat_activity;

-- Pending COGS
SELECT id, shipment_number FROM export_shipments
WHERE cogs_posted = false AND status IN ('shipped', 'in_transit') AND total_cost > 0;

-- Pending approvals
SELECT entity_type, entity_id, action FROM approval_history
WHERE to_status = 'pending';
```

### 2.3 Manual COGS Posting (if RPC fails)
```sql
SELECT * FROM rpc_post_shipment_with_cogs(
  p_shipment_id := <id>,
  p_new_status := 'shipped',
  p_user_id := '<admin-uuid>'
);
```

---

## 3. Backup & Recovery

### 3.1 Automatic Backups
Supabase Pro plan includes:
- Daily backups with 7-day retention
- Point-in-time recovery (PITR) available

### 3.2 Manual Backup via App
1. Go to **النسخ الاحتياطي** (Backup)
2. Click **إنشاء نسخة احتياطية** (Create Backup)
3. Verify in backup history

### 3.3 Manual Backup via pg_dump
```bash
pg_dump -h <host> -U <user> -d <database> -F c -f backup_$(date +%Y%m%d).dump
```

### 3.4 Restore Procedure
```bash
# Stop application
# Restore database
pg_restore -h <host> -U <user> -d <database> -c backup_file.dump

# Or via Supabase dashboard: Database → Backups → Restore
```

---

## 4. Monitoring & Alerts

### 4.1 Dashboard Monitoring
Access Supabase Dashboard:
- **Database → Query Performance** — slow queries
- **Database → Indexes** — index usage
- **Logs → Postgres Logs** — error logs

### 4.2 Health Check
```bash
# Run periodically from any machine
curl -X POST https://<project>.supabase.co/rest/v1/rpc/rpc_health_check \
  -H "apikey: <anon-key>"
```

### 4.3 Alert Thresholds
| Metric | Warning | Critical |
|---|---|---|
| DB connections | > 12 | > 15 |
| Avg query time | > 300ms | > 1s |
| Error count/hour | > 10 | > 50 |
| Backup age | > 24h | > 48h |

---

## 5. Security Administration

### 5.1 RLS Policies
All tables have RLS enabled with `authenticated` user access:
```sql
-- View current policies
SELECT tablename, policyname, permissive
FROM pg_policies WHERE schemaname = 'public';
```

### 5.2 Audit Log Review
```sql
-- Recent sensitive actions
SELECT * FROM audit_logs_text
WHERE action IN ('post_cogs', 'approve', 'reject', 'payment')
ORDER BY created_at DESC
LIMIT 50;
```

### 5.3 Session Management
```sql
-- View active sessions
SELECT * FROM auth.sessions
WHERE created_at > NOW() - INTERVAL '24 hours';

-- Revoke all sessions for a user
SELECT * FROM auth.revoke_sessions(<user_id>);
```

---

## 6. Maintenance Tasks

### 6.1 Regular Maintenance Schedule

| Frequency | Task | Executed By |
|---|---|---|
| Daily | Verify backups | Automated |
| Daily | Check error logs | Admin |
| Weekly | Performance review | Admin |
| Weekly | Clean notifications > 90 days | Automated |
| Monthly | Archive audit_logs_text | Admin |
| Monthly | Review index usage | Admin |
| Quarterly | Full performance audit | Dev team |

### 6.2 Database Maintenance
```sql
-- Update statistics
ANALYZE;

-- Reindex if needed
REINDEX INDEX CONCURRENTLY idx_stock_batches_product_status;

-- Vacuum (Supabase auto-vacuums, but manual if needed)
VACUUM ANALYZE audit_logs_text;
```

---

## 7. Troubleshooting

### 7.1 Common Issues

**Issue:** COGS not posting automatically
- Check shipment status is `shipped` or `in_transit`
- Check `cogs_posted` flag is `false`
- Check `total_cost > 0`
- Run RPC function manually

**Issue:** User cannot login
- Check user is active in auth.users
- Check email/password are correct
- Reset password via Supabase Auth dashboard

**Issue:** Backup fails
- Check database connection
- Check disk space on Supabase
- Review backup logs

### 7.2 Rollback a Migration
```bash
# If migration caused issues
supabase migration repair --status reverted <bad-migration>
# Then apply the fix
```

### 7.3 Emergency Contact
- **Database Emergency:** Supabase Support
- **Application Bug:** Dev team (internal)
- **Security Incident:** Report immediately to security team
