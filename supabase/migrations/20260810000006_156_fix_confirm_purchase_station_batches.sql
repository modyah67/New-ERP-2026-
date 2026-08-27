-- Migration 156: Fix confirm purchase station batches
-- Problem: When confirming a purchase with multiple packing material items,
-- the station_product_batches were being created correctly by the SQL,
-- but if station_id was NULL on purchase_invoice_items, the fallback
-- used sp.id (row primary key) instead of sp.station_id (foreign key to stations).
-- This caused batches to not be found by the station_product_details_page
-- (which queries by station_id + product_name), leading the Dart reconciliation
-- logic to create one big catch-up batch instead of individual per-purchase batches.

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
  v_company_id UUID;
  v_je_id BIGINT;
  v_supplier_leaf_account_id INTEGER;
  v_inventory_je_id BIGINT;
  v_payment_je_id BIGINT;
  v_supplier_name TEXT;
BEGIN
  -- ============================================================
  -- PHASE 0a: Load purchase
  -- ============================================================
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

  -- ============================================================
  -- PHASE 0a2: Get company_id
  -- ============================================================
  BEGIN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

    IF v_company_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';
    END IF;

    RAISE NOTICE 'PHASE0 OK: v_company_id=%', v_company_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE0_FAILED (get company_id): %', SQLERRM;
  END;

  -- ============================================================
  -- PHASE 0b: Get supplier accounts
  -- ============================================================
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

    RAISE NOTICE 'PHASE0b OK: supplier_account=% leaf=%', v_supplier_account_id, v_supplier_leaf_account_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE0b_FAILED (supplier accounts): %', SQLERRM;
  END;

  -- ============================================================
  -- PHASE 1: Stock batches + raw materials + station products
  -- ============================================================
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

          -- FIX: Use sp.station_id (FK to stations) instead of sp.id (row PK)
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
              v_item.unit_cost, v_inv_currency, COALESCE(v_item.exchange_rate, 1.0),
              'purchase', now(),
              v_supplier_name,
              v_purchase.id
            );
          END IF;
        END;
      END IF;

      v_item_egp := v_item.quantity * v_item.unit_cost * COALESCE(NULLIF(v_item.exchange_rate, 0), 1.0);
      v_total_egp := v_total_egp + v_item_egp;
    END LOOP;

    RAISE NOTICE 'PHASE1 OK: batches=% total_egp=%', v_batches_created, v_total_egp;
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
      IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL AND v_paid_amount > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + COALESCE(v_purchase.total_amount, 0)
        WHERE id = v_purchase.supplier_id;
      ELSE
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- ============================================================
  -- PHASE 2: Inventory journal entry
  -- ============================================================
  BEGIN
    SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1200' AND company_id = v_company_id LIMIT 1;
    IF v_inventory_account_id IS NULL THEN
      SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code LIKE '12%' AND company_id = v_company_id AND is_leaf = true LIMIT 1;
    END IF;
    IF v_inventory_account_id IS NULL THEN
      RAISE NOTICE 'No inventory account found, skipping inventory JE';
    ELSE
      INSERT INTO journal_entries (
        entry_date, description, source_type, source_id, company_id, status, created_by
      ) VALUES (
        COALESCE(v_purchase.invoice_date::date, now()::date),
        'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
        'purchase',
        v_purchase.id::TEXT,
        v_company_id,
        'posted',
        p_user_id
      ) RETURNING id INTO v_inventory_je_id;

      INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description, company_id)
      VALUES (v_inventory_je_id, v_inventory_account_id, v_total_egp, 0,
              'مشتريات - فاتورة ' || COALESCE(v_purchase.invoice_number, ''),
              v_company_id);

      INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description, company_id)
      VALUES (v_inventory_je_id, v_supplier_leaf_account_id, 0, v_total_egp,
              'مورد: ' || COALESCE(v_supplier_name, ''),
              v_company_id);

      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;

      RAISE NOTICE 'PHASE2 OK: inventory_je=%', v_inventory_je_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE2_FAILED (inventory JE): %', SQLERRM;
  END;

  -- ============================================================
  -- PHASE 3: Payment processing
  -- ============================================================
  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN
    BEGIN
      IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
        SELECT name INTO v_bank_name FROM bank_accounts WHERE id = v_bank_account_id;

        INSERT INTO bank_transactions (
          bank_account_id, transaction_type, amount, currency, description,
          reference_type, reference_id, transaction_date, created_by
        ) VALUES (
          v_bank_account_id, 'withdrawal', v_paid_amount, v_inv_currency,
          'دفعة مشتريات - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          'purchase', v_purchase.id::TEXT,
          COALESCE(v_purchase.invoice_date::date, now()::date),
          p_user_id
        );

        UPDATE bank_accounts
        SET balance = balance - v_paid_amount
        WHERE id = v_bank_account_id;

        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_paid_amount
        WHERE id = v_purchase.supplier_id;

        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (SELECT gl_account_code FROM bank_accounts WHERE id = v_bank_account_id)
          AND company_id = v_company_id LIMIT 1;

        IF v_cash_account_id IS NULL THEN
          SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1100' AND company_id = v_company_id LIMIT 1;
        END IF;

        IF v_cash_account_id IS NOT NULL THEN
          INSERT INTO journal_entries (
            entry_date, description, source_type, source_id, company_id, status, created_by
          ) VALUES (
            COALESCE(v_purchase.invoice_date::date, now()::date),
            'دفعة مشتريات (بنك) - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
            'purchase_payment',
            v_purchase.id::TEXT,
            v_company_id,
            'posted',
            p_user_id
          ) RETURNING id INTO v_payment_je_id;

          INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description, company_id)
          VALUES (v_payment_je_id, v_supplier_leaf_account_id, v_paid_amount * COALESCE(NULLIF((SELECT exchange_rate FROM purchase_invoice_items WHERE invoice_id::TEXT = p_purchase_id LIMIT 1), 0), 1.0), 0,
                  'سداد مورد: ' || COALESCE(v_supplier_name, ''),
                  v_company_id);

          INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description, company_id)
          VALUES (v_payment_je_id, v_cash_account_id, 0, v_paid_amount * COALESCE(NULLIF((SELECT exchange_rate FROM purchase_invoice_items WHERE invoice_id::TEXT = p_purchase_id LIMIT 1), 0), 1.0),
                  'بنك: ' || COALESCE(v_bank_name, ''),
                  v_company_id);
        END IF;

      ELSIF v_treasury_id IS NOT NULL THEN
        SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_treasury_id;

        -- Resolve treasury GL account
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          SELECT gl_account_code FROM treasuries WHERE id = v_treasury_id
        ) AND company_id = v_company_id LIMIT 1;

        IF v_cash_account_id IS NULL THEN
          SELECT id INTO v_cash_account_id FROM accounts
          WHERE account_code = '1000' AND company_id = v_company_id LIMIT 1;
        END IF;

        IF v_cash_account_id IS NULL THEN
          SELECT id INTO v_cash_account_id FROM accounts
          WHERE account_code LIKE '10%' AND company_id = v_company_id AND is_leaf = true
          ORDER BY account_code LIMIT 1;
        END IF;

        v_payment_number := 'PAY-' || v_date_str || '-' || v_purchase.id::TEXT;

        SELECT id INTO v_treasury_balance_id FROM treasury_balances
        WHERE treasury_id = v_treasury_id AND currency = v_inv_currency;

        IF v_treasury_balance_id IS NOT NULL THEN
          SELECT balance INTO v_balance_before FROM treasury_balances WHERE id = v_treasury_balance_id;
          v_balance_after := COALESCE(v_balance_before, 0) - v_paid_amount;
          UPDATE treasury_balances SET balance = v_balance_after WHERE id = v_treasury_balance_id;
        ELSE
          v_balance_before := 0;
          v_balance_after := -v_paid_amount;
          INSERT INTO treasury_balances (treasury_id, currency, balance)
          VALUES (v_treasury_id, v_inv_currency, v_balance_after)
          RETURNING id INTO v_treasury_balance_id;
        END IF;

        INSERT INTO treasury_transactions (
          treasury_id, transaction_type, amount, currency,
          description, reference_type, reference_id,
          transaction_number, balance_before, balance_after,
          user_id
        ) VALUES (
          v_treasury_id, 'expense', v_paid_amount, v_inv_currency,
          'دفعة مشتريات - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          'purchase', v_purchase.id::TEXT,
          v_payment_number, COALESCE(v_balance_before, 0), v_balance_after,
          p_user_id
        );

        IF v_cash_account_id IS NOT NULL THEN
          INSERT INTO journal_entries (
            entry_date, description, source_type, source_id, company_id, status, created_by
          ) VALUES (
            COALESCE(v_purchase.invoice_date::date, now()::date),
            'دفعة مشتريات (خزنة) - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
            'purchase_payment',
            v_purchase.id::TEXT,
            v_company_id,
            'posted',
            p_user_id
          ) RETURNING id INTO v_payment_je_id;

          INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description, company_id)
          VALUES (v_payment_je_id, v_supplier_leaf_account_id, v_paid_amount * COALESCE(NULLIF((SELECT exchange_rate FROM purchase_invoice_items WHERE invoice_id::TEXT = p_purchase_id LIMIT 1), 0), 1.0), 0,
                  'سداد مورد: ' || COALESCE(v_supplier_name, ''),
                  v_company_id);

          INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description, company_id)
          VALUES (v_payment_je_id, v_cash_account_id, 0, v_paid_amount * COALESCE(NULLIF((SELECT exchange_rate FROM purchase_invoice_items WHERE invoice_id::TEXT = p_purchase_id LIMIT 1), 0), 1.0),
                  'خزنة: ' || COALESCE(v_treasury_name, ''),
                  v_company_id);
        END IF;
      END IF;

      UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;
      RAISE NOTICE 'PHASE3 OK: paid=% source=%', v_paid_amount, v_source_type;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'PHASE3_FAILED (payment): %', SQLERRM;
    END;
  END IF;

  -- ============================================================
  -- PHASE 4: Mark confirmed
  -- ============================================================
  UPDATE purchase_invoices SET status = 'confirmed' WHERE id = v_purchase.id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', v_purchase.id,
    'batches_created', v_batches_created,
    'total_egp', v_total_egp,
    'inventory_je_id', v_inventory_je_id,
    'payment_je_id', v_payment_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_confirm_purchase(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
