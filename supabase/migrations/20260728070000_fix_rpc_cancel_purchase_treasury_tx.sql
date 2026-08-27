CREATE OR REPLACE FUNCTION rpc_cancel_purchase(
  p_purchase_id TEXT,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purchase RECORD;
  v_batch RECORD;
  v_item RECORD;
  v_total_egp NUMERIC := 0;
  v_inventory_account_id INTEGER;
  v_supplier_account_id INTEGER;
  v_category_name TEXT;
  v_remaining NUMERIC;
  v_paid_amount NUMERIC;
  v_cash_account_id INTEGER;
  v_treasury_id TEXT;
  v_bank_account_id INTEGER;
  v_source_type TEXT;
  v_treasury_balance_id INTEGER;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_old_treasury_tx RECORD;
  v_supplier_uuid UUID;
  v_inv_currency TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  IF v_purchase.status != 'confirmed' THEN
    RAISE EXCEPTION 'يمكن إلغاء الفواتير المؤكدة فقط. الحالة الحالية: %', v_purchase.status;
  END IF;

  v_supplier_uuid := _safe_uuid(v_purchase.supplier_id::TEXT);
  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_treasury_id := v_purchase.payment_treasury_id::TEXT;
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');

  FOR v_batch IN
    SELECT sb.id, sb.batch_number, sb.quantity, sb.remaining_quantity,
           rm.name AS raw_material_name
    FROM stock_batches sb
    LEFT JOIN raw_materials rm ON rm.id = sb.product_id
    WHERE _safe_uuid(sb.purchase_invoice_id::TEXT) = _safe_uuid(v_purchase.id::TEXT)
  LOOP
    UPDATE raw_materials
    SET quantity = GREATEST(COALESCE(quantity, 0) - v_batch.remaining_quantity, 0),
        updated_at = now()
    WHERE name = v_batch.raw_material_name;

    DELETE FROM stock_batches WHERE id = v_batch.id;
  END LOOP;

  IF v_purchase.supplier_id IS NOT NULL THEN
    v_remaining := COALESCE(v_purchase.total_amount, 0) - COALESCE(v_purchase.paid_amount, 0);
    IF v_remaining > 0 THEN
      UPDATE suppliers
      SET outstanding_balance = GREATEST(COALESCE(outstanding_balance, 0) - v_remaining, 0)
      WHERE id = v_purchase.supplier_id;
    END IF;
  END IF;

  IF v_total_egp > 0 THEN
    SELECT id INTO v_supplier_account_id FROM accounts WHERE account_code = '2000' LIMIT 1;
    SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1030' LIMIT 1;

    IF v_inventory_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
      PERFORM create_balanced_entry(
        p_debit_account_id := v_supplier_account_id,
        p_credit_account_id := v_inventory_account_id,
        p_amount := v_total_egp,
        p_description := 'إلغاء مشتريات رقم ' || COALESCE(v_purchase.invoice_number, ''),
        p_transaction_date := now()::DATE,
        p_reference_type := 'purchase_cancel',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := NULL
      );
    END IF;
  END IF;

  IF v_paid_amount > 0 AND v_purchase.supplier_id IS NOT NULL THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1010' LIMIT 1;
      UPDATE bank_accounts
      SET balance = balance + v_paid_amount, updated_at = now()
      WHERE id = v_bank_account_id AND currency = v_inv_currency;

      IF v_cash_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
        PERFORM create_balanced_entry(
          p_debit_account_id := v_cash_account_id,
          p_credit_account_id := v_supplier_account_id,
          p_amount := v_paid_amount,
          p_description := 'إلغاء دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          p_transaction_date := now()::DATE,
          p_reference_type := 'purchase_cancel_payment',
          p_reference_id := NULL,
          p_currency_snapshot := NULL,
          p_purchase_invoice_ref := NULL
        );
      END IF;

    ELSIF v_source_type = 'treasury' AND v_treasury_id IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1000' LIMIT 1;

      SELECT id, balance INTO v_treasury_balance_id, v_balance_before
      FROM treasury_balances
      WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency LIMIT 1;

      IF v_treasury_balance_id IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)
        VALUES (v_treasury_id::INTEGER, v_inv_currency, 0, now(), now())
        RETURNING id, balance INTO v_treasury_balance_id, v_balance_before;
      END IF;

      UPDATE treasury_balances
      SET balance = balance + v_paid_amount
      WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency;

      SELECT balance INTO v_balance_after
      FROM treasury_balances
      WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency;

      SELECT * INTO v_old_treasury_tx
      FROM treasury_transactions
      WHERE type IN ('expense', 'supplier_payment')
        AND supplier_id = v_supplier_uuid
        AND description LIKE '%' || COALESCE(v_purchase.invoice_number, '') || '%'
      ORDER BY created_at DESC LIMIT 1;

      IF v_old_treasury_tx IS NOT NULL THEN
        UPDATE treasury_transactions
        SET type = 'deposit',
            description = 'إلغاء دفعة نقدية - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
            balance_before = v_balance_before,
            balance_after = v_balance_after,
            currency = v_inv_currency
        WHERE id = v_old_treasury_tx.id;
      ELSE
        INSERT INTO treasury_transactions (
          treasury_id, type, currency, amount,
          balance_before, balance_after,
          description, supplier_id, created_by, created_at
        ) VALUES (
          v_treasury_id::INTEGER, 'deposit', v_inv_currency, v_paid_amount,
          v_balance_before, v_balance_after,
          'إلغاء دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          v_supplier_uuid, p_user_id, now()
        );
      END IF;

      IF v_cash_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
        PERFORM create_balanced_entry(
          p_debit_account_id := v_cash_account_id,
          p_credit_account_id := v_supplier_account_id,
          p_amount := v_paid_amount,
          p_description := 'إلغاء دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          p_transaction_date := now()::DATE,
          p_reference_type := 'purchase_cancel_payment',
          p_reference_id := NULL,
          p_currency_snapshot := NULL,
          p_purchase_invoice_ref := NULL
        );
      END IF;
    END IF;
  END IF;

  UPDATE purchase_invoices
  SET status = 'cancelled', updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', p_purchase_id,
    'paid_amount_reversed', v_paid_amount
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء إلغاء المشتريات: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_cancel_purchase(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
