-- ==============================================================================
-- Migration: 20260828000004_427_shipping_and_clearing_true_balances.sql
-- Description:
-- 1. Create get_shipping_company_true_balances() RPC to compute true balances
--    dynamically from shipments, treasury, bank, and cheques.
-- 2. Create get_clearing_agent_true_balances() RPC to compute true balances
--    dynamically for customs clearing agents.
-- 3. Sync and backfill shipping_companies.balance and clearing_agents.balance.
-- ==============================================================================

-- ── 1. Shipping Companies True Balances ──
CREATE OR REPLACE FUNCTION public.get_shipping_company_true_balances()
RETURNS TABLE (
  shipping_company_id bigint,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  SELECT
    sc.id,
    (
      -- 1. Initial Balance
      (CASE WHEN sc.initial_balance_direction = 'CREDIT' THEN COALESCE(sc.initial_balance, 0) ELSE -COALESCE(sc.initial_balance, 0) END)
      
      -- 2. Shipment Cost Items (تكاليف الشحن)
      + COALESCE((
          SELECT SUM(sci.total_price / COALESCE(NULLIF(sci.exchange_rate, 0), 1.0))
          FROM public.shipment_cost_items sci
          WHERE (
            (sci.shipping_company_id IS NOT NULL AND sci.shipping_company_id = sc.id)
            OR
            (sci.vendor_type = 'shipping_company' AND sci.vendor_id = sc.id)
          )
        ), 0)
      
      -- 3. Treasury Transactions
      + COALESCE((SELECT SUM(amount) FROM public.treasury_transactions WHERE shipping_company_id = sc.id AND type IN ('deposit', 'receive', 'income') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM public.treasury_transactions WHERE shipping_company_id = sc.id AND type IN ('expense', 'shipping_company_payment', 'payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 4. Bank Transactions
      + COALESCE((SELECT SUM(amount) FROM public.bank_account_transactions WHERE entity_type = 'shipping_company' AND entity_id = sc.id::TEXT AND type IN ('deposit', 'receive', 'income') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM public.bank_account_transactions WHERE entity_type = 'shipping_company' AND entity_id = sc.id::TEXT AND type IN ('withdraw', 'withdrawal', 'expense', 'shipping_company_payment', 'payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 5. Cheques
      + COALESCE((SELECT SUM(amount) FROM public.cheques WHERE (shipping_company_id = sc.id OR (counterparty_type = 'shipping_company' AND counterparty_id = sc.id)) AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
      - COALESCE((SELECT SUM(amount) FROM public.cheques WHERE (shipping_company_id = sc.id OR (counterparty_type = 'shipping_company' AND counterparty_id = sc.id)) AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)

      -- 6. Direct Ledger Entries (excluding ones created for treasury/bank transactions already counted)
      + COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END)
          FROM public.ledger_entries le
          WHERE le.entity_type = 'shipping_company' 
            AND le.entity_id = sc.id::text
            AND le.reference_type NOT IN ('shipment_cost_item', 'expense', 'receive')
            AND NOT (
                le.reference_type IN ('shipping_company_payment', 'treasury_deposit', 'treasury_withdrawal', 'treasury_transaction', 'cash_payment', 'receive', 'deposit')
                AND EXISTS (SELECT 1 FROM public.treasury_transactions tt WHERE tt.id::TEXT = le.reference_id::TEXT)
            )
            AND NOT (
                le.reference_type IN ('bank_payment', 'bank_receipt', 'bank_transaction', 'cheque', 'shipping_company_payment', 'receive', 'deposit')
                AND EXISTS (SELECT 1 FROM public.bank_account_transactions bt WHERE bt.id::TEXT = le.reference_id::TEXT)
            )
      ), 0)
    ) AS true_balance
  FROM public.shipping_companies sc;
$func$;

GRANT EXECUTE ON FUNCTION public.get_shipping_company_true_balances() TO authenticated, anon, service_role;

-- ── 2. Clearing Agents True Balances ──
CREATE OR REPLACE FUNCTION public.get_clearing_agent_true_balances()
RETURNS TABLE (
  clearing_agent_id bigint,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  SELECT
    ca.id,
    (
      -- 1. Initial Balance
      (CASE WHEN ca.initial_balance_direction = 'CREDIT' THEN COALESCE(ca.initial_balance, 0) ELSE -COALESCE(ca.initial_balance, 0) END)
      
      -- 2. Shipment Cost Items (تكاليف التخليص)
      + COALESCE((
          SELECT SUM(sci.total_price / COALESCE(NULLIF(sci.exchange_rate, 0), 1.0))
          FROM public.shipment_cost_items sci
          WHERE (
            (sci.clearing_agent_id IS NOT NULL AND sci.clearing_agent_id = ca.id)
            OR
            (sci.vendor_type = 'clearing_agent' AND sci.vendor_id = ca.id)
          )
        ), 0)
      
      -- 3. Treasury Transactions
      + COALESCE((SELECT SUM(amount) FROM public.treasury_transactions WHERE clearing_agent_id = ca.id AND type IN ('deposit', 'receive', 'income') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM public.treasury_transactions WHERE clearing_agent_id = ca.id AND type IN ('expense', 'clearing_agent_payment', 'payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 4. Bank Transactions
      + COALESCE((SELECT SUM(amount) FROM public.bank_account_transactions WHERE entity_type = 'clearing_agent' AND entity_id = ca.id::TEXT AND type IN ('deposit', 'receive', 'income') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM public.bank_account_transactions WHERE entity_type = 'clearing_agent' AND entity_id = ca.id::TEXT AND type IN ('withdraw', 'withdrawal', 'expense', 'clearing_agent_payment', 'payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 5. Cheques
      + COALESCE((SELECT SUM(amount) FROM public.cheques WHERE (clearing_agent_id = ca.id OR (counterparty_type = 'clearing_agent' AND counterparty_id = ca.id)) AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
      - COALESCE((SELECT SUM(amount) FROM public.cheques WHERE (clearing_agent_id = ca.id OR (counterparty_type = 'clearing_agent' AND counterparty_id = ca.id)) AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)

      -- 6. Direct Ledger Entries (excluding ones created for treasury/bank transactions already counted)
      + COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END)
          FROM public.ledger_entries le
          WHERE le.entity_type = 'clearing_agent' 
            AND le.entity_id = ca.id::text
            AND le.reference_type NOT IN ('shipment_cost_item', 'expense', 'receive')
            AND NOT (
                le.reference_type IN ('clearing_agent_payment', 'treasury_deposit', 'treasury_withdrawal', 'treasury_transaction', 'cash_payment', 'receive', 'deposit')
                AND EXISTS (SELECT 1 FROM public.treasury_transactions tt WHERE tt.id::TEXT = le.reference_id::TEXT)
            )
            AND NOT (
                le.reference_type IN ('bank_payment', 'bank_receipt', 'bank_transaction', 'cheque', 'clearing_agent_payment', 'receive', 'deposit')
                AND EXISTS (SELECT 1 FROM public.bank_account_transactions bt WHERE bt.id::TEXT = le.reference_id::TEXT)
            )
      ), 0)
    ) AS true_balance
  FROM public.clearing_agents ca;
$func$;

GRANT EXECUTE ON FUNCTION public.get_clearing_agent_true_balances() TO authenticated, anon, service_role;

-- ── 3. Sync and Backfill balance columns on both tables ──
UPDATE public.shipping_companies sc
SET balance = COALESCE((SELECT true_balance FROM public.get_shipping_company_true_balances() WHERE shipping_company_id = sc.id), 0);

UPDATE public.clearing_agents ca
SET balance = COALESCE((SELECT true_balance FROM public.get_clearing_agent_true_balances() WHERE clearing_agent_id = ca.id), 0);

NOTIFY pgrst, 'reload schema';
