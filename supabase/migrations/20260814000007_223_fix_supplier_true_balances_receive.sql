-- Migration 223: Fix supplier true balances to exclude 'receive' and 'deposit' ledger entries
-- When receiving money from a supplier in treasury, the 'receive_payment' RPC inserts a ledger entry with reference_type = 'receive'.
-- We need to exclude this ledger entry from the true balance calculation since it's already counted in the treasury_transactions sum.

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
      -- 1. Initial Balance
      (CASE WHEN s.initial_balance_direction = 'CREDIT' THEN COALESCE(s.initial_balance, 0) ELSE -COALESCE(s.initial_balance, 0) END)
      
      -- 2. Purchases 
      + COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = s.id AND status = 'confirmed'), 0)
      
      -- 3. Treasury Transactions
      + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('deposit', 'receive', 'income', 'supplier_refund')), 0)
      - COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('expense', 'supplier_payment')), 0)
      
      -- 4. Bank Transactions
      + COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::TEXT AND type IN ('deposit', 'receive', 'income', 'supplier_refund')), 0)
      - COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::TEXT AND type IN ('withdraw', 'expense', 'supplier_payment')), 0)
      
      -- 5. Cheques
      + COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
      - COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)
      
      -- 6. Ledger Entries (Lot Receipts, manual journal entries, packing costs, etc.)
      -- We EXCLUDE entries that are already represented by treasury_transactions or bank_transactions above 
      -- (only if their reference_type indicates they actually came from those tables)
      + COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END)
          FROM ledger_entries le
          WHERE le.entity_type = 'supplier' 
            AND le.entity_id IN (s.id::text, s.code)
            AND NOT (
                -- Exclude if it's a treasury transaction AND exists in the treasury table
                le.reference_type IN ('supplier_payment', 'treasury_deposit', 'treasury_withdrawal', 'treasury_transaction', 'cash_payment', 'receive', 'deposit', 'supplier_refund')
                AND EXISTS (SELECT 1 FROM treasury_transactions tt WHERE tt.id::TEXT = le.reference_id::TEXT)
            )
            AND NOT (
                -- Exclude if it's a bank transaction AND exists in the bank table
                le.reference_type IN ('bank_payment', 'bank_receipt', 'bank_transaction', 'cheque', 'supplier_payment', 'cheque_payment', 'receive', 'deposit', 'supplier_refund')
                AND EXISTS (SELECT 1 FROM bank_account_transactions bt WHERE bt.id::TEXT = le.reference_id::TEXT)
            )
      ), 0)
    ) AS true_balance
  FROM suppliers s;
$$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated;

-- Force schema reload
NOTIFY pgrst, 'reload schema';
