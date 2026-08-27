-- Migration 159: Fix supplier balance calculation and purchase journal entry accounts

-- 1. Fix get_supplier_true_balances
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
      + COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = s.id AND status = 'confirmed'), 0)
      - COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('expense', 'supplier_payment')), 0)
      + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('income', 'receive', 'supplier_refund')), 0)
      - COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::text AND type = 'withdraw'), 0)
      + COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::text AND type = 'deposit'), 0)
      + COALESCE((SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) FROM ledger_entries WHERE entity_type = 'supplier' AND entity_id = s.id::text), 0)
      - COALESCE((
          SELECT SUM(debit - credit) 
          FROM transactions 
          WHERE supplier_id = s.id AND purchase_id IS NULL
      ), 0)
      - COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)
      + COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
    ) AS true_balance
  FROM suppliers s;
$$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated;

-- 2. Retroactively fix existing purchase journal entries where debit account was Bank (1010) instead of Raw Materials (1030)
DO $$
DECLARE
    v_target_acc_id INTEGER;
    v_company_id UUID;
BEGIN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    
    SELECT id INTO v_target_acc_id FROM accounts WHERE account_code = '1030' AND company_id = v_company_id LIMIT 1;
    IF v_target_acc_id IS NULL THEN
        SELECT id INTO v_target_acc_id FROM accounts WHERE account_code = '1200' AND company_id = v_company_id LIMIT 1;
    END IF;
    
    IF v_target_acc_id IS NOT NULL THEN
        UPDATE account_ledger_entries jel
        SET account_id = v_target_acc_id
        FROM journal_entries je
        WHERE jel.journal_entry_id = je.id
          AND je.source_type IN ('purchase_inventory', 'purchase')
          AND jel.debit > 0
          AND jel.account_id IN (SELECT id FROM accounts WHERE account_code = '1010' AND company_id = v_company_id);
    END IF;
END $$;

-- 3. Restore rpc_confirm_purchase with full fixes
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
  v_total_foreign NUMERIC := 0;
  v_total_egp NUMERIC := 0;
  v_exchange_rate NUMERIC := 1.0;
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
  v_treasury_balance_id BIGINT;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_payment_number TEXT;
  v_inv_currency TEXT;
  v_batches_created INT := 0;
  v_company_id UUID;
  v_supplier_leaf_account_id INTEGER;
  v_inventory_je_id BIGINT;
  v_payment_je_id BIGINT;
  v_supplier_name TEXT;
BEGIN
  -- PHASE 0a: Load purchase
  BEGIN
    SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');
    END IF;
    IF v_purchase.status = 'confirmed' THEN
      RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');
    END IF;

    v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');
    v_inv_currency := COALESCE(v_purchase.currency, 'EGP');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE0_FAILED (load purchase): %', SQLERRM;
  END;

  -- Get exchange rate globally from first item (as ERPA does)
  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate FROM purchase_invoice_items WHERE invoice_id = v_purchase.id LIMIT 1;
  IF v_exchange_rate IS NULL THEN v_exchange_rate := 1.0; END IF;

  -- PHASE 0a2: Get company_id
  BEGIN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    IF v_company_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE0_FAILED (get company_id): %', SQLERRM;
  END;

  -- PHASE 0b: Get supplier accounts
  BEGIN
    SELECT id INTO v_supplier_account_id FROM accounts WHERE account_code = '2000' AND company_id = v_company_id LIMIT 1;
    IF v_supplier_account_id IS NULL THEN
      RAISE EXCEPTION 'حساب الموردين (2000) غير موجود في شجرة الحسابات';
    END IF;

    SELECT s.account_id INTO v_supplier_leaf_account_id
    FROM suppliers s WHERE s.id = v_purchase.supplier_id;

    IF v_supplier_leaf_account_id IS NULL THEN
      v_supplier_leaf_account_id := v_supplier_account_id;
    END IF;

    SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE0b_FAILED (supplier accounts): %', SQLERRM;
  END;

  -- PHASE 1: Stock batches + raw materials + station products
  BEGIN
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
        v_supplier_name,
        v_purchase.id,
        v_item.quantity,
        v_item.quantity,
        v_item.unit_cost,
        v_item.unit_cost,
        v_exchange_rate,
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
            SELECT sp.station_id INTO v_station_id
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
              v_item.unit_cost, v_inv_currency, v_exchange_rate,
              'purchase', now(),
              v_supplier_name,
              v_purchase.id
            );
          END IF;
        END;
      END IF;

      v_total_foreign := v_total_foreign + (v_item.quantity * v_item.unit_cost);
      v_total_egp := v_total_egp + (v_item.quantity * v_item.unit_cost * v_exchange_rate);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE1_FAILED (stock batches): %', SQLERRM;
  END;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_treasury_id := v_purchase.payment_treasury_id;
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');

  IF v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_remaining NUMERIC;
    BEGIN
      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;
      IF v_remaining > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- PHASE 2: Inventory journal entry
  IF v_total_foreign > 0 THEN
    BEGIN
      DECLARE
        v_lines_array JSONB := '[]'::jsonb;
      BEGIN
        FOR v_account_group IN
          SELECT
            CASE
              WHEN rmc.name = 'مواد تعبئة' THEN '1040'
              ELSE '1030'
            END AS inv_code,
            SUM(pii.quantity * pii.unit_cost) AS group_total_foreign,
            SUM(pii.quantity * pii.unit_cost * v_exchange_rate) AS group_total_egp
          FROM purchase_invoice_items pii
          LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
          LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id
          WHERE pii.invoice_id::TEXT = p_purchase_id
          GROUP BY 1
        LOOP
          SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = v_account_group.inv_code AND company_id = v_company_id LIMIT 1;
          IF v_inventory_account_id IS NULL THEN
            SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1200' AND company_id = v_company_id LIMIT 1;
          END IF;

          IF v_inventory_account_id IS NOT NULL THEN
            v_lines_array := v_lines_array || jsonb_build_object(
                'account_id', v_inventory_account_id,
                'debit', v_account_group.group_total_foreign,
                'base_debit', v_account_group.group_total_egp,
                'credit', 0,
                'base_credit', 0,
                'currency', v_inv_currency,
                'description', 'مشتريات - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, '')
            );
          END IF;
        END LOOP;

        v_lines_array := v_lines_array || jsonb_build_object(
            'account_id', v_supplier_leaf_account_id,
            'debit', 0,
            'base_debit', 0,
            'credit', v_total_foreign,
            'base_credit', v_total_egp,
            'currency', v_inv_currency,
            'description', 'مورد: ' || COALESCE(v_supplier_name, '')
        );

        v_inventory_je_id := public.post_journal_entry(
          p_source_type := 'purchase_inventory',
          p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := p_user_id,
          p_lines       := v_lines_array,
          p_source_id   := v_purchase.id::TEXT
        );
        UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;
      END;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'PHASE2_FAILED (inventory GL): %', SQLERRM;
    END;
  END IF;

  -- PHASE 3: Payment Processing
  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      BEGIN
        SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;

        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '11202'
            WHEN 'EUR' THEN '11203'
            WHEN 'GBP' THEN '11204'
            ELSE '11201'
          END
        ) AND company_id = v_company_id LIMIT 1;
        IF v_cash_account_id IS NULL THEN
          SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1010' AND company_id = v_company_id LIMIT 1;
        END IF;

        UPDATE bank_accounts SET balance = balance - v_paid_amount WHERE id = v_bank_account_id;

        INSERT INTO bank_account_transactions (
          bank_account_id, type, amount, balance_before, balance_after, description, entity_type, entity_id, created_by, created_at
        ) VALUES (
          v_bank_account_id, 'withdraw', v_paid_amount, (SELECT balance + v_paid_amount FROM bank_accounts WHERE id = v_bank_account_id), (SELECT balance FROM bank_accounts WHERE id = v_bank_account_id), 'دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''), 'supplier', v_purchase.supplier_id::TEXT, p_user_id, COALESCE(v_purchase.invoice_date::date, now()::date)
        );

        v_payment_number := 'PAY-' || v_date_str || '-' || v_purchase.id::TEXT;
        INSERT INTO cash_payments (payment_number, supplier_id, amount, payment_method, payment_date, created_by)
        VALUES (v_payment_number, v_purchase.supplier_id, v_paid_amount, 'bank', COALESCE(v_purchase.invoice_date::date, now()::date), p_user_id);

        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'دفعة بنكية - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := p_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', v_paid_amount * v_exchange_rate,
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', v_paid_amount * v_exchange_rate,
              'currency', v_inv_currency,
              'description', 'بنك: ' || COALESCE(v_bank_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'PHASE3_FAILED (bank payment): %', SQLERRM;
      END;

    ELSIF v_treasury_id IS NOT NULL THEN
      BEGIN
        SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_treasury_id::INTEGER;

        v_cash_account_id := public.resolve_treasury_account(v_treasury_id::INTEGER, v_inv_currency, v_company_id);
        IF v_cash_account_id IS NULL THEN
          SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1100' AND company_id = v_company_id LIMIT 1;
        END IF;

        v_payment_number := 'PAY-' || v_date_str || '-' || v_purchase.id::TEXT;

        SELECT id, balance INTO v_treasury_balance_id, v_balance_before
        FROM treasury_balances WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency LIMIT 1;

        IF v_treasury_balance_id IS NULL THEN
          INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
          VALUES (v_treasury_id::INTEGER, v_inv_currency, 0, v_cash_account_id)
          RETURNING id, balance INTO v_treasury_balance_id, v_balance_before;
        END IF;

        v_balance_after := COALESCE(v_balance_before, 0) - v_paid_amount;
        UPDATE treasury_balances SET balance = v_balance_after, updated_at = now()
        WHERE id = v_treasury_balance_id;

        INSERT INTO treasury_transactions (
          treasury_id, type, currency, amount, balance_before, balance_after,
          description, supplier_id, created_by, created_at
        ) VALUES (
          v_treasury_id::INTEGER, 'supplier_payment', v_inv_currency, v_paid_amount, v_balance_before, v_balance_after,
          'دفعة خزنة - فاتورة ' || COALESCE(v_purchase.invoice_number, ''), v_purchase.supplier_id, p_user_id, COALESCE(v_purchase.invoice_date::date, now()::date)
        );

        INSERT INTO cash_payments (payment_number, supplier_id, amount, payment_method, payment_date, created_by)
        VALUES (v_payment_number, v_purchase.supplier_id, v_paid_amount, 'cash', COALESCE(v_purchase.invoice_date::date, now()::date), p_user_id);

        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'دفعة نقدية - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := p_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', v_paid_amount * v_exchange_rate,
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', v_paid_amount * v_exchange_rate,
              'currency', v_inv_currency,
              'description', 'خزنة: ' || COALESCE(v_treasury_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'PHASE3_FAILED (treasury payment GL): %', SQLERRM;
      END;
    END IF;

    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;
  END IF;

  -- PHASE 4: Mark confirmed
  UPDATE purchase_invoices
  SET status = 'confirmed',
      journal_entry_id = COALESCE(v_payment_je_id, v_inventory_je_id),
      updated_at = now()
  WHERE id = v_purchase.id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', v_purchase.id,
    'batches_created', v_batches_created,
    'total_foreign', v_total_foreign,
    'total_egp', v_total_egp,
    'paid_amount', v_paid_amount,
    'remaining', COALESCE(v_purchase.total_amount, 0) - v_paid_amount,
    'inventory_je_id', v_inventory_je_id,
    'payment_je_id', v_payment_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_confirm_purchase(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
