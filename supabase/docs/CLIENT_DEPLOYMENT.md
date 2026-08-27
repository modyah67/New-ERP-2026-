# Client Deployment Guide

## Prerequisites

- Supabase CLI installed (`npm install -g supabase`)
- Supabase project created (via supabase.com dashboard)
- Project linked to the repository

## Step 1: Link to Client Project

```bash
supabase link <client-project-ref>
```

Find the project ref in the Supabase dashboard → Settings → General → Project ID.

## Step 2: Push Schema

```bash
supabase db push
```

This applies the baseline migration which creates:
- All 80 tables
- All 198 functions/RPCs
- All 50 triggers
- All 108 RLS policies
- All 237 indexes
- All 6 views
- All extensions (uuid-ossp, pg_trgm)

## Step 3: Seed Required Data

```bash
supabase db seed --file supabase/seeds/seed_required.sql
```

This inserts:
- Currencies (EGP, USD, EUR, GBP)
- Exchange rates
- Chart of accounts (19 core accounts)
- System settings
- Company profile
- Fruit types (10 core types)
- Invoice numbering sequences
- Default fiscal year

## Step 4: Verify

```bash
.\scripts\verify.ps1
```

Expected output: **PASS**

## Step 5: Optional — Load Demo Data

```bash
supabase db seed --file supabase/seeds/seed_demo.sql
```

This adds demo customers, suppliers, products, stations, treasuries, etc.

## Step 6: Client Access

The client can now:
1. Open the Flutter ERP application
2. Sign up as the first user (admin)
3. Start entering their own data

## What the Client Gets

| Item | Status |
|------|--------|
| Complete database schema | ✅ |
| All business logic (RPCs) | ✅ |
| All security policies (RLS) | ✅ |
| Master data (currencies, accounts, etc.) | ✅ |
| No transactional data | ✅ |
| No demo data (unless loaded) | ✅ |

## Rollback

If something goes wrong:

```bash
# Reset the client database
supabase db reset

# Re-apply schema
supabase db push

# Re-seed
supabase db seed --file supabase/seeds/seed_required.sql
```

## Support

For issues, contact the development team with:
1. Error message from `verify.ps1`
2. Supabase project ref
3. Steps to reproduce
