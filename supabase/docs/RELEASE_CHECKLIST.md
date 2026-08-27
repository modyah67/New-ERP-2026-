# Release Checklist

Use this checklist before every production release or client delivery.

## Schema Verification

- [ ] `supabase db reset` succeeds without errors
- [ ] `supabase db push` succeeds without errors
- [ ] `supabase db seed --file supabase/seeds/seed_required.sql` succeeds
- [ ] `.\scripts\verify.ps1` reports **PASS**

## Database Objects

- [ ] All 80 tables exist and have correct columns
- [ ] All 198 functions/RPCs compile without errors
- [ ] All 50 triggers are active on correct tables
- [ ] All 108 RLS policies are attached to correct tables
- [ ] All 237 indexes exist
- [ ] All 6 views compile and return correct data
- [ ] All 2 extensions are enabled (uuid-ossp, pg_trgm)
- [ ] All sequences are properly configured

## Flutter Compatibility

- [ ] `flutter analyze` passes with no errors
- [ ] `flutter test` passes all tests
- [ ] All DAOs reference correct table names
- [ ] All RPC calls match function signatures
- [ ] All column names match between Dart models and DB
- [ ] All FK relationships work correctly

## Business Logic

- [ ] Purchase workflow works (create → confirm → receive)
- [ ] Sales workflow works (create → confirm → deliver)
- [ ] Export workflow works (create → pack → ship)
- [ ] Treasury operations work (deposit → withdraw → transfer)
- [ ] Cheque operations work (create → clear → cancel)
- [ ] Lot receipt workflow works (receive → grade → pack)
- [ ] Fiscal year operations work (open → close → reopen)
- [ ] Dashboard statistics load correctly
- [ ] Reports generate correctly

## Security

- [ ] RLS policies block unauthorized access
- [ ] Admin-only operations require admin role
- [ ] Employee operations are properly scoped
- [ ] No SQL injection vulnerabilities in RPCs
- [ ] All dynamic SQL uses `format('%I', ...)` or `quote_ident()`

## Seed Data

- [ ] Required seed inserts all mandatory data
- [ ] Seed is idempotent (can be run multiple times)
- [ ] Demo seed is separate and optional
- [ ] No duplicate key errors on re-run

## Deployment

- [ ] Baseline migration builds entire DB from zero
- [ ] New customer deployment works with `deploy_new_customer.ps1`
- [ ] Client can sign up and use the application immediately
- [ ] No manual SQL required after deployment

## Documentation

- [ ] DATABASE_WORKFLOW.md is up-to-date
- [ ] CLIENT_DEPLOYMENT.md is up-to-date
- [ ] RELEASE_CHECKLIST.md is up-to-date
- [ ] DATABASE_RESTRUCTURE_REPORT.md is up-to-date
- [ ] DATABASE_STRUCTURE.md is up-to-date

## Final Verification

- [ ] Fresh database created with `supabase db reset`
- [ ] All migrations applied
- [ ] All seeds executed
- [ ] Flutter app launches without errors
- [ ] Authentication works
- [ ] All major modules functional
- [ ] No console errors
- [ ] No runtime exceptions

## Sign-off

| Item | Status | Verified By | Date |
|------|--------|-------------|------|
| Schema | ☐ | | |
| Functions | ☐ | | |
| Triggers | ☐ | | |
| Policies | ☐ | | |
| Flutter | ☐ | | |
| Business Logic | ☐ | | |
| Security | ☐ | | |
| Documentation | ☐ | | |
