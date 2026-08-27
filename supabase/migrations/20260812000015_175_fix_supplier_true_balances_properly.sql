
-- ============================================================================
-- 175: Fix supplier true balances calculation to prevent double counting
-- of payments and to include crop purchases.
-- ============================================================================

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
      (CASE WHEN s.initial_balance_direction = 'CREDIT' THEN s.initial_balance ELSE -s.initial_balance END)
      
      -- Normal Purchases
      + COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = s.id AND status = 'confirmed'), 0)
      
      -- Crop Purchases (Lot Receipts)
      + COALESCE((SELECT SUM(total_fruit_cost) FROM lot_receipts WHERE supplier_id = s.id AND status NOT IN ('closed', 'cancelled')), 0)
      
      -- Treasury
      - COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('expense', 'supplier_payment')), 0)
      + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('income', 'receive', 'supplier_refund')), 0)
      
      -- Bank
      - COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::text AND type = 'withdraw'), 0)
      + COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::text AND type = 'deposit'), 0)
      
      -- Cheques
      - COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)
      + COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
      
      -- Ledger Entries (Manual only - exclude payments to prevent double counting since they are explicitly added above)
      + COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) 
          FROM ledger_entries 
          WHERE entity_type = 'supplier' 
            AND entity_id = s.id::text
            AND reference_type NOT IN (
              'supplier_payment', 'receive', 'expense', 'income', 'supplier_refund', 'payment',
              'withdraw', 'deposit', 'bank_payment',
              'cheque'
            )
      ), 0)
      
      -- Old transactions (if any)
      - COALESCE((
          SELECT SUM(debit - credit) 
          FROM transactions 
          WHERE supplier_id = s.id AND purchase_id IS NULL
      ), 0)
    ) AS true_balance
  FROM suppliers s;
$$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated;
