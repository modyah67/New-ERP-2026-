# Monitoring Setup Guide

**Date:** 2026-06-20  
**Applies to:** ERP System v1.0.0

---

## 1. Error Logging

### 1.1 Server-Side (PostgreSQL)
Errors are logged to `audit_logs_text` table via:
- `rpc_confirm_packing` — logs packing confirmations
- `rpc_post_shipment_with_cogs` — logs COGS posting
- `rpc_process_approval` — logs approval actions
- `rpc_process_treasury_transaction` — logs treasury transactions

**Query to view recent errors:**
```sql
SELECT * FROM audit_logs_text
WHERE action LIKE '%error%' OR action LIKE '%fail%'
ORDER BY created_at DESC
LIMIT 50;
```

### 1.2 Client-Side (Flutter)
Add a global error handler in `main.dart`:

```dart
void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log to Supabase audit_logs_text
    supabase.from('audit_logs_text').insert({
      'table_name': 'client_error',
      'record_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'action': details.exceptionAsString().substring(0, 500),
      'old_values': {},
      'new_values': {'stack': details.stack.toString().substring(0, 2000)},
      'performed_by': supabase.auth.currentUser?.id ?? 'anonymous',
    });
  };
}
```

---

## 2. Crash Reporting

### 2.1 Option A: Supabase Logs (free)
Supabase provides built-in query logging:
1. Go to **Supabase Dashboard → Database → Query Performance**
2. Monitor slow queries, error rates, and frequent queries
3. Set up alerts for query duration > 1 second

### 2.2 Option B: Sentry (recommended for production)
1. Create account at [sentry.io](https://sentry.io)
2. Add dependency: `sentry_flutter: ^7.0.0`
3. Initialize in `main.dart`:
```dart
import 'package:sentry_flutter/sentry_flutter.dart';

await SentryFlutter.init(
  (options) => options.dsn = 'https://your-dsn@sentry.io/project-id',
  appRunner: () => runApp(MyApp()),
);
```

---

## 3. Performance Monitoring

### 3.1 Supabase Query Analysis
**Dashboard:** Supabase → Database → Query Performance
- Track: execution time, row counts, temp file I/O
- Set threshold: alert when avg query time > 500ms

**Key queries to monitor:**
```sql
-- Top 10 slowest queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### 3.2 Custom Health Check Endpoint
Create an RPC function:
```sql
CREATE OR REPLACE FUNCTION rpc_health_check()
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
  'status', 'healthy',
  'db_time', NOW(),
  'connections', (SELECT count(*) FROM pg_stat_activity),
  'tables', (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public')
);
$$;
```

Call from a cron job or external uptime monitor.

---

## 4. Operational Alerts

### 4.1 Low Stock Alert
Monitor stock_batches with quantity below threshold:
```sql
SELECT p.name AS product, SUM(sb.quantity) AS total_qty
FROM stock_batches sb
JOIN products p ON p.id = sb.product_id
WHERE sb.status = 'active'
GROUP BY p.id, p.name
HAVING SUM(sb.quantity) < 1000;
```

### 4.2 Pending Approvals Alert
```sql
SELECT entity_type, COUNT(*) AS pending_count
FROM approval_history
WHERE to_status = 'pending'
  AND created_at > NOW() - INTERVAL '24 hours'
GROUP BY entity_type;
```

### 4.3 Failed COGS Posting Alert
```sql
SELECT id, shipment_number, total_cost
FROM export_shipments
WHERE cogs_posted = false
  AND status IN ('shipped', 'in_transit')
  AND total_cost > 0;
```

---

## 5. Dashboard Setup

### 5.1 Supabase Dashboard Widgets
Add to your Supabase project dashboard:
| Widget | SQL Source | Refresh Rate |
|---|---|---|
| Active Users | `SELECT count(*) FROM pg_stat_activity` | 30s |
| Query Response Time | `SELECT avg(mean_exec_time) FROM pg_stat_statements` | 60s |
| Error Rate | `SELECT count(*) FROM audit_logs_text WHERE created_at > NOW() - INTERVAL '1 hour'` | 60s |
| DB Size | `SELECT pg_size_pretty(pg_database_size(current_database()))` | 300s |

### 5.2 External Monitoring (Grafana)
1. Connect to Supabase via PostgreSQL data source
2. Import sample dashboard: [ERP Dashboard Template](https://grafana.com/grafana/dashboards)
3. Configure alert channels (email, Slack, Telegram)

---

## 6. Backup Monitoring

Verify backups with:
```sql
SELECT * FROM backup_history
ORDER BY created_at DESC
LIMIT 5;
```

**Expected:** At least one successful backup in the last 24 hours.

---

## 7. Alert Channels Configuration

| Channel | Configuration | Cost |
|---|---|---|
| Email | Supabase project alerts (built-in) | Free |
| Slack | Supabase → Integration → Slack Webhook | Free |
| Telegram | Custom bot via Supabase Edge Functions | Free |
| SMS | Twilio integration | Paid |

**Recommended:** Start with Supabase built-in alerts (free).

---

## 8. Monitoring Runbook

### Daily Checks
1. View Supabase Query Performance dashboard
2. Check `audit_logs_text` for unexpected errors
3. Verify backup_history for last 24h

### Weekly Checks
1. Run `rpc_health_check()` 
2. Review slow query log, add indexes if needed
3. Check `stock_batches` for orphaned records

### Monthly Checks
1. Re-run performance audit
2. Archive audit_logs_text > 90 days
3. Review monitoring budget (Supabase Logs retention)
