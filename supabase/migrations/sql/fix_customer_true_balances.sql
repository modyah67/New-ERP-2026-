-- ============================================================================
-- Migration: Fix Customer True Balances to Prevent Double Counting Opening Balance
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_customer_true_balances()
RETURNS TABLE (
  customer_id bigint,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $func$
  SELECT
    c.id,
    (
      -- 1. Initial Balance (DEBIT is positive debt / customer owes us, CREDIT is negative / overpayment)
      (CASE 
        WHEN UPPER(COALESCE(c.initial_balance_direction, 'DEBIT')) = 'CREDIT' THEN -COALESCE(c.initial_balance, 0) 
        ELSE COALESCE(c.initial_balance, 0) 
      END)
      
      -- 2. Export Shipments (Debits - customer owes us)
      + COALESCE((
          SELECT SUM(
            CASE 
              WHEN UPPER(COALESCE(c.currency, 'EGP')) = 'EGP' THEN COALESCE(es.total_revenue_egp, 0)
              ELSE COALESCE(es.total_revenue_foreign, es.total_revenue_egp, 0)
            END 
            - COALESCE(es.discount_amount, 0)
          )
          FROM public.export_shipments es
          WHERE es.customer_id = c.id
            AND es.is_confirmed = true
            AND (es.status IS NULL OR es.status <> 'cancelled')
        ), 0)

      -- 3. Local Invoices (Debits - customer owes us)
      + COALESCE((
          SELECT SUM(COALESCE(inv.total_amount, 0))
          FROM public.invoices inv
          WHERE inv.customer_id = c.id
            AND inv.status IN ('confirmed', 'paid')
        ), 0)

      -- 4. Treasury Transactions (Receiving money from customer is Credit / reduces debt; refund is Debit)
      - COALESCE((SELECT SUM(amount) FROM public.treasury_transactions WHERE customer_id = c.id AND type IN ('deposit', 'receive', 'income') AND (status = 'confirmed' OR status IS NULL)), 0)
      + COALESCE((SELECT SUM(amount) FROM public.treasury_transactions WHERE customer_id = c.id AND type IN ('expense', 'withdrawal', 'customer_refund') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 5. Bank Transactions (Deposit from customer is Credit; withdrawal/refund is Debit)
      - COALESCE((SELECT SUM(amount) FROM public.bank_account_transactions WHERE entity_type = 'customer' AND entity_id = c.id::TEXT AND type IN ('deposit', 'receive', 'income') AND (status = 'confirmed' OR status IS NULL)), 0)
      + COALESCE((SELECT SUM(amount) FROM public.bank_account_transactions WHERE entity_type = 'customer' AND entity_id = c.id::TEXT AND type IN ('withdraw', 'withdrawal', 'expense') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 6. Cheques (Incoming cheques from customer are Credit / reduces debt; outgoing refund cheques are Debit)
      - COALESCE((SELECT SUM(amount) FROM public.cheques WHERE (counterparty_type = 'customer' AND counterparty_id = c.id) AND type = 'incoming' AND status IN ('cleared', 'collected', 'pending')), 0)
      + COALESCE((SELECT SUM(amount) FROM public.cheques WHERE (counterparty_type = 'customer' AND counterparty_id = c.id) AND type = 'outgoing' AND status IN ('cleared', 'collected', 'pending')), 0)

      -- 7. Direct / Manual Journal Entries specifically for this customer
      -- MUST EXCLUDE 'opening_balance' because initial_balance is already included in step 1!
      -- Also excludes automated entries for shipments, invoices, treasury, bank, and cheques.
      + COALESCE((
          SELECT SUM(ale.debit - ale.credit)
          FROM public.account_ledger_entries ale
          JOIN public.journal_entries je ON je.id = ale.journal_entry_id
          WHERE ale.account_id = c.account_id
            AND (je.source_id = 'customers_' || c.id::text OR je.source_id = c.id::text)
            AND je.source_type NOT IN (
                'opening_balance',
                'customer_opening_balance',
                'export_shipment',
                'invoice',
                'sales_invoice',
                'treasury_transaction',
                'treasury_deposit',
                'treasury_receive',
                'treasury_expense',
                'bank_transaction',
                'bank_deposit',
                'bank_withdrawal',
                'cheque_receipt',
                'cheque_issuance',
                'cheque_deposit',
                'cheque_clearance'
            )
        ), 0)
    ) AS true_balance
  FROM public.customers c;
$func$;

GRANT EXECUTE ON FUNCTION public.get_customer_true_balances() TO authenticated, anon, service_role;
