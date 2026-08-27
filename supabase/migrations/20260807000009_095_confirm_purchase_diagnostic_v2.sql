-- Migration 095: Diagnostic v2 — wrap each phase in individual EXCEPTION blocks
-- to pinpoint exactly where "invalid input syntax for type uuid: "" occurs

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

  -- ============================================================
  -- PHASE 0: Get company_id
  -- ============================================================
  BEGIN
    SELECT a.company_id INTO v_company_id
    FROM accounts a
    WHERE a.account_code = '2000' AND a.company_id IS NOT NULL
    LIMIT 1;

    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

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
        IF v_remaining > 0 THEN
          UPDATE suppliers
          SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining
          WHERE id = v_purchase.supplier_id;
        END IF;
      END IF;
    END;
  END IF;

  -- ============================================================
  -- PHASE 2: Inventory GL Entry
  -- ============================================================
  IF v_total_egp > 0 THEN
    BEGIN
      FOR v_account_group IN
        SELECT
          CASE
            WHEN rmc.name = 'مواد تعبئة' THEN '1040'
            ELSE '1010'
          END AS inv_code,
          SUM(pii.quantity * pii.unit_cost * COALESCE(NULLIF(pii.exchange_rate, 0), 1.0)) AS group_total
        FROM purchase_invoice_items pii
        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
        LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id
        WHERE pii.invoice_id::TEXT = p_purchase_id
        GROUP BY 1
      LOOP
        SELECT id INTO v_inventory_account_id
        FROM accounts WHERE account_code = v_account_group.inv_code AND company_id = v_company_id
        LIMIT 1;

        RAISE NOTICE 'PHASE2: inv_code=% company_id=% account_id=% group_total=%',
          v_account_group.inv_code, v_company_id, v_inventory_account_id, v_account_group.group_total;

        IF v_inventory_account_id IS NOT NULL AND v_account_group.group_total > 0 THEN
          RAISE NOTICE 'PHASE2: calling post_journal_entry for inventory...';
          v_inventory_je_id := public.post_journal_entry(
            p_company_id := v_company_id,
            p_entry_date := v_purchase.invoice_date,
            p_source_type := 'purchase_inventory',
            p_description := 'مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_purchase.supplier_id, ''),
            p_created_by := p_user_id,
            p_lines := jsonb_build_array(
              jsonb_build_object(
                'account_id', v_inventory_account_id,
                'debit', v_account_group.group_total,
                'credit', 0,
                'currency', v_inv_currency,
                'description', 'مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '')
              ),
              jsonb_build_object(
                'account_id', v_supplier_leaf_account_id,
                'debit', 0,
                'credit', v_account_group.group_total,
                'currency', v_inv_currency,
                'description', 'مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '')
              )
            )
          );
          RAISE NOTICE 'PHASE2 OK: inventory_je_id=%', v_inventory_je_id;
        END IF;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'PHASE2_FAILED (inventory GL): %', SQLERRM;
    END;
  END IF;

  -- ============================================================
  -- PHASE 3: Payment GL Entry
  -- ============================================================
  IF v_paid_amount > 0 THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      -- Bank payment path
      BEGIN
        RAISE NOTICE 'PHASE3: bank payment path, bank_account_id=%', v_bank_account_id;

        SELECT ba.name INTO v_bank_name
        FROM bank_accounts ba WHERE ba.id = v_bank_account_id;

        SELECT id INTO v_cash_account_id
        FROM accounts WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '11202'
            WHEN 'EUR' THEN '11203'
            WHEN 'GBP' THEN '11204'
            ELSE '11201'
          END
        ) AND company_id = v_company_id
        LIMIT 1;

        DECLARE
          v_bank_res JSONB;
        BEGIN
          RAISE NOTICE 'PHASE3: calling withdraw_bank_account...';
          v_bank_res := public.withdraw_bank_account(
            v_bank_account_id,
            v_paid_amount,
            'دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
            'supplier',
            v_purchase.supplier_id::TEXT,
            (SELECT name FROM suppliers WHERE id = v_purchase.supplier_id),
            v_supplier_leaf_account_id
          );
          v_payment_je_id := (v_bank_res->>'journal_entry_id')::BIGINT;
          RAISE NOTICE 'PHASE3: withdraw_bank_account OK, je_id=%', v_payment_je_id;
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'PHASE3_FAILED (withdraw_bank_account): %', SQLERRM;
        END;

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
          RAISE NOTICE 'PHASE3 OK: bank cash_payment inserted';
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'PHASE3: cash_payments insert failed: %', SQLERRM;
        END;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'PHASE3_FAILED (bank path): %', SQLERRM;
      END;
    ELSE
      -- Treasury payment path
      BEGIN
        RAISE NOTICE 'PHASE3: treasury payment path, treasury_id=%', v_treasury_id;

        SELECT id INTO v_cash_account_id
        FROM accounts WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '11102'
            WHEN 'EUR' THEN '11103'
            WHEN 'GBP' THEN '11104'
            ELSE '11101'
          END
        ) AND company_id = v_company_id
        LIMIT 1;

        IF v_cash_account_id IS NULL THEN
          RAISE EXCEPTION 'حساب الخزينة غير موجود للعملة %', v_inv_currency;
        END IF;

        IF v_treasury_id IS NOT NULL THEN
          DECLARE
            v_treasury_tx_id BIGINT;
          BEGIN
            SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_treasury_id::INTEGER;

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
              treasury_id, type, currency, amount,
              balance_before, balance_after,
              description, supplier_id, created_by, created_at
            ) VALUES (
              v_treasury_id::INTEGER, 'supplier_payment', v_inv_currency, v_paid_amount,
              COALESCE(v_balance_before, 0), COALESCE(v_balance_after, 0),
              'دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, ''),
              v_purchase.supplier_id, p_user_id, now()
            ) RETURNING id INTO v_treasury_tx_id;

            RAISE NOTICE 'PHASE3: treasury tx OK, calling post_journal_entry...';
            v_payment_je_id := public.post_journal_entry(
              p_company_id := v_company_id,
              p_entry_date := v_purchase.invoice_date,
              p_source_type := 'purchase_payment',
              p_description := 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, ''),
              p_created_by := p_user_id,
              p_lines := jsonb_build_array(
                jsonb_build_object(
                  'account_id', v_supplier_leaf_account_id,
                  'debit', v_paid_amount,
                  'credit', 0,
                  'currency', v_inv_currency,
                  'description', 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, '')
                ),
                jsonb_build_object(
                  'account_id', v_cash_account_id,
                  'debit', 0,
                  'credit', v_paid_amount,
                  'currency', v_inv_currency,
                  'description', 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, '')
                )
              )
            );

            IF v_payment_je_id IS NOT NULL THEN
              UPDATE treasury_transactions SET journal_entry_id = v_payment_je_id WHERE id = v_treasury_tx_id;
            END IF;

            RAISE NOTICE 'PHASE3 OK: treasury payment_je_id=%', v_payment_je_id;
          EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'PHASE3_FAILED (treasury payment GL): %', SQLERRM;
          END;

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
            RAISE NOTICE 'PHASE3 OK: treasury cash_payment inserted';
          EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'PHASE3: cash_payments insert failed: %', SQLERRM;
          END;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'PHASE3_FAILED (treasury path): %', SQLERRM;
      END;
    END IF;
  END IF;

  -- ============================================================
  -- PHASE 4: Final update
  -- ============================================================
  BEGIN
    UPDATE purchase_invoices
    SET status = 'confirmed',
        journal_entry_id = COALESCE(v_payment_je_id, v_inventory_je_id),
        updated_at = now()
    WHERE id::TEXT = p_purchase_id;

    RAISE NOTICE 'PHASE4 OK: purchase confirmed';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'PHASE4_FAILED (confirm update): %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', p_purchase_id,
    'batches_created', v_batches_created,
    'paid_amount', v_paid_amount,
    'remaining', COALESCE(v_purchase.total_amount, 0) - v_paid_amount,
    'source_type', COALESCE(v_source_type, 'treasury'),
    'treasury_name', COALESCE(v_treasury_name, ''),
    'bank_name', COALESCE(v_bank_name, ''),
    'journal_entry_id', COALESCE(v_payment_je_id, v_inventory_je_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_confirm_purchase(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
