-- Migration 20260728160000: Fix supplier statement duplicate entries
--
-- PROBLEM:
--   rpc_confirm_purchase inserts into ledger_entries (purchase credit + payment debit)
--   AND into treasury_transactions (payment debit).
--   The supplier statement cubit reads from purchase_invoices, ledger_entries, AND treasury_transactions.
--   This causes EVERY purchase + payment to appear TWICE.
--
-- FIX:
--   1. Remove the purchase credit ledger_entries INSERT (line 208-216 in 150000 migration)
--      -- cubit already shows purchases from purchase_invoices table.
--   2. Remove the treasury payment debit ledger_entries INSERT (line 370-378)
--      -- cubit already shows treasury payments from treasury_transactions table.
--   3. Keep the bank payment debit ledger_entries INSERT (line 286-294)
--      -- cubit does NOT query bank_account_transactions, so ledger_entries is the only source.
--   4. Clean up existing duplicate ledger_entries for confirmed purchases.

DROP FUNCTION IF EXISTS rpc_confirm_purchase(TEXT, UUID);

CREATE OR REPLACE FUNCTION rpc_confirm_purchase(
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
  v_item RECORD;
  v_batch_number TEXT;
  v_date_str TEXT;
  v_seq INT := 0;
  v_station_product_name TEXT;
  v_cur_qty NUMERIC;
  v_cur_price NUMERIC;
  v_new_qty NUMERIC;
  v_new_price NUMERIC;
  v_total_egp NUMERIC := 0;
  v_item_egp NUMERIC;
  v_inventory_account_id INTEGER;
  v_supplier_account_id INTEGER;
  v_account_group RECORD;
  v_paid_amount NUMERIC;
  v_treasury_id TEXT;
  v_bank_account_id INTEGER;
  v_source_type TEXT;
  v_cash_account_id INTEGER;
  v_treasury_name TEXT;
  v_bank_name TEXT;
  v_treasury_balance_id INTEGER;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_payment_number TEXT;
  v_inv_currency TEXT;
  v_batches_created INT := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  IF v_purchase.status = 'confirmed' THEN
    RAISE EXCEPTION 'الفاتورة مؤكدة بالفعل';
  END IF;

  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');
  v_date_str := COALESCE(to_char(v_purchase.invoice_date, 'YYYYMMDD'), to_char(now(), 'YYYYMMDD'));

  SELECT id INTO v_supplier_account_id FROM accounts WHERE account_code = '2000' LIMIT 1;
  IF v_supplier_account_id IS NULL THEN
    RAISE EXCEPTION 'حساب الموردين (2000) غير موجود في شجرة الحسابات';
  END IF;

  FOR v_item IN
    SELECT pii.*, rm.code AS rm_code, rm.name AS rm_name, rm.unit AS rm_unit,
           rmc.name AS category_name
    FROM purchase_invoice_items pii
    LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
    LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id
    WHERE pii.invoice_id::TEXT = p_purchase_id
  LOOP
    v_seq := v_seq + 1;
    v_batch_number := 'B-' || v_date_str || '-' || v_purchase.id::TEXT || '-' || lpad(v_seq::TEXT, 4, '0');

    INSERT INTO stock_batches (
      batch_number, product_id, supplier_id, supplier_name, purchase_invoice_id,
      quantity, remaining_quantity, purchase_cost, average_cost,
      exchange_rate, currency, status, user_id
    ) VALUES (
      v_batch_number,
      v_item.raw_material_id,
      v_purchase.supplier_id,
      (SELECT name FROM suppliers WHERE id = v_purchase.supplier_id),
      v_purchase.id,
      v_item.quantity,
      v_item.quantity,
      v_item.unit_cost,
      v_item.unit_cost,
      COALESCE(v_item.exchange_rate, 1.0),
      v_inv_currency,
      'active',
      p_user_id
    );
    v_batches_created := v_batches_created + 1;

    IF v_item.raw_material_id IS NOT NULL THEN
      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price
      FROM raw_materials WHERE id = v_item.raw_material_id;

      IF FOUND THEN
        v_cur_qty := COALESCE(v_cur_qty, 0);
        v_cur_price := COALESCE(v_cur_price, 0);
        v_new_qty := v_cur_qty + v_item.quantity;
        IF v_new_qty > 0 THEN
          v_new_price := ((v_cur_qty * v_cur_price) + (v_item.quantity * v_item.unit_cost)) / v_new_qty;
        ELSE
          v_new_price := v_item.unit_cost;
        END IF;
        UPDATE raw_materials
        SET quantity = v_new_qty, default_purchase_price = v_new_price, updated_at = now()
        WHERE id = v_item.raw_material_id;
      END IF;
    END IF;

    IF v_item.raw_material_id IS NOT NULL THEN
      DECLARE
        v_station_id BIGINT;
      BEGIN
        v_station_id := v_item.station_id;

        IF v_station_id IS NULL THEN
          SELECT spb.station_id INTO v_station_id
          FROM station_product_batches spb
          WHERE spb.product_code = COALESCE(v_item.rm_code, '') AND spb.source_type = 'purchase'
          LIMIT 1;
        END IF;

        IF v_station_id IS NULL THEN
          SELECT sp.id INTO v_station_id
          FROM station_products sp
          WHERE sp.product_code = COALESCE(v_item.rm_code, '') LIMIT 1;
        END IF;

        IF v_station_id IS NOT NULL THEN
          v_station_product_name := COALESCE(v_item.rm_name, '') || ' (مادة تعبئة)';
          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), v_item.quantity::INT);

          INSERT INTO station_product_batches (
            station_id, product_name, product_code, quantity, remaining_quantity,
            unit_cost, currency, exchange_rate, source_type, source_date,
            supplier_name, purchase_invoice_id
          ) VALUES (
            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),
            v_item.quantity, v_item.quantity,
            v_item.unit_cost, v_inv_currency, COALESCE(v_item.exchange_rate, 1.0),
            'purchase', now(),
            (SELECT name FROM suppliers WHERE id = v_purchase.supplier_id),
            v_purchase.id
          );
        END IF;
      END;
    END IF;

    v_item_egp := v_item.quantity * v_item.unit_cost * COALESCE(NULLIF(v_item.exchange_rate, 0), 1.0);
    v_total_egp := v_total_egp + v_item_egp;
  END LOOP;

  IF v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_remaining NUMERIC;
    BEGIN
      v_remaining := COALESCE(v_purchase.total_amount, 0) - COALESCE(v_purchase.paid_amount, 0);
      IF v_remaining > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  IF v_total_egp > 0 THEN
    FOR v_account_group IN
      SELECT
        CASE
          WHEN rmc.name = 'مواد تعبئة' THEN '1040'
          ELSE '1030'
        END AS account_code,
        SUM(pii.quantity * pii.unit_cost * COALESCE(NULLIF(pii.exchange_rate, 0), 1.0)) AS total_egp
      FROM purchase_invoice_items pii
      LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
      LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id
      WHERE pii.invoice_id::TEXT = p_purchase_id
      GROUP BY CASE WHEN rmc.name = 'مواد تعبئة' THEN '1040' ELSE '1030' END
    LOOP
      SELECT id INTO v_inventory_account_id
      FROM accounts WHERE account_code = v_account_group.account_code LIMIT 1;

      IF v_inventory_account_id IS NULL THEN
        RAISE EXCEPTION 'حساب المخزون (%) غير موجود في شجرة الحسابات', v_account_group.account_code;
      END IF;

      PERFORM create_balanced_entry(
        p_debit_account_id := v_inventory_account_id,
        p_credit_account_id := v_supplier_account_id,
        p_amount := v_account_group.total_egp,
        p_description := 'مشتريات رقم ' || COALESCE(v_purchase.invoice_number, ''),
        p_transaction_date := v_purchase.invoice_date,
        p_reference_type := 'purchase',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := v_purchase.id
      );
    END LOOP;
  END IF;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_treasury_id := v_purchase.payment_treasury_id::TEXT;
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');

  IF v_paid_amount > 0 AND v_purchase.supplier_id IS NOT NULL THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1010' LIMIT 1;
      IF v_cash_account_id IS NULL THEN
        RAISE EXCEPTION 'حساب البنك (1010) غير موجود في شجرة الحسابات.';
      END IF;

      SELECT balance INTO v_balance_before FROM bank_accounts WHERE id = v_bank_account_id;

      UPDATE bank_accounts
      SET balance = balance - v_paid_amount, updated_at = now()
      WHERE id = v_bank_account_id AND currency = v_inv_currency;

      v_balance_after := COALESCE(v_balance_before, 0) - v_paid_amount;

      SELECT name INTO v_bank_name FROM bank_accounts WHERE id = v_bank_account_id;

      INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, created_at
      ) VALUES (
        v_bank_account_id, 'withdrawal', v_paid_amount,
        COALESCE(v_balance_before, 0), v_balance_after,
        'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
        p_user_id, now()
      );

      -- Bank payments: ledger_entries is the ONLY source (cubit doesn't query bank_account_transactions)
      INSERT INTO ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, description, created_by, created_at
      ) VALUES (
        'supplier', v_purchase.supplier_id::TEXT, 'debit', v_paid_amount, v_inv_currency,
        'purchase_payment',
        'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_bank_name, ''),
        p_user_id, now()
      );

      PERFORM create_balanced_entry(
        p_debit_account_id := v_supplier_account_id,
        p_credit_account_id := v_cash_account_id,
        p_amount := v_paid_amount,
        p_description := 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_bank_name, ''),
        p_transaction_date := v_purchase.invoice_date,
        p_reference_type := 'purchase_payment',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := v_purchase.id
      );

      BEGIN
        v_payment_number := 'PAY-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(nextval('entry_number_seq')::TEXT, 4, '0');
        INSERT INTO cash_payments (
          payment_number, supplier_id, amount, payment_method,
          notes, payment_date, created_by, created_at, updated_at
        ) VALUES (
          v_payment_number, v_purchase.supplier_id, v_paid_amount, 'bank',
          'دفعة من ' || COALESCE(v_bank_name, 'البنك') || ' - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          v_purchase.invoice_date, p_user_id, now(), now()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'cash_payments insert failed: %', SQLERRM;
      END;

    ELSIF v_source_type = 'treasury' AND v_treasury_id IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1000' LIMIT 1;
      IF v_cash_account_id IS NULL THEN
        RAISE EXCEPTION 'حساب الصندوق (1000) غير موجود في شجرة الحسابات.';
      END IF;

      SELECT id, balance INTO v_treasury_balance_id, v_balance_before
      FROM treasury_balances
      WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency LIMIT 1;

      IF v_treasury_balance_id IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)
        VALUES (v_treasury_id::INTEGER, v_inv_currency, 0, now(), now())
        RETURNING id, balance INTO v_treasury_balance_id, v_balance_before;
      END IF;

      UPDATE treasury_balances
      SET balance = balance - v_paid_amount
      WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency;

      SELECT balance INTO v_balance_after
      FROM treasury_balances
      WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency;

      SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_treasury_id::INTEGER;

      INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after,
        description, supplier_id, created_by, created_at
      ) VALUES (
        v_treasury_id::INTEGER, 'expense', v_inv_currency, v_paid_amount,
        COALESCE(v_balance_before, 0), COALESCE(v_balance_after, 0),
        'دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, ''),
        v_purchase.supplier_id, p_user_id, now()
      );

      -- REMOVED: ledger_entries INSERT for treasury payments
      -- The supplier statement cubit already reads from treasury_transactions.
      -- Having both caused every payment to appear TWICE.

      PERFORM create_balanced_entry(
        p_debit_account_id := v_supplier_account_id,
        p_credit_account_id := v_cash_account_id,
        p_amount := v_paid_amount,
        p_description := 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, ''),
        p_transaction_date := v_purchase.invoice_date,
        p_reference_type := 'purchase_payment',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := v_purchase.id
      );

      BEGIN
        v_payment_number := 'PAY-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(nextval('entry_number_seq')::TEXT, 4, '0');
        INSERT INTO cash_payments (
          payment_number, supplier_id, amount, payment_method,
          notes, payment_date, created_by, created_at, updated_at
        ) VALUES (
          v_payment_number, v_purchase.supplier_id, v_paid_amount, 'cash',
          'دفعة من ' || COALESCE(v_treasury_name, 'الخزينة') || ' - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          v_purchase.invoice_date, p_user_id, now(), now()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'cash_payments insert failed: %', SQLERRM;
      END;
    END IF;
  END IF;

  UPDATE purchase_invoices
  SET status = 'confirmed', updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', p_purchase_id,
    'batches_created', v_batches_created,
    'paid_amount', v_paid_amount,
    'remaining', COALESCE(v_purchase.total_amount, 0) - v_paid_amount,
    'source_type', COALESCE(v_source_type, 'treasury'),
    'treasury_name', COALESCE(v_treasury_name, ''),
    'bank_name', COALESCE(v_bank_name, '')
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تأكيد المشتريات: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_confirm_purchase(TEXT, UUID) TO authenticated;

-- Clean up existing duplicate ledger_entries for confirmed purchases
-- Remove ledger_entries with reference_type 'purchase' or 'purchase_payment'
-- that have a matching purchase_invoices row (the cubit already shows those).
DELETE FROM ledger_entries le
USING purchase_invoices pi
WHERE le.entity_type = 'supplier'
  AND le.entity_id = pi.supplier_id::TEXT
  AND le.reference_type IN ('purchase', 'purchase_payment')
  AND pi.status = 'confirmed'
  AND pi.id::TEXT = SUBSTRING(le.description FROM 'رقم\s+(.+?)(?:\s+-|$)');

-- Also clean up any orphaned duplicates: ledger_entries where reference_type='purchase'
-- and there's a confirmed purchase_invoices with matching supplier and similar date
DELETE FROM ledger_entries le
WHERE le.entity_type = 'supplier'
  AND le.reference_type = 'purchase'
  AND le.entry_type = 'credit'
  AND EXISTS (
    SELECT 1 FROM purchase_invoices pi
    WHERE pi.supplier_id::TEXT = le.entity_id
      AND pi.status = 'confirmed'
      AND pi.total_amount = le.amount
      AND pi.created_at::DATE = le.created_at::DATE
  );

-- Clean up duplicate payment ledger_entries where a matching treasury_transactions exists
DELETE FROM ledger_entries le
WHERE le.entity_type = 'supplier'
  AND le.reference_type = 'purchase_payment'
  AND le.entry_type = 'debit'
  AND EXISTS (
    SELECT 1 FROM treasury_transactions tt
    WHERE tt.supplier_id::TEXT = le.entity_id
      AND tt.amount = le.amount
      AND tt.type = 'expense'
      AND tt.created_at::DATE = le.created_at::DATE
  );

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
