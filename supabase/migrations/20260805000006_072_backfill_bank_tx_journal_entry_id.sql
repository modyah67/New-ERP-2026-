-- Migration 072: Backfill journal_entry_id on bank_account_transactions
-- Some bank transactions were created before journal_entry_id was stored.
-- This migration links them to their correct journal entries.

-- ============================================================
-- 1. Ensure journal_entry_id column exists on bank_account_transactions
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bank_account_transactions' AND column_name = 'journal_entry_id'
  ) THEN
    ALTER TABLE public.bank_account_transactions
      ADD COLUMN journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- 2. Backfill bank_account_transactions where journal_entry_id IS NULL
--    Match by: source_type + description + date proximity + amount
-- ============================================================

-- 2a. Match by source_type = 'opening_balance'
UPDATE public.bank_account_transactions bat
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type = 'opening_balance'
    AND je.deleted_at IS NULL
    AND je.description ILIKE '%' || bat.description || '%'
    AND je.entry_date = bat.created_at::date
  ORDER BY je.id DESC
  LIMIT 1
)
WHERE bat.journal_entry_id IS NULL
  AND bat.source_type = 'opening_balance'
  AND bat.description IS NOT NULL;

-- 2b. Match by source_type = 'cheque'
UPDATE public.bank_account_transactions bat
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type IN ('bank_deposit', 'bank_withdraw')
    AND je.deleted_at IS NULL
    AND je.description ILIKE '%' || bat.description || '%'
  ORDER BY je.id DESC
  LIMIT 1
)
WHERE bat.journal_entry_id IS NULL
  AND bat.source_type = 'cheque'
  AND bat.description IS NOT NULL;

-- 2c. Match by source_type = 'revenue'
UPDATE public.bank_account_transactions bat
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type = 'bank_deposit'
    AND je.deleted_at IS NULL
    AND je.description ILIKE '%' || bat.description || '%'
  ORDER BY je.id DESC
  LIMIT 1
)
WHERE bat.journal_entry_id IS NULL
  AND bat.source_type = 'revenue'
  AND bat.description IS NOT NULL;

-- 2d. Match remaining bank_deposit source_type
UPDATE public.bank_account_transactions bat
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type = 'bank_deposit'
    AND je.deleted_at IS NULL
    AND je.description ILIKE '%' || bat.description || '%'
  ORDER BY je.id DESC
  LIMIT 1
)
WHERE bat.journal_entry_id IS NULL
  AND bat.source_type = 'bank_deposit'
  AND bat.description IS NOT NULL;

-- 2e. Match remaining bank_withdraw source_type
UPDATE public.bank_account_transactions bat
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type = 'bank_withdraw'
    AND je.deleted_at IS NULL
    AND je.description ILIKE '%' || bat.description || '%'
  ORDER BY je.id DESC
  LIMIT 1
)
WHERE bat.journal_entry_id IS NULL
  AND bat.source_type = 'bank_withdraw'
  AND bat.description IS NOT NULL;

-- 2f. Final catch-all: match any remaining transactions by description
UPDATE public.bank_account_transactions bat
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type IN ('bank_deposit', 'bank_withdraw', 'opening_balance')
    AND je.deleted_at IS NULL
    AND je.description ILIKE '%' || bat.description || '%'
  ORDER BY ABS(EXTRACT(EPOCH FROM (je.entry_date::timestamp - bat.created_at))) ASC
  LIMIT 1
)
WHERE bat.journal_entry_id IS NULL
  AND bat.description IS NOT NULL
  AND length(bat.description) > 5;

-- ============================================================
-- 3. Verify results
-- ============================================================
DO $$
DECLARE
  v_total INT;
  v_linked INT;
  v_unlinked INT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM public.bank_account_transactions;
  SELECT COUNT(*) INTO v_linked FROM public.bank_account_transactions WHERE journal_entry_id IS NOT NULL;
  SELECT COUNT(*) INTO v_unlinked FROM public.bank_account_transactions WHERE journal_entry_id IS NULL;
  RAISE NOTICE 'Bank transactions: total=%, linked=%, unlinked=%', v_total, v_linked, v_unlinked;
END $$;

NOTIFY pgrst, 'reload schema';
