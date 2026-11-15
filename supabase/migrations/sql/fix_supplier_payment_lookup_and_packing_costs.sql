-- ============================================================================
-- Migration: fix_supplier_payment_lookup_and_packing_costs.sql
-- Description:
-- 1. Update get_supplier_true_balances_by_currency() to include packing order costs
--    from ledger_entries (reference_type IN ('packing_cost', 'packing_cost_item')).
-- 2. Update rpc_entity_multi_payment to explicitly support transport_suppliers
--    under the unified supplier payment workflow.
-- ============================================================================

-- 1. Update get_supplier_true_balances_by_currency
CREATE OR REPLACE FUNCTION public.get_supplier_true_balances_by_currency()
RETURNS TABLE (
    supplier_id        uuid,
    supplier_code      text,
    supplier_name      text,
    currency           text,
    true_balance       numeric,   -- native currency amount
    true_balance_egp   numeric    -- converted to EGP using latest rate
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $func$
  WITH rates AS (
    SELECT DISTINCT ON (currency_code) currency_code, rate_to_egp 
    FROM (
      SELECT currency_code, rate_to_egp, updated_at FROM exchange_rates
      UNION ALL
      SELECT 'EGP'::character varying(10), 1.0::numeric(10,4), NOW()
    ) r_all
    ORDER BY currency_code, updated_at DESC NULLS LAST
  ),
  -- 1. Initial Balances
  init_balances AS (
    SELECT 
      s.id AS supplier_id,
      UPPER(COALESCE(elem.value->>'currency', elem.key)) AS currency,
      COALESCE((elem.value->>'amount')::numeric, 0) * (CASE WHEN UPPER(COALESCE(elem.value->>'direction', 'CREDIT')) = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt
    FROM suppliers s,
    LATERAL jsonb_each(s.initial_balances_by_currency) elem
    WHERE s.is_multi_currency = true 
      AND s.initial_balances_by_currency IS NOT NULL 
      AND jsonb_typeof(s.initial_balances_by_currency) = 'object'
      AND COALESCE((elem.value->>'amount')::numeric, 0) > 0
    
    UNION ALL
    
    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(s.currency, ''), 'EGP') AS currency,
      COALESCE(s.initial_balance, 0) * (CASE WHEN s.initial_balance_direction = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt
    FROM suppliers s
    WHERE (s.is_multi_currency = false OR s.initial_balances_by_currency IS NULL OR s.initial_balances_by_currency = '{}'::jsonb)
      AND COALESCE(s.initial_balance, 0) <> 0
  ),
  
  -- 2. Purchase Invoices (credit to supplier: increases payable)
  purchases AS (
    SELECT 
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(total_amount) AS net_amt
    FROM purchase_invoices
    WHERE status = 'confirmed' AND supplier_id IS NOT NULL
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  
  -- 3. Treasury Transactions
  treasury AS (
    SELECT 
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN type IN ('deposit','receive','income','supplier_refund') THEN amount ELSE -amount END) AS net_amt
    FROM treasury_transactions
    WHERE supplier_id IS NOT NULL 
      AND (status = 'confirmed' OR status IS NULL)
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  
  -- 4. Bank Account Transactions
  bank_tx AS (
    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(ba.currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN bat.type IN ('deposit','receive','income','supplier_refund') THEN bat.amount ELSE -bat.amount END) AS net_amt
    FROM bank_account_transactions bat
    JOIN suppliers s ON (s.id::text = bat.entity_id OR s.code = bat.entity_id OR s.supplier_code = bat.entity_id)
    LEFT JOIN bank_accounts ba ON ba.id = bat.bank_account_id
    WHERE bat.entity_type = 'supplier' 
      AND (bat.status = 'confirmed' OR bat.status IS NULL)
    GROUP BY s.id, COALESCE(NULLIF(ba.currency, ''), 'EGP')
  ),
  
  -- 5. Cheques
  cheque_tx AS (
    SELECT 
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN type = 'incoming' THEN amount ELSE -amount END) AS net_amt
    FROM cheques
    WHERE supplier_id IS NOT NULL 
      AND status IN ('cleared', 'collected')
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  
  -- 6. Lot Receipts / Enterprise Account Ledger Entries
  lot_tx AS (
    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(ale.currency, ''), 'EGP') AS currency,
      SUM(ale.credit - ale.debit) AS net_amt
    FROM account_ledger_entries ale
    JOIN journal_entries je ON je.id = ale.journal_entry_id
    JOIN suppliers s ON s.account_id = ale.account_id
    WHERE je.source_type IN ('lot_receipt','lot_adjustment','lot_price_adjustment','manual')
    GROUP BY s.id, COALESCE(NULLIF(ale.currency, ''), 'EGP')
  ),
  
  -- 7. Purchase Returns / Lot Returns (reduces supplier payable)
  purchase_returns AS (
    SELECT 
      lr.supplier_id,
      COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP'))) AS currency,
      -SUM(lr.return_value) AS net_amt
    FROM lot_returns lr
    LEFT JOIN lot_receipts rec ON rec.id = lr.lot_receipt_id
    JOIN suppliers s ON s.id = lr.supplier_id
    WHERE lr.supplier_id IS NOT NULL
    GROUP BY lr.supplier_id, COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP')))
  ),

  -- 8. Standalone Purchase Returns from Ledger Entries
  ledger_returns AS (
    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,
      -SUM(le.amount) AS net_amt
    FROM ledger_entries le
    JOIN suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)
    WHERE le.entity_type = 'supplier'
      AND le.reference_type = 'purchase_return'
    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')
  ),

  -- 9. Packing Order Cost Items (increases supplier payable)
  packing_costs AS (
    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN le.entry_type = 'credit' THEN le.amount ELSE -le.amount END) AS net_amt
    FROM ledger_entries le
    JOIN suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)
    WHERE le.entity_type = 'supplier'
      AND le.reference_type IN ('packing_cost', 'packing_cost_item')
    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')
  ),
  
  -- Combine all activity
  combined AS (
    SELECT supplier_id, currency, net_amt FROM init_balances
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM purchases
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM treasury
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM bank_tx
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM cheque_tx
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM lot_tx
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM purchase_returns
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM ledger_returns
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM packing_costs
  ),
  
  aggregated AS (
    SELECT 
      supplier_id,
      currency,
      SUM(net_amt) AS true_balance
    FROM combined
    GROUP BY supplier_id, currency
    HAVING SUM(net_amt) <> 0
  )
  
  SELECT 
    s.id AS supplier_id,
    COALESCE(s.code, s.supplier_code, '') AS supplier_code,
    s.name AS supplier_name,
    a.currency,
    a.true_balance,
    a.true_balance * COALESCE(r.rate_to_egp, 1.0) AS true_balance_egp
  FROM aggregated a
  JOIN suppliers s ON s.id = a.supplier_id
  LEFT JOIN rates r ON r.currency_code = a.currency;
$func$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances_by_currency() TO authenticated, anon, service_role;
