-- Migration 20260728080000: Fix stock_batches for raw materials purchase flow
-- Problem: rpc_confirm_purchase silently fails to create batches because:
--   1. stock_batches.product_id has FK → products(id), but we insert raw_materials(id) UUIDs
--   2. stock_batches is missing exchange_rate and currency columns that the RPC tries to insert
-- Both errors are swallowed by EXCEPTION WHEN OTHERS THEN RAISE NOTICE in the RPC.

-- 1. Drop the FK constraint on stock_batches.product_id
ALTER TABLE public.stock_batches
  DROP CONSTRAINT IF EXISTS stock_batches_product_id_fkey;

-- 2. Add missing exchange_rate and currency columns
ALTER TABLE public.stock_batches
  ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15,6) DEFAULT 1.0;

ALTER TABLE public.stock_batches
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'EGP';

-- 3. Also fix purchase_invoice_items if it has the same FK issue
ALTER TABLE public.purchase_invoice_items
  DROP CONSTRAINT IF EXISTS purchase_invoice_items_product_id_fkey;

-- 4. Verify
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'stock_batches_product_id_fkey'
      AND conrelid = 'public.stock_batches'::regclass
  ) THEN
    RAISE EXCEPTION 'FK constraint still exists on stock_batches.product_id';
  ELSE
    RAISE NOTICE 'OK: stock_batches.product_id FK dropped';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'stock_batches' AND column_name = 'exchange_rate'
  ) THEN
    RAISE EXCEPTION 'exchange_rate column missing on stock_batches';
  ELSE
    RAISE NOTICE 'OK: stock_batches.exchange_rate exists';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'stock_batches' AND column_name = 'currency'
  ) THEN
    RAISE EXCEPTION 'currency column missing on stock_batches';
  ELSE
    RAISE NOTICE 'OK: stock_batches.currency exists';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
