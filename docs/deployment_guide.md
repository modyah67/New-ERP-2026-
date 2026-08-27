# Deployment Guide

**Version:** 1.0.0  
**Last Updated:** 2026-06-20  
**Target Platform:** Windows Desktop

---

## 1. Prerequisites

### 1.1 Required Software
- **Flutter SDK** 3.x ([install guide](https://docs.flutter.dev/get-started/install/windows))
- **Dart SDK** 3.x (included with Flutter)
- **Git** for version control
- **Supabase CLI** for database management
- **Windows SDK** for Windows desktop builds

### 1.2 Accounts
- **Supabase Project** (production tier)
- **Sentry** (optional, for crash reporting)

---

## 2. Database Setup

### 2.1 Create Supabase Project
1. Go to [supabase.com](https://supabase.com) and create a new project
2. Note the project URL and anon key
3. Choose region closest to your users

### 2.2 Run Migrations
```bash
# Clone the repository
git clone <repo-url> && cd erp-system

# Install Supabase CLI
npm install -g supabase

# Link to your Supabase project
supabase link --project-ref <your-project-ref>

# Push all migrations
supabase db push

# Verify
supabase db diff
```

### 2.3 Seed Initial Data
Run the seed script (if available) or manually:
- Create admin user via Supabase Auth dashboard
- Run `rpc_ensure_default_accounts()` to seed Chart of Accounts

---

## 3. Application Configuration

### 3.1 Environment Variables
Create `lib/core/env.dart`:
```dart
class AppEnv {
  static const supabaseUrl = 'https://your-project.supabase.co';
  static const supabaseAnonKey = 'your-anon-key';
  static const sentryDsn = 'your-sentry-dsn'; // optional
  static const appName = 'نظام المحاسبة';
  static const version = '1.0.0';
}
```

### 3.2 Firebase/GCM (optional, for push notifications)
- Not required for current notification system (uses in-app polling)

---

## 4. Build & Deployment

### 4.1 Windows Desktop Build
```bash
# Clean and get dependencies
flutter clean && flutter pub get

# Run tests
flutter test

# Build release
flutter build windows --release

# Output location: build/windows/runner/Release/
```

### 4.2 Installation Package
Use [Inno Setup](https://jrsoftware.org/isinfo.php) to create an installer:
```iss
; setup.iss
[Setup]
AppName=نظام المحاسبة
AppVersion=1.0.0
DefaultDirName={pf}\ERP System
OutputDir=dist

[Files]
Source: "build\windows\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\نظام المحاسبة"; Filename: "{app}\accounting_system.exe"
```

---

## 5. Post-Deployment Checklist

- [ ] Verify database connection
- [ ] Run `rpc_health_check()` — should return `{"status": "healthy"}`
- [ ] Verify user authentication (login/logout)
- [ ] Run a test purchase workflow
- [ ] Verify backup creation
- [ ] Check monitoring dashboard
- [ ] Test notification delivery
- [ ] Verify security assessment page shows correct score

---

## 6. Rollback Plan

### Database Rollback
```bash
# Rollback to specific migration
supabase migration repair --status reverted <migration-number>

# Or restore from backup
psql -h <host> -U <user> -d <database> -f backup_file.sql
```

### Application Rollback
- Keep previous build artifacts
- Re-install previous version via installer

---

## 7. Production Support

### Monitoring
- Supabase Dashboard for DB metrics
- Error logs in `audit_logs_text` table
- Weekly performance review

### Backup Strategy
| Type | Frequency | Retention |
|---|---|---|
| Full DB backup | Daily | 30 days |
| Migration backups | On each change | Indefinite |
| Transaction logs | Continuous | 7 days |

### Contact
- **Dev Team:** [internal email]
- **Supabase Support:** [support@supabase.com](mailto:support@supabase.com)
