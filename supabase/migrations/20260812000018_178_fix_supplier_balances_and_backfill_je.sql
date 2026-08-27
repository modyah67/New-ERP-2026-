-- ============================================================================
-- 178: Fix supplier true balances and backfill treasury_transactions journal entries
-- ============================================================================

-- 1. Fix get_supplier_true_balances to strictly use ledger_entries
-- Since ledger_entries is a double-entry ledger that records every action
-- (initial balances, confirmed purchases, lot receipts, payments, etc.),
-- we can simply sum its credits and debits to get the perfect TRUE balance.
CREATE OR REPLACE FUNCTION public.get_supplier_true_balances()
RETURNS TABLE (
  supplier_id uuid,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    s.id,
    (
      -- We ONLY sum ledger_entries. The supplier balance is: Sum(Credits) - Sum(Debits)
      -- because a supplier is a Liability (creditor) account.
      COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) 
          FROM ledger_entries 
          WHERE entity_type = 'supplier' 
            AND entity_id = s.id::text
      ), 0)
    ) AS true_balance
  FROM suppliers s;
$$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated;

-- 2. Backfill OLD treasury_transactions (purchase payments) with journal_entry_id
-- We look for treasury_transactions of type 'expense' or 'supplier_payment'
-- and match them with journal_entries of type 'purchase_payment' or 'supplier_payment'.
UPDATE treasury_transactions tt
SET journal_entry_id = sub.id
FROM (
    SELECT je.id, je.description, je.created_at, je.created_by, ale.credit, ale.currency
    FROM journal_entries je
    JOIN account_ledger_entries ale ON ale.journal_entry_id = je.id
    WHERE je.source_type IN ('supplier_payment', 'purchase_payment', 'purchase')
      AND ale.credit > 0
) sub
WHERE tt.type IN ('supplier_payment', 'expense')
  AND tt.supplier_id IS NOT NULL
  AND tt.journal_entry_id IS NULL
  AND tt.amount = sub.credit
  AND (tt.currency = sub.currency OR tt.currency = 'EGP' OR sub.currency IS NULL)
  AND tt.created_by = sub.created_by
  AND tt.created_at::DATE = sub.created_at::DATE;

-- 3. Fix the "source_id" reference in journal entries to point to treasury_transactions.id
-- This allows the fallback UI lookup to work correctly if direct navigation fails.
UPDATE journal_entries je
SET source_id = tt.id::TEXT
FROM treasury_transactions tt
WHERE je.source_type IN ('supplier_payment', 'purchase_payment')
  AND tt.journal_entry_id = je.id
  AND je.source_id IS DISTINCT FROM tt.id::TEXT;

-- 4. Fix currency in old journal entries
-- The user reported that the journal entry showed EGP when the transaction was USD.
-- If the treasury transaction is USD, we force the account_ledger_entries to USD.
UPDATE account_ledger_entries ale
SET currency = tt.currency
FROM journal_entries je
JOIN treasury_transactions tt ON tt.journal_entry_id = je.id
WHERE ale.journal_entry_id = je.id
  AND tt.currency != ale.currency
  AND tt.currency IS NOT NULL;

-- 5. Force schema reload
NOTIFY pgrst, 'reload schema';
