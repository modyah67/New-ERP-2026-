-- ============================================================================
-- Migration 375: Exclude Draft Transactions from get_supplier_true_balances
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_supplier_true_balances()
RETURNS TABLE (
  supplier_id uuid,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  SELECT
    s.id,
    (
      -- 1. Initial Balance
      (CASE WHEN s.initial_balance_direction = 'CREDIT' THEN COALESCE(s.initial_balance, 0) ELSE -COALESCE(s.initial_balance, 0) END)
      
      -- 2. Purchases 
      + COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = s.id AND status = 'confirmed'), 0)
      
      -- 3. Treasury Transactions (Exclude Drafts)
      + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('deposit', 'receive', 'income', 'supplier_refund') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('expense', 'supplier_payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 4. Bank Transactions (Exclude Drafts)
      + COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::TEXT AND type IN ('deposit', 'receive', 'income', 'supplier_refund') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::TEXT AND type IN ('withdraw', 'expense', 'supplier_payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 5. Cheques
      + COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
      - COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)
      
      -- 6. Legacy Ledger Entries (Manual journal entries, packing costs, old lot receipts, etc.)
      + COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END)
          FROM ledger_entries le
          WHERE le.entity_type = 'supplier' 
            AND le.entity_id IN (s.id::text, s.code)
            AND NOT (
                le.reference_type IN ('supplier_payment', 'treasury_deposit', 'treasury_withdrawal', 'treasury_transaction', 'cash_payment', 'receive', 'deposit', 'supplier_refund')
                AND EXISTS (SELECT 1 FROM treasury_transactions tt WHERE tt.id::TEXT = le.reference_id::TEXT)
            )
            AND NOT (
                le.reference_type IN ('bank_payment', 'bank_receipt', 'bank_transaction', 'cheque', 'supplier_payment', 'cheque_payment', 'receive', 'deposit', 'supplier_refund')
                AND EXISTS (SELECT 1 FROM bank_account_transactions bt WHERE bt.id::TEXT = le.reference_id::TEXT)
            )
            AND le.reference_type NOT IN ('lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return')
      ), 0)

      -- 7. New Enterprise Account Ledger Entries (New lot receipts, adjustments)
      + COALESCE((
          SELECT SUM(ale.credit - ale.debit)
          FROM account_ledger_entries ale
          JOIN journal_entries je ON je.id = ale.journal_entry_id
          WHERE ale.account_id = s.account_id
            AND je.source_type IN (
              'lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return', 'manual'
            )
      ), 0)
    ) AS true_balance
  FROM suppliers s;
$func$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';
