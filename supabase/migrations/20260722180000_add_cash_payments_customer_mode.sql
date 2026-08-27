-- ============================================================================
-- Migration: Add customer mode support to cash_payments
-- Date: 2026-07-22
-- Status: RETROACTIVE — this migration documents changes already applied
--         manually via `supabase db query --linked`. It is idempotent
--         (IF NOT EXISTS) so it is safe to run on any environment.
-- ============================================================================

-- 1. Make supplier_id nullable (was NOT NULL, now nullable for customer mode)
ALTER TABLE public.cash_payments
  ALTER COLUMN supplier_id DROP NOT NULL;

-- 2. Add customer_id column (INTEGER, nullable, FK to customers)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cash_payments' AND column_name = 'customer_id'
  ) THEN
    ALTER TABLE public.cash_payments
      ADD COLUMN customer_id integer REFERENCES customers(id);
  END IF;
END $$;

-- 3. Add account_id column (INTEGER, nullable, FK to accounts)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cash_payments' AND column_name = 'account_id'
  ) THEN
    ALTER TABLE public.cash_payments
      ADD COLUMN account_id integer REFERENCES accounts(id);
  END IF;
END $$;

-- 4. Add mode column (TEXT, nullable, default 'other')
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cash_payments' AND column_name = 'mode'
  ) THEN
    ALTER TABLE public.cash_payments
      ADD COLUMN mode text DEFAULT 'other';
  END IF;
END $$;

-- 5. Add description column (TEXT, nullable)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cash_payments' AND column_name = 'description'
  ) THEN
    ALTER TABLE public.cash_payments
      ADD COLUMN description text;
  END IF;
END $$;
