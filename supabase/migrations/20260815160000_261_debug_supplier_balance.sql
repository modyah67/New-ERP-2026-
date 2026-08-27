CREATE OR REPLACE FUNCTION public.debug_supplier_balance(p_supplier_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result json;
  v_supplier record;
  v_initial numeric;
  v_purchases numeric;
  v_treasury_in numeric;
  v_treasury_out numeric;
  v_bank_in numeric;
  v_bank_out numeric;
  v_cheques_in numeric;
  v_cheques_out numeric;
  v_legacy_ledger numeric;
  v_enterprise_ledger numeric;
BEGIN
  SELECT * INTO v_supplier FROM suppliers WHERE id = p_supplier_id;
  
  -- 1. Initial Balance
  v_initial := CASE WHEN v_supplier.initial_balance_direction = 'CREDIT' THEN COALESCE(v_supplier.initial_balance, 0) ELSE -COALESCE(v_supplier.initial_balance, 0) END;
  
  -- 2. Purchases 
  v_purchases := COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = v_supplier.id AND status = 'confirmed'), 0);
  
  -- 3. Treasury Transactions
  v_treasury_in := COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = v_supplier.id AND type IN ('deposit', 'receive', 'income', 'supplier_refund')), 0);
  v_treasury_out := COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = v_supplier.id AND type IN ('expense', 'supplier_payment')), 0);
  
  -- 4. Bank Transactions
  v_bank_in := COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = v_supplier.id::TEXT AND type IN ('deposit', 'receive', 'income', 'supplier_refund')), 0);
  v_bank_out := COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = v_supplier.id::TEXT AND type IN ('withdraw', 'expense', 'supplier_payment')), 0);
  
  -- 5. Cheques
  v_cheques_in := COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = v_supplier.id AND type = 'incoming' AND status IN ('cleared', 'collected')), 0);
  v_cheques_out := COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = v_supplier.id AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0);
  
  SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END)
  INTO v_legacy_ledger
  FROM ledger_entries le
  WHERE le.entity_type = 'supplier' 
    AND le.entity_id IN (v_supplier.id::text, v_supplier.code)
    AND NOT (
        le.reference_type IN ('supplier_payment', 'treasury_deposit', 'treasury_withdrawal', 'treasury_transaction', 'cash_payment', 'receive', 'deposit', 'supplier_refund')
        AND EXISTS (SELECT 1 FROM treasury_transactions tt WHERE tt.id::TEXT = le.reference_id::TEXT)
    )
    AND NOT (
        le.reference_type IN ('bank_payment', 'bank_receipt', 'bank_transaction', 'cheque', 'supplier_payment', 'cheque_payment', 'receive', 'deposit', 'supplier_refund')
        AND EXISTS (SELECT 1 FROM bank_account_transactions bt WHERE bt.id::TEXT = le.reference_id::TEXT)
    )
    AND le.reference_type NOT IN ('lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return');
    
  SELECT SUM(ale.credit - ale.debit)
  INTO v_enterprise_ledger
  FROM account_ledger_entries ale
  JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE ale.account_id = v_supplier.account_id
    AND je.source_type IN (
      'lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return', 'manual'
    );

  v_result := json_build_object(
    'initial', v_initial,
    'purchases', v_purchases,
    'treasury_in', v_treasury_in,
    'treasury_out', v_treasury_out,
    'bank_in', v_bank_in,
    'bank_out', v_bank_out,
    'cheques_in', v_cheques_in,
    'cheques_out', v_cheques_out,
    'legacy_ledger', COALESCE(v_legacy_ledger, 0),
    'enterprise_ledger', COALESCE(v_enterprise_ledger, 0),
    'true_balance', (SELECT true_balance FROM get_supplier_true_balances() WHERE supplier_id = p_supplier_id)
  );
  
  RETURN v_result;
END;
$$;
