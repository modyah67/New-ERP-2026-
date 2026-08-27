# System Architecture Document

**Version:** 1.0.0  
**Last Updated:** 2026-06-20

---

## 1. Technology Stack

| Layer | Technology | Version |
|---|---|---|
| Frontend | Flutter (Dart) | 3.x |
| Backend | Supabase (PostgreSQL) | 15+ |
| Auth | Supabase Auth | Built-in |
| State Management | flutter_bloc | 8.1.6 |
| DI | get_it + injectable | 8.0.2 |
| Routing | go_router | 14.0 |
| PDF | pdf + printing | 3.10 / 5.12 |
| Localization | flutter_localizations + intl | 0.20 |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Flutter Client                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │   UI /   │  │   BLoC   │  │    Services       │  │
│  │  Pages   │  │  Cubits  │  │  (Business Logic) │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│                       │                             │
│              ┌────────▼────────┐                    │
│              │     DAO Layer   │                    │
│              │  (Data Access)  │                    │
│              └────────┬────────┘                    │
│                       │                             │
│              ┌────────▼────────┐                    │
│              │  Supabase SDK   │                    │
│              └────────┬────────┘                    │
└───────────────────────┼─────────────────────────────┘
                        │ HTTPS / REST
┌───────────────────────┼─────────────────────────────┐
│              ┌────────▼────────┐                    │
│              │  Supabase API   │                    │
│              │  (PostgREST)    │                    │
│              └────────┬────────┘                    │
│                       │                             │
│              ┌────────▼────────┐                    │
│              │   PostgreSQL    │                    │
│              │   (35+ tables)  │                    │
│              │   + RPC fns     │                    │
│              └─────────────────┘                    │
│                        Supabase Cloud               │
└─────────────────────────────────────────────────────┘
```

---

## 3. Application Layers

### 3.1 Presentation Layer
- **Pages:** 30+ feature pages organized by domain
- **State:** BLoC/Cubit pattern with flutter_bloc
- **Routing:** go_router with named routes
- **Theme:** Custom AppTheme with system colors

### 3.2 Business Logic Layer
- **Services:** 13 standalone services (cost_allocation, cogs, approvals, etc.)
- **Repositories:** Data aggregation between DAOs and services
- **Validation:** Client-side validation before API calls

### 3.3 Data Access Layer
- **DAOs:** 37 data access objects, one per table
- **Models:** Dart model classes with fromMap/toMap
- **Supabase SDK:** Direct PostgREST queries via `supabase.from('table')`

### 3.4 Database Layer
- **35+ tables** across 12 domains
- **7 RPC functions** for atomic operations
- **59 migrations** for schema evolution
- **Row-Level Security** on all tables

---

## 4. Module Architecture

### 4.1 Core Modules
```
core/
├── theme.dart          # AppTheme, colors, text styles
├── utils.dart          # AppUtils helpers
├── constants.dart      # App-wide constants
└── router.dart         # go_router configuration
```

### 4.2 Feature Modules
```
features/
├── auth/               # Authentication (login, register)
├── purchases/          # Purchase invoices, items
├── lots/               # Lot receiving, tracking
├── packing/            # Packing orders, recipes
├── exports/            # Export shipments, costing, invoices
├── dashboard/          # Executive dashboard, KPIs
├── treasury/           # Cash management
├── accounting/         # Chart of accounts, COGS
├── inventory/          # Inventory valuation
├── notifications/      # Notification center
├── activity/           # Activity feed
├── settings/           # System settings
├── backup/             # Backup & restore
├── security/           # Security assessment
├── checklist/          # Go-live checklist
└── ...                 # Other domains
```

### 4.3 Data Modules
```
data/
├── dao/                # 37 data access objects
├── models/             # Dart model classes
├── services/           # 13 business services
├── repositories/       # Data aggregation
└── database/           # Connection config
```

---

## 5. Key Design Patterns

| Pattern | Usage | Example |
|---|---|---|
| Repository | Data access abstraction | DAO → Service |
| Singleton | Shared instances | get_it DI container |
| BLoC/Cubit | State management | ExportShipmentCubit |
| Strategy | Cost allocation | Grading cost split |
| Observer | Notification polling | Notification polling timer |

---

## 6. Security Architecture

- **Authentication:** Supabase Auth (email/password, magic link)
- **Authorization:** Row-Level Security on all tables
- **Audit:** All transactions logged with `created_by`, `reference_type`, `reference_id`
- **Data Validation:** Client + DB level constraints
- **Sensitive Data:** Encryption for backup files

---

## 7. Deployment Architecture

### Development
```
Flutter: flutter run --flavor dev
Supabase: Local project (supabase start)
```

### Staging
```
Flutter: flutter build apk/windows --flavor staging
Supabase: Staging project (separate DB)
```

### Production
```
Flutter: flutter build windows --release
Supabase: Production project (scaled)
Backups: Automated daily via pg_dump
```

---

## 8. Scalability Considerations

- **Database:** Supabase auto-scales PostgreSQL (up to 8GB RAM, 2 vCPU on Pro)
- **Connections:** 15 connection pool (enough for <50 concurrent users)
- **Query Performance:** 30+ indexes on high-frequency queries
- **RPC Functions:** Reduce round-trips for multi-step operations
- **Client State:** Flutter BLoC state is in-memory, no server-side caching needed
