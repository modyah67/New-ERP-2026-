-- Migration 257: Fix lot return currency in ledger_entries and get_supplier_true_balances

BEGIN;

-- 1. Fix existing lot_returns in ledger_entries to use original currency instead of EGP
UPDATE ledger_entries le
SET amount = (
  SELECT ROUND((rt.returned_quantity * (lr.total_fruit_cost / NULLIF(lr.gross_weight_kg, 0)))::NUMERIC, 2)
  FROM lot_returns rt
  JOIN lot_receipts lr ON lr.id = rt.lot_receipt_id
  WHERE rt.id::TEXT = le.reference_text
)
WHERE le.reference_type = 'lot_return';

-- 2. Update rpc_process_lot_return to insert original currency into ledger_entries
CREATE OR REPLACE FUNCTION public.rpc_process_lot_return(
  p_lot_id BIGINT,
  p_return_quantity NUMERIC,
  p_notes TEXT DEFAULT NULL,
  p_station_id BIGINT DEFAULT NULL,
  p_batch_id BIGINT DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_product_name TEXT;
  v_unit_cost NUMERIC := 0;
  v_return_value NUMERIC := 0;
  v_remaining_in_batches NUMERIC := 0;
  v_batch RECORD;
  v_qty_to_deduct NUMERIC;
  v_desc TEXT;
  v_target_station BIGINT;
  v_return_id BIGINT;
  v_company_id UUID;
  v_supplier_leaf_account_id BIGINT;
  v_inventory_account_id BIGINT;
  v_return_value_egp NUMERIC;
  v_je_id BIGINT;
BEGIN
  IF p_return_quantity <= 0 THEN
    RAISE EXCEPTION 'الكمية المرتجعة يجب أن تكون أكبر من الصفر';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول لإتمام المرتجع';
  END IF;

  SELECT lr.*, ft.name AS fruit_type_name
  INTO v_lot
  FROM lot_receipts lr
  LEFT JOIN fruit_types ft ON ft.id = lr.fruit_type_id
  WHERE lr.id = p_lot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل شراء المحصول غير موجود';
  END IF;

  v_product_name := COALESCE(
    NULLIF(v_lot.product_name, ''),
    NULLIF(v_lot.fruit_type_name, ''),
    'محصول'
  );

  v_target_station := COALESCE(p_station_id, v_lot.station_id);

  v_unit_cost := COALESCE(v_lot.total_fruit_cost / NULLIF(v_lot.gross_weight_kg, 0), 0);
  v_return_value := p_return_quantity * v_unit_cost;

  -- 1. Deduct from station inventory / batches
  IF p_batch_id IS NOT NULL THEN
    SELECT remaining_quantity INTO v_remaining_in_batches
    FROM station_product_batches
    WHERE id = p_batch_id
      AND product_code = v_lot.lot_number
      AND station_id = v_target_station;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'الدفعة غير موجودة';
    END IF;

    IF v_remaining_in_batches < p_return_quantity THEN
      RAISE EXCEPTION 'الكمية المرتجعة (%) أكبر من الكمية المتبقية (%) في الدفعة', p_return_quantity, v_remaining_in_batches;
    END IF;

    UPDATE station_product_batches
    SET remaining_quantity = remaining_quantity - p_return_quantity
    WHERE id = p_batch_id;
  ELSE
    SELECT COALESCE(SUM(remaining_quantity), 0)
    INTO v_remaining_in_batches
    FROM station_product_batches
    WHERE product_code = v_lot.lot_number
      AND station_id = v_target_station;

    IF v_remaining_in_batches < p_return_quantity THEN
      RAISE EXCEPTION 'الكمية المرتجعة (%) أكبر من الكمية المتبقية (%) في المحطة', p_return_quantity, v_remaining_in_batches;
    END IF;

    v_qty_to_deduct := p_return_quantity;

    FOR v_batch IN
      SELECT id, remaining_quantity
      FROM station_product_batches
      WHERE product_code = v_lot.lot_number
        AND station_id = v_target_station
        AND remaining_quantity > 0
      ORDER BY id ASC
      FOR UPDATE
    LOOP
      IF v_qty_to_deduct <= 0 THEN EXIT; END IF;

      IF v_batch.remaining_quantity >= v_qty_to_deduct THEN
        UPDATE station_product_batches
        SET remaining_quantity = remaining_quantity - v_qty_to_deduct
        WHERE id = v_batch.id;
        v_qty_to_deduct := 0;
      ELSE
        v_qty_to_deduct := v_qty_to_deduct - v_batch.remaining_quantity;
        UPDATE station_product_batches
        SET remaining_quantity = 0
        WHERE id = v_batch.id;
      END IF;
    END LOOP;
  END IF;

  UPDATE station_products
  SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
      updated_at = now()
  WHERE station_id = v_target_station
    AND product_name = v_product_name;

  IF NOT FOUND THEN
    UPDATE station_products
    SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
        updated_at = now()
    WHERE station_id = v_target_station
      AND product_name = v_lot.fruit_type_name;
  END IF;

  DELETE FROM station_products
  WHERE station_id = v_target_station
    AND (product_name = v_product_name OR product_name = v_lot.fruit_type_name)
    AND COALESCE(quantity, 0) <= 0;

  -- 2. Insert into lot_returns
  INSERT INTO lot_returns (
    lot_receipt_id, supplier_id, station_id, returned_quantity, return_value, notes, created_by
  ) VALUES (
    v_lot.id, v_lot.supplier_id, v_target_station, p_return_quantity, v_return_value, p_notes, p_user_id
  ) RETURNING id INTO v_return_id;

  -- 3. Update legacy supplier ledger
  IF v_lot.supplier_id IS NOT NULL THEN
    v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_return_value,
        updated_at = now()
    WHERE id = v_lot.supplier_id;

    v_desc := 'مرتجع شراء محصول خام ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT);
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, reference_type, reference_text, description, created_by
    ) VALUES (
      'supplier', v_lot.supplier_id::TEXT, 'debit', v_return_value, 'lot_return', v_return_id::TEXT, v_desc, p_user_id
    );
  END IF;

  -- 4. Post Enterprise Double-Entry Journal Entry
  -- Dr. Supplier Leaf Account (2000s) -> Debit Supplier (decreases liability)
  -- Cr. Inventory Account (1030)       -> Credit Inventory (decreases asset)
  IF v_return_value > 0 THEN
    SELECT a.company_id INTO v_company_id
    FROM accounts a
    WHERE a.account_code = '1030'
    LIMIT 1;

    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- Resolve Inventory leaf account
    SELECT a.id INTO v_inventory_account_id
    FROM accounts a
    WHERE a.account_code = '1030' AND a.company_id = v_company_id
    LIMIT 1;

    IF v_inventory_account_id IS NULL THEN
      SELECT a.id INTO v_inventory_account_id
      FROM accounts a
      WHERE a.account_code = '1030'
      LIMIT 1;
    END IF;

    -- Resolve Supplier leaf account
    v_supplier_leaf_account_id := NULL;
    IF v_lot.supplier_id IS NOT NULL THEN
      SELECT s.account_id INTO v_supplier_leaf_account_id
      FROM suppliers s
      WHERE s.id = v_lot.supplier_id;
    END IF;

    IF v_supplier_leaf_account_id IS NULL THEN
      SELECT a.id INTO v_supplier_leaf_account_id
      FROM accounts a
      WHERE a.account_code = '2000' AND a.company_id = v_company_id
      LIMIT 1;

      IF v_supplier_leaf_account_id IS NULL THEN
        SELECT a.id INTO v_supplier_leaf_account_id
        FROM accounts a
        WHERE a.account_code = '2000'
        LIMIT 1;
      END IF;
    END IF;

    IF v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN
      v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
      v_desc := 'مرتجع شراء محصول خام ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT);

      v_je_id := public.post_journal_entry(
        p_company_id := v_company_id,
        p_entry_date := CURRENT_DATE,
        p_source_type := 'lot_return',
        p_description := v_desc,
        p_created_by := p_user_id,
        p_lines := jsonb_build_array(
          jsonb_build_object(
            'account_id', v_supplier_leaf_account_id,
            'debit', v_return_value,
            'credit', 0,
            'base_debit', v_return_value_egp,
            'base_credit', 0,
            'currency', COALESCE(v_lot.currency, 'EGP'),
            'description', 'تخفيض مستحقات مورد عن مرتجع شراء محصول رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
          ),
          jsonb_build_object(
            'account_id', v_inventory_account_id,
            'debit', 0,
            'credit', v_return_value,
            'base_debit', 0,
            'base_credit', v_return_value_egp,
            'currency', COALESCE(v_lot.currency, 'EGP'),
            'description', 'تخفيض مخزون محصول خام عن مرتجع رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
          )
        )
      );

      UPDATE journal_entries
      SET source_id = v_return_id::TEXT
      WHERE id = v_je_id;

      UPDATE lot_returns
      SET journal_entry_id = v_je_id
      WHERE id = v_return_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'return_id', v_return_id,
    'returned_quantity', p_return_quantity,
    'return_value', v_return_value,
    'unit_cost_used', v_unit_cost,
    'station_id', v_target_station,
    'batch_id', p_batch_id,
    'journal_entry_id', v_je_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- 3. Exclude lot_return from ledger_entries in get_supplier_true_balances to avoid double counting
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
      
      -- 6. Legacy Ledger Entries (Manual journal entries, packing costs, old lot receipts, etc.)
      -- We EXCLUDE entries that are already represented by treasury_transactions or bank_transactions above 
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
      -- Include source types that were migrated to enterprise journals and are no longer in legacy ledger_entries
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
$$;

-- Run backfill to sync `outstanding_balance` field in `suppliers` table
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT * FROM public.get_supplier_true_balances() LOOP
    UPDATE public.suppliers 
    SET outstanding_balance = r.true_balance
    WHERE id = r.supplier_id;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
