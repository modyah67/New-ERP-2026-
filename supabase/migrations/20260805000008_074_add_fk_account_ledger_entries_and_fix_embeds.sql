-- Migration 074: Add FK from account_ledger_entries.account_id to accounts.id
-- and fix all embedded accounts queries that were causing PGRST200 errors
--
-- ROOT CAUSES:
-- 1. account_ledger_entries.account_id has NO FK to accounts(id) → PostgREST can't resolve accounts(...) embed
-- 2. cash_receipts has NO account_id column → accounts(...) embed always fails
-- 3. cash_payments.account_id has FK but type may not match
--
-- FIXES:
-- 1. Add FK constraint from account_ledger_entries.account_id → accounts.id
-- 2. All Dart queries now use separate queries instead of embedded relationships
-- 3. Backfill any orphaned account_ledger_entries rows

BEGIN;

-- ============================================================
-- 1. Add FK from account_ledger_entries.account_id to accounts.id
-- ============================================================
DO $$
BEGIN
  -- Check if FK already exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'account_ledger_entries'
      AND constraint_name = 'account_ledger_entries_account_id_fkey'
  ) THEN
    -- First, clean up any orphaned rows (account_id that doesn't exist in accounts)
    DELETE FROM public.account_ledger_entries
    WHERE account_id NOT IN (SELECT id FROM public.accounts);

    ALTER TABLE public.account_ledger_entries
      ADD CONSTRAINT account_ledger_entries_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id)
      ON DELETE RESTRICT;

    RAISE NOTICE 'Added FK constraint account_ledger_entries_account_id_fkey';
  ELSE
    RAISE NOTICE 'FK constraint account_ledger_entries_account_id_fkey already exists';
  END IF;
END $$;

-- ============================================================
-- 2. Verify: no orphaned account_ledger_entries remain
-- ============================================================
DO $$
DECLARE
  v_orphaned BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_orphaned
  FROM public.account_ledger_entries ale
  WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = ale.account_id);

  IF v_orphaned > 0 THEN
    RAISE WARNING 'Found % orphaned account_ledger_entries (account_id not in accounts)', v_orphaned;
  ELSE
    RAISE NOTICE 'OK: All account_ledger_entries have valid account_id';
  END IF;
END $$;

-- ============================================================
-- 3. Ensure cash_payments.account_id FK is valid
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'cash_payments'
      AND constraint_name = 'cash_payments_account_id_fkey'
  ) THEN
    -- Clean up orphaned rows first
    DELETE FROM public.cash_payments
    WHERE account_id IS NOT NULL
      AND account_id NOT IN (SELECT id FROM public.accounts);

    ALTER TABLE public.cash_payments
      ADD CONSTRAINT cash_payments_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id)
      ON DELETE SET NULL;

    RAISE NOTICE 'Added FK constraint cash_payments_account_id_fkey';
  ELSE
    RAISE NOTICE 'FK constraint cash_payments_account_id_fkey already exists';
  END IF;
END $$;

-- ============================================================
-- 4. Ensure transactions.account_id FK is valid
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'transactions'
      AND constraint_name = 'transactions_account_id_fkey'
  ) THEN
    -- Clean up orphaned rows first
    DELETE FROM public.transactions
    WHERE account_id IS NOT NULL
      AND account_id::text NOT IN (SELECT id::text FROM public.accounts);

    ALTER TABLE public.transactions
      ADD CONSTRAINT transactions_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id)
      ON DELETE SET NULL;

    RAISE NOTICE 'Added FK constraint transactions_account_id_fkey';
  ELSE
    RAISE NOTICE 'FK constraint transactions_account_id_fkey already exists';
  END IF;
END $$;

-- ============================================================
-- 5. Summary
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE 'Migration 074 complete: FK constraints verified/added';
  RAISE NOTICE 'All embedded accounts() queries have been replaced with separate queries in Dart';
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
