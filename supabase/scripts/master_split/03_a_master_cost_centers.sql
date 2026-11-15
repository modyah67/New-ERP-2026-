BEGIN;

-- ==============================================================================
-- المرحلة 0: متطلبات مراكز التكلفة والمواسم والعمليات الزراعية
-- ==============================================================================
ALTER TABLE IF EXISTS public.cost_centers 
    ADD COLUMN IF NOT EXISTS name_ar TEXT,
    ADD COLUMN IF NOT EXISTS name_en TEXT,
    ADD COLUMN IF NOT EXISTS cost_center_type TEXT NOT NULL DEFAULT 'variety',
    ADD COLUMN IF NOT EXISTS product_id BIGINT,
    ADD COLUMN IF NOT EXISTS entity_type TEXT DEFAULT 'fruit_type',
    ADD COLUMN IF NOT EXISTS crop_name TEXT,
    ADD COLUMN IF NOT EXISTS crop_code TEXT,
    ADD COLUMN IF NOT EXISTS season TEXT DEFAULT '2026-2027',
    ADD COLUMN IF NOT EXISTS season_status TEXT NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(15,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS current_balance NUMERIC(15,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS branch_id BIGINT,
    ADD COLUMN IF NOT EXISTS rollover_cost_center_id BIGINT,
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS closure_count INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS season_number INT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS color TEXT,
    ADD COLUMN IF NOT EXISTS icon TEXT,
    ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE IF EXISTS public.cost_center_transactions 
    ADD COLUMN IF NOT EXISTS cost_center_name TEXT,
    ADD COLUMN IF NOT EXISTS cost_center_type TEXT DEFAULT 'variety',
    ADD COLUMN IF NOT EXISTS supplier_id TEXT,
    ADD COLUMN IF NOT EXISTS supplier_name TEXT,
    ADD COLUMN IF NOT EXISTS product_id BIGINT,
    ADD COLUMN IF NOT EXISTS raw_material_id UUID,
    ADD COLUMN IF NOT EXISTS item_name TEXT DEFAULT '',
    ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'تكلفة المحاصيل',
    ADD COLUMN IF NOT EXISTS quantity NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'EGP',
    ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC DEFAULT 1.0,
    ADD COLUMN IF NOT EXISTS total_in_currency NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS notes TEXT,
    ADD COLUMN IF NOT EXISTS is_confirmed BOOLEAN DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT c.conname 
        FROM pg_constraint c
        WHERE c.conrelid = 'public.cost_center_transactions'::regclass 
          AND c.contype = 'f'
    ) LOOP
        EXECUTE 'ALTER TABLE public.cost_center_transactions DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
    END LOOP;

    -- Drop triggers that depend on column cost_center_id before altering its type
    DROP TRIGGER IF EXISTS trg_prevent_closed_cost_center_bleed ON public.cost_center_transactions;

    -- Only alter column if not already TEXT
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cost_center_transactions' 
          AND column_name = 'cost_center_id' 
          AND data_type <> 'text'
    ) THEN
        ALTER TABLE public.cost_center_transactions ALTER COLUMN cost_center_id TYPE TEXT USING cost_center_id::TEXT;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_cct_source ON public.cost_center_transactions(source_type, source_id);

ALTER TABLE IF EXISTS public.fruit_types 
    ADD COLUMN IF NOT EXISTS cost_center_id TEXT,
    ADD COLUMN IF NOT EXISTS code TEXT,
    ADD COLUMN IF NOT EXISTS purchase_mode TEXT;

ALTER TABLE IF EXISTS public.fruit_types 
    ALTER COLUMN cost_center_id TYPE TEXT USING cost_center_id::TEXT;

ALTER TABLE IF EXISTS public.raw_materials 
    ADD COLUMN IF NOT EXISTS cost_center_id TEXT,
    ADD COLUMN IF NOT EXISTS code TEXT;

ALTER TABLE IF EXISTS public.raw_materials 
    ALTER COLUMN cost_center_id TYPE TEXT USING cost_center_id::TEXT;

CREATE TABLE IF NOT EXISTS public.tenant_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES public.sys_companies(id),
    user_id UUID,
    role TEXT DEFAULT 'member',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE IF EXISTS public.tenant_users 
    ADD COLUMN IF NOT EXISTS user_id UUID;

ALTER TABLE IF EXISTS public.tenant_users ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- Migration: 20260909000004_460_fix_purchase_confirm_company_id_and_full_flow.sql
-- Description: Fix rpc_confirm_purchase bug where v_purchase.company_id was accessed
--              (table purchase_invoices has no company_id column).
--              Restores full item-level flow, stock batches, raw materials inventory,
--              station products, and multicurrency exchange rate balance conversion.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_confirm_purchase(
  p_purchase_id TEXT,
  p_user_id UUID DEFAULT NULL
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
  v_supplier_leaf_account_id INTEGER;
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
  v_inventory_je_id BIGINT;
  v_payment_je_id BIGINT;
  v_supplier_name TEXT;
  v_effective_user_id UUID;
BEGIN
  v_effective_user_id := COALESCE(p_user_id, auth.uid());

  -- ── PHASE 0a: Load Purchase Invoice ─────────────────────────────────────────
  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');
  END IF;
  IF v_purchase.status = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');
  END IF;

  v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');
  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');

  -- Determine transaction exchange rate
  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate 
  FROM purchase_invoice_items 
  WHERE invoice_id::TEXT = p_purchase_id 
  LIMIT 1;
  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN 
    v_exchange_rate := COALESCE(NULLIF(v_purchase.exchange_rate, 0), 1.0);
  END IF;
  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;

  -- ── PHASE 0a2: Resolve Company ID (from suppliers or sys_companies) ────────
  SELECT company_id INTO v_company_id FROM suppliers WHERE id = v_purchase.supplier_id;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';
  END IF;

  -- ── PHASE 0b: Resolve Supplier Leaf Account (Credit Account) ────────────────
  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;

  -- Priority 1: Use supplier's assigned account if valid, active, and allows posting
  SELECT a.id INTO v_supplier_leaf_account_id
  FROM suppliers s
  JOIN accounts a ON a.id = s.account_id
  WHERE s.id = v_purchase.supplier_id
    AND a.deleted_at IS NULL
    AND (a.allow_posting = TRUE OR a.is_leaf = TRUE);

  -- Priority 2: Lookup supplier's dedicated leaf sub-account under 2111
  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT a.id INTO v_supplier_leaf_account_id
    FROM accounts a
    WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2116%' OR a.account_code LIKE '2117%' OR a.parent_id IN (SELECT id FROM accounts WHERE account_code IN ('2111', '2115', '2116', '2117') AND deleted_at IS NULL))
      AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')
      AND a.deleted_at IS NULL
    ORDER BY a.id ASC
    LIMIT 1;
  END IF;

  -- Priority 3: Auto-create leaf account under 2111 if missing
  IF v_supplier_leaf_account_id IS NULL AND v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_p2111_id BIGINT;
      v_next_num INT;
      v_next_code TEXT;
    BEGIN
      SELECT id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1 INTO v_p2111_id;
      IF v_p2111_id IS NOT NULL THEN
        SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1
        INTO v_next_num
        FROM accounts
        WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;

        v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');

        INSERT INTO accounts (
          account_code, name, account_name, account_type,
          parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id
        ) VALUES (
          v_next_code,
          'Supplier - ' || COALESCE(v_supplier_name, 'Unknown'),
          'مورد - ' || COALESCE(v_supplier_name, 'غير محدد'),
          'liability',
          v_p2111_id,
          5,
          TRUE,
          TRUE,
          TRUE,
          FALSE,
          v_company_id
        ) RETURNING id INTO v_supplier_leaf_account_id;

        UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- Priority 4: Fallback to Level 4 parent account 2111 (enable posting if needed)
  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;
    IF v_supplier_leaf_account_id IS NOT NULL THEN
      UPDATE accounts SET allow_posting = TRUE WHERE id = v_supplier_leaf_account_id;
    END IF;
  END IF;

  -- Priority 5: Fallback to legacy 2000
  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND deleted_at IS NULL LIMIT 1;
  END IF;

  IF v_supplier_leaf_account_id IS NULL THEN
    RAISE EXCEPTION 'لم يتم العثور على حساب المورد في شجرة الحسابات (دليل الحسابات)';
  END IF;

  -- ── PHASE 1: Stock Batches + Raw Materials + Station Products ───────────────
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
      COALESCE(v_item.quantity, 0),
      COALESCE(v_item.quantity, 0),
      COALESCE(v_item.unit_cost, 0),
      COALESCE(v_item.unit_cost, 0),
      v_exchange_rate,
      v_inv_currency,
      'active',
      v_effective_user_id
    );
    v_batches_created := v_batches_created + 1;

    IF v_item.raw_material_id IS NOT NULL THEN
      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price
      FROM raw_materials WHERE id = v_item.raw_material_id;

      IF FOUND THEN
        v_cur_qty := COALESCE(v_cur_qty, 0);
        v_cur_price := COALESCE(v_cur_price, 0);
        v_new_qty := v_cur_qty + COALESCE(v_item.quantity, 0);
        IF v_new_qty > 0 THEN
          v_new_price := ((v_cur_qty * v_cur_price) + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0))) / v_new_qty;
        ELSE
          v_new_price := COALESCE(v_item.unit_cost, 0);
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
          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), COALESCE(v_item.quantity, 0)::INT);

          INSERT INTO station_product_batches (
            station_id, product_name, product_code, quantity, remaining_quantity,
            unit_cost, currency, exchange_rate, source_type, source_date,
            supplier_name, purchase_invoice_id
          ) VALUES (
            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),
            COALESCE(v_item.quantity, 0), COALESCE(v_item.quantity, 0),
            COALESCE(v_item.unit_cost, 0), v_inv_currency, v_exchange_rate,
            'purchase', now(),
            v_supplier_name,
            v_purchase.id
          );
        END IF;
      END;
    END IF;

    v_total_foreign := v_total_foreign + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0));
    v_total_egp := v_total_egp + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0) * v_exchange_rate);
  END LOOP;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_treasury_id := v_purchase.payment_treasury_id;
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');

  -- Update Supplier Outstanding Balance in converted EGP to preserve multi-currency integrity
  IF v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_remaining NUMERIC;
      v_remaining_egp NUMERIC;
    BEGIN
      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;
      v_remaining_egp := v_remaining * v_exchange_rate;
      IF v_remaining > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining_egp
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- ── PHASE 2: Granular Item-Level Inventory Journal Entry Lines ───────────────
  IF v_total_foreign > 0 THEN
    DECLARE
      v_lines_array JSONB := '[]'::jsonb;
      v_line_desc TEXT;
      v_item_line RECORD;
      v_item_foreign NUMERIC;
      v_item_egp NUMERIC;
      v_sum_debit_foreign NUMERIC := 0;
      v_sum_debit_egp NUMERIC := 0;
      v_items_summary TEXT := '';
      v_item_count INT := 0;
    BEGIN
      -- Loop through each purchased item to generate granular debit lines:
      FOR v_item_line IN
        SELECT
          pii.id,
          pii.quantity,
          pii.unit_cost,
          pii.raw_material_id,
          COALESCE(rm.name, rm.code, 'صنف غير محدد') AS item_name,
          COALESCE(rm.unit, '') AS item_unit,
          CASE 
            WHEN pii.raw_material_id IS NOT NULL THEN '12411'
            ELSE '12412'
          END AS inv_code
        FROM purchase_invoice_items pii
        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
        WHERE pii.invoice_id::TEXT = p_purchase_id
        ORDER BY pii.id ASC
      LOOP
        v_item_foreign := ROUND(COALESCE(v_item_line.quantity, 0) * COALESCE(v_item_line.unit_cost, 0), 2);
        v_item_egp := ROUND(v_item_foreign * v_exchange_rate, 2);

        v_sum_debit_foreign := v_sum_debit_foreign + v_item_foreign;
        v_sum_debit_egp := v_sum_debit_egp + v_item_egp;

        v_item_count := v_item_count + 1;
        IF v_item_count <= 3 THEN
          IF v_items_summary <> '' THEN
            v_items_summary := v_items_summary || ' + ';
          END IF;
          v_items_summary := v_items_summary || v_item_line.item_name || ' (' || v_item_line.quantity || 
            CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 
            ' بسعر ' || v_item_line.unit_cost || ' ' || v_inv_currency || ')';
        END IF;

        -- Resolve target inventory account (12411 packaging / 12412 produce)
        SELECT id INTO v_inventory_account_id 
        FROM accounts 
        WHERE account_code = v_item_line.inv_code 
          AND company_id = v_company_id 
          AND deleted_at IS NULL 
        LIMIT 1;

        IF v_inventory_account_id IS NULL THEN
          SELECT id INTO v_inventory_account_id 
          FROM accounts 
          WHERE account_code = v_item_line.inv_code 
            AND deleted_at IS NULL 
          LIMIT 1;
        END IF;

        -- Fallback between 12411 and 12412 or parent 1241
        IF v_inventory_account_id IS NULL THEN
          IF v_item_line.inv_code = '12411' THEN
            SELECT id INTO v_inventory_account_id 
            FROM accounts 
            WHERE account_code IN ('12412', '1241') AND deleted_at IS NULL 
            ORDER BY account_code ASC LIMIT 1;
          ELSE
            SELECT id INTO v_inventory_account_id 
            FROM accounts 
            WHERE account_code IN ('12411', '1241') AND deleted_at IS NULL 
            ORDER BY account_code ASC LIMIT 1;
          END IF;
        END IF;

        -- Fallback to any inventory asset account
        IF v_inventory_account_id IS NULL THEN
          SELECT id INTO v_inventory_account_id 
          FROM accounts 
          WHERE account_code LIKE '124%' AND allow_posting = TRUE AND deleted_at IS NULL 
          LIMIT 1;
        END IF;

        -- Hard validation: Never silently skip debit line
        IF v_inventory_account_id IS NULL THEN
          RAISE EXCEPTION 'لم يتم العثور على حساب المخزون (%) في شجرة الحسابات', v_item_line.inv_code;
        END IF;

        -- Granular line description with item details
        v_line_desc := 'مخزون - ' || v_item_line.item_name || 
          ' - كمية: ' || v_item_line.quantity || 
          CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 
          ' - بسعر: ' || v_item_line.unit_cost || ' ' || v_inv_currency ||
          ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '');

        -- Granular Debit Line (مدين): Inventory Account per purchased item
        v_lines_array := v_lines_array || jsonb_build_object(
          'account_id', v_inventory_account_id,
          'debit', v_item_foreign,
          'base_debit', v_item_egp,
          'credit', 0,
          'base_credit', 0,
          'currency', v_inv_currency,
          'description', v_line_desc
        );
      END LOOP;

      IF v_item_count > 3 THEN
        v_items_summary := v_items_summary || ' (+ ' || (v_item_count - 3)::TEXT || ' أصناف أخرى)';
      END IF;

      -- Credit Line (دائن): Supplier Sub-Account strictly balancing all debit lines
      v_lines_array := v_lines_array || jsonb_build_object(
        'account_id', v_supplier_leaf_account_id,
        'debit', 0,
        'base_debit', 0,
        'credit', v_sum_debit_foreign,
        'base_credit', v_sum_debit_egp,
        'currency', v_inv_currency,
        'description', 'مستحقات مورد: ' || COALESCE(v_supplier_name, '') || ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '') ||
                       CASE WHEN v_items_summary <> '' THEN ' [' || v_items_summary || ']' ELSE '' END
      );

      -- Post balanced inventory journal entry
      v_inventory_je_id := public.post_journal_entry(
        p_source_type := 'purchase_inventory',
        p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, '') ||
                         CASE WHEN v_items_summary <> '' THEN ': ' || v_items_summary ELSE '' END,
        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
        p_company_id  := v_company_id,
        p_created_by  := v_effective_user_id,
        p_lines       := v_lines_array,
        p_source_id   := v_purchase.id::TEXT
      );
      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;
    END;
  END IF;

  -- ── PHASE 3: Payment Processing (Treasury or Bank) ─────────────────────────
  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;

      -- Resolve bank account under 1211 (12111 EGP, 12112 USD, 12113 EUR, 12114 GBP)
      SELECT id INTO v_cash_account_id FROM accounts
      WHERE account_code = (
        CASE v_inv_currency
          WHEN 'USD' THEN '12112'
          WHEN 'EUR' THEN '12113'
          WHEN 'GBP' THEN '12114'
          ELSE '12111'
        END
      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12112'
            WHEN 'EUR' THEN '12113'
            WHEN 'GBP' THEN '12114'
            ELSE '12111'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE (account_code LIKE '1211%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL
        LIMIT 1;
      END IF;

      INSERT INTO bank_transactions (
        bank_account_id, type, amount, description, transaction_date,
        currency, exchange_rate, amount_in_base_currency, company_id
      ) VALUES (
        v_bank_account_id, 'withdrawal', v_paid_amount,
        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),
        COALESCE(v_purchase.invoice_date::date, now()::date),
        v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate), v_company_id
      );

      UPDATE bank_accounts
      SET current_balance = COALESCE(current_balance, 0) - v_paid_amount, updated_at = now()
      WHERE id = v_bank_account_id;

      -- Post payment journal entry
      IF v_cash_account_id IS NOT NULL THEN
        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'سداد بنكي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := v_effective_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', (v_paid_amount * v_exchange_rate),
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', (v_paid_amount * v_exchange_rate),
              'currency', v_inv_currency,
              'description', 'صرف من بنك: ' || COALESCE(v_bank_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      END IF;

    ELSIF v_treasury_id IS NOT NULL THEN
      SELECT name INTO v_treasury_name FROM treasuries WHERE id::TEXT = v_treasury_id;

      -- Resolve treasury GL account under 1221 (12211 EGP, 12212 USD, 12213 EUR, 12214 GBP)
      SELECT id INTO v_cash_account_id FROM accounts
      WHERE account_code = (
        CASE v_inv_currency
          WHEN 'USD' THEN '12212'
          WHEN 'EUR' THEN '12213'
          WHEN 'GBP' THEN '12214'
          ELSE '12211'
        END
      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12212'
            WHEN 'EUR' THEN '12213'
            WHEN 'GBP' THEN '12214'
            ELSE '12211'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12122'
            WHEN 'EUR' THEN '12123'
            WHEN 'GBP' THEN '12124'
            ELSE '12121'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE (account_code LIKE '1212%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL
        LIMIT 1;
      END IF;

      -- Update treasury balance
      SELECT id, balance INTO v_treasury_balance_id, v_balance_before
      FROM treasury_balances
      WHERE treasury_id::TEXT = v_treasury_id AND currency = v_inv_currency
      LIMIT 1;

      IF v_treasury_balance_id IS NOT NULL THEN
        v_balance_after := v_balance_before - v_paid_amount;
        UPDATE treasury_balances SET balance = v_balance_after, updated_at = now() WHERE id = v_treasury_balance_id;
      ELSE
        v_balance_before := 0;
        v_balance_after := -v_paid_amount;
        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)
        VALUES (v_treasury_id::UUID, v_inv_currency, v_balance_after, now(), now());
      END IF;

      v_payment_number := 'PAY-' || v_date_str || '-' || lpad(COALESCE(v_purchase.id, 0)::TEXT, 4, '0');

      INSERT INTO treasury_transactions (
        transaction_number, transaction_type, treasury_id, amount,
        balance_before, balance_after, transaction_date, notes, user_id,
        currency, exchange_rate, amount_in_base_currency, source_id, source_type,
        supplier_id, company_id
      ) VALUES (
        v_payment_number, 'supplier_payment', v_treasury_id::UUID, v_paid_amount,
        v_balance_before, v_balance_after,
        COALESCE(v_purchase.invoice_date::date, now()::date),
        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),
        v_effective_user_id, v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate),
        v_purchase.id::TEXT, 'purchase_payment', v_purchase.supplier_id, v_company_id
      );

      -- Post payment journal entry
      IF v_cash_account_id IS NOT NULL THEN
        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'سداد نقدي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := v_effective_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', (v_paid_amount * v_exchange_rate),
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', (v_paid_amount * v_exchange_rate),
              'currency', v_inv_currency,
              'description', 'صرف من خزينة: ' || COALESCE(v_treasury_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      END IF;
    END IF;

    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;
  END IF;

  -- ── PHASE 4: Finalize Purchase Invoice Status ──────────────────────────────
  UPDATE purchase_invoices
  SET status = 'confirmed',
      updated_at = now()
  WHERE id = v_purchase.id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم تأكيد المشتريات وتوليد بنود القيد المحاسبي التفصيلية بنجاح',
    'batches_created', v_batches_created,
    'inventory_journal_entry_id', v_inventory_je_id,
    'payment_journal_entry_id', v_payment_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_purchase(TEXT, UUID) TO authenticated, anon, service_role;

-- Migration 452: Dynamic Cost Centers for Products & Operational Lines

CREATE TABLE IF NOT EXISTS public.cost_centers (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  name_ar TEXT NOT NULL,
  name_en TEXT,
  cost_center_type TEXT NOT NULL DEFAULT 'variety', -- 'variety' or 'operational'
  product_id BIGINT,
  entity_type TEXT DEFAULT 'fruit_type',
  crop_name TEXT,
  crop_code TEXT,
  season TEXT DEFAULT '2026-2027',
  season_status TEXT DEFAULT 'active', -- 'active', 'closed', 'permanently_closed'
  opening_balance NUMERIC(15,2) DEFAULT 0.00,
  current_balance NUMERIC(15,2) DEFAULT 0.00,
  branch_id BIGINT,
  rollover_cost_center_id BIGINT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  closure_count INT NOT NULL DEFAULT 0,   -- Max 2 per agricultural year
  season_number INT NOT NULL DEFAULT 1,   -- 1 = Period 1, 2 = Period 2
  color TEXT,
  icon TEXT,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Season Locking & Uniform Querying Support:
ALTER TABLE public.cost_centers
  ADD COLUMN IF NOT EXISTS is_closed BOOLEAN GENERATED ALWAYS AS (
    NOT is_active 
    OR season_status IN ('closed', 'permanently_closed') 
    OR status IN ('closed', 'permanently_closed')
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_cost_centers_is_closed ON public.cost_centers(is_closed);

-- Index for instant lookups
CREATE INDEX IF NOT EXISTS idx_cost_centers_code ON public.cost_centers(code);
CREATE INDEX IF NOT EXISTS idx_cost_centers_product_id ON public.cost_centers(product_id);
CREATE INDEX IF NOT EXISTS idx_cost_centers_type ON public.cost_centers(cost_center_type);

-- RLS Policies
ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cost_centers' AND policyname = 'Allow read cost_centers to authenticated'
  ) THEN
    CREATE POLICY "Allow read cost_centers to authenticated" ON public.cost_centers FOR SELECT TO authenticated USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cost_centers' AND policyname = 'Allow all cost_centers to service_role'
  ) THEN
    CREATE POLICY "Allow all cost_centers to service_role" ON public.cost_centers FOR ALL TO service_role USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cost_centers' AND policyname = 'Allow insert/update cost_centers to authenticated'
  ) THEN
    CREATE POLICY "Allow insert/update cost_centers to authenticated" ON public.cost_centers FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Automatic trigger removed: Cost centers are created explicitly and manually by accountants.
DROP TRIGGER IF EXISTS trg_fruit_types_cost_center ON public.fruit_types;
DROP FUNCTION IF EXISTS public.fn_sync_fruit_type_cost_center();

COMMIT;

-- ==============================================================================
-- Migration: 20260908000001_453_cost_center_transactions_and_ledger.sql
-- Description: Automated Cost Center Transactions Ledger for Crop Purchases
--              and Synchronization with Cost Reports.
-- ==============================================================================

BEGIN;

-- ── 1. Create cost_center_transactions table ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cost_center_transactions (
  id BIGSERIAL PRIMARY KEY,
  cost_center_id TEXT NOT NULL,
  cost_center_name TEXT,
  cost_center_type TEXT DEFAULT 'variety', -- 'variety' or 'operational'
  source_type TEXT NOT NULL DEFAULT 'crop_purchase', -- 'crop_purchase', 'lot_receipt', 'packing_order'
  source_id TEXT,
  transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
  supplier_id TEXT,
  supplier_name TEXT,
  product_id BIGINT,
  item_name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'تكلفة المحاصيل',
  quantity NUMERIC NOT NULL DEFAULT 0,
  unit_price NUMERIC NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'EGP',
  exchange_rate NUMERIC NOT NULL DEFAULT 1.0,
  total_in_currency NUMERIC NOT NULL DEFAULT 0,
  amount NUMERIC NOT NULL DEFAULT 0, -- Total in local currency (EGP)
  notes TEXT,
  is_confirmed BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexing for high performance querying & reporting
CREATE INDEX IF NOT EXISTS idx_cct_cost_center_id ON public.cost_center_transactions(cost_center_id);
CREATE INDEX IF NOT EXISTS idx_cct_date ON public.cost_center_transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_cct_source ON public.cost_center_transactions(source_type, source_id);

-- Unique index to prevent duplicate transaction entries per source
CREATE UNIQUE INDEX IF NOT EXISTS uq_cct_source ON public.cost_center_transactions(source_type, source_id);

-- ── 2. Enable Row Level Security (RLS) ─────────────────────────────────────────
ALTER TABLE public.cost_center_transactions ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cost_center_transactions' AND policyname = 'Allow all authenticated to cost_center_transactions'
  ) THEN
    CREATE POLICY "Allow all authenticated to cost_center_transactions" ON public.cost_center_transactions FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cost_center_transactions' AND policyname = 'Allow all service_role to cost_center_transactions'
  ) THEN
    CREATE POLICY "Allow all service_role to cost_center_transactions" ON public.cost_center_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cost_center_transactions' AND policyname = 'Allow read anon to cost_center_transactions'
  ) THEN
    CREATE POLICY "Allow read anon to cost_center_transactions" ON public.cost_center_transactions FOR SELECT TO anon USING (true);
  END IF;
END $$;

-- ── 3. Cost Centers are managed manually (no automatic fruit_types backfill) ──


-- ── 4. Trigger to sync lot_receipts into cost_center_transactions ──────────────
CREATE OR REPLACE FUNCTION public.fn_sync_lot_receipt_cost_center_transaction()
RETURNS TRIGGER AS $$
DECLARE
  v_ft_code TEXT;
  v_ft_name TEXT;
  v_supplier_name TEXT;
  v_unit_price NUMERIC;
  v_amount NUMERIC;
  v_cc_id TEXT;
  v_cc_name TEXT;
  v_ex_rate NUMERIC;
BEGIN
  -- Lookup fruit type details
  SELECT code, name INTO v_ft_code, v_ft_name
  FROM public.fruit_types
  WHERE id = NEW.fruit_type_id;

  -- Unified resolution using fn_resolve_active_crop_cost_center
  SELECT r.cost_center_id, r.cost_center_name
  INTO v_cc_id, v_cc_name
  FROM public.fn_resolve_active_crop_cost_center(
    COALESCE(NEW.product_name, v_ft_name, 'محصول'),
    NEW.fruit_type_id
  ) r;

  IF v_cc_id IS NULL OR v_cc_id = '' THEN
    v_cc_id := 'CC-' || COALESCE(v_ft_code, NEW.fruit_type_id::text);
    v_cc_name := COALESCE(NEW.product_name, v_ft_name, 'محصول');
  END IF;

  -- Lookup supplier name
  SELECT name INTO v_supplier_name
  FROM public.suppliers
  WHERE id::text = NEW.supplier_id::text;

  v_ex_rate := COALESCE(NEW.exchange_rate, 1.0);
  IF v_ex_rate <= 0 THEN
    v_ex_rate := 1.0;
  END IF;

  v_amount := ROUND((NEW.total_fruit_cost * v_ex_rate)::numeric, 2);
  v_unit_price := ROUND((v_amount / NULLIF(NEW.gross_weight_kg, 0))::numeric, 2);

  INSERT INTO public.cost_center_transactions (
    cost_center_id,
    cost_center_name,
    cost_center_type,
    source_type,
    source_id,
    transaction_date,
    supplier_id,
    supplier_name,
    product_id,
    item_name,
    category,
    quantity,
    unit_price,
    currency,
    exchange_rate,
    total_in_currency,
    amount,
    notes,
    is_confirmed
  ) VALUES (
    v_cc_id,
    v_cc_name,
    'variety',
    'lot_receipt',
    NEW.id::text,
    NEW.receipt_date::date,
    NEW.supplier_id::text,
    v_supplier_name,
    NEW.fruit_type_id,
    COALESCE(NEW.product_name, v_ft_name, 'محصول'),
    'تكلفة المحاصيل',
    NEW.gross_weight_kg,
    v_unit_price,
    COALESCE(NEW.currency, 'EGP'),
    v_ex_rate,
    ROUND(NEW.total_fruit_cost::numeric, 2),
    v_amount,
    NEW.notes,
    COALESCE(NEW.is_confirmed, TRUE)
  )
  ON CONFLICT (source_type, source_id) DO UPDATE SET
    cost_center_id = EXCLUDED.cost_center_id,
    cost_center_name = EXCLUDED.cost_center_name,
    transaction_date = EXCLUDED.transaction_date,
    supplier_id = EXCLUDED.supplier_id,
    supplier_name = EXCLUDED.supplier_name,
    product_id = EXCLUDED.product_id,
    item_name = EXCLUDED.item_name,
    quantity = EXCLUDED.quantity,
    unit_price = EXCLUDED.unit_price,
    currency = EXCLUDED.currency,
    exchange_rate = EXCLUDED.exchange_rate,
    total_in_currency = EXCLUDED.total_in_currency,
    amount = EXCLUDED.amount,
    notes = EXCLUDED.notes,
    is_confirmed = EXCLUDED.is_confirmed,
    updated_at = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_lot_receipts_cost_center_transaction ON public.lot_receipts;
CREATE TRIGGER trg_lot_receipts_cost_center_transaction
AFTER INSERT OR UPDATE OF fruit_type_id, product_name, supplier_id, gross_weight_kg, total_fruit_cost, exchange_rate, receipt_date, is_confirmed
ON public.lot_receipts
FOR EACH ROW EXECUTE FUNCTION public.fn_sync_lot_receipt_cost_center_transaction();

-- ── 5. Backfill existing lot_receipts into cost_center_transactions ────────────
INSERT INTO public.cost_center_transactions (
  cost_center_id,
  cost_center_name,
  cost_center_type,
  source_type,
  source_id,
  transaction_date,
  supplier_id,
  supplier_name,
  product_id,
  item_name,
  category,
  quantity,
  unit_price,
  currency,
  exchange_rate,
  total_in_currency,
  amount,
  notes,
  is_confirmed
)
SELECT
  'CC-' || COALESCE(ft.code, lr.fruit_type_id::text) AS cost_center_id,
  COALESCE(lr.product_name, ft.name, 'محصول') AS cost_center_name,
  'variety' AS cost_center_type,
  'lot_receipt' AS source_type,
  lr.id::text AS source_id,
  lr.receipt_date::date AS transaction_date,
  lr.supplier_id::text AS supplier_id,
  s.name AS supplier_name,
  lr.fruit_type_id AS product_id,
  COALESCE(lr.product_name, ft.name, 'محصول') AS item_name,
  'تكلفة المحاصيل' AS category,
  lr.gross_weight_kg AS quantity,
  ROUND(((lr.total_fruit_cost * COALESCE(lr.exchange_rate, 1.0)) / NULLIF(lr.gross_weight_kg, 0))::numeric, 2) AS unit_price,
  COALESCE(lr.currency, 'EGP') AS currency,
  COALESCE(lr.exchange_rate, 1.0) AS exchange_rate,
  ROUND(lr.total_fruit_cost::numeric, 2) AS total_in_currency,
  ROUND((lr.total_fruit_cost * COALESCE(lr.exchange_rate, 1.0))::numeric, 2) AS amount,
  lr.notes AS notes,
  COALESCE(lr.is_confirmed, TRUE) AS is_confirmed
FROM public.lot_receipts lr
LEFT JOIN public.suppliers s ON s.id::text = lr.supplier_id::text
LEFT JOIN public.fruit_types ft ON ft.id = lr.fruit_type_id
ON CONFLICT (source_type, source_id) DO UPDATE SET
  cost_center_id = EXCLUDED.cost_center_id,
  cost_center_name = EXCLUDED.cost_center_name,
  transaction_date = EXCLUDED.transaction_date,
  supplier_id = EXCLUDED.supplier_id,
  supplier_name = EXCLUDED.supplier_name,
  product_id = EXCLUDED.product_id,
  item_name = EXCLUDED.item_name,
  quantity = EXCLUDED.quantity,
  unit_price = EXCLUDED.unit_price,
  currency = EXCLUDED.currency,
  exchange_rate = EXCLUDED.exchange_rate,
  total_in_currency = EXCLUDED.total_in_currency,
  amount = EXCLUDED.amount,
  notes = EXCLUDED.notes,
  is_confirmed = EXCLUDED.is_confirmed,
  updated_at = NOW();

COMMIT;

-- ==============================================================================
-- Migration: 20260909000004_460_fix_purchase_confirm_company_id_and_full_flow.sql
-- Description: Fix rpc_confirm_purchase bug where v_purchase.company_id was accessed
--              (table purchase_invoices has no company_id column).
--              Restores full item-level flow, stock batches, raw materials inventory,
--              station products, and multicurrency exchange rate balance conversion.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_confirm_purchase(
  p_purchase_id TEXT,
  p_user_id UUID DEFAULT NULL
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
  v_supplier_leaf_account_id INTEGER;
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
  v_inventory_je_id BIGINT;
  v_payment_je_id BIGINT;
  v_supplier_name TEXT;
  v_effective_user_id UUID;
BEGIN
  v_effective_user_id := COALESCE(p_user_id, auth.uid());

  -- ── PHASE 0a: Load Purchase Invoice ─────────────────────────────────────────
  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');
  END IF;
  IF v_purchase.status = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');
  END IF;

  v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');
  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');

  -- Determine transaction exchange rate
  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate 
  FROM purchase_invoice_items 
  WHERE invoice_id::TEXT = p_purchase_id 
  LIMIT 1;
  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN 
    v_exchange_rate := COALESCE(NULLIF(v_purchase.exchange_rate, 0), 1.0);
  END IF;
  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;

  -- ── PHASE 0a2: Resolve Company ID (from suppliers or sys_companies) ────────
  SELECT company_id INTO v_company_id FROM suppliers WHERE id = v_purchase.supplier_id;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';
  END IF;

  -- ── PHASE 0b: Resolve Supplier Leaf Account (Credit Account) ────────────────
  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;

  -- Priority 1: Use supplier's assigned account if valid, active, and allows posting
  SELECT a.id INTO v_supplier_leaf_account_id
  FROM suppliers s
  JOIN accounts a ON a.id = s.account_id
  WHERE s.id = v_purchase.supplier_id
    AND a.deleted_at IS NULL
    AND (a.allow_posting = TRUE OR a.is_leaf = TRUE);

  -- Priority 2: Lookup supplier's dedicated leaf sub-account under 2111
  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT a.id INTO v_supplier_leaf_account_id
    FROM accounts a
    WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2116%' OR a.account_code LIKE '2117%' OR a.parent_id IN (SELECT id FROM accounts WHERE account_code IN ('2111', '2115', '2116', '2117') AND deleted_at IS NULL))
      AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')
      AND a.deleted_at IS NULL
    ORDER BY a.id ASC
    LIMIT 1;
  END IF;

  -- Priority 3: Auto-create leaf account under 2111 if missing
  IF v_supplier_leaf_account_id IS NULL AND v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_p2111_id BIGINT;
      v_next_num INT;
      v_next_code TEXT;
    BEGIN
      SELECT id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1 INTO v_p2111_id;
      IF v_p2111_id IS NOT NULL THEN
        SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1
        INTO v_next_num
        FROM accounts
        WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;

        v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');

        INSERT INTO accounts (
          account_code, name, account_name, account_type,
          parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id
        ) VALUES (
          v_next_code,
          'Supplier - ' || COALESCE(v_supplier_name, 'Unknown'),
          'مورد - ' || COALESCE(v_supplier_name, 'غير محدد'),
          'liability',
          v_p2111_id,
          5,
          TRUE,
          TRUE,
          TRUE,
          FALSE,
          v_company_id
        ) RETURNING id INTO v_supplier_leaf_account_id;

        UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- Priority 4: Fallback to Level 4 parent account 2111 (enable posting if needed)
  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;
    IF v_supplier_leaf_account_id IS NOT NULL THEN
      UPDATE accounts SET allow_posting = TRUE WHERE id = v_supplier_leaf_account_id;
    END IF;
  END IF;

  -- Priority 5: Fallback to legacy 2000
  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND deleted_at IS NULL LIMIT 1;
  END IF;

  IF v_supplier_leaf_account_id IS NULL THEN
    RAISE EXCEPTION 'لم يتم العثور على حساب المورد في شجرة الحسابات (دليل الحسابات)';
  END IF;

  -- ── PHASE 1: Stock Batches + Raw Materials + Station Products ───────────────
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
      COALESCE(v_item.quantity, 0),
      COALESCE(v_item.quantity, 0),
      COALESCE(v_item.unit_cost, 0),
      COALESCE(v_item.unit_cost, 0),
      v_exchange_rate,
      v_inv_currency,
      'active',
      v_effective_user_id
    );
    v_batches_created := v_batches_created + 1;

    IF v_item.raw_material_id IS NOT NULL THEN
      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price
      FROM raw_materials WHERE id = v_item.raw_material_id;

      IF FOUND THEN
        v_cur_qty := COALESCE(v_cur_qty, 0);
        v_cur_price := COALESCE(v_cur_price, 0);
        v_new_qty := v_cur_qty + COALESCE(v_item.quantity, 0);
        IF v_new_qty > 0 THEN
          v_new_price := ((v_cur_qty * v_cur_price) + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0))) / v_new_qty;
        ELSE
          v_new_price := COALESCE(v_item.unit_cost, 0);
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
          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), COALESCE(v_item.quantity, 0)::INT);

          INSERT INTO station_product_batches (
            station_id, product_name, product_code, quantity, remaining_quantity,
            unit_cost, currency, exchange_rate, source_type, source_date,
            supplier_name, purchase_invoice_id
          ) VALUES (
            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),
            COALESCE(v_item.quantity, 0), COALESCE(v_item.quantity, 0),
            COALESCE(v_item.unit_cost, 0), v_inv_currency, v_exchange_rate,
            'purchase', now(),
            v_supplier_name,
            v_purchase.id
          );
        END IF;
      END;
    END IF;

    v_total_foreign := v_total_foreign + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0));
    v_total_egp := v_total_egp + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0) * v_exchange_rate);
  END LOOP;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_treasury_id := v_purchase.payment_treasury_id;
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');

  -- Update Supplier Outstanding Balance in converted EGP to preserve multi-currency integrity
  IF v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_remaining NUMERIC;
      v_remaining_egp NUMERIC;
    BEGIN
      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;
      v_remaining_egp := v_remaining * v_exchange_rate;
      IF v_remaining > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining_egp
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- ── PHASE 2: Granular Item-Level Inventory Journal Entry Lines ───────────────
  IF v_total_foreign > 0 THEN
    DECLARE
      v_lines_array JSONB := '[]'::jsonb;
      v_line_desc TEXT;
      v_item_line RECORD;
      v_item_foreign NUMERIC;
      v_item_egp NUMERIC;
      v_sum_debit_foreign NUMERIC := 0;
      v_sum_debit_egp NUMERIC := 0;
      v_items_summary TEXT := '';
      v_item_count INT := 0;
    BEGIN
      -- Loop through each purchased item to generate granular debit lines:
      FOR v_item_line IN
        SELECT
          pii.id,
          pii.quantity,
          pii.unit_cost,
          pii.raw_material_id,
          COALESCE(rm.name, rm.code, 'صنف غير محدد') AS item_name,
          COALESCE(rm.unit, '') AS item_unit,
          CASE 
            WHEN pii.raw_material_id IS NOT NULL THEN '12411'
            ELSE '12412'
          END AS inv_code
        FROM purchase_invoice_items pii
        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
        WHERE pii.invoice_id::TEXT = p_purchase_id
        ORDER BY pii.id ASC
      LOOP
        v_item_foreign := ROUND(COALESCE(v_item_line.quantity, 0) * COALESCE(v_item_line.unit_cost, 0), 2);
        v_item_egp := ROUND(v_item_foreign * v_exchange_rate, 2);

        v_sum_debit_foreign := v_sum_debit_foreign + v_item_foreign;
        v_sum_debit_egp := v_sum_debit_egp + v_item_egp;

        v_item_count := v_item_count + 1;
        IF v_item_count <= 3 THEN
          IF v_items_summary <> '' THEN
            v_items_summary := v_items_summary || ' + ';
          END IF;
          v_items_summary := v_items_summary || v_item_line.item_name || ' (' || v_item_line.quantity || 
            CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 
            ' بسعر ' || v_item_line.unit_cost || ' ' || v_inv_currency || ')';
        END IF;

        -- Resolve target inventory account (12411 packaging / 12412 produce)
        SELECT id INTO v_inventory_account_id 
        FROM accounts 
        WHERE account_code = v_item_line.inv_code 
          AND company_id = v_company_id 
          AND deleted_at IS NULL 
        LIMIT 1;

        IF v_inventory_account_id IS NULL THEN
          SELECT id INTO v_inventory_account_id 
          FROM accounts 
          WHERE account_code = v_item_line.inv_code 
            AND deleted_at IS NULL 
          LIMIT 1;
        END IF;

        -- Fallback between 12411 and 12412 or parent 1241
        IF v_inventory_account_id IS NULL THEN
          IF v_item_line.inv_code = '12411' THEN
            SELECT id INTO v_inventory_account_id 
            FROM accounts 
            WHERE account_code IN ('12412', '1241') AND deleted_at IS NULL 
            ORDER BY account_code ASC LIMIT 1;
          ELSE
            SELECT id INTO v_inventory_account_id 
            FROM accounts 
            WHERE account_code IN ('12411', '1241') AND deleted_at IS NULL 
            ORDER BY account_code ASC LIMIT 1;
          END IF;
        END IF;

        -- Fallback to any inventory asset account
        IF v_inventory_account_id IS NULL THEN
          SELECT id INTO v_inventory_account_id 
          FROM accounts 
          WHERE account_code LIKE '124%' AND allow_posting = TRUE AND deleted_at IS NULL 
          LIMIT 1;
        END IF;

        -- Hard validation: Never silently skip debit line
        IF v_inventory_account_id IS NULL THEN
          RAISE EXCEPTION 'لم يتم العثور على حساب المخزون (%) في شجرة الحسابات', v_item_line.inv_code;
        END IF;

        -- Granular line description with item details
        v_line_desc := 'مخزون - ' || v_item_line.item_name || 
          ' - كمية: ' || v_item_line.quantity || 
          CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 
          ' - بسعر: ' || v_item_line.unit_cost || ' ' || v_inv_currency ||
          ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '');

        -- Granular Debit Line (مدين): Inventory Account per purchased item
        v_lines_array := v_lines_array || jsonb_build_object(
          'account_id', v_inventory_account_id,
          'debit', v_item_foreign,
          'base_debit', v_item_egp,
          'credit', 0,
          'base_credit', 0,
          'currency', v_inv_currency,
          'description', v_line_desc
        );
      END LOOP;

      IF v_item_count > 3 THEN
        v_items_summary := v_items_summary || ' (+ ' || (v_item_count - 3)::TEXT || ' أصناف أخرى)';
      END IF;

      -- Credit Line (دائن): Supplier Sub-Account strictly balancing all debit lines
      v_lines_array := v_lines_array || jsonb_build_object(
        'account_id', v_supplier_leaf_account_id,
        'debit', 0,
        'base_debit', 0,
        'credit', v_sum_debit_foreign,
        'base_credit', v_sum_debit_egp,
        'currency', v_inv_currency,
        'description', 'مستحقات مورد: ' || COALESCE(v_supplier_name, '') || ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '') ||
                       CASE WHEN v_items_summary <> '' THEN ' [' || v_items_summary || ']' ELSE '' END
      );

      -- Post balanced inventory journal entry
      v_inventory_je_id := public.post_journal_entry(
        p_source_type := 'purchase_inventory',
        p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, '') ||
                         CASE WHEN v_items_summary <> '' THEN ': ' || v_items_summary ELSE '' END,
        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
        p_company_id  := v_company_id,
        p_created_by  := v_effective_user_id,
        p_lines       := v_lines_array,
        p_source_id   := v_purchase.id::TEXT
      );
      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;
    END;
  END IF;

  -- ── PHASE 3: Payment Processing (Treasury or Bank) ─────────────────────────
  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;

      -- Resolve bank account under 1211 (12111 EGP, 12112 USD, 12113 EUR, 12114 GBP)
      SELECT id INTO v_cash_account_id FROM accounts
      WHERE account_code = (
        CASE v_inv_currency
          WHEN 'USD' THEN '12112'
          WHEN 'EUR' THEN '12113'
          WHEN 'GBP' THEN '12114'
          ELSE '12111'
        END
      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12112'
            WHEN 'EUR' THEN '12113'
            WHEN 'GBP' THEN '12114'
            ELSE '12111'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE (account_code LIKE '1211%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL
        LIMIT 1;
      END IF;

      INSERT INTO bank_transactions (
        bank_account_id, type, amount, description, transaction_date,
        currency, exchange_rate, amount_in_base_currency, company_id
      ) VALUES (
        v_bank_account_id, 'withdrawal', v_paid_amount,
        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),
        COALESCE(v_purchase.invoice_date::date, now()::date),
        v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate), v_company_id
      );

      UPDATE bank_accounts
      SET current_balance = COALESCE(current_balance, 0) - v_paid_amount, updated_at = now()
      WHERE id = v_bank_account_id;

      -- Post payment journal entry
      IF v_cash_account_id IS NOT NULL THEN
        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'سداد بنكي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := v_effective_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', (v_paid_amount * v_exchange_rate),
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', (v_paid_amount * v_exchange_rate),
              'currency', v_inv_currency,
              'description', 'صرف من بنك: ' || COALESCE(v_bank_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      END IF;

    ELSIF v_treasury_id IS NOT NULL THEN
      SELECT name INTO v_treasury_name FROM treasuries WHERE id::TEXT = v_treasury_id;

      -- Resolve treasury GL account under 1221 (12211 EGP, 12212 USD, 12213 EUR, 12214 GBP)
      SELECT id INTO v_cash_account_id FROM accounts
      WHERE account_code = (
        CASE v_inv_currency
          WHEN 'USD' THEN '12212'
          WHEN 'EUR' THEN '12213'
          WHEN 'GBP' THEN '12214'
          ELSE '12211'
        END
      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12212'
            WHEN 'EUR' THEN '12213'
            WHEN 'GBP' THEN '12214'
            ELSE '12211'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12122'
            WHEN 'EUR' THEN '12123'
            WHEN 'GBP' THEN '12124'
            ELSE '12121'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE (account_code LIKE '1212%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL
        LIMIT 1;
      END IF;

      -- Update treasury balance
      SELECT id, balance INTO v_treasury_balance_id, v_balance_before
      FROM treasury_balances
      WHERE treasury_id::TEXT = v_treasury_id AND currency = v_inv_currency
      LIMIT 1;

      IF v_treasury_balance_id IS NOT NULL THEN
        v_balance_after := v_balance_before - v_paid_amount;
        UPDATE treasury_balances SET balance = v_balance_after, updated_at = now() WHERE id = v_treasury_balance_id;
      ELSE
        v_balance_before := 0;
        v_balance_after := -v_paid_amount;
        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)
        VALUES (v_treasury_id::UUID, v_inv_currency, v_balance_after, now(), now());
      END IF;

      v_payment_number := 'PAY-' || v_date_str || '-' || lpad(COALESCE(v_purchase.id, 0)::TEXT, 4, '0');

      INSERT INTO treasury_transactions (
        transaction_number, transaction_type, treasury_id, amount,
        balance_before, balance_after, transaction_date, notes, user_id,
        currency, exchange_rate, amount_in_base_currency, source_id, source_type,
        supplier_id, company_id
      ) VALUES (
        v_payment_number, 'supplier_payment', v_treasury_id::UUID, v_paid_amount,
        v_balance_before, v_balance_after,
        COALESCE(v_purchase.invoice_date::date, now()::date),
        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),
        v_effective_user_id, v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate),
        v_purchase.id::TEXT, 'purchase_payment', v_purchase.supplier_id, v_company_id
      );

      -- Post payment journal entry
      IF v_cash_account_id IS NOT NULL THEN
        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'سداد نقدي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := v_effective_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', (v_paid_amount * v_exchange_rate),
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', (v_paid_amount * v_exchange_rate),
              'currency', v_inv_currency,
              'description', 'صرف من خزينة: ' || COALESCE(v_treasury_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      END IF;
    END IF;

    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;
  END IF;

  -- ── PHASE 4: Finalize Purchase Invoice Status ──────────────────────────────
  UPDATE purchase_invoices
  SET status = 'confirmed',
      updated_at = now()
  WHERE id = v_purchase.id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم تأكيد المشتريات وتوليد بنود القيد المحاسبي التفصيلية بنجاح',
    'batches_created', v_batches_created,
    'inventory_journal_entry_id', v_inventory_je_id,
    'payment_journal_entry_id', v_payment_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_purchase(TEXT, UUID) TO authenticated, anon, service_role;

-- ==============================================================================
-- Migration: 20260909000005_461_packaging_purchase_cost_center_sync.sql
-- Description: Propagate cost_center_id to packaging material purchases,
--              attach cost_center_id to journal entries and transaction logs,
--              update cost_center_transactions, post_journal_entry,
--              rpc_confirm_purchase, and cost reports live views.
-- ==============================================================================

BEGIN;

-- ── 1. Add cost_center_id column to purchase_invoice_items & account_ledger_entries ──
ALTER TABLE public.purchase_invoice_items
  ADD COLUMN IF NOT EXISTS cost_center_id TEXT DEFAULT 'packing_station';

ALTER TABLE public.account_ledger_entries
  ADD COLUMN IF NOT EXISTS cost_center_id TEXT;

ALTER TABLE public.cost_center_transactions
  ADD COLUMN IF NOT EXISTS raw_material_id UUID;

CREATE INDEX IF NOT EXISTS idx_ale_cost_center_id ON public.account_ledger_entries(cost_center_id);
CREATE INDEX IF NOT EXISTS idx_pii_cost_center_id ON public.purchase_invoice_items(cost_center_id);
CREATE INDEX IF NOT EXISTS idx_cct_raw_material_id ON public.cost_center_transactions(raw_material_id);

-- ── 2. مراكز التكلفة التشغيلية ────────────────────────────────────────────────
-- ملاحظة: مراكز التكلفة أصبحت تُدار بالكامل من العميل
-- لا يتم إضافة مراكز تكلفة تشغيلية من الماستر
-- العميل ينشئ مراكز التكلفة حسب احتياجاته من واجهة التطبيق

-- ── 3. Update view v_journal_entry_lines to include cost_center_id ─────────────
-- Drop dependent function and view first to prevent Postgres ERROR: 42P16 (cannot drop columns from view)
DROP FUNCTION IF EXISTS public.rpc_get_journal_history(text, date, date, int);
DROP VIEW IF EXISTS public.v_journal_entry_lines CASCADE;

CREATE VIEW public.v_journal_entry_lines AS
SELECT
    ale.id,
    ale.journal_entry_id,
    je.id AS entry_id,
    je.entry_number,
    je.entry_date AS transaction_date,
    ale.account_id,
    COALESCE(NULLIF(a.account_code, ''), NULLIF(a.code, ''), '') AS account_code,
    COALESCE(NULLIF(a.account_name, ''), NULLIF(a.name, ''), '') AS account_name,
    CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END AS type,
    (CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END) AS amount,
    ale.description,
    je.created_by,
    je.created_at,
    je.company_id,
    ale.debit,
    ale.credit,
    ale.currency,
    ale.amount_in_base_currency,
    je.source_type,
    je.source_id,
    je.status,
    ale.cost_center_id,
    COALESCE(cc.name_ar, cc.name, cc.code, ale.cost_center_id, '') AS cost_center_name,
    COALESCE(cc.code, ale.cost_center_id, '') AS cost_center_code,
    ale.entity_type,
    ale.entity_id,
    ale.branch_id,
    st.name AS branch_name,
    st.code AS branch_code
FROM account_ledger_entries ale
JOIN journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN accounts a ON a.id = ale.account_id
LEFT JOIN stations st ON st.id = ale.branch_id
LEFT JOIN public.cost_centers cc ON (
    cc.code = ale.cost_center_id 
    OR cc.code = 'CC-' || UPPER(ale.cost_center_id)
    OR (ale.cost_center_id = 'general_admin' AND cc.code = 'CC-ADMIN')
    OR (ale.cost_center_id = 'packing_station' AND cc.code = 'CC-PACKING')
    OR (ale.cost_center_id = 'freight_logistics' AND cc.code = 'CC-LOGISTICS')
    OR (ale.cost_center_id = 'customs_clearance' AND cc.code = 'CC-CUSTOMS')
    OR cc.id::TEXT = ale.cost_center_id
)
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;

CREATE OR REPLACE VIEW public.journal_entry_lines AS
SELECT * FROM public.v_journal_entry_lines;

GRANT SELECT ON public.journal_entry_lines TO authenticated, service_role, anon;

-- Recreate rpc_get_journal_history to ensure composite return type matches new view definition
CREATE OR REPLACE FUNCTION public.rpc_get_journal_history(
    p_search text DEFAULT NULL,
    p_from_date date DEFAULT NULL,
    p_to_date date DEFAULT NULL,
    p_limit int DEFAULT 300
)
RETURNS SETOF v_journal_entry_lines AS $$
BEGIN
  IF p_search IS NULL OR p_search = '' THEN
    RETURN QUERY
    WITH latest AS (
      SELECT id 
      FROM journal_entries 
      WHERE deleted_at IS NULL
        AND (p_from_date IS NULL OR entry_date >= p_from_date)
        AND (p_to_date IS NULL OR entry_date <= p_to_date)
      ORDER BY created_at DESC, id DESC 
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN latest l ON l.id = v.entry_id
    ORDER BY v.created_at DESC, v.entry_id DESC, v.id ASC;
  ELSE
    RETURN QUERY
    WITH matched_entries AS (
      SELECT entry_id
      FROM v_journal_entry_lines
      WHERE (p_from_date IS NULL OR transaction_date >= p_from_date)
        AND (p_to_date IS NULL OR transaction_date <= p_to_date)
        AND (
          entry_number ILIKE '%' || p_search || '%'
          OR account_name ILIKE '%' || p_search || '%'
          OR account_code ILIKE '%' || p_search || '%'
          OR description ILIKE '%' || p_search || '%'
          OR cost_center_name ILIKE '%' || p_search || '%'
          OR branch_name ILIKE '%' || p_search || '%'
        )
      GROUP BY entry_id
      ORDER BY MAX(created_at) DESC, entry_id DESC
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN matched_entries m ON m.entry_id = v.entry_id
    ORDER BY v.created_at DESC, v.entry_id DESC, v.id ASC;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.rpc_get_journal_history(text, date, date, int) TO authenticated, service_role, anon;

-- ── 4. Update post_journal_entry to record cost_center_id per ledger line ──────
CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type   TEXT,
    p_description   TEXT,
    p_entry_date    DATE,
    p_company_id    UUID,
    p_created_by    UUID,
    p_lines         JSONB,
    p_source_id     TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_je_id         BIGINT;
    v_entry_number  TEXT;
    v_total_debit   NUMERIC := 0;
    v_total_credit  NUMERIC := 0;
    v_line          JSONB;
    v_account_id    BIGINT;
    v_debit         NUMERIC;
    v_credit        NUMERIC;
    v_base_debit    NUMERIC;
    v_base_credit   NUMERIC;
    v_currency      TEXT;
    v_desc          TEXT;
    v_cost_center_id TEXT;
    v_actual_date   DATE;
    v_base_amount   NUMERIC;
    v_is_leaf       BOOLEAN;
    v_acct_code     TEXT;
BEGIN
    -- ── IDEMPOTENCY SAFEGUARD ────────────────────────────────────────────────
    IF p_source_type IS NOT NULL AND p_source_id IS NOT NULL 
       AND p_source_type NOT IN ('manual', 'adjustment', 'lot_price_adjustment') THEN
        SELECT id INTO v_je_id
        FROM public.journal_entries
        WHERE source_type = p_source_type
          AND source_id = p_source_id
          AND deleted_at IS NULL
        ORDER BY id ASC
        LIMIT 1;

        IF v_je_id IS NOT NULL THEN
            RETURN v_je_id;
        END IF;
    END IF;

    -- Auto-provision or resolve company_id
    IF p_company_id IS NULL THEN
        SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    END IF;

    IF p_company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE id = p_company_id) THEN
        BEGIN
            INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)
            VALUES (p_company_id, 'شركة النظام', true, now(), now())
            ON CONFLICT (id) DO UPDATE SET 
                is_active = true,
                updated_at = now();
        EXCEPTION WHEN OTHERS THEN
            SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
        END;
    END IF;

    IF p_company_id IS NULL THEN
        INSERT INTO public.sys_companies (name, is_active, created_at, updated_at)
        VALUES ('الشركة الافتراضية', true, now(), now())
        RETURNING id INTO p_company_id;
    END IF;

    v_actual_date := COALESCE(p_entry_date, (NOW() AT TIME ZONE 'Africa/Cairo')::DATE);
    IF p_entry_date = CURRENT_DATE AND (NOW() AT TIME ZONE 'Africa/Cairo')::DATE != CURRENT_DATE THEN
        v_actual_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;
    END IF;

    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, created_by, company_id
    ) VALUES (
        v_entry_number, v_actual_date, p_description, 'posted',
        true, p_source_type, p_source_id, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id    := (v_line->>'account_id')::BIGINT;
        v_debit         := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit        := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit    := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit   := COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency      := COALESCE(v_line->>'currency', 'EGP');
        v_desc          := COALESCE(v_line->>'description', p_description);
        v_cost_center_id:= COALESCE(NULLIF(v_line->>'cost_center_id', ''), NULL);

        SELECT a.is_leaf, a.account_code INTO v_is_leaf, v_acct_code
        FROM public.accounts a WHERE a.id = v_account_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        IF v_is_leaf IS NOT TRUE THEN
            RAISE EXCEPTION 'Account % (ID: %) is a control/header account and cannot be posted to. Only Level 5 posting accounts (is_leaf = true) are allowed.', v_acct_code, v_account_id;
        END IF;

        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'Single line cannot have both debit and credit';
        END IF;

        IF v_debit = 0 AND v_credit = 0 THEN
            CONTINUE;
        END IF;

        v_total_debit  := v_total_debit + v_base_debit;
        v_total_credit := v_total_credit + v_base_credit;
        v_base_amount  := CASE WHEN v_debit > 0 THEN v_base_debit ELSE v_base_credit END;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id, cost_center_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, v_base_amount, v_desc, p_company_id, v_cost_center_id
        );
    END LOOP;

    IF ABS(v_total_debit - v_total_credit) > 0.05 THEN
        RAISE EXCEPTION 'Journal entry unbalanced in base currency: Total Base Debit = %, Total Base Credit = %', v_total_debit, v_total_credit;
    END IF;

    RETURN v_je_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;

-- ── 5. Update rpc_confirm_purchase to propagate cost_center_id & sync logs ──
DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_confirm_purchase(
  p_purchase_id TEXT,
  p_user_id UUID DEFAULT NULL
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
  v_supplier_leaf_account_id INTEGER;
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
  v_inventory_je_id BIGINT;
  v_payment_je_id BIGINT;
  v_supplier_name TEXT;
  v_effective_user_id UUID;
  v_item_cost_center_id TEXT;
BEGIN
  v_effective_user_id := COALESCE(p_user_id, auth.uid());

  -- ── PHASE 0a: Load Purchase Invoice ─────────────────────────────────────────
  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');
  END IF;
  IF v_purchase.status = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');
  END IF;

  v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');
  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');

  -- Determine transaction exchange rate
  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate 
  FROM purchase_invoice_items 
  WHERE invoice_id::TEXT = p_purchase_id 
  LIMIT 1;
  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN 
    v_exchange_rate := COALESCE(NULLIF(v_purchase.exchange_rate, 0), 1.0);
  END IF;
  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;

  -- ── PHASE 0a2: Resolve Company ID (from suppliers or sys_companies) ────────
  SELECT company_id INTO v_company_id FROM suppliers WHERE id = v_purchase.supplier_id;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;
  IF v_company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = v_company_id) THEN
    BEGIN
      INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)
      VALUES (v_company_id, 'شركة النظام', true, now(), now())
      ON CONFLICT (id) DO UPDATE SET is_active = true, updated_at = now();
    EXCEPTION WHEN OTHERS THEN
      SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    END;
  END IF;
  IF v_company_id IS NULL THEN
    INSERT INTO public.sys_companies (name, is_active, created_at, updated_at)
    VALUES ('الشركة الافتراضية', true, now(), now())
    RETURNING id INTO v_company_id;
  END IF;

  -- ── PHASE 0b: Resolve Supplier Leaf Account (Credit Account) ────────────────
  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;

  SELECT a.id INTO v_supplier_leaf_account_id
  FROM suppliers s
  JOIN accounts a ON a.id = s.account_id
  WHERE s.id = v_purchase.supplier_id
    AND a.deleted_at IS NULL
    AND (a.allow_posting = TRUE OR a.is_leaf = TRUE);

  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT a.id INTO v_supplier_leaf_account_id
    FROM accounts a
    WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2116%' OR a.account_code LIKE '2117%' OR a.parent_id IN (SELECT id FROM accounts WHERE account_code IN ('2111', '2115', '2116', '2117') AND deleted_at IS NULL))
      AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')
      AND a.deleted_at IS NULL
    ORDER BY a.id ASC
    LIMIT 1;
  END IF;

  IF v_supplier_leaf_account_id IS NULL AND v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_p2111_id BIGINT;
      v_next_num INT;
      v_next_code TEXT;
    BEGIN
      SELECT id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1 INTO v_p2111_id;
      IF v_p2111_id IS NOT NULL THEN
        SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1
        INTO v_next_num
        FROM accounts
        WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;

        v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');

        INSERT INTO accounts (
          account_code, name, account_name, account_type,
          parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id
        ) VALUES (
          v_next_code,
          'Supplier - ' || COALESCE(v_supplier_name, 'Unknown'),
          'مورد - ' || COALESCE(v_supplier_name, 'غير محدد'),
          'liability',
          v_p2111_id,
          5,
          TRUE,
          TRUE,
          TRUE,
          FALSE,
          v_company_id
        ) RETURNING id INTO v_supplier_leaf_account_id;

        UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;
    IF v_supplier_leaf_account_id IS NOT NULL THEN
      UPDATE accounts SET allow_posting = TRUE WHERE id = v_supplier_leaf_account_id;
    END IF;
  END IF;

  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND deleted_at IS NULL LIMIT 1;
  END IF;

  IF v_supplier_leaf_account_id IS NULL THEN
    RAISE EXCEPTION 'لم يتم العثور على حساب المورد في شجرة الحسابات (دليل الحسابات)';
  END IF;

  -- ── PHASE 1: Stock Batches + Raw Materials + Station Products ───────────────
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
      COALESCE(v_item.quantity, 0),
      COALESCE(v_item.quantity, 0),
      COALESCE(v_item.unit_cost, 0),
      COALESCE(v_item.unit_cost, 0),
      v_exchange_rate,
      v_inv_currency,
      'active',
      v_effective_user_id
    );
    v_batches_created := v_batches_created + 1;

    IF v_item.raw_material_id IS NOT NULL THEN
      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price
      FROM raw_materials WHERE id = v_item.raw_material_id;

      IF FOUND THEN
        v_cur_qty := COALESCE(v_cur_qty, 0);
        v_cur_price := COALESCE(v_cur_price, 0);
        v_new_qty := v_cur_qty + COALESCE(v_item.quantity, 0);
        IF v_new_qty > 0 THEN
          v_new_price := ((v_cur_qty * v_cur_price) + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0))) / v_new_qty;
        ELSE
          v_new_price := COALESCE(v_item.unit_cost, 0);
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
          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), COALESCE(v_item.quantity, 0)::INT);

          INSERT INTO station_product_batches (
            station_id, product_name, product_code, quantity, remaining_quantity,
            unit_cost, currency, exchange_rate, source_type, source_date,
            supplier_name, purchase_invoice_id
          ) VALUES (
            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),
            COALESCE(v_item.quantity, 0), COALESCE(v_item.quantity, 0),
            COALESCE(v_item.unit_cost, 0), v_inv_currency, v_exchange_rate,
            'purchase', now(),
            v_supplier_name,
            v_purchase.id
          );
        END IF;
      END;
    END IF;

    v_total_foreign := v_total_foreign + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0));
    v_total_egp := v_total_egp + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0) * v_exchange_rate);
  END LOOP;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_treasury_id := v_purchase.payment_treasury_id;
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');

  -- Update Supplier Outstanding Balance in converted EGP
  IF v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_remaining NUMERIC;
      v_remaining_egp NUMERIC;
    BEGIN
      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;
      v_remaining_egp := v_remaining * v_exchange_rate;
      IF v_remaining > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining_egp
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  -- ── PHASE 2: Granular Item-Level Inventory Journal Entry Lines & Cost Center Sync ──
  IF v_total_foreign > 0 THEN
    DECLARE
      v_lines_array JSONB := '[]'::jsonb;
      v_line_desc TEXT;
      v_item_line RECORD;
      v_item_foreign NUMERIC;
      v_item_egp NUMERIC;
      v_sum_debit_foreign NUMERIC := 0;
      v_sum_debit_egp NUMERIC := 0;
      v_items_summary TEXT := '';
      v_item_count INT := 0;
      v_cct_cost_center_name TEXT;
    BEGIN
      -- Loop through each purchased item to generate granular debit lines:
      FOR v_item_line IN
        SELECT
          pii.id,
          pii.quantity,
          pii.unit_cost,
          pii.raw_material_id,
          COALESCE(NULLIF(pii.cost_center_id, ''), 'packing_station') AS cost_center_id,
          COALESCE(rm.name, rm.code, 'صنف غير محدد') AS item_name,
          COALESCE(rm.unit, '') AS item_unit,
          CASE 
            WHEN pii.raw_material_id IS NOT NULL THEN '12411'
            ELSE '12412'
          END AS inv_code
        FROM purchase_invoice_items pii
        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
        WHERE pii.invoice_id::TEXT = p_purchase_id
        ORDER BY pii.id ASC
      LOOP
        v_item_foreign := ROUND(COALESCE(v_item_line.quantity, 0) * COALESCE(v_item_line.unit_cost, 0), 2);
        v_item_egp := ROUND(v_item_foreign * v_exchange_rate, 2);

        v_sum_debit_foreign := v_sum_debit_foreign + v_item_foreign;
        v_sum_debit_egp := v_sum_debit_egp + v_item_egp;

        v_item_count := v_item_count + 1;
        IF v_item_count <= 3 THEN
          IF v_items_summary <> '' THEN
            v_items_summary := v_items_summary || ' + ';
          END IF;
          v_items_summary := v_items_summary || v_item_line.item_name || ' (' || v_item_line.quantity || 
            CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 
            ' بسعر ' || v_item_line.unit_cost || ' ' || v_inv_currency || ')';
        END IF;

        -- Resolve target inventory account (12411 packaging / 12412 produce)
        SELECT id INTO v_inventory_account_id 
        FROM accounts 
        WHERE account_code = v_item_line.inv_code 
          AND company_id = v_company_id 
          AND deleted_at IS NULL 
        LIMIT 1;

        IF v_inventory_account_id IS NULL THEN
          SELECT id INTO v_inventory_account_id 
          FROM accounts 
          WHERE account_code = v_item_line.inv_code 
            AND deleted_at IS NULL 
          LIMIT 1;
        END IF;

        -- Fallback between 12411 and 12412 or parent 1241
        IF v_inventory_account_id IS NULL THEN
          IF v_item_line.inv_code = '12411' THEN
            SELECT id INTO v_inventory_account_id 
            FROM accounts 
            WHERE account_code IN ('12412', '1241') AND deleted_at IS NULL 
            ORDER BY account_code ASC LIMIT 1;
          ELSE
            SELECT id INTO v_inventory_account_id 
            FROM accounts 
            WHERE account_code IN ('12411', '1241') AND deleted_at IS NULL 
            ORDER BY account_code ASC LIMIT 1;
          END IF;
        END IF;

        -- Fallback to any inventory asset account
        IF v_inventory_account_id IS NULL THEN
          SELECT id INTO v_inventory_account_id 
          FROM accounts 
          WHERE account_code LIKE '124%' AND allow_posting = TRUE AND deleted_at IS NULL 
          LIMIT 1;
        END IF;

        IF v_inventory_account_id IS NULL THEN
          RAISE EXCEPTION 'لم يتم العثور على حساب المخزون (%) في شجرة الحسابات', v_item_line.inv_code;
        END IF;

        v_line_desc := 'مخزون - ' || v_item_line.item_name || 
          ' - كمية: ' || v_item_line.quantity || 
          CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 
          ' - بسعر: ' || v_item_line.unit_cost || ' ' || v_inv_currency ||
          ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '');

        -- Granular Debit Line with attached cost_center_id
        v_lines_array := v_lines_array || jsonb_build_object(
          'account_id', v_inventory_account_id,
          'debit', v_item_foreign,
          'base_debit', v_item_egp,
          'credit', 0,
          'base_credit', 0,
          'currency', v_inv_currency,
          'description', v_line_desc,
          'cost_center_id', v_item_line.cost_center_id
        );

        -- Sync confirmed packaging purchase item into cost_center_transactions
        IF v_item_line.raw_material_id IS NOT NULL OR v_item_line.inv_code = '12411' THEN
          SELECT COALESCE(name_ar, name) INTO v_cct_cost_center_name
          FROM public.cost_centers
          WHERE code = v_item_line.cost_center_id OR id::text = v_item_line.cost_center_id;
          
          IF v_cct_cost_center_name IS NULL THEN
            v_cct_cost_center_name := 'محطة التعبئة والتجهيز';
          END IF;

          INSERT INTO public.cost_center_transactions (
            cost_center_id,
            cost_center_name,
            cost_center_type,
            source_type,
            source_id,
            transaction_date,
            supplier_id,
            supplier_name,
            product_id,
            raw_material_id,
            item_name,
            category,
            quantity,
            unit_price,
            currency,
            exchange_rate,
            total_in_currency,
            amount,
            notes,
            is_confirmed
          ) VALUES (
            v_item_line.cost_center_id,
            v_cct_cost_center_name,
            'operational',
            'purchase',
            'pii_' || v_item_line.id::TEXT,
            COALESCE(v_purchase.invoice_date::date, now()::date),
            v_purchase.supplier_id::TEXT,
            v_supplier_name,
            NULL::bigint,
            v_item_line.raw_material_id,
            v_item_line.item_name,
            'مواد التعبئة',
            COALESCE(v_item_line.quantity, 0),
            COALESCE(v_item_line.unit_cost, 0),
            v_inv_currency,
            v_exchange_rate,
            v_item_foreign,
            v_item_egp,
            'فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || v_item_line.item_name,
            TRUE
          )
          ON CONFLICT (source_type, source_id) DO UPDATE SET
            cost_center_id = EXCLUDED.cost_center_id,
            cost_center_name = EXCLUDED.cost_center_name,
            cost_center_type = EXCLUDED.cost_center_type,
            transaction_date = EXCLUDED.transaction_date,
            supplier_id = EXCLUDED.supplier_id,
            supplier_name = EXCLUDED.supplier_name,
            product_id = EXCLUDED.product_id,
            raw_material_id = EXCLUDED.raw_material_id,
            item_name = EXCLUDED.item_name,
            category = EXCLUDED.category,
            quantity = EXCLUDED.quantity,
            unit_price = EXCLUDED.unit_price,
            currency = EXCLUDED.currency,
            exchange_rate = EXCLUDED.exchange_rate,
            total_in_currency = EXCLUDED.total_in_currency,
            amount = EXCLUDED.amount,
            notes = EXCLUDED.notes,
            is_confirmed = EXCLUDED.is_confirmed,
            updated_at = NOW();
        END IF;
      END LOOP;

      IF v_item_count > 3 THEN
        v_items_summary := v_items_summary || ' (+ ' || (v_item_count - 3)::TEXT || ' أصناف أخرى)';
      END IF;

      -- Credit Line: Supplier Sub-Account strictly balancing all debit lines
      v_lines_array := v_lines_array || jsonb_build_object(
        'account_id', v_supplier_leaf_account_id,
        'debit', 0,
        'base_debit', 0,
        'credit', v_sum_debit_foreign,
        'base_credit', v_sum_debit_egp,
        'currency', v_inv_currency,
        'description', 'مستحقات مورد: ' || COALESCE(v_supplier_name, '') || ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '') ||
                       CASE WHEN v_items_summary <> '' THEN ' [' || v_items_summary || ']' ELSE '' END
      );

      -- Post balanced inventory journal entry
      v_inventory_je_id := public.post_journal_entry(
        p_source_type := 'purchase_inventory',
        p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, '') ||
                         CASE WHEN v_items_summary <> '' THEN ': ' || v_items_summary ELSE '' END,
        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
        p_company_id  := v_company_id,
        p_created_by  := v_effective_user_id,
        p_lines       := v_lines_array,
        p_source_id   := v_purchase.id::TEXT
      );
      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;
    END;
  END IF;

  -- ── PHASE 3: Payment Processing (Treasury or Bank) ─────────────────────────
  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;

      SELECT id INTO v_cash_account_id FROM accounts
      WHERE account_code = (
        CASE v_inv_currency
          WHEN 'USD' THEN '12112'
          WHEN 'EUR' THEN '12113'
          WHEN 'GBP' THEN '12114'
          ELSE '12111'
        END
      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12112'
            WHEN 'EUR' THEN '12113'
            WHEN 'GBP' THEN '12114'
            ELSE '12111'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE (account_code LIKE '1211%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL
        LIMIT 1;
      END IF;

      INSERT INTO bank_transactions (
        bank_account_id, type, amount, description, transaction_date,
        currency, exchange_rate, amount_in_base_currency, company_id
      ) VALUES (
        v_bank_account_id, 'withdrawal', v_paid_amount,
        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),
        COALESCE(v_purchase.invoice_date::date, now()::date),
        v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate), v_company_id
      );

      UPDATE bank_accounts
      SET current_balance = COALESCE(current_balance, 0) - v_paid_amount, updated_at = now()
      WHERE id = v_bank_account_id;

      IF v_cash_account_id IS NOT NULL THEN
        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'سداد بنكي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := v_effective_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', (v_paid_amount * v_exchange_rate),
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', (v_paid_amount * v_exchange_rate),
              'currency', v_inv_currency,
              'description', 'صرف من بنك: ' || COALESCE(v_bank_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      END IF;

    ELSIF v_treasury_id IS NOT NULL THEN
      SELECT name INTO v_treasury_name FROM treasuries WHERE id::TEXT = v_treasury_id;

      SELECT id INTO v_cash_account_id FROM accounts
      WHERE account_code = (
        CASE v_inv_currency
          WHEN 'USD' THEN '12212'
          WHEN 'EUR' THEN '12213'
          WHEN 'GBP' THEN '12214'
          ELSE '12211'
        END
      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12212'
            WHEN 'EUR' THEN '12213'
            WHEN 'GBP' THEN '12214'
            ELSE '12211'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE account_code = (
          CASE v_inv_currency
            WHEN 'USD' THEN '12122'
            WHEN 'EUR' THEN '12123'
            WHEN 'GBP' THEN '12124'
            ELSE '12121'
          END
        ) AND deleted_at IS NULL LIMIT 1;
      END IF;

      IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM accounts
        WHERE (account_code LIKE '1212%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL
        LIMIT 1;
      END IF;

      SELECT id, balance INTO v_treasury_balance_id, v_balance_before
      FROM treasury_balances
      WHERE treasury_id::TEXT = v_treasury_id AND currency = v_inv_currency
      LIMIT 1;

      IF v_treasury_balance_id IS NOT NULL THEN
        v_balance_after := v_balance_before - v_paid_amount;
        UPDATE treasury_balances SET balance = v_balance_after, updated_at = now() WHERE id = v_treasury_balance_id;
      ELSE
        v_balance_before := 0;
        v_balance_after := -v_paid_amount;
        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)
        VALUES (v_treasury_id::UUID, v_inv_currency, v_balance_after, now(), now());
      END IF;

      v_payment_number := 'PAY-' || v_date_str || '-' || lpad(COALESCE(v_purchase.id, 0)::TEXT, 4, '0');

      INSERT INTO treasury_transactions (
        transaction_number, transaction_type, treasury_id, amount,
        balance_before, balance_after, transaction_date, notes, user_id,
        currency, exchange_rate, amount_in_base_currency, source_id, source_type,
        supplier_id, company_id
      ) VALUES (
        v_payment_number, 'supplier_payment', v_treasury_id::UUID, v_paid_amount,
        v_balance_before, v_balance_after,
        COALESCE(v_purchase.invoice_date::date, now()::date),
        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),
        v_effective_user_id, v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate),
        v_purchase.id::TEXT, 'purchase_payment', v_purchase.supplier_id, v_company_id
      );

      IF v_cash_account_id IS NOT NULL THEN
        v_payment_je_id := public.post_journal_entry(
          p_source_type := 'purchase_payment',
          p_description := 'سداد نقدي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),
          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
          p_company_id  := v_company_id,
          p_created_by  := v_effective_user_id,
          p_lines       := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', v_paid_amount,
              'base_debit', (v_paid_amount * v_exchange_rate),
              'credit', 0,
              'base_credit', 0,
              'currency', v_inv_currency,
              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')
            ),
            jsonb_build_object(
              'account_id', v_cash_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_paid_amount,
              'base_credit', (v_paid_amount * v_exchange_rate),
              'currency', v_inv_currency,
              'description', 'صرف من خزينة: ' || COALESCE(v_treasury_name, '')
            )
          ),
          p_source_id   := v_purchase.id::TEXT
        );
      END IF;
    END IF;

    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;
  END IF;

  -- ── PHASE 4: Finalize Purchase Invoice Status ──────────────────────────────
  UPDATE purchase_invoices
  SET status = 'confirmed',
      updated_at = now()
  WHERE id = v_purchase.id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم تأكيد المشتريات وربط مركز التكلفة وتوليد بنود القيد المحاسبي التفصيلية بنجاح',
    'batches_created', v_batches_created,
    'inventory_journal_entry_id', v_inventory_je_id,
    'payment_journal_entry_id', v_payment_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_purchase(TEXT, UUID) TO authenticated, anon, service_role;

-- ── 6. RPC function to get cost center report metrics ────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_get_cost_center_report(
  p_cost_center_id TEXT DEFAULT NULL,
  p_from_date DATE DEFAULT NULL,
  p_to_date DATE DEFAULT NULL
)
RETURNS TABLE (
  cost_center_id TEXT,
  cost_center_name TEXT,
  cost_center_type TEXT,
  category TEXT,
  item_name TEXT,
  total_amount NUMERIC,
  total_quantity NUMERIC,
  transaction_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cct.cost_center_id,
    COALESCE(cct.cost_center_name, cc.name_ar, 'مركز تكلفة') AS cost_center_name,
    COALESCE(cct.cost_center_type, cc.cost_center_type, 'operational') AS cost_center_type,
    cct.category,
    cct.item_name,
    ROUND(SUM(cct.amount)::numeric, 2) AS total_amount,
    SUM(cct.quantity) AS total_quantity,
    COUNT(*) AS transaction_count
  FROM public.cost_center_transactions cct
  LEFT JOIN public.cost_centers cc ON (cc.code = cct.cost_center_id OR cc.id::text = cct.cost_center_id)
  WHERE cct.is_confirmed = TRUE
    AND (p_cost_center_id IS NULL OR cct.cost_center_id = p_cost_center_id OR cc.code = p_cost_center_id)
    AND (p_from_date IS NULL OR cct.transaction_date >= p_from_date)
    AND (p_to_date IS NULL OR cct.transaction_date <= p_to_date)
    -- Deduplication: Exclude season_rollover if the cost center already contains detailed operational transactions for that period
    AND NOT (
      cct.source_type = 'season_rollover'
      AND EXISTS (
        SELECT 1 FROM public.cost_center_transactions cct_ops
        WHERE (cct_ops.cost_center_id = cct.cost_center_id OR cct_ops.cost_center_name = cct.cost_center_name)
          AND cct_ops.source_type <> 'season_rollover'
          AND cct_ops.is_confirmed = TRUE
          AND (
            cct.source_id ~ '^rollover_([0-9]+)_to_\1$'
            OR cct.source_id = 'rollover_' || COALESCE(cc.id::text, '') || '_to_' || COALESCE(cc.id::text, '')
          )
      )
    )
    -- Deduplication: Exclude redundant preliminary purchase orders if detailed lot receipt exists
    AND NOT (
      cct.source_type IN ('crop_purchase', 'purchase_order')
      AND EXISTS (
        SELECT 1 FROM public.cost_center_transactions cct2
        WHERE cct2.source_type = 'lot_receipt'
          AND cct2.cost_center_id = cct.cost_center_id
          AND (
            cct2.source_id = cct.source_id
            OR (
              cct2.product_id = cct.product_id
              AND cct2.transaction_date BETWEEN cct.transaction_date - INTERVAL '7 days' AND cct.transaction_date + INTERVAL '7 days'
              AND ABS(cct2.amount - cct.amount) < 1.0
            )
          )
      )
    )
  GROUP BY cct.cost_center_id, COALESCE(cct.cost_center_name, cc.name_ar, 'مركز تكلفة'), COALESCE(cct.cost_center_type, cc.cost_center_type, 'operational'), cct.category, cct.item_name
  ORDER BY total_amount DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_cost_center_report(TEXT, DATE, DATE) TO authenticated, service_role, anon;

-- ── 6b. RPC to fetch unified, deduplicated cost center details ─────────────
CREATE OR REPLACE FUNCTION public.rpc_get_cost_center_details(
  p_cost_center_id TEXT DEFAULT NULL,
  p_from_date DATE DEFAULT NULL,
  p_to_date DATE DEFAULT NULL,
  p_category TEXT DEFAULT NULL
)
RETURNS TABLE (
  id TEXT,
  cost_center_id TEXT,
  cost_center_name TEXT,
  cost_center_type TEXT,
  source_type TEXT,
  source_id TEXT,
  shipment_no TEXT,
  shipment_date DATE,
  supplier_name TEXT,
  customer_name TEXT,
  item_name TEXT,
  category TEXT,
  quantity NUMERIC,
  unit_price NUMERIC,
  currency TEXT,
  exchange_rate NUMERIC,
  total_in_currency NUMERIC,
  amount NUMERIC,
  notes TEXT,
  is_confirmed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    'cct_' || cct.id::TEXT AS id,
    cct.cost_center_id,
    COALESCE(cct.cost_center_name, cc.name_ar, 'مركز تكلفة') AS cost_center_name,
    COALESCE(cct.cost_center_type, cc.cost_center_type, 'variety') AS cost_center_type,
    cct.source_type,
    cct.source_id,
    CASE 
      WHEN cct.source_type = 'season_rollover' THEN 'رصيد مرحل'
      WHEN cct.source_type = 'opening_balance' THEN 'رصيد أول المدة'
      WHEN cct.source_type = 'lot_return' THEN 'مرتجع شراء محصول'
      WHEN cct.source_type = 'lot_receipt' THEN 'استلام لوط'
      WHEN cct.source_type IN ('purchase', 'crop_purchase') THEN 'فاتورة مشتريات'
      WHEN cct.source_type = 'sorting_sale' THEN 'بيع فرز'
      ELSE COALESCE(cct.source_type, 'معاملة')
    END AS shipment_no,
    cct.transaction_date AS shipment_date,
    cct.supplier_name,
    COALESCE(cct.supplier_name, 
      CASE 
        WHEN cct.source_type = 'season_rollover' THEN 'رصيد افتتاحي مرحل'
        WHEN cct.source_type = 'opening_balance' THEN 'رصيد افتتاحي'
        ELSE 'مورد محصول'
      END
    ) AS customer_name,
    cct.item_name,
    CASE 
      WHEN cct.source_type = 'season_rollover' THEN 'رصيد افتتاحي'
      ELSE cct.category
    END AS category,
    CASE WHEN cct.source_type = 'lot_return' THEN -ABS(cct.quantity) ELSE cct.quantity END AS quantity,
    cct.unit_price,
    COALESCE(cct.currency, 'EGP') AS currency,
    COALESCE(cct.exchange_rate, 1.0) AS exchange_rate,
    CASE WHEN cct.source_type IN ('lot_return', 'sorting_sale') THEN -ABS(cct.total_in_currency) ELSE cct.total_in_currency END AS total_in_currency,
    CASE WHEN cct.source_type IN ('lot_return', 'sorting_sale') THEN -ABS(cct.amount) ELSE cct.amount END AS amount,
    cct.notes,
    cct.is_confirmed
  FROM public.cost_center_transactions cct
  LEFT JOIN public.cost_centers cc ON (cc.code = cct.cost_center_id OR cc.id::text = cct.cost_center_id)
  WHERE cct.is_confirmed = TRUE
    AND (p_cost_center_id IS NULL OR cct.cost_center_id = p_cost_center_id OR cc.code = p_cost_center_id)
    AND (p_from_date IS NULL OR cct.transaction_date >= p_from_date)
    AND (p_to_date IS NULL OR cct.transaction_date <= p_to_date)
    AND (p_category IS NULL OR cct.category ILIKE p_category)
    -- Deduplication: Exclude preliminary purchase orders if detailed lot receipt exists
    AND NOT (
      cct.source_type IN ('crop_purchase', 'purchase_order')
      AND EXISTS (
        SELECT 1 FROM public.cost_center_transactions cct2
        WHERE cct2.source_type = 'lot_receipt'
          AND cct2.cost_center_id = cct.cost_center_id
          AND (
            cct2.source_id = cct.source_id
            OR (
              cct2.product_id = cct.product_id
              AND cct2.transaction_date BETWEEN cct.transaction_date - INTERVAL '7 days' AND cct.transaction_date + INTERVAL '7 days'
              AND ABS(cct2.amount - cct.amount) < 1.0
            )
          )
      )
    )
  ORDER BY 
    cct.transaction_date DESC,
    CASE 
      WHEN cct.source_type IN ('opening_balance', 'season_rollover') THEN 0
      WHEN cct.source_type IN ('purchase', 'crop_purchase') THEN 1
      WHEN cct.source_type = 'lot_receipt' THEN 2
      WHEN cct.source_type = 'lot_return' THEN 4
      ELSE 3
    END ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_cost_center_details(TEXT, DATE, DATE, TEXT) TO authenticated, service_role, anon;

-- ── 7. Backfill existing confirmed purchase invoices into cost_center_transactions ──
INSERT INTO public.cost_center_transactions (
  cost_center_id,
  cost_center_name,
  cost_center_type,
  source_type,
  source_id,
  transaction_date,
  supplier_id,
  supplier_name,
  product_id,
  raw_material_id,
  item_name,
  category,
  quantity,
  unit_price,
  currency,
  exchange_rate,
  total_in_currency,
  amount,
  notes,
  is_confirmed
)
SELECT
  COALESCE(NULLIF(pii.cost_center_id, ''), 'packing_station') AS cost_center_id,
  'محطة التعبئة والتجهيز' AS cost_center_name,
  'operational' AS cost_center_type,
  'purchase' AS source_type,
  'pii_' || pii.id::text AS source_id,
  COALESCE(pi.invoice_date::date, pi.created_at::date, CURRENT_DATE) AS transaction_date,
  pi.supplier_id::text AS supplier_id,
  s.name AS supplier_name,
  NULL::bigint AS product_id,
  pii.raw_material_id AS raw_material_id,
  COALESCE(rm.name, rm.code, 'مادة تعبئة') AS item_name,
  'مواد التعبئة' AS category,
  COALESCE(pii.quantity, 0) AS quantity,
  COALESCE(pii.unit_cost, 0) AS unit_price,
  COALESCE(pi.currency, 'EGP') AS currency,
  COALESCE(pii.exchange_rate, pi.exchange_rate, 1.0) AS exchange_rate,
  ROUND((COALESCE(pii.quantity, 0) * COALESCE(pii.unit_cost, 0))::numeric, 2) AS total_in_currency,
  ROUND((COALESCE(pii.quantity, 0) * COALESCE(pii.unit_cost, 0) * COALESCE(pii.exchange_rate, pi.exchange_rate, 1.0))::numeric, 2) AS amount,
  'فاتورة مشتريات رقم ' || COALESCE(pi.invoice_number, '') || ' - ' || COALESCE(rm.name, rm.code, '') AS notes,
  TRUE AS is_confirmed
FROM public.purchase_invoice_items pii
JOIN public.purchase_invoices pi ON pi.id = pii.invoice_id
LEFT JOIN public.suppliers s ON s.id = pi.supplier_id
LEFT JOIN public.raw_materials rm ON rm.id = pii.raw_material_id
WHERE pi.status = 'confirmed'
ON CONFLICT (source_type, source_id) DO UPDATE SET
  cost_center_id = EXCLUDED.cost_center_id,
  cost_center_name = EXCLUDED.cost_center_name,
  cost_center_type = EXCLUDED.cost_center_type,
  transaction_date = EXCLUDED.transaction_date,
  supplier_id = EXCLUDED.supplier_id,
  supplier_name = EXCLUDED.supplier_name,
  product_id = EXCLUDED.product_id,
  raw_material_id = EXCLUDED.raw_material_id,
  item_name = EXCLUDED.item_name,
  category = EXCLUDED.category,
  quantity = EXCLUDED.quantity,
  unit_price = EXCLUDED.unit_price,
  currency = EXCLUDED.currency,
  exchange_rate = EXCLUDED.exchange_rate,
  total_in_currency = EXCLUDED.total_in_currency,
  amount = EXCLUDED.amount,
  notes = EXCLUDED.notes,
  is_confirmed = EXCLUDED.is_confirmed,
  updated_at = NOW();

-- ── 8. Backfill cost_center_id in account_ledger_entries for purchase inventory ──
UPDATE public.account_ledger_entries ale
SET cost_center_id = 'packing_station'
FROM public.journal_entries je
WHERE ale.journal_entry_id = je.id
  AND je.source_type = 'purchase_inventory'
  AND ale.debit > 0
  AND ale.cost_center_id IS NULL;

-- ==============================================================================
-- Migration: 20260909000006_462_packaging_opening_balance_cost_center_sync.sql
-- Description: Include raw material initial balances (أرصدة أول المدة) in
--              cost center transactions, update rpc_record_raw_material_opening_gl,
--              and backfill historical opening stocks for packaging materials.
-- ==============================================================================

-- ── 1. Update rpc_record_raw_material_opening_gl to tag ledger lines and sync cost_center_transactions ──
CREATE OR REPLACE FUNCTION public.rpc_record_raw_material_opening_gl(
    p_raw_material_id UUID, 
    p_quantity NUMERIC, 
    p_unit_price NUMERIC, 
    p_currency TEXT, 
    p_company_id UUID DEFAULT NULL::UUID,
    p_exchange_rate NUMERIC DEFAULT NULL::NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_company_id UUID;
    v_rate NUMERIC;
    v_total_foreign NUMERIC;
    v_total_base NUMERIC;
    v_inv_acct BIGINT;
    v_equity_acct BIGINT;
    v_je_id BIGINT;
    v_material_name TEXT;
    v_desc TEXT;
    v_source_id TEXT;
    v_entry_number TEXT;
BEGIN
    IF p_quantity <= 0 OR p_unit_price <= 0 THEN
        RETURN jsonb_build_object('success', false, 'reason', 'Zero quantity or price');
    END IF;

    -- Resolve company_id with robust multi-level fallback
    v_company_id := p_company_id;
    IF v_company_id IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT tenant_id INTO v_company_id FROM public.tenant_users WHERE user_id = auth.uid() LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM public.treasuries WHERE type = 'main' AND company_id IS NOT NULL LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    SELECT name INTO v_material_name FROM public.raw_materials WHERE id = p_raw_material_id;
    v_desc := 'رصيد افتتاحي مخزون مادة تعبئة - ' || COALESCE(v_material_name, '');

    -- Exchange rate resolution:
    IF p_currency = 'EGP' OR p_currency IS NULL OR p_currency = '' THEN
        v_rate := 1.0;
    ELSIF p_exchange_rate IS NOT NULL AND p_exchange_rate > 0 THEN
        v_rate := p_exchange_rate;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
    END IF;

    IF v_rate IS NULL OR v_rate <= 0 THEN
        v_rate := 1.0;
    END IF;

    v_total_foreign := ROUND(p_quantity * p_unit_price, 2);
    v_total_base := ROUND(v_total_foreign * v_rate, 2);

    -- Resolve GL accounts:
    -- Debit 1040 (Packing Materials Inventory - non-monetary asset in base currency EGP)
    v_inv_acct := public.resolve_gl_account('1040', v_company_id);
    IF v_inv_acct IS NULL THEN
        RAISE EXCEPTION 'Packing Materials Inventory account (1040) not found in chart of accounts';
    END IF;

    -- Credit 3901 (Opening Balance Equity - EGP)
    v_equity_acct := public.resolve_opening_balance_equity_account('EGP', v_company_id);
    IF v_equity_acct IS NULL THEN
        RAISE EXCEPTION 'Opening Balance Equity account (3901 - EGP) not found in chart of accounts';
    END IF;

    v_source_id := 'raw_material_' || p_raw_material_id::text;

    -- Idempotency check: check if a journal entry already exists for this raw material
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'raw_material_opening'
      AND (source_id = v_source_id OR source_id = p_raw_material_id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        -- Atomically wipe old lines within this transaction and update header
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

        UPDATE public.journal_entries
        SET description = v_desc,
            entry_date = CURRENT_DATE,
            status = 'posted'
        WHERE id = v_je_id;
    ELSE
        v_entry_number := 'PAC-OB-' || LPAD((COALESCE((SELECT MAX(id) FROM public.journal_entries), 0) + 1)::text, 5, '0');

        INSERT INTO public.journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
        ) VALUES (
            'raw_material_opening', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
        ) RETURNING id INTO v_je_id;
    END IF;

    -- Double entry lines:
    -- Debit: 1040 (Packing Materials Inventory) tagged with cost_center_id = 'packing_station'
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id, cost_center_id
    ) VALUES (
        v_je_id, v_inv_acct, v_total_base, 0, 'EGP', v_total_base, v_desc, v_company_id, 'packing_station'
    );

    -- Credit: 3901 (Opening Balance Equity - EGP)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_equity_acct, 0, v_total_base, 'EGP', v_total_base, v_desc, v_company_id
    );

    -- Sync opening stock directly into cost_center_transactions for Cost Reports
    INSERT INTO public.cost_center_transactions (
        cost_center_id,
        cost_center_name,
        cost_center_type,
        source_type,
        source_id,
        transaction_date,
        supplier_id,
        supplier_name,
        product_id,
        raw_material_id,
        item_name,
        category,
        quantity,
        unit_price,
        currency,
        exchange_rate,
        total_in_currency,
        amount,
        notes,
        is_confirmed
    ) VALUES (
        'packing_station',
        'محطة التعبئة والتجهيز',
        'operational',
        'opening_balance',
        'ob_rm_' || p_raw_material_id::text,
        CURRENT_DATE,
        NULL,
        'رصيد أول المدة',
        NULL::bigint,
        p_raw_material_id,
        COALESCE(v_material_name, 'مادة تعبئة'),
        'مواد التعبئة',
        COALESCE(p_quantity, 0),
        COALESCE(p_unit_price, 0),
        COALESCE(p_currency, 'EGP'),
        v_rate,
        v_total_foreign,
        v_total_base,
        v_desc,
        TRUE
    )
    ON CONFLICT (source_type, source_id) DO UPDATE SET
        cost_center_id = EXCLUDED.cost_center_id,
        cost_center_name = EXCLUDED.cost_center_name,
        cost_center_type = EXCLUDED.cost_center_type,
        transaction_date = EXCLUDED.transaction_date,
        supplier_id = EXCLUDED.supplier_id,
        supplier_name = EXCLUDED.supplier_name,
        product_id = EXCLUDED.product_id,
        raw_material_id = EXCLUDED.raw_material_id,
        item_name = EXCLUDED.item_name,
        category = EXCLUDED.category,
        quantity = EXCLUDED.quantity,
        unit_price = EXCLUDED.unit_price,
        currency = EXCLUDED.currency,
        exchange_rate = EXCLUDED.exchange_rate,
        total_in_currency = EXCLUDED.total_in_currency,
        amount = EXCLUDED.amount,
        notes = EXCLUDED.notes,
        is_confirmed = EXCLUDED.is_confirmed,
        updated_at = NOW();

    RETURN jsonb_build_object(
        'success', true, 
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_number,
        'amount_egp', v_total_base,
        'quantity', p_quantity,
        'unit_price', p_unit_price,
        'currency', p_currency,
        'exchange_rate', v_rate
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_record_raw_material_opening_gl(uuid, numeric, numeric, text, uuid, numeric) TO authenticated, service_role, anon;

-- ── 2. Backfill existing raw_materials with initial_quantity into cost_center_transactions ──
INSERT INTO public.cost_center_transactions (
  cost_center_id,
  cost_center_name,
  cost_center_type,
  source_type,
  source_id,
  transaction_date,
  supplier_id,
  supplier_name,
  product_id,
  raw_material_id,
  item_name,
  category,
  quantity,
  unit_price,
  currency,
  exchange_rate,
  total_in_currency,
  amount,
  notes,
  is_confirmed
)
SELECT
  'packing_station' AS cost_center_id,
  'محطة التعبئة والتجهيز' AS cost_center_name,
  'operational' AS cost_center_type,
  'opening_balance' AS source_type,
  'ob_rm_' || rm.id::text AS source_id,
  COALESCE(rm.created_at::date, CURRENT_DATE) AS transaction_date,
  NULL AS supplier_id,
  'رصيد أول المدة' AS supplier_name,
  NULL::bigint AS product_id,
  rm.id AS raw_material_id,
  COALESCE(rm.name, rm.code, 'مادة تعبئة') AS item_name,
  'مواد التعبئة' AS category,
  COALESCE(rm.initial_quantity, 0) AS quantity,
  COALESCE(rm.initial_avg_price, 0) AS unit_price,
  COALESCE(rm.currency, 'EGP') AS currency,
  COALESCE(rm.exchange_rate, 1.0) AS exchange_rate,
  ROUND((COALESCE(rm.initial_quantity, 0) * COALESCE(rm.initial_avg_price, 0))::numeric, 2) AS total_in_currency,
  ROUND((COALESCE(rm.initial_quantity, 0) * COALESCE(rm.initial_avg_price, 0) * COALESCE(rm.exchange_rate, 1.0))::numeric, 2) AS amount,
  'رصيد أول المدة - ' || COALESCE(rm.name, rm.code, '') AS notes,
  TRUE AS is_confirmed
FROM public.raw_materials rm
WHERE rm.initial_quantity > 0
ON CONFLICT (source_type, source_id) DO UPDATE SET
  cost_center_id = EXCLUDED.cost_center_id,
  cost_center_name = EXCLUDED.cost_center_name,
  cost_center_type = EXCLUDED.cost_center_type,
  transaction_date = EXCLUDED.transaction_date,
  supplier_id = EXCLUDED.supplier_id,
  supplier_name = EXCLUDED.supplier_name,
  product_id = EXCLUDED.product_id,
  raw_material_id = EXCLUDED.raw_material_id,
  item_name = EXCLUDED.item_name,
  category = EXCLUDED.category,
  quantity = EXCLUDED.quantity,
  unit_price = EXCLUDED.unit_price,
  currency = EXCLUDED.currency,
  exchange_rate = EXCLUDED.exchange_rate,
  total_in_currency = EXCLUDED.total_in_currency,
  amount = EXCLUDED.amount,
  notes = EXCLUDED.notes,
  is_confirmed = EXCLUDED.is_confirmed,
  updated_at = NOW();

-- ── 3. Backfill cost_center_id on existing raw material opening ledger entries ──
UPDATE public.account_ledger_entries ale
SET cost_center_id = 'packing_station'
FROM public.journal_entries je
WHERE ale.journal_entry_id = je.id
  AND je.source_type = 'raw_material_opening'
  AND ale.debit > 0
  AND ale.cost_center_id IS NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';



-- ==============================================================================
-- APPENDED FROM MIGRATION 463
-- ==============================================================================

-- ==============================================================================
-- Migration: 20260909000007_463_expense_disbursal_coa_cost_center_sync.sql
-- Description:
-- 1. Add cost_center_id to public.treasury_transactions.
-- 2. RPC get_next_sub_account_code: compute next sequential account code under parent.
-- 3. RPC create_expense_sub_account: dynamic Level 4 expense sub-account creator.
-- 4. Update rpc_save_treasury_draft & rpc_update_treasury_draft to support cost_center_id.
-- 5. Update spend_custody to accept cost_center_id and tag debit line in post_journal_entry.
-- 6. Update rpc_confirm_treasury_draft to propagate cost_center_id to spend_custody.
-- 7. Update withdraw_bank_account to accept cost_center_id and tag debit line.
-- ==============================================================================

BEGIN;

-- ── 1. Add cost_center_id column to treasury_transactions ─────────────────────
ALTER TABLE public.treasury_transactions
ADD COLUMN IF NOT EXISTS cost_center_id TEXT;

CREATE INDEX IF NOT EXISTS idx_treasury_transactions_cost_center_id
ON public.treasury_transactions (cost_center_id);

-- ── 2. RPC: Get next sub-account code under parent account ────────────────────
CREATE OR REPLACE FUNCTION public.get_next_sub_account_code(
    p_parent_code TEXT,
    p_company_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id UUID := p_company_id;
    v_parent_id BIGINT;
    v_max_code BIGINT;
    v_next_code TEXT;
BEGIN
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    SELECT id INTO v_parent_id
    FROM public.accounts
    WHERE account_code = p_parent_code
      AND (company_id = v_company_id OR company_id IS NULL)
    LIMIT 1;

    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Parent account % not found', p_parent_code;
    END IF;

    -- Look for highest numeric account_code starting with p_parent_code
    SELECT MAX(account_code::BIGINT) INTO v_max_code
    FROM public.accounts
    WHERE (parent_id = v_parent_id OR account_code LIKE p_parent_code || '%')
      AND account_code ~ '^[0-9]+$'
      AND account_code != p_parent_code;

    IF v_max_code IS NOT NULL THEN
        v_next_code := (v_max_code + 1)::TEXT;
    ELSE
        IF LENGTH(p_parent_code) = 3 THEN
            v_next_code := p_parent_code || '1';
        ELSE
            v_next_code := p_parent_code || '01';
        END IF;
    END IF;

    RETURN v_next_code;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_next_sub_account_code(TEXT, UUID) TO authenticated, service_role, anon;

-- ── 3. RPC: Create dynamic expense sub-account ────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_expense_sub_account(
    p_parent_code TEXT,
    p_name_ar TEXT,
    p_name_en TEXT DEFAULT NULL,
    p_cost_center_id TEXT DEFAULT NULL,
    p_custom_code TEXT DEFAULT NULL,
    p_company_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id UUID := p_company_id;
    v_parent_id BIGINT;
    v_parent_level INT;
    v_code TEXT;
    v_account_id BIGINT;
BEGIN
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    SELECT id, level INTO v_parent_id, v_parent_level
    FROM public.accounts
    WHERE account_code = p_parent_code
      AND (company_id = v_company_id OR company_id IS NULL)
    LIMIT 1;

    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Parent account % not found', p_parent_code;
    END IF;

    IF p_custom_code IS NOT NULL AND p_custom_code != '' THEN
        v_code := p_custom_code;
    ELSE
        v_code := public.get_next_sub_account_code(p_parent_code, v_company_id);
    END IF;

    -- Make sure parent account is marked as non-leaf branch
    UPDATE public.accounts
    SET is_leaf = FALSE, allow_posting = FALSE
    WHERE id = v_parent_id;

    INSERT INTO public.accounts (
        account_code,
        name,
        account_name,
        account_type,
        parent_id,
        level,
        is_leaf,
        allow_posting,
        is_system,
        is_active,
        normal_balance,
        company_id
    ) VALUES (
        v_code,
        COALESCE(NULLIF(p_name_en, ''), p_name_ar),
        p_name_ar,
        'expense',
        v_parent_id,
        COALESCE(v_parent_level, 3) + 1,
        TRUE,
        TRUE,
        FALSE,
        TRUE,
        'Debit',
        v_company_id
    )
    RETURNING id INTO v_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'account_code', v_code,
        'name', COALESCE(NULLIF(p_name_en, ''), p_name_ar),
        'account_name', p_name_ar,
        'parent_id', v_parent_id,
        'cost_center_id', p_cost_center_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_expense_sub_account(TEXT, TEXT, TEXT, TEXT, TEXT, UUID) TO authenticated, service_role, anon;

-- ── 4 & 5. Drop legacy draft RPCs ─────────────────────────────────────────────
-- (Definitive 19-parameter versions with full cost center and branch binding are defined in Section 11)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS func_sig 
             FROM pg_proc 
             WHERE proname IN ('rpc_save_treasury_draft', 'rpc_update_treasury_draft')
               AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;


-- ── 6. Update spend_custody to accept cost_center_id and tag ledger lines ─────
CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_customer_id integer DEFAULT NULL::integer,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_clearing_agent_id bigint DEFAULT NULL::bigint,
    p_shipping_company_id bigint DEFAULT NULL::bigint,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_cost_center_id text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_je_source_type  TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_cc_name         TEXT;
    v_acct_name       TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock treasury balance row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %, المطلوب: %)', v_current_balance, p_amount;
    END IF;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Use Treasury Book Rate for disbursement in Base Currency (IAS 21)
    IF p_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    -- 3. Resolve entity and GL accounts
    IF p_customer_id IS NOT NULL THEN
        v_source_type := 'customer';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لعميل');
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id = p_customer_id;
    ELSIF p_supplier_id IS NOT NULL THEN
        v_source_type := 'supplier';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمورد');
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id = p_supplier_id;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        v_source_type := 'clearing_agent';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمخلص جمركي');
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id = p_clearing_agent_id;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        v_source_type := 'shipping_company';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لشركة شحن');
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id = p_shipping_company_id;
    ELSIF p_shareholder_id IS NOT NULL THEN
        v_source_type := 'shareholder';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمساهم');
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_shareholder_id;
    ELSE
        v_source_type := 'expense';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف مصروفات');
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id::integer, p_currency, v_company_id);

    -- 4. Update Invoice / Lot reference if provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    -- 5. Distinct Journal Entry source_type
    v_je_source_type := CASE
        WHEN p_supplier_id IS NOT NULL THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_customer_id IS NOT NULL THEN 'customer_refund'
        WHEN p_clearing_agent_id IS NOT NULL THEN 'clearing_agent_payment'
        WHEN p_shipping_company_id IS NOT NULL THEN 'shipping_company_payment'
        WHEN p_shareholder_id IS NOT NULL THEN 'shareholder_withdrawal'
        ELSE 'expense_payment'
    END;

    -- 6. Post balanced Journal Entry with cost_center_id explicitly attached to debit line
    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_expense_acct,  
                'debit', p_amount, 
                'credit', 0, 
                'base_debit', v_base_amount, 
                'base_credit', 0, 
                'currency', p_currency, 
                'description', v_desc,
                'cost_center_id', p_cost_center_id
            ),
            jsonb_build_object(
                'account_id', v_treasury_acct, 
                'debit', 0, 
                'credit', p_amount, 
                'base_debit', 0, 
                'base_credit', v_base_amount, 
                'currency', p_currency, 
                'description', v_desc
            )
        ),
        p_source_id := p_reference_id
    );

    -- 7. Update treasury balances
    UPDATE public.treasury_balances
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency;

    -- 8. Insert transaction snapshot
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'cost_center_id', p_cost_center_id,
        'rate_date', CURRENT_DATE,
        'rate_source', 'treasury_book_rate'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after,
        description, created_by, customer_id, supplier_id, clearing_agent_id,
        shipping_company_id, shareholder_id, source_type, journal_entry_id,
        expense_account_id, exchange_rate, amount_in_base_currency, currency_snapshot,
        cost_center_id
    ) VALUES (
        p_treasury_id, 'expense', p_currency, p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_customer_id, p_supplier_id, p_clearing_agent_id,
        p_shipping_company_id, p_shareholder_id, v_source_type, v_je_id,
        v_expense_acct, v_book_rate, v_base_amount, v_snapshot,
        p_cost_center_id
    ) RETURNING id INTO v_tx_id;

    -- 9. Update Counterparty Balances
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
    ELSIF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_clearing_agent_id;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_shipping_company_id;
    ELSIF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        END IF;
    END IF;

    -- 10. Sync into cost_center_transactions for Cost Reporting if cost center specified
    IF p_cost_center_id IS NOT NULL AND p_cost_center_id != '' THEN
        SELECT name_ar INTO v_cc_name FROM public.cost_centers WHERE code = p_cost_center_id OR id::text = p_cost_center_id LIMIT 1;
        SELECT COALESCE(account_name, name) INTO v_acct_name FROM public.accounts WHERE id = v_expense_acct LIMIT 1;

        INSERT INTO public.cost_center_transactions (
            cost_center_id,
            cost_center_name,
            cost_center_type,
            source_type,
            source_id,
            transaction_date,
            supplier_id,
            supplier_name,
            product_id,
            item_name,
            category,
            quantity,
            unit_price,
            currency,
            exchange_rate,
            total_in_currency,
            amount,
            notes,
            is_confirmed
        ) VALUES (
            p_cost_center_id,
            COALESCE(v_cc_name, 'مركز تكلفة'),
            'operational',
            'expense',
            'exp_' || v_tx_id::text,
            CURRENT_DATE,
            p_supplier_id,
            v_desc,
            NULL::bigint,
            COALESCE(v_acct_name, v_desc),
            'مصروفات عمومية وتشغيلية',
            1,
            p_amount,
            p_currency,
            v_book_rate,
            p_amount,
            v_base_amount,
            v_desc,
            TRUE
        )
        ON CONFLICT (source_type, source_id) DO UPDATE SET
            cost_center_id = EXCLUDED.cost_center_id,
            amount = EXCLUDED.amount,
            total_in_currency = EXCLUDED.total_in_currency,
            updated_at = NOW();
    END IF;

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_custody(bigint, text, numeric, text, integer, uuid, bigint, bigint, uuid, integer, text, text, text, text) TO authenticated, service_role, anon;

-- ── 7. Update rpc_confirm_treasury_draft to propagate cost_center_id ──────────
CREATE OR REPLACE FUNCTION public.rpc_confirm_treasury_draft(
    p_transaction_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx RECORD;
    v_res JSONB;
    v_spend_id BIGINT;
    v_receipt_type TEXT;
    v_counterparty_type TEXT;
    v_mp_source_type TEXT;
    v_mp_source_id BIGINT;
    v_cost_center_id TEXT;
    v_branch_id BIGINT;
BEGIN
    SELECT * INTO v_tx
    FROM public.treasury_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    v_cost_center_id := COALESCE(v_tx.cost_center_id, NULLIF(v_tx.payload->>'cost_center_id', ''));
    v_branch_id := COALESCE(
        v_tx.branch_id, 
        CASE WHEN (v_tx.payload->>'branch_id') ~ '^[0-9]+$' THEN (v_tx.payload->>'branch_id')::BIGINT ELSE NULL END
    );

    IF v_tx.type = 'deposit' OR v_tx.type = 'receipt' THEN
        v_receipt_type := COALESCE(v_tx.payload->>'receipt_type', 'cash');
        v_counterparty_type := v_tx.payload->>'counterparty_type';

        v_res := public.receive_payment(
            p_receipt_type      := v_receipt_type,
            p_amount            := v_tx.amount,
            p_currency          := v_tx.currency,
            p_counterparty_type := v_counterparty_type,
            p_counterparty_id   := COALESCE(v_tx.customer_id, NULLIF(v_tx.payload->>'counterparty_id', '')::integer, NULLIF(v_tx.payload->>'customer_id', '')::integer),
            p_supplier_id       := COALESCE(v_tx.supplier_id, NULLIF(v_tx.payload->>'supplier_id', '')::uuid),
            p_shareholder_id    := COALESCE(v_tx.shareholder_id, NULLIF(v_tx.payload->>'shareholder_id', '')::uuid),
            p_description       := v_tx.description,
            p_notes             := v_tx.notes,
            p_treasury_id       := v_tx.treasury_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الاستلام وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'multi_payment' OR COALESCE((v_tx.payload->>'is_multi_payment')::boolean, false) = true THEN
        v_mp_source_type := COALESCE(v_tx.payload->>'source_type', 'treasury');
        v_mp_source_id   := COALESCE(
            (v_tx.payload->>'source_id')::bigint,
            v_tx.treasury_id::bigint
        );

        v_res := public.rpc_entity_multi_payment(
            p_source_type        := v_mp_source_type,
            p_source_id          := v_mp_source_id,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_entity_type        := LOWER(COALESCE(v_tx.payload->>'entity_type', 'supplier')),
            p_entity_id          := COALESCE(v_tx.payload->>'entity_id', v_tx.supplier_id::text),
            p_description        := COALESCE(v_tx.description, 'سداد متعدد'),
            p_expense_account_id := v_tx.expense_account_id,
            p_notes              := v_tx.notes
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد السداد المتعدد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'exchange' OR v_tx.type = 'currency_exchange' THEN
        PERFORM public.exchange_currency(
            p_treasury_id   := v_tx.treasury_id::text,
            p_from_currency := COALESCE(v_tx.payload->>'from_currency', v_tx.currency),
            p_to_currency   := (v_tx.payload->>'to_currency')::text,
            p_amount_from   := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to     := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate := (v_tx.payload->>'exchange_rate')::numeric,
            p_user_id       := v_tx.created_by,
            p_transfer_mode := COALESCE(v_tx.payload->>'transfer_mode', 'exchange'),
            p_description   := COALESCE(v_tx.description, 'تحويل عملة')
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة بنجاح');

    ELSIF v_tx.type = 'expense' OR v_tx.type = 'withdrawal' THEN
        v_spend_id := public.spend_custody(
            p_treasury_id        := v_tx.treasury_id::bigint,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_description        := v_tx.description,
            p_supplier_id        := COALESCE(v_tx.supplier_id, NULLIF(v_tx.payload->>'supplier_id', '')::uuid),
            p_expense_account_id := COALESCE(
                v_tx.expense_account_id::integer, 
                NULLIF(v_tx.payload->>'expense_account_id', '')::integer, 
                v_tx.category_id::integer
            ),
            p_notes              := v_tx.notes,
            p_customer_id        := COALESCE(v_tx.customer_id, NULLIF(v_tx.payload->>'customer_id', '')::integer),
            p_clearing_agent_id  := COALESCE(v_tx.clearing_agent_id, NULLIF(v_tx.payload->>'clearing_agent_id', '')::bigint),
            p_shipping_company_id := COALESCE(v_tx.shipping_company_id, NULLIF(v_tx.payload->>'shipping_company_id', '')::bigint),
            p_shareholder_id     := COALESCE(v_tx.shareholder_id, NULLIF(v_tx.payload->>'shareholder_id', '')::uuid),
            p_cost_center_id     := v_cost_center_id,
            p_branch_id          := v_branch_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object(
            'success', true, 
            'message', 'تم تأكيد المصروف وترحيل القيد بنجاح', 
            'result', jsonb_build_object('transaction_id', v_spend_id)
        );
    ELSE
        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_treasury_draft(bigint) TO authenticated, anon, service_role;

-- ── 8. Update withdraw_bank_account to accept cost_center_id ──────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS func_sig 
             FROM pg_proc 
             WHERE proname = 'withdraw_bank_account' 
               AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

-- ==============================================================================
-- Bank GL Account Resolution Helper
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.resolve_bank_gl_account(
    p_account_id INTEGER,
    p_currency TEXT DEFAULT NULL,
    p_company_id UUID DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id BIGINT;
    v_curr TEXT := UPPER(COALESCE(p_currency, 'EGP'));
    v_code TEXT;
    v_real_company_id UUID := p_company_id;
BEGIN
    IF p_account_id IS NOT NULL THEN
        SELECT b.account_id, COALESCE(p_currency, b.currency), COALESCE(v_real_company_id, b.company_id)
        INTO v_account_id, v_curr, v_real_company_id
        FROM public.bank_accounts b
        WHERE b.id = p_account_id;

        IF v_account_id IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM public.accounts WHERE id = v_account_id) THEN
                RETURN v_account_id;
            END IF;
        END IF;
    END IF;

    v_curr := UPPER(COALESCE(v_curr, 'EGP'));
    IF v_curr = 'EGP' THEN
        v_code := '12111';
    ELSIF v_curr = 'USD' THEN
        v_code := '12112';
    ELSIF v_curr = 'EUR' THEN
        v_code := '12113';
    ELSIF v_curr = 'GBP' THEN
        v_code := '12114';
    ELSE
        v_code := '12111';
    END IF;

    v_account_id := public.resolve_gl_account(v_code, v_real_company_id);

    IF v_account_id IS NULL THEN
        IF v_curr = 'EGP' THEN
            v_code := '11201';
        ELSIF v_curr = 'USD' THEN
            v_code := '11202';
        ELSIF v_curr = 'EUR' THEN
            v_code := '11203';
        ELSIF v_curr = 'GBP' THEN
            v_code := '11204';
        END IF;
        v_account_id := public.resolve_gl_account(v_code, v_real_company_id);
    END IF;

    IF v_account_id IS NULL THEN
        v_account_id := public.resolve_gl_account('1211', v_real_company_id);
    END IF;
    IF v_account_id IS NULL THEN
        v_account_id := public.resolve_gl_account('1120', v_real_company_id);
    END IF;
    IF v_account_id IS NULL THEN
        SELECT a.id INTO v_account_id FROM public.accounts a WHERE a.code = '12111' LIMIT 1;
    END IF;

    IF v_account_id IS NOT NULL AND p_account_id IS NOT NULL THEN
        UPDATE public.bank_accounts
        SET account_id = v_account_id
        WHERE id = p_account_id AND (account_id IS NULL OR account_id != v_account_id);
    END IF;

    RETURN v_account_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_bank_gl_account(INTEGER, TEXT, UUID) TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.resolve_bank_gl_account(
    p_account_id BIGINT,
    p_currency TEXT DEFAULT NULL,
    p_company_id UUID DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.resolve_bank_gl_account(p_account_id::INTEGER, p_currency, p_company_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_bank_gl_account(BIGINT, TEXT, UUID) TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_cost_center_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_je_source_type  TEXT;
    v_source_type     TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_cc_name         TEXT;
    v_acct_name       TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_current_balance;
    END IF;

    IF v_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(v_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_je_source_type := 'bank_withdraw';
        v_desc := COALESCE(p_description, 'سحب من الحساب البنكي');
    ELSIF p_entity_type = 'supplier' THEN
        v_source_type := 'supplier_payment';
        v_je_source_type := 'purchase_payment';
        v_desc := COALESCE(p_description, 'سداد لمورد عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id = p_entity_id::uuid;
    ELSIF p_entity_type = 'customer' THEN
        v_source_type := 'customer_refund';
        v_je_source_type := 'customer_refund';
        v_desc := COALESCE(p_description, 'رد مالي لعميل عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id = p_entity_id::integer;
    ELSIF p_entity_type = 'clearing_agent' THEN
        v_source_type := 'clearing_agent_payment';
        v_je_source_type := 'clearing_agent_payment';
        v_desc := COALESCE(p_description, 'سداد لمخلص جمركي عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        v_source_type := 'shipping_company_payment';
        v_je_source_type := 'shipping_company_payment';
        v_desc := COALESCE(p_description, 'سداد لشركة شحن عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' THEN
        v_source_type := 'shareholder_withdrawal';
        v_je_source_type := 'shareholder_withdrawal';
        v_desc := COALESCE(p_description, 'مسحوبات مساهم عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_entity_id::uuid;
    ELSE
        v_source_type := 'expense_payment';
        v_je_source_type := 'expense_payment';
        v_desc := COALESCE(p_description, 'صرف مصروف عبر البنك');
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    BEGIN
        v_bank_acct := public.resolve_bank_gl_account(p_account_id::integer, v_currency, v_company_id);
    EXCEPTION WHEN OTHERS THEN
        v_bank_acct := NULL;
    END;

    IF v_bank_acct IS NULL THEN
        SELECT b.account_id INTO v_bank_acct FROM public.bank_accounts b WHERE b.id = p_account_id;
    END IF;

    IF v_bank_acct IS NULL THEN
        v_bank_acct := public.resolve_gl_account(
            CASE UPPER(v_currency) 
                WHEN 'EGP' THEN '12111' 
                WHEN 'USD' THEN '12112' 
                WHEN 'EUR' THEN '12113' 
                WHEN 'GBP' THEN '12114' 
                ELSE '12111' 
            END, 
            v_company_id
        );
    END IF;

    IF v_bank_acct IS NULL THEN
        v_bank_acct := public.resolve_gl_account(
            CASE UPPER(v_currency) 
                WHEN 'EGP' THEN '11201' 
                WHEN 'USD' THEN '11202' 
                WHEN 'EUR' THEN '11203' 
                WHEN 'GBP' THEN '11204' 
                ELSE '11201' 
            END, 
            v_company_id
        );
    END IF;

    IF v_bank_acct IS NULL THEN
        SELECT a.id INTO v_bank_acct FROM public.accounts a WHERE a.code = '12111' LIMIT 1;
    END IF;

    -- Post balanced Journal Entry with cost_center_id on debit line
    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_expense_acct,
                'debit', p_amount,
                'credit', 0,
                'base_debit', v_base_amount,
                'base_credit', 0,
                'currency', v_currency,
                'description', v_desc,
                'cost_center_id', p_cost_center_id
            ),
            jsonb_build_object(
                'account_id', v_bank_acct,
                'debit', 0,
                'credit', p_amount,
                'base_debit', 0,
                'base_credit', v_base_amount,
                'currency', v_currency,
                'description', v_desc
            )
        ),
        p_source_id := p_reference_id
    );

    UPDATE public.bank_accounts
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'cost_center_id', p_cost_center_id,
        'rate_date', CURRENT_DATE,
        'rate_source', 'bank_book_rate'
    );

    INSERT INTO public.bank_transactions (
        bank_account_id, type, amount, balance_after, currency,
        description, notes, counterparty_name, created_by,
        journal_entry_id, expense_account_id, exchange_rate,
        amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_new_balance, v_currency,
        v_desc, p_notes, p_counterparty_name, auth.uid(),
        v_je_id, v_expense_acct, v_book_rate,
        v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    -- Sync into cost_center_transactions if cost center specified
    IF p_cost_center_id IS NOT NULL AND p_cost_center_id != '' THEN
        SELECT name_ar INTO v_cc_name FROM public.cost_centers WHERE code = p_cost_center_id OR id::text = p_cost_center_id LIMIT 1;
        SELECT COALESCE(account_name, name) INTO v_acct_name FROM public.accounts WHERE id = v_expense_acct LIMIT 1;

        INSERT INTO public.cost_center_transactions (
            cost_center_id,
            cost_center_name,
            cost_center_type,
            source_type,
            source_id,
            transaction_date,
            supplier_name,
            product_id,
            item_name,
            category,
            quantity,
            unit_price,
            currency,
            exchange_rate,
            total_in_currency,
            amount,
            notes,
            is_confirmed
        ) VALUES (
            p_cost_center_id,
            COALESCE(v_cc_name, 'مركز تكلفة'),
            'operational',
            'expense',
            'bank_exp_' || v_tx_id::text,
            CURRENT_DATE,
            p_counterparty_name,
            NULL::bigint,
            COALESCE(v_acct_name, v_desc),
            'مصروفات عمومية وتشغيلية',
            1,
            p_amount,
            v_currency,
            v_book_rate,
            p_amount,
            v_base_amount,
            v_desc,
            TRUE
        )
        ON CONFLICT (source_type, source_id) DO UPDATE SET
            cost_center_id = EXCLUDED.cost_center_id,
            amount = EXCLUDED.amount,
            total_in_currency = EXCLUDED.total_in_currency,
            updated_at = NOW();
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(bigint, numeric, text, bigint, text, text, text, text, text, text, text) TO authenticated, service_role, anon;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ==============================================================================
-- APPENDED FROM MIGRATION 465
-- ==============================================================================

-- ==============================================================================
-- Migration: 20260909000009_465_automated_cost_category_coa_and_cost_center_sync.sql
-- Description:
-- 1. Add account_id and cost_center_id columns to public.cost_report_categories.
-- 2. Add cost_center_id column to public.accounts.
-- 3. Function fn_resolve_category_parent_account: determines parent account under Root 3.
-- 4. Trigger function fn_sync_cost_report_category_to_coa_and_cost_center:
--    - Creates corresponding sub-account in Chart of Accounts (under Root 3).
--    - Creates corresponding Cost Center in public.cost_centers.
--    - Synchronizes cross-references between category, account, and cost center.
-- 5. Updated RPC create_cost_report_category, update_cost_report_category, list_cost_report_categories.
-- 6. Updated spend_custody: fallback to account / category cost center and balanced JE debit tagging.
-- 7. Backfill existing 7 categories in cost_report_categories.
-- ==============================================================================

BEGIN;

-- ── 1. Schema Enhancements ───────────────────────────────────────────────────

ALTER TABLE public.cost_report_categories
ADD COLUMN IF NOT EXISTS account_id BIGINT REFERENCES public.accounts(id) ON DELETE SET NULL;

ALTER TABLE public.cost_report_categories
ADD COLUMN IF NOT EXISTS cost_center_id TEXT;

ALTER TABLE public.accounts
ADD COLUMN IF NOT EXISTS cost_center_id TEXT;

CREATE INDEX IF NOT EXISTS idx_cost_report_categories_account_id
ON public.cost_report_categories(account_id);

CREATE INDEX IF NOT EXISTS idx_cost_report_categories_cost_center_id
ON public.cost_report_categories(cost_center_id);

CREATE INDEX IF NOT EXISTS idx_accounts_cost_center_id
ON public.accounts(cost_center_id);

-- ── 2. RPC: Robust Collision-Proof Next Sub-Account Code ────────────────────

CREATE OR REPLACE FUNCTION public.get_next_sub_account_code(
    p_parent_code TEXT,
    p_company_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id UUID := p_company_id;
    v_parent_id BIGINT;
    v_next_code TEXT;
    v_suffix INT;
BEGIN
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    SELECT id INTO v_parent_id
    FROM public.accounts
    WHERE account_code = p_parent_code
      AND (company_id = v_company_id OR company_id IS NULL)
    LIMIT 1;

    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Parent account % not found', p_parent_code;
    END IF;

    -- 1. Try single-digit extension: p_parent_code || '1' ... '9'
    FOR v_suffix IN 1..9 LOOP
        v_next_code := p_parent_code || v_suffix::TEXT;
        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = v_next_code) THEN
            RETURN v_next_code;
        END IF;
    END LOOP;

    -- 2. If single digits are exhausted (e.g. 3211-3219), switch to 2-digit extension (32101..32199)
    FOR v_suffix IN 1..99 LOOP
        v_next_code := p_parent_code || LPAD(v_suffix::TEXT, 2, '0');
        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = v_next_code) THEN
            RETURN v_next_code;
        END IF;
    END LOOP;

    -- 3. If 2 digits exhausted, switch to 3-digit extension (321001..321999)
    FOR v_suffix IN 1..999 LOOP
        v_next_code := p_parent_code || LPAD(v_suffix::TEXT, 3, '0');
        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = v_next_code) THEN
            RETURN v_next_code;
        END IF;
    END LOOP;

    RETURN p_parent_code || '_' || EXTRACT(EPOCH FROM NOW())::INT::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_next_sub_account_code(TEXT, UUID) TO authenticated, service_role, anon;

-- ── 3. Helper: Resolve Parent Account under Root 3 ────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_resolve_category_parent_account(
    p_scope TEXT,
    p_name TEXT,
    p_supplier_type TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_clean_name TEXT := LOWER(TRIM(COALESCE(p_name, '')));
    v_clean_scope TEXT := LOWER(TRIM(COALESCE(p_scope, 'all')));
    v_clean_type TEXT := LOWER(TRIM(COALESCE(p_supplier_type, '')));
BEGIN
    -- 1. Station Suppliers / Operation Costs -> Level 4 Control: 3124 (تكاليف ومصروفات تشغيل المحطات)
    IF v_clean_type = 'station' OR v_clean_name ~* '(محطة|تبريد|تشغيل|حفظ مبرد|تقفيل كرتون|تعتيق|تدوير|تبخير|station)' THEN
        RETURN '3124';
    END IF;

    -- 2. Deduction Suppliers / Inspection Fees -> Level 4 Control: 3126 (رسوم فحص وتخصيمات التشغيل)
    IF v_clean_type IN ('deduction', 'deductions') OR v_clean_name ~* '(تخصيم|فحص|تحليل|عينة|عينات|حجر زراعي|سلامة غذاء|وجات|deduction|inspection)' THEN
        RETURN '3126';
    END IF;

    -- 3. Packaging waste / scrap -> 3124 (هالك وفاقد التشغيل)
    IF v_clean_scope = 'packing_waste' OR v_clean_name ~* '(هالك|فاقد|تالف|توالف|waste|scrap)' THEN
        RETURN '3124';
    END IF;

    -- 4. Direct Sales Costs / Produce purchases -> 3411 (تكاليف المبيعات)
    IF v_clean_name ~* '(محصول|محاصيل|شراء خام|فراولة|مانجو|مبيعات|خام|produce|crop)' THEN
        RETURN '3411';
    END IF;

    -- 5. Shipping, Freight, Customs, Logistics -> 3411 (مصروفات الشحن والتخليص واللوجستيات)
    IF v_clean_scope = 'shipment' OR v_clean_name ~* '(شحن|نولون|تخليص|لوجست|مشال|نقل|جمارك|مخلص|shipping|freight|customs|logistics)' THEN
        RETURN '3411';
    END IF;

    -- 6. General & Administrative -> 3131 / 3132
    IF v_clean_scope IN ('general_admin', 'admin') THEN
        IF v_clean_name ~* '(استشار|اشتراك|رسوم|أتعاب|مراجعة|legal|consulting)' THEN
            RETURN '3132';
        END IF;
        RETURN '3131';
    END IF;

    -- 7. Fallback based on scope
    IF v_clean_scope = 'packing' THEN
        RETURN '3124';
    ELSIF v_clean_scope = 'shipment' THEN
        RETURN '3411';
    ELSE
        RETURN '3131';
    END IF;
END;
$$;

-- Backward compatible 2-arg signature
CREATE OR REPLACE FUNCTION public.fn_resolve_category_parent_account(
    p_scope TEXT,
    p_name TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT public.fn_resolve_category_parent_account(p_scope, p_name, NULL);
$$;

GRANT EXECUTE ON FUNCTION public.fn_resolve_category_parent_account(TEXT, TEXT, TEXT) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolve_category_parent_account(TEXT, TEXT) TO authenticated, service_role, anon;

-- ── 3. Trigger Function: Sync Category to COA & Cost Center ───────────────────

CREATE OR REPLACE FUNCTION public.fn_sync_cost_report_category_to_coa_and_cost_center()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_company_id UUID;
    v_parent_code TEXT;
    v_parent_id BIGINT;
    v_parent_level INT;
    v_new_account_id BIGINT := NEW.account_id;
    v_cat_name TEXT := TRIM(NEW.name);
BEGIN
    -- Prevent recursive trigger loops
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Resolve Company ID
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- ──────────────────────────────────────────────────────────────────────────
    -- CHART OF ACCOUNTS (ROOT 3) RESOLUTION ONLY (NO AUTO-CREATION OF COST CENTERS)
    -- ──────────────────────────────────────────────────────────────────────────
    IF v_new_account_id IS NULL THEN
        -- Match approved leaf accounts based on category name
        SELECT id INTO v_new_account_id FROM public.accounts 
        WHERE (account_name = v_cat_name OR name = v_cat_name) AND is_leaf = TRUE 
        LIMIT 1;

        IF v_new_account_id IS NULL THEN
            IF v_cat_name IN ('مواد التعبئة', 'تعبئة وتغليف') THEN
                SELECT id INTO v_new_account_id FROM public.accounts WHERE account_code = '33111' LIMIT 1;
            ELSIF v_cat_name = 'تكلفة المحاصيل' THEN
                SELECT id INTO v_new_account_id FROM public.accounts WHERE account_code = '34111' LIMIT 1;
            ELSIF v_cat_name IN ('تكلفة شركات الشحن', 'لوجستيك ونقل', 'تكلفة المخلصين') THEN
                SELECT id INTO v_new_account_id FROM public.accounts WHERE account_code = '34114' LIMIT 1;
            ELSE
                SELECT id INTO v_new_account_id FROM public.accounts WHERE account_code = '31310' LIMIT 1;
            END IF;
        END IF;
    END IF;

    -- Update category record with resolved account only
    UPDATE public.cost_report_categories
    SET account_id = v_new_account_id
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_cost_report_category ON public.cost_report_categories;

CREATE TRIGGER trg_sync_cost_report_category
AFTER INSERT OR UPDATE OF name, scope
ON public.cost_report_categories
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_cost_report_category_to_coa_and_cost_center();

-- ── 4. Updated RPC: create_cost_report_category ───────────────────────────────

DROP FUNCTION IF EXISTS public.create_cost_report_category(TEXT, TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.create_cost_report_category(TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.create_cost_report_category(TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.create_cost_report_category(TEXT) CASCADE;

CREATE OR REPLACE FUNCTION public.create_cost_report_category(
    p_name        TEXT,
    p_scope       TEXT DEFAULT 'both',
    p_parent_code TEXT DEFAULT NULL,
    p_supplier_type TEXT DEFAULT 'general'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_parent_code   TEXT;
    v_next_code     TEXT;
    v_account_id    BIGINT;
    v_cost_center_id TEXT;
    v_cat_id        INTEGER;
    v_company_id    UUID;
    v_parent_id     BIGINT;
    v_row           RECORD;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- 1. Resolve parent account code under Root 3
    IF p_parent_code IS NOT NULL AND p_parent_code != '' AND p_parent_code != '312' THEN
        v_parent_code := p_parent_code;
    ELSE
        v_parent_code := public.fn_resolve_category_parent_account(p_scope, p_name, p_supplier_type);
    END IF;

    -- 2. Verify or create parent control account (Level 4: 3124 or 3126)
    SELECT id INTO v_parent_id
    FROM public.accounts
    WHERE account_code = v_parent_code
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_id IS NULL AND v_parent_code IN ('3124', '3126') THEN
        INSERT INTO public.accounts (
            account_code, name, account_name, account_type,
            normal_balance, is_leaf, allow_posting, is_active, level,
            parent_id, company_id
        ) VALUES (
            v_parent_code,
            CASE WHEN v_parent_code = '3124' THEN 'Station Packing & Operations Control' ELSE 'Inspection & Deduction Fees Control' END,
            CASE WHEN v_parent_code = '3124' THEN 'تكاليف ومصروفات تشغيل المحطات' ELSE 'رسوم فحص وتخصيمات التشغيل' END,
            'expense', 'Debit', FALSE, FALSE, TRUE, 4,
            (SELECT id FROM public.accounts WHERE account_code = '312' LIMIT 1),
            v_company_id
        ) RETURNING id INTO v_parent_id;
    END IF;

    -- 3. Get next 5-digit sub-account code
    v_next_code := public.get_next_sub_account_code(v_parent_code, v_company_id);

    -- 4. Find or create sub-account at Level 5
    IF v_next_code IS NOT NULL THEN
        SELECT id INTO v_account_id
        FROM public.accounts
        WHERE account_code = v_next_code
          AND (company_id = v_company_id OR company_id IS NULL)
        LIMIT 1;

        IF v_account_id IS NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type,
                normal_balance, is_leaf, allow_posting, is_active, level,
                parent_id, company_id
            ) VALUES (
                v_next_code, TRIM(p_name), TRIM(p_name), 'expense',
                'Debit', TRUE, TRUE, TRUE, 5,
                v_parent_id,
                v_company_id
            )
            ON CONFLICT (account_code) DO UPDATE
            SET is_active = TRUE,
                allow_posting = TRUE
            RETURNING id INTO v_account_id;
        END IF;
    END IF;

    -- 5. Insert or update category
    INSERT INTO public.cost_report_categories (name, scope, is_system, type, account_id, supplier_type)
    VALUES (TRIM(p_name), p_scope, FALSE, 'direct', v_account_id, COALESCE(p_supplier_type, 'general'))
    ON CONFLICT (name) DO UPDATE 
    SET scope = CASE 
            WHEN cost_report_categories.scope != EXCLUDED.scope THEN 'both' 
            ELSE cost_report_categories.scope 
        END,
        account_id = COALESCE(cost_report_categories.account_id, EXCLUDED.account_id),
        supplier_type = COALESCE(EXCLUDED.supplier_type, cost_report_categories.supplier_type)
    RETURNING id INTO v_cat_id;

    -- 6. Cost centers are created manually only (no automatic cost center generation)
    v_cost_center_id := NULL;

    -- 8. Fetch the full updated record
    SELECT 
        c.id,
        c.name,
        c.scope,
        c.is_system,
        c.type,
        c.account_id,
        a.account_code,
        COALESCE(a.account_name, a.name) AS account_name,
        c.cost_center_id,
        COALESCE(cc.name_ar, cc.name, c.cost_center_id) AS cost_center_name,
        c.supplier_type
    INTO v_row
    FROM public.cost_report_categories c
    LEFT JOIN public.accounts a ON a.id = c.account_id
    LEFT JOIN public.cost_centers cc ON cc.code = c.cost_center_id
    WHERE c.id = v_cat_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'id', v_row.id,
        'name', v_row.name,
        'scope', v_row.scope,
        'is_system', v_row.is_system,
        'account_id', v_row.account_id,
        'account_code', v_row.account_code,
        'account_name', v_row.account_name,
        'cost_center_id', v_row.cost_center_id,
        'cost_center_name', v_row.cost_center_name,
        'supplier_type', v_row.supplier_type
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_cost_report_category(TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role, anon;

-- ── 5. Updated RPC: update_cost_report_category ───────────────────────────────

DROP FUNCTION IF EXISTS public.update_cost_report_category(INTEGER, TEXT, TEXT, BIGINT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_cost_report_category(INTEGER, TEXT, TEXT, BIGINT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_cost_report_category(INTEGER, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_cost_report_category(INTEGER) CASCADE;

CREATE OR REPLACE FUNCTION public.update_cost_report_category(
    p_id    INTEGER,
    p_name  TEXT DEFAULT NULL,
    p_scope TEXT DEFAULT NULL,
    p_account_id BIGINT DEFAULT NULL,
    p_cost_center_id TEXT DEFAULT NULL,
    p_supplier_type TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.cost_report_categories
    SET name  = COALESCE(NULLIF(TRIM(p_name), ''), name),
        scope = COALESCE(NULLIF(TRIM(p_scope), ''), scope),
        account_id = COALESCE(p_account_id, account_id),
        cost_center_id = COALESCE(NULLIF(TRIM(p_cost_center_id), ''), cost_center_id),
        supplier_type = COALESCE(NULLIF(TRIM(p_supplier_type), ''), supplier_type)
    WHERE id = p_id;

    IF p_account_id IS NOT NULL AND p_cost_center_id IS NOT NULL THEN
        UPDATE public.accounts
        SET cost_center_id = p_cost_center_id
        WHERE id = p_account_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'id', p_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_cost_report_category(INTEGER, TEXT, TEXT, BIGINT, TEXT, TEXT) TO authenticated, service_role, anon;

-- Function to delete cost report category
CREATE OR REPLACE FUNCTION public.delete_cost_report_category(p_id INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    DELETE FROM public.cost_report_categories WHERE id = p_id;
    RETURN jsonb_build_object('success', TRUE, 'id', p_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_cost_report_category(INT) TO authenticated, service_role, anon;

-- ── 6. Updated RPC: list_cost_report_categories ───────────────────────────────

DROP FUNCTION IF EXISTS public.list_cost_report_categories(TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.list_cost_report_categories() CASCADE;

CREATE OR REPLACE FUNCTION public.list_cost_report_categories(
    p_scope TEXT DEFAULT NULL
)
RETURNS TABLE (
    id INTEGER,
    name TEXT,
    scope TEXT,
    is_system BOOLEAN,
    type TEXT,
    account_id BIGINT,
    account_code TEXT,
    account_name TEXT,
    cost_center_id TEXT,
    cost_center_name TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT 
        c.id,
        c.name,
        c.scope,
        c.is_system,
        c.type,
        c.account_id,
        a.account_code,
        COALESCE(a.account_name, a.name) AS account_name,
        c.cost_center_id,
        COALESCE(cc.name_ar, cc.name, c.cost_center_id) AS cost_center_name,
        c.created_at
    FROM public.cost_report_categories c
    LEFT JOIN public.accounts a ON a.id = c.account_id
    LEFT JOIN public.cost_centers cc ON cc.code = c.cost_center_id
    WHERE (p_scope IS NULL OR c.scope = p_scope OR c.scope = 'both' OR c.scope = 'all')
    ORDER BY c.id;
$$;

GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(TEXT) TO authenticated, service_role, anon;

-- ── 7. Enhanced spend_custody: Unified Disbursal Binding ──────────────────────

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS func_sig 
             FROM pg_proc 
             WHERE proname = 'spend_custody' 
               AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id         BIGINT,
    p_currency            TEXT,
    p_amount              NUMERIC,
    p_description         TEXT,
    p_supplier_id         UUID DEFAULT NULL,
    p_expense_account_id  BIGINT DEFAULT NULL,
    p_notes               TEXT DEFAULT NULL,
    p_customer_id         INTEGER DEFAULT NULL,
    p_clearing_agent_id   INTEGER DEFAULT NULL,
    p_shipping_company_id INTEGER DEFAULT NULL,
    p_shareholder_id      UUID DEFAULT NULL,
    p_cost_center_id      TEXT DEFAULT NULL,
    p_reference_type      TEXT DEFAULT NULL,
    p_reference_id        TEXT DEFAULT NULL,
    p_category_id         BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_current_cost_base NUMERIC;
    v_current_book_rate NUMERIC;
    v_new_balance     NUMERIC;
    v_new_cost_base   NUMERIC;
    v_new_book_rate   NUMERIC;
    v_tx_id           BIGINT;
    v_je_id           BIGINT;
    v_expense_acct    BIGINT := p_expense_account_id;
    v_treasury_acct   BIGINT;
    v_desc            TEXT;
    v_company_id      UUID;
    v_source_type     TEXT;
    v_je_source_type  TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_cost_center_id  TEXT := TRIM(COALESCE(p_cost_center_id, ''));
    v_resolved_cc     TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock treasury balance row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %, المطلوب: %)', v_current_balance, p_amount;
    END IF;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Use Treasury Book Rate for disbursement in Base Currency (IAS 21)
    IF p_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    -- 3. Resolve entity and GL accounts
    IF p_customer_id IS NOT NULL THEN
        v_source_type := 'customer';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لعميل');
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id = p_customer_id;
    ELSIF p_supplier_id IS NOT NULL THEN
        v_source_type := 'supplier';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمورد');
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id = p_supplier_id;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        v_source_type := 'clearing_agent';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمخلص جمركي');
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id = p_clearing_agent_id;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        v_source_type := 'shipping_company';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لشركة شحن');
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id = p_shipping_company_id;
    ELSIF p_shareholder_id IS NOT NULL THEN
        v_source_type := 'shareholder';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمساهم');
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_shareholder_id;
    ELSE
        v_source_type := 'expense';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف مصروفات');
    END IF;

    -- Automatic resolution from Category if expense account not specified
    IF v_expense_acct IS NULL AND p_category_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct
        FROM public.cost_report_categories
        WHERE id = p_category_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    -- Automatic resolution of Cost Center if not explicitly provided
    IF v_cost_center_id = '' THEN
        -- Check Account default Cost Center
        IF v_expense_acct IS NOT NULL THEN
            SELECT cost_center_id INTO v_resolved_cc
            FROM public.accounts
            WHERE id = v_expense_acct;
            IF v_resolved_cc IS NOT NULL AND TRIM(v_resolved_cc) != '' THEN
                v_cost_center_id := v_resolved_cc;
            END IF;
        END IF;

        -- Check Category default Cost Center
        IF v_cost_center_id = '' AND p_category_id IS NOT NULL THEN
            SELECT cost_center_id INTO v_resolved_cc
            FROM public.cost_report_categories
            WHERE id = p_category_id;
            IF v_resolved_cc IS NOT NULL AND TRIM(v_resolved_cc) != '' THEN
                v_cost_center_id := v_resolved_cc;
            END IF;
        END IF;
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id::integer, p_currency, v_company_id);

    -- 4. Update Invoice / Lot reference if provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    -- 5. Distinct Journal Entry source_type
    v_je_source_type := CASE
        WHEN p_supplier_id IS NOT NULL THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_customer_id IS NOT NULL THEN 'customer_refund'
        WHEN p_clearing_agent_id IS NOT NULL THEN 'clearing_agent_payment'
        WHEN p_shipping_company_id IS NOT NULL THEN 'shipping_company_payment'
        WHEN p_shareholder_id IS NOT NULL THEN 'shareholder_withdrawal'
        ELSE 'expense_payment'
    END;

    -- 6. Post balanced Journal Entry with cost_center_id explicitly attached to debit line
    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_expense_acct,  
                'debit', p_amount, 
                'credit', 0, 
                'base_debit', v_base_amount, 
                'base_credit', 0, 
                'currency', p_currency, 
                'description', v_desc,
                'cost_center_id', NULLIF(v_cost_center_id, '')
            ),
            jsonb_build_object(
                'account_id', v_treasury_acct, 
                'debit', 0, 
                'credit', p_amount, 
                'base_debit', 0, 
                'base_credit', v_base_amount, 
                'currency', p_currency, 
                'description', v_desc
            )
        ),
        p_source_id := p_reference_id
    );

    -- 7. Update treasury balances
    UPDATE public.treasury_balances
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency;

    -- 8. Insert transaction snapshot
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'cost_center_id', NULLIF(v_cost_center_id, ''),
        'rate_date', CURRENT_DATE,
        'rate_source', 'treasury_book_rate'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after,
        description, notes, source_type, source_id, created_by,
        journal_entry_id, status, supplier_id, customer_id,
        clearing_agent_id, shipping_company_id, shareholder_id,
        transaction_date, payload, category_id, cost_center_id
    ) VALUES (
        p_treasury_id, 'expense', p_currency, p_amount, v_current_balance, v_new_balance,
        v_desc, p_notes, v_source_type, v_je_id::TEXT, auth.uid(),
        v_je_id, 'completed', p_supplier_id::TEXT, p_customer_id::TEXT,
        p_clearing_agent_id::TEXT, p_shipping_company_id::TEXT, p_shareholder_id::TEXT,
        CURRENT_DATE, v_snapshot, p_category_id::TEXT, NULLIF(v_cost_center_id, '')
    )
    RETURNING id INTO v_tx_id;

    -- 9. Record in cost_center_transactions for operational / variety reporting
    IF v_cost_center_id != '' AND v_cost_center_id != 'ALL' THEN
        INSERT INTO public.cost_center_transactions (
            cost_center_id,
            account_id,
            journal_entry_id,
            amount,
            transaction_type,
            reference_type,
            reference_id,
            description,
            company_id
        ) VALUES (
            v_cost_center_id,
            v_expense_acct,
            v_je_id,
            v_base_amount,
            'expense',
            'treasury_disbursal',
            v_tx_id::TEXT,
            v_desc,
            v_company_id
        );
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance_before', v_current_balance,
        'balance_after', v_new_balance,
        'cost_base_after', v_new_cost_base,
        'book_rate_after', v_new_book_rate,
        'cost_center_id', NULLIF(v_cost_center_id, '')
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_custody(BIGINT, TEXT, NUMERIC, TEXT, UUID, BIGINT, TEXT, INTEGER, INTEGER, INTEGER, UUID, TEXT, TEXT, TEXT, BIGINT) TO authenticated, service_role, anon;

-- ── 7b. spend_with_category: Unified Disbursal Binding Parity ────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS func_sig 
             FROM pg_proc 
             WHERE proname = 'spend_with_category' 
               AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_category_id integer DEFAULT NULL::integer,
    p_customer_id integer DEFAULT NULL::integer,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_clearing_agent_id bigint DEFAULT NULL::bigint,
    p_shipping_company_id bigint DEFAULT NULL::bigint,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_cost_center_id text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.spend_custody(
        p_treasury_id         := p_treasury_id,
        p_currency            := p_currency,
        p_amount              := p_amount,
        p_description         := p_description,
        p_supplier_id         := p_supplier_id,
        p_expense_account_id  := p_expense_account_id::bigint,
        p_notes               := p_notes,
        p_customer_id         := p_customer_id,
        p_clearing_agent_id   := p_clearing_agent_id::integer,
        p_shipping_company_id := p_shipping_company_id::integer,
        p_shareholder_id      := p_shareholder_id,
        p_cost_center_id      := p_cost_center_id,
        p_reference_type      := p_reference_type,
        p_reference_id        := p_reference_id,
        p_category_id         := p_category_id::bigint
    );
    RETURN (v_res->>'transaction_id')::bigint;
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_with_category(bigint, text, numeric, text, integer, integer, uuid, bigint, bigint, uuid, integer, text, text, text, text) TO authenticated, service_role, anon;

-- ── 8. Backfill Existing Categories ───────────────────────────────────────────

DO $$
DECLARE
    r RECORD;
    v_company_id UUID;
    v_parent_code TEXT;
    v_parent_id BIGINT;
    v_parent_level INT;
    v_acct_id BIGINT;
    v_acct_code TEXT;
    v_cc_code TEXT;
    v_cc_color TEXT;
    v_cc_icon TEXT;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    FOR r IN SELECT * FROM public.cost_report_categories ORDER BY id LOOP
        -- Account Resolution (Bind to standard approved COA)
        v_acct_id := r.account_id;
        IF v_acct_id IS NULL THEN
            SELECT id INTO v_acct_id FROM public.accounts WHERE (account_name = r.name OR name = r.name) AND is_leaf = TRUE LIMIT 1;
            IF v_acct_id IS NULL THEN
                SELECT id INTO v_acct_id FROM public.accounts WHERE account_code = '31310' LIMIT 1;
            END IF;
        END IF;

        UPDATE public.cost_report_categories
        SET account_id = v_acct_id,
            cost_center_id = NULL
        WHERE id = r.id;
    END LOOP;

    -- Ensure permanent deletion of stale accounts (only if unreferenced by foreign keys)
    DELETE FROM public.accounts a
    WHERE a.account_code IN ('3121', '3123', '3212', '3222', '3223', '3224', '3412')
      AND NOT EXISTS (SELECT 1 FROM public.shareholders sh WHERE sh.account_id = a.id)
      AND NOT EXISTS (SELECT 1 FROM public.account_ledger_entries ale WHERE ale.account_id = a.id)
      AND NOT EXISTS (SELECT 1 FROM public.cost_report_categories crc WHERE crc.account_id = a.id);
END;
$$;

COMMIT;


NOTIFY pgrst, 'reload schema';

-- ==============================================================================
-- APPENDED FROM MIGRATION 466
-- ==============================================================================

-- ============================================================================
-- Migration 466: Fix Purchase Lot Return Multi-Currency Balances & Ledger Currency
-- ============================================================================
-- Purpose:
--   1. Update rpc_process_lot_return to:
--      - Deduct converted equivalent in EGP (v_return_value * exchange_rate) from suppliers.outstanding_balance.
--      - Deduct native currency amount from suppliers.current_balances_by_currency.
--      - Stamp the native currency on the inserted ledger_entries record.
--   2. Backfill existing lot_return ledger_entries with their native lot currency.
-- ============================================================================

BEGIN;

-- 1. Schema Enhancements
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS current_balances_by_currency JSONB DEFAULT '{}'::jsonb;

-- 2. Backfill currency for existing lot_returns in ledger_entries
UPDATE ledger_entries le
SET currency = COALESCE(lr.currency, 'EGP')
FROM lot_returns rt
JOIN lot_receipts lr ON lr.id = rt.lot_receipt_id
WHERE le.reference_type = 'lot_return'
  AND (rt.id::TEXT = le.reference_text OR rt.id::TEXT = le.reference_id::TEXT)
  AND (le.currency IS NULL OR le.currency = 'EGP')
  AND lr.currency IS NOT NULL
  AND lr.currency <> 'EGP';

-- 3. Update rpc_process_lot_return
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'rpc_process_lot_return'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_process_lot_return(
  p_lot_id bigint,
  p_return_quantity numeric,
  p_return_price numeric DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_user_id uuid DEFAULT NULL,
  p_batch_id bigint DEFAULT NULL,
  p_cost_center_id text DEFAULT NULL,
  p_station_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot record;
  v_unit_cost numeric;
  v_return_value numeric;
  v_return_value_egp numeric;
  v_return_id bigint;
  v_target_station bigint;
  v_product_name text;
  v_company_id uuid;
  v_inventory_account_id bigint;
  v_supplier_leaf_account_id bigint;
  v_je_id bigint;
  v_desc text;
  v_cur text;
  v_supplier_name text;
  v_canon_crop text;
  v_slug text;
  v_cc_id text;
  v_cc_name text;
BEGIN
  -- 1. Load lot and validate
  SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'اللوط غير موجود');
  END IF;

  IF v_lot.is_confirmed != true THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا يمكن إرجاع لوط غير مؤكد');
  END IF;

  IF p_return_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'كمية الإرجاع يجب أن تكون أكبر من صفر');
  END IF;

  v_target_station := COALESCE(p_station_id, v_lot.station_id);

  -- Determine unit cost
  IF p_return_price IS NOT NULL AND p_return_price > 0 THEN
    v_unit_cost := p_return_price;
  ELSE
    v_unit_cost := COALESCE(v_lot.fruit_cost_per_kg, 0);
  END IF;

  v_return_value := p_return_quantity * v_unit_cost;
  v_product_name := COALESCE(v_lot.product_name, 'محصول خام');
  v_cur := COALESCE(NULLIF(v_lot.currency, ''), 'EGP');

  -- 2. Insert lot_return record
  INSERT INTO lot_returns (
    lot_receipt_id,
    supplier_id,
    station_id,
    returned_quantity,
    return_value,
    notes,
    created_by,
    created_at
  ) VALUES (
    v_lot.id,
    v_lot.supplier_id,
    v_target_station,
    p_return_quantity,
    v_return_value,
    p_notes,
    p_user_id,
    now()
  )
  RETURNING id INTO v_return_id;

  -- 2.b Deduct from station inventory / batches
  IF p_batch_id IS NOT NULL AND p_batch_id > 0 THEN
    UPDATE public.station_product_batches
    SET remaining_quantity = GREATEST(0, remaining_quantity - p_return_quantity)
    WHERE id = p_batch_id;
  ELSIF v_target_station IS NOT NULL THEN
    UPDATE public.station_product_batches
    SET remaining_quantity = GREATEST(0, remaining_quantity - p_return_quantity)
    WHERE id = (
      SELECT id FROM public.station_product_batches
      WHERE station_id = v_target_station
        AND (product_code = v_lot.lot_number OR product_name = v_lot.product_name)
        AND remaining_quantity > 0
      ORDER BY id ASC
      LIMIT 1
    );
  END IF;

  IF v_target_station IS NOT NULL THEN
    UPDATE public.station_products
    SET quantity = (
      SELECT COALESCE(SUM(remaining_quantity), 0)
      FROM public.station_product_batches
      WHERE station_id = v_target_station
        AND (product_name = v_lot.product_name OR product_code = v_lot.lot_number)
    ),
    updated_at = NOW()
    WHERE station_id = v_target_station
      AND (product_name = v_lot.product_name OR product_code = v_lot.lot_number);
  END IF;

  -- 3. Adjust supplier outstanding balance (converted to EGP) and current_balances_by_currency (native)
  IF v_lot.supplier_id IS NOT NULL AND v_return_value > 0 THEN
    v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_return_value_egp,
        current_balances_by_currency = jsonb_set(
          COALESCE(current_balances_by_currency, '{}'::jsonb),
          ARRAY[v_cur],
          to_jsonb(COALESCE((current_balances_by_currency->>v_cur)::numeric, 0) - v_return_value)
        ),
        updated_at = now()
    WHERE id = v_lot.supplier_id;

    v_desc := 'مرتجع محصول - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT) || ' (كمية: ' || p_return_quantity || ')';
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by
    ) VALUES (
      'supplier', v_lot.supplier_id::TEXT, 'debit', v_return_value, v_cur, 'lot_return', v_return_id::TEXT, v_desc, p_user_id
    );
  END IF;

  -- 4. Post Double-Entry Journal Entry
  -- Dr. Supplier Leaf Account (2000s) -> Debit Supplier in foreign currency
  -- Cr. Inventory Account (1030)       -> Credit Inventory in local base currency (EGP)
  IF v_return_value > 0 THEN
    SELECT a.company_id INTO v_company_id
    FROM accounts a
    WHERE a.account_code = '1030'
    LIMIT 1;

    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

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
            'currency', v_cur,
            'description', 'تخفيض مستحقات مورد عن مرتجع شراء محصول رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
          ),
          jsonb_build_object(
            'account_id', v_inventory_account_id,
            'debit', 0,
            'credit', v_return_value_egp,
            'base_debit', 0,
            'base_credit', v_return_value_egp,
            'currency', 'EGP',
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

  -- 5. Resolve Cost Center:
  -- Priority 1: Match the EXACT cost center of the lot receipt from cost_center_transactions!
  SELECT cost_center_id, cost_center_name INTO v_cc_id, v_cc_name
  FROM public.cost_center_transactions
  WHERE source_type = 'lot_receipt' AND source_id = v_lot.id::text
  LIMIT 1;

  -- Priority 2: Use passed cost center ID if provided and Priority 1 was empty
  IF (v_cc_id IS NULL OR v_cc_id = '') AND p_cost_center_id IS NOT NULL AND TRIM(p_cost_center_id) <> '' THEN
    SELECT code, name_ar INTO v_cc_id, v_cc_name
    FROM public.cost_centers
    WHERE (code = p_cost_center_id OR id::text = p_cost_center_id)
    LIMIT 1;
  END IF;

  -- Priority 3: Resolve via canonical active seasonal cost center
  IF v_cc_id IS NULL OR v_cc_id = '' THEN
    SELECT r.cost_center_id, r.cost_center_name
    INTO v_cc_id, v_cc_name
    FROM public.fn_resolve_active_crop_cost_center(
      COALESCE(v_lot.product_name, 'محصول'),
      v_lot.fruit_type_id
    ) r;
  END IF;

  -- Lookup supplier name
  SELECT name INTO v_supplier_name
  FROM public.suppliers
  WHERE id = v_lot.supplier_id;

  INSERT INTO public.cost_center_transactions (
    cost_center_id,
    cost_center_name,
    cost_center_type,
    source_type,
    source_id,
    transaction_date,
    supplier_id,
    supplier_name,
    product_id,
    item_name,
    category,
    quantity,
    unit_price,
    currency,
    exchange_rate,
    total_in_currency,
    amount,
    notes,
    is_confirmed
  ) VALUES (
    v_cc_id,
    v_cc_name,
    'variety',
    'lot_return',
    v_return_id::text,
    CURRENT_DATE,
    v_lot.supplier_id::text,
    v_supplier_name,
    v_lot.fruit_type_id,
    'مرتجع شراء محصول - ' || COALESCE(v_lot.product_name, v_canon_crop, 'محصول') || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::text),
    'تكلفة المحاصيل',
    -p_return_quantity,
    v_unit_cost,
    v_cur,
    COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0),
    -v_return_value,
    -COALESCE(v_return_value_egp, v_return_value),
    COALESCE(v_desc, p_notes, 'مرتجع شراء محصول'),
    TRUE
  )
  ON CONFLICT (source_type, source_id) DO UPDATE SET
    cost_center_id = EXCLUDED.cost_center_id,
    cost_center_name = EXCLUDED.cost_center_name,
    quantity = EXCLUDED.quantity,
    amount = EXCLUDED.amount,
    total_in_currency = EXCLUDED.total_in_currency,
    updated_at = NOW();

  RETURN jsonb_build_object(
    'success', true,
    'return_id', v_return_id,
    'returned_quantity', p_return_quantity,
    'return_value', v_return_value,
    'unit_cost_used', v_unit_cost,
    'station_id', v_target_station,
    'batch_id', p_batch_id,
    'journal_entry_id', v_je_id,
    'cost_center_id', v_cc_id,
    'cost_center_name', v_cc_name
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- 3. Update get_supplier_true_balances_by_currency to account for purchase returns (lot_returns & ledger returns)
DROP FUNCTION IF EXISTS public.get_supplier_true_balances() CASCADE;
DROP FUNCTION IF EXISTS public.get_supplier_true_balances_by_currency() CASCADE;

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
  
  -- 3. Treasury Transactions (cash receipts/deposits from supplier increase credit: +amount, payments to supplier: -amount)
  treasury AS (
    SELECT 
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN LOWER(COALESCE(type, '')) IN ('deposit', 'receive', 'income', 'supplier_refund') THEN amount ELSE -amount END) AS net_amt
    FROM treasury_transactions
    WHERE supplier_id IS NOT NULL 
      AND (status = 'confirmed' OR status IS NULL)
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  
  -- 4. Bank Account Transactions (deposits/receipts from supplier: +amount, payments to supplier: -amount)
  bank_tx AS (
    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(ba.currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN LOWER(COALESCE(bat.type, '')) IN ('deposit', 'receive', 'income') THEN bat.amount ELSE -bat.amount END) AS net_amt
    FROM bank_account_transactions bat
    JOIN suppliers s ON (s.id::text = bat.entity_id OR s.code = bat.entity_id OR s.supplier_code = bat.entity_id)
    LEFT JOIN bank_accounts ba ON ba.id = bat.bank_account_id
    WHERE bat.entity_type = 'supplier' 
      AND (bat.status = 'confirmed' OR bat.status IS NULL)
    GROUP BY s.id, COALESCE(NULLIF(ba.currency, ''), 'EGP')
  ),
  
  -- 5. Cheques (incoming cheques from supplier: +amount, outgoing cheques to supplier: -amount)
  cheque_tx AS (
    SELECT 
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN LOWER(COALESCE(type, '')) = 'incoming' THEN amount ELSE -amount END) AS net_amt
    FROM cheques
    WHERE supplier_id IS NOT NULL 
      AND status IN ('cleared', 'collected')
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  
  -- 6. Lot Receipts / Enterprise Account Ledger Entries
  -- Isolated by lr.supplier_id to prevent transaction bleeding across suppliers sharing account 5104
  lot_tx AS (
    SELECT 
      lr.supplier_id,
      COALESCE(NULLIF(lr.currency, ''), COALESCE(NULLIF(ale.currency, ''), 'USD')) AS currency,
      SUM(ale.credit - ale.debit) AS net_amt
    FROM account_ledger_entries ale
    JOIN journal_entries je ON je.id = ale.journal_entry_id
    JOIN lot_receipts lr ON lr.id::text = je.source_id
    WHERE je.source_type IN ('lot_receipt','lot_adjustment','lot_price_adjustment')
      AND lr.supplier_id IS NOT NULL
    GROUP BY lr.supplier_id, COALESCE(NULLIF(lr.currency, ''), COALESCE(NULLIF(ale.currency, ''), 'USD'))

    UNION ALL

    SELECT 
      s.id AS supplier_id,
      COALESCE(NULLIF(ale.currency, ''), 'EGP') AS currency,
      SUM(ale.credit - ale.debit) AS net_amt
    FROM account_ledger_entries ale
    JOIN journal_entries je ON je.id = ale.journal_entry_id
    JOIN suppliers s ON (s.id::text = ale.entity_id OR s.code = ale.entity_id OR s.supplier_code = ale.entity_id)
    WHERE je.source_type = 'manual'
      AND ale.entity_type = 'supplier'
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

  -- 8. Standalone Purchase Returns from Ledger Entries (if any not linked to lot_returns)
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

-- 4. Update get_supplier_true_balances() to derive base EGP true balance directly from get_supplier_true_balances_by_currency()
DROP FUNCTION IF EXISTS public.get_supplier_true_balances();

CREATE OR REPLACE FUNCTION public.get_supplier_true_balances()
RETURNS TABLE (
  supplier_id uuid,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  WITH cur_balances AS (
    SELECT 
      supplier_id,
      SUM(true_balance_egp) AS total_egp
    FROM public.get_supplier_true_balances_by_currency()
    GROUP BY supplier_id
  )
  SELECT 
    s.id AS supplier_id,
    COALESCE(cb.total_egp, 0) AS true_balance
  FROM public.suppliers s
  LEFT JOIN cur_balances cb ON cb.supplier_id = s.id;
$func$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_process_lot_return(bigint, numeric, numeric, text, uuid, bigint, text, bigint) TO authenticated, anon, service_role;

-- 5. Run backfill to sync `outstanding_balance` in suppliers table
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


-- ==============================================================================
-- APPENDED FROM MIGRATION 467
-- ==============================================================================

-- ============================================================================
-- Migration 467: Link Sorting Sales to Cost Center Transactions (Net Cost Offset)
-- ============================================================================
-- When sorting waste or sorted produce items are sold via rpc_sell_sorting:
-- 1. Resolve parent fruit's cost_center_id and cost_center_name.
-- 2. Insert/upsert cost-reducing credit entry into cost_center_transactions:
--    category = 'تكلفة الفرز'
--    amount = -revenue
--    total_in_currency = -revenue
-- 3. Broadcast and return cost_center_id and cost_center_transaction_id.
-- ============================================================================

BEGIN;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'rpc_sell_sorting'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;
DROP FUNCTION IF EXISTS public.rpc_sell_sorting(integer, numeric, numeric, bigint, text, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.rpc_sell_sorting(integer, numeric, numeric, bigint, text, uuid, integer) CASCADE;
DROP FUNCTION IF EXISTS public.rpc_sell_sorting CASCADE;

CREATE OR REPLACE FUNCTION public.rpc_sell_sorting(
    p_sorting_id integer,
    p_qty numeric,
    p_price numeric,
    p_treasury_id bigint,
    p_treasury_name text,
    p_user_id uuid DEFAULT auth.uid(),
    p_customer_id integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
    v_revenue NUMERIC;
    v_sorting RECORD;
    v_new_remaining NUMERIC;
    v_new_sale_total NUMERIC;
    v_new_status TEXT;
    v_updated_treasury_names TEXT;
    
    v_company_id UUID;
    v_currency TEXT := 'EGP';
    
    v_current_balance NUMERIC;
    v_new_balance NUMERIC;
    v_treasury_balance_id INTEGER;
    v_treasury_acct BIGINT;
    v_sorting_inv_acct BIGINT;
    v_cust_acc_id BIGINT;
    
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_tx_id INTEGER;
    v_desc TEXT;
    v_lines JSONB;

    -- Customer variables
    v_customer_name TEXT;

    -- Cost Center variables
    v_fruit_type_id BIGINT;
    v_fruit_name TEXT;
    v_order_number TEXT;
    v_cc_id TEXT;
    v_cc_name TEXT;
    v_cc_type TEXT := 'variety';
    v_source_id TEXT;
    v_cct_id BIGINT;
BEGIN
    v_revenue := ROUND((p_qty * p_price)::numeric, 2);
    IF v_revenue <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Lock the sorting row
    SELECT * INTO v_sorting FROM public.packing_order_sortings WHERE id = p_sorting_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'سجل الفرز غير موجود';
    END IF;

    IF p_qty > v_sorting.remaining_weight_kg THEN
        RAISE EXCEPTION 'الكمية المباعة أكبر من المتبقي (% كجم)', v_sorting.remaining_weight_kg;
    END IF;

    v_new_remaining := v_sorting.remaining_weight_kg - p_qty;
    v_new_sale_total := COALESCE(v_sorting.total_sale_amount, 0) + v_revenue;
    
    IF v_new_remaining <= 0 THEN
        v_new_status := 'sold';
    ELSE
        v_new_status := 'pending';
    END IF;

    v_updated_treasury_names := v_sorting.treasury_names;
    IF p_treasury_name IS NOT NULL THEN
        IF v_updated_treasury_names IS NULL OR v_updated_treasury_names = '' THEN
            v_updated_treasury_names := p_treasury_name;
        ELSIF v_updated_treasury_names NOT LIKE '%' || p_treasury_name || '%' THEN
            v_updated_treasury_names := v_updated_treasury_names || '، ' || p_treasury_name;
        END IF;
    END IF;

    -- Lookup customer name and resolve customer GL account (12512 Local Customers)
    IF p_customer_id IS NOT NULL THEN
        SELECT name, account_id INTO v_customer_name, v_cust_acc_id
        FROM public.customers
        WHERE id = p_customer_id;

        IF v_cust_acc_id IS NULL THEN
            v_cust_acc_id := COALESCE(
                public.resolve_gl_account('12512', v_company_id),
                (SELECT id FROM public.accounts WHERE account_code = '12512' AND deleted_at IS NULL LIMIT 1),
                (SELECT id FROM public.accounts WHERE account_code = '12512' LIMIT 1)
            );
        END IF;
    END IF;

    -- Update sorting row
    UPDATE public.packing_order_sortings SET
        remaining_weight_kg = GREATEST(0, v_new_remaining),
        total_sale_amount = v_new_sale_total,
        status = v_new_status,
        sold_at = CASE WHEN v_new_status = 'sold' THEN now() ELSE sold_at END,
        treasury_names = v_updated_treasury_names
    WHERE id = p_sorting_id;

    -- Resolve Treasury and Company
    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- Treasury Balance
    SELECT id, COALESCE(balance, 0) INTO v_treasury_balance_id, v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = v_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + v_revenue;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, v_currency, v_company_id);
    IF v_treasury_balance_id IS NULL THEN
        INSERT INTO public.treasury_balances (treasury_id, currency, balance, account_id)
        VALUES (p_treasury_id, v_currency, v_new_balance, v_treasury_acct)
        RETURNING id INTO v_treasury_balance_id;
    ELSE
        UPDATE public.treasury_balances SET balance = v_new_balance WHERE id = v_treasury_balance_id;
    END IF;

    -- Resolve 12414 / 1032 Sorting Inventory GL Account
    v_sorting_inv_acct := COALESCE(public.resolve_gl_account('12414', v_company_id), public.resolve_gl_account('1032', v_company_id));
    IF v_sorting_inv_acct IS NULL THEN
        SELECT id INTO v_sorting_inv_acct FROM public.accounts WHERE account_code IN ('12414', '1032') LIMIT 1;
    END IF;

    v_desc := 'بيع فرز - ' || COALESCE(v_sorting.product_name, '') || ' - ' || trim(to_char(p_qty, '9999990.9')) || ' كجم';
    IF v_customer_name IS NOT NULL AND v_customer_name != '' THEN
        v_desc := v_desc || ' (العميل: ' || v_customer_name || ')';
    END IF;

    -- Build Journal Entry:
    IF p_customer_id IS NOT NULL AND v_cust_acc_id IS NOT NULL THEN
        -- قيد محاسبي متكامل ومتزن (4 أطراف) يوثق البيع والسداد للعميل في نفس اللحظة:
        -- 1. مدين: حساب العميل المحلي (12512) - إثبات مديونية بيع الفرز على العميل
        -- 2. دائن: حساب مخزون الفرز والتالف (12414) - تخفيض المخزون بحصيلة البيع
        -- 3. مدين: حساب الخزينة المستهدفة - تحصيل نقدي بالخزينة
        -- 4. دائن: حساب العميل المحلي (12512) - سداد نقدي للمديونية وإقفالها
        v_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_cust_acc_id,
                'debit', v_revenue,
                'base_debit', v_revenue,
                'credit', 0,
                'base_credit', 0,
                'currency', v_currency,
                'description', 'إثبات مديونية بيع فرز - ' || COALESCE(v_sorting.product_name, '') || ' (العميل: ' || COALESCE(v_customer_name, '') || ')'
            ),
            jsonb_build_object(
                'account_id', v_sorting_inv_acct,
                'debit', 0,
                'base_debit', 0,
                'credit', v_revenue,
                'base_credit', v_revenue,
                'currency', v_currency,
                'description', 'تخفيض مخزون الفرز بحصيلة البيع - ' || COALESCE(v_sorting.product_name, '')
            ),
            jsonb_build_object(
                'account_id', v_treasury_acct,
                'debit', v_revenue,
                'base_debit', v_revenue,
                'credit', 0,
                'base_credit', 0,
                'currency', v_currency,
                'description', 'تحصيل نقدي بالخزينة (' || COALESCE(p_treasury_name, '') || ') - بيع فرز'
            ),
            jsonb_build_object(
                'account_id', v_cust_acc_id,
                'debit', 0,
                'base_debit', 0,
                'credit', v_revenue,
                'base_credit', v_revenue,
                'currency', v_currency,
                'description', 'سداد نقدي لمديونية بيع فرز - ' || COALESCE(v_customer_name, '')
            )
        );
    ELSE
        -- قيد مباشر بحال عدم تحديد عميل (الخزينة مباشرة مقابل مخزون الفرز والتالف):
        v_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_treasury_acct,
                'debit', v_revenue,
                'base_debit', v_revenue,
                'credit', 0,
                'base_credit', 0,
                'currency', v_currency,
                'description', v_desc
            ),
            jsonb_build_object(
                'account_id', v_sorting_inv_acct,
                'debit', 0,
                'base_debit', 0,
                'credit', v_revenue,
                'base_credit', v_revenue,
                'currency', v_currency,
                'description', 'تخفيض مخزون الفرز بحصيلة البيع - ' || COALESCE(v_sorting.product_name, '')
            )
        );
    END IF;

    v_je_id := public.post_journal_entry(
        'sale_sorting',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        COALESCE(p_user_id, auth.uid()),
        v_lines
    );

    SELECT entry_number INTO v_entry_num FROM public.journal_entries WHERE id = v_je_id;

    -- Treasury Transaction with Customer ID
    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after,
        description, source_type, journal_entry_id, revenue_account_id, created_by,
        customer_id
    ) VALUES (
        p_treasury_id, 'deposit', v_currency, v_revenue, v_current_balance, v_new_balance,
        v_desc, 'sale_sorting', v_je_id, v_sorting_inv_acct, COALESCE(p_user_id, auth.uid()),
        p_customer_id
    ) RETURNING id INTO v_tx_id;

    -- إثبات حركة البيع والسداد في سجل العميل (كشف حساب العميل)
    IF p_customer_id IS NOT NULL THEN
        -- 1. حركة البيع (مدين العميل)
        INSERT INTO public.ledger_entries (
            entity_id,
            entity_type,
            amount,
            currency,
            entry_type,
            reference_id,
            reference_type,
            reference_text,
            description,
            created_by,
            created_at
        ) VALUES (
            p_customer_id::text,
            'customer',
            v_revenue,
            v_currency,
            'debit',
            p_sorting_id,
            'payment',
            'sorting_sale',
            'فاتورة بيع فرز - ' || COALESCE(v_sorting.product_name, '') || ' (' || trim(to_char(p_qty, '9999990.9')) || ' كجم)',
            COALESCE(p_user_id, auth.uid()),
            now()
        );

        -- 2. حركة السداد النقدي بالخزينة (دائن العميل)
        INSERT INTO public.ledger_entries (
            entity_id,
            entity_type,
            amount,
            currency,
            entry_type,
            reference_id,
            reference_type,
            reference_text,
            description,
            created_by,
            created_at
        ) VALUES (
            p_customer_id::text,
            'customer',
            v_revenue,
            v_currency,
            'credit',
            p_sorting_id,
            'payment',
            'sorting_sale_cash',
            'سداد نقدي لبيع الفرز - خزينة: ' || COALESCE(p_treasury_name, 'الخزينة'),
            COALESCE(p_user_id, auth.uid()),
            now() + interval '1 millisecond'
        );
    END IF;

    -- ========================================================================
    -- Cost Center Resolution and Net Cost Offsetting Transaction
    -- ========================================================================
    v_fruit_name := v_sorting.product_name;

    IF v_sorting.packing_order_id IS NOT NULL THEN
        SELECT po.fruit_type_id::bigint, po.product_name, po.order_number
        INTO v_fruit_type_id, v_fruit_name, v_order_number
        FROM public.packing_orders po
        WHERE po.id = v_sorting.packing_order_id;
        
        IF v_fruit_name IS NULL OR v_fruit_name = '' THEN
            v_fruit_name := v_sorting.product_name;
        END IF;
    END IF;

    -- Strict Item-Bound Cost Center Resolution
    SELECT r.cost_center_id, r.cost_center_name
    INTO v_cc_id, v_cc_name
    FROM public.fn_resolve_active_crop_cost_center(
      COALESCE(v_fruit_name, 'محصول'),
      v_fruit_type_id
    ) r;
    v_cc_type := 'variety';

    v_source_id := 'sorting_sale_' || p_sorting_id || '_' || v_tx_id;

    INSERT INTO public.cost_center_transactions (
        cost_center_id,
        cost_center_name,
        cost_center_type,
        source_type,
        source_id,
        transaction_date,
        product_id,
        item_name,
        category,
        quantity,
        unit_price,
        currency,
        exchange_rate,
        total_in_currency,
        amount,
        notes,
        is_confirmed
    ) VALUES (
        v_cc_id,
        COALESCE(v_cc_name, v_fruit_name, 'محصول'),
        COALESCE(v_cc_type, 'variety'),
        'sorting_sale',
        v_source_id,
        CURRENT_DATE,
        v_fruit_type_id,
        'مبيعات فرزة - ' || COALESCE(v_fruit_name, 'محصول') || CASE WHEN v_order_number IS NOT NULL THEN ' (تشغيلة ' || v_order_number || ')' ELSE '' END,
        'تكلفة الفرز',
        p_qty,
        p_price,
        v_currency,
        1.0,
        -v_revenue,
        -v_revenue,
        'خصم تكلفة من حصيلة بيع فرز: ' || COALESCE(v_desc, ''),
        true
    )
    ON CONFLICT (source_type, source_id)
    DO UPDATE SET
        amount = EXCLUDED.amount,
        total_in_currency = EXCLUDED.total_in_currency,
        quantity = EXCLUDED.quantity,
        unit_price = EXCLUDED.unit_price,
        notes = EXCLUDED.notes
    RETURNING id INTO v_cct_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_num,
        'treasury_transaction_id', v_tx_id,
        'cost_center_transaction_id', v_cct_id,
        'cost_center_id', v_cc_id,
        'remaining_weight_kg', v_new_remaining,
        'status', v_new_status,
        'revenue', v_revenue,
        'customer_id', p_customer_id,
        'customer_name', v_customer_name
    );
END;
$func$;

GRANT EXECUTE ON FUNCTION public.rpc_sell_sorting(integer, numeric, numeric, bigint, text, uuid, integer) TO authenticated, anon, service_role;

-- ==============================================================================
-- APPENDED FROM MIGRATION 468 (Packing Order Balance Precision)
-- ==============================================================================
-- Migration 468: Fix floating-point precision imbalance in rpc_confirm_packing_order
--
-- Root cause: v_order.total_packing_cost may contain repeating-decimal fractions
-- (e.g. 683066.6622222222 from quantity/3 divisions), causing ROUND(debit,2) != ROUND(credit,2).
--
-- Fix strategy:
--   1. ROUND every cost component to 4dp immediately after computation.
--   2. Balance check changed to ABS(debit - credit) > 0.01 tolerance.
--   3. Absorb any residual sub-cent penny difference into finished-goods debit line.
CREATE OR REPLACE FUNCTION public._packing_allocate_shares(p_method text, p_bases numeric[])
 RETURNS numeric[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_n INT;
  v_total NUMERIC := 0;
  v_shares NUMERIC[];
  i INT;
BEGIN
  v_n := COALESCE(array_length(p_bases, 1), 0);
  IF v_n = 0 THEN
    RETURN ARRAY[]::NUMERIC[];
  END IF;

  FOR i IN 1..v_n LOOP
    v_total := v_total + COALESCE(p_bases[i], 0);
  END LOOP;

  IF v_total <= 0 THEN
    v_shares := ARRAY[]::NUMERIC[];
    FOR i IN 1..v_n LOOP
      v_shares := v_shares || ARRAY[ROUND((1.0 / v_n)::numeric, 8)];
    END LOOP;
    RETURN v_shares;
  END IF;

  v_shares := ARRAY[]::NUMERIC[];
  FOR i IN 1..v_n LOOP
    v_shares := v_shares || ARRAY[ROUND((COALESCE(p_bases[i], 0) / v_total)::numeric, 8)];
  END LOOP;
  RETURN v_shares;
END;
$function$;

GRANT EXECUTE ON FUNCTION public._packing_allocate_shares(text, numeric[]) TO authenticated, anon, service_role;

-- Resolve supplier liability account for packing cost item
CREATE OR REPLACE FUNCTION public.fn_resolve_packing_cost_supplier_account(
    p_supplier_id UUID,
    p_company_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_acc_id BIGINT;
    v_supp_type TEXT;
    v_supp_code TEXT;
    v_target_code TEXT;
BEGIN
    IF p_supplier_id IS NULL THEN
        RETURN public.resolve_gl_account('2111', p_company_id);
    END IF;

    SELECT account_id, supplier_type, code INTO v_acc_id, v_supp_type, v_supp_code
    FROM public.suppliers
    WHERE id = p_supplier_id;

    IF v_acc_id IS NOT NULL THEN
        RETURN v_acc_id;
    END IF;

    -- Infer code from supplier_type
    IF v_supp_type = 'station' OR v_supp_code LIKE '85%' OR v_supp_code LIKE '86%' OR v_supp_code LIKE '87%' OR v_supp_code LIKE '88%' OR v_supp_code LIKE '89%' THEN
        v_target_code := '21117';
    ELSIF v_supp_type IN ('deduction', 'deductions') OR v_supp_code LIKE '4%' THEN
        v_target_code := '21118';
    ELSIF v_supp_type = 'transport' OR v_supp_code LIKE '6%' THEN
        v_target_code := '21111';
    ELSIF v_supp_type = 'packaging' OR v_supp_code LIKE '70%' OR v_supp_code LIKE '71%' THEN
        v_target_code := '21112';
    ELSIF v_supp_type = 'shared' OR v_supp_code LIKE '75%' THEN
        v_target_code := '21114';
    ELSIF v_supp_type = 'shipping' OR v_supp_code LIKE '9%' THEN
        v_target_code := '21115';
    ELSE
        v_target_code := '21113';
    END IF;

    RETURN public.resolve_gl_account(v_target_code, p_company_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_resolve_packing_cost_supplier_account(UUID, UUID) TO authenticated, anon, service_role;

-- ============================================================================
-- STAGE 1: Confirm Crops & Deduct Inventory (تأكيد المحاصيل وخصم المخزون)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_crops(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_station_id INT;
  v_packed_at TIMESTAMPTZ;
  v_company_id UUID;

  v_tot_raw_cost NUMERIC := 0;
  v_tot_waste_cost NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_fruit_net_cost NUMERIC := 0;

  v_finished_inv_acc INT;
  v_raw_inv_acc INT;
  v_sorting_inv_acc INT;
  v_crop_waste_inter_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_alloc JSONB;
  v_el JSONB;
  v_batch_id BIGINT;
  v_used_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_curr_rem NUMERIC;
  v_sp_qty NUMERIC;
  v_crops_found BOOLEAN := false;

  v_target_cc_id TEXT;
  v_target_cc_name TEXT;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Idempotency check: only block if the order has already been final approved / completed
  IF v_order.status IN ('final_approved', 'completed') THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة معتمد نهائياً ومقفل بالكامل',
      'status', v_order.status,
      'journal_entry_id', COALESCE(v_order.crops_journal_entry_id, v_order.journal_entry_id)
    );
  END IF;

  BEGIN
    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_notes) = 'string' THEN
      v_notes := (v_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_notes := '{}'::jsonb;
  END;

  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);
  v_station_id := v_order.station_id;
  v_packed_at := COALESCE(v_order.packed_at, now());

  -- Resolve Target Variety Cost Center
  v_target_cc_id := NULL;
  v_target_cc_name := NULL;

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' AND jsonb_array_length(v_notes->'materials') > 0 THEN
    v_target_cc_id := v_notes->'materials'->0->>'cost_center_id';
    v_target_cc_name := v_notes->'materials'->0->>'cost_center_name';
  END IF;

  IF v_target_cc_id IS NULL OR v_target_cc_id = '' THEN
    SELECT id, name_ar INTO v_target_cc_id, v_target_cc_name
    FROM public.cost_centers
    WHERE (name_ar = v_order.product_name OR name_ar ILIKE '%' || v_order.product_name || '%')
      AND (is_closed IS FALSE OR is_closed IS NULL)
    ORDER BY id ASC LIMIT 1;
  END IF;

  IF v_target_cc_id IS NULL OR v_target_cc_id = '' THEN
    SELECT id, name_ar INTO v_target_cc_id, v_target_cc_name
    FROM public.cost_centers
    WHERE name_ar = v_order.product_name OR name_ar ILIKE '%' || v_order.product_name || '%'
    ORDER BY id ASC LIMIT 1;
  END IF;

  -- 1. Deduct Fruit Batches from inventory
  IF v_notes ? 'fruit_allocation' THEN
    v_alloc := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_alloc) = 'object' THEN v_alloc := jsonb_build_array(v_alloc); END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
        v_crops_found := true;
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id
        FOR UPDATE;

        IF FOUND AND v_curr_rem >= v_used_qty THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - v_used_qty
          WHERE id = v_batch_id;
        ELSE
          DECLARE
            v_rem_needed NUMERIC := v_used_qty;
            r_b RECORD;
            v_take NUMERIC;
          BEGIN
            FOR r_b IN (
              SELECT id, remaining_quantity
              FROM public.station_product_batches
              WHERE station_id = v_station_id
                AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode))
                AND remaining_quantity > 0
              ORDER BY id ASC
              FOR UPDATE
            ) LOOP
              IF v_rem_needed <= 0 THEN EXIT; END IF;
              v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
              UPDATE public.station_product_batches
              SET remaining_quantity = remaining_quantity - v_take
              WHERE id = r_b.id;
              v_rem_needed := v_rem_needed - v_take;
            END LOOP;
          END;
        END IF;

        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

        UPDATE public.station_products
        SET quantity = v_sp_qty, updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
      END IF;
    END LOOP;
  END IF;

  -- 2. Read Crop Costs
  v_tot_raw_cost := COALESCE(v_order.fruit_cost_base, v_order.fruit_cost_allocated, 0);
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, (v_notes->'waste_data'->>'waste_cost')::numeric, 0);
  v_tot_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, (v_notes->'sorting_data'->>'sorting_cost')::numeric, 0);

  IF v_tot_raw_cost = 0 THEN
    SELECT COALESCE(SUM(raw_material_cost), 0),
           COALESCE(SUM(waste_cost), 0),
           COALESCE(SUM(sorting_cost), 0)
    INTO v_tot_raw_cost, v_tot_waste_cost, v_tot_sorting_cost
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id;
  END IF;

  v_fruit_net_cost := v_tot_raw_cost - (v_tot_waste_cost + v_tot_sorting_cost);

  -- 3. Resolve GL Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc    := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));
  v_raw_inv_acc         := COALESCE(public.resolve_gl_account('12412', v_company_id), public.resolve_gl_account('1030', v_company_id));
  v_sorting_inv_acc     := COALESCE(public.resolve_gl_account('12414', v_company_id), public.resolve_gl_account('1032', v_company_id));
  v_crop_waste_inter_acc := public.resolve_gl_account('12415', v_company_id);

  -- 4. Create or Update Journal Entry
  IF v_tot_raw_cost > 0 THEN
    IF v_order.crops_journal_entry_id IS NOT NULL THEN
      v_je_id := v_order.crops_journal_entry_id;
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      UPDATE public.journal_entries
      SET description = 'قيد استهلاك محصول خام لأمر تعبئة رقم ' || v_order_num,
          updated_at = now()
      WHERE id = v_je_id;
    ELSE
      INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
      ) VALUES (
        'PENDING',
        COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),
        'قيد استهلاك محصول خام لأمر تعبئة رقم ' || v_order_num,
        'posted', true, 'packing_order_crops', p_packing_order_id::text, v_company_id,
        auth.uid(), now(), now()
      ) RETURNING id INTO v_je_id;

      v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_crop', NULL, NULL);
      IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'POC-' || LPAD(v_je_id::text, 5, '0');
      END IF;
      UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
    END IF;

    -- DR Finished Goods Inventory (12413 / 1031) tagged with target cost center
    IF (v_fruit_net_cost + v_tot_waste_cost) > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id, cost_center_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, (v_fruit_net_cost + v_tot_waste_cost), 0, 'EGP', (v_fruit_net_cost + v_tot_waste_cost),
        'تكلفة المحصول الداخل في التعبئة وهالك الفاقد - أمر ' || v_order_num, v_company_id, v_target_cc_id
      );
      v_sum_debit := v_sum_debit + (v_fruit_net_cost + v_tot_waste_cost);
    END IF;

    -- DR Sorting Inventory (12414 / 1032)
    IF v_tot_sorting_cost > 0 AND v_sorting_inv_acc IS NOT NULL THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, 'EGP', v_tot_sorting_cost,
        'مخزون الفرز - أمر تعبئة ' || v_order_num, v_company_id
      );
      v_sum_debit := v_sum_debit + v_tot_sorting_cost;
    END IF;

    -- CR Raw Produce Inventory (12412 / 1030)
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,
      'صرف محصول خام بالكامل - أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;

    -- Balance check
    IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
      RAISE EXCEPTION 'فشل تأكيد قيد المحاصيل: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
    END IF;

    -- Penny rounding absorption
    IF v_sum_debit != v_sum_credit THEN
      UPDATE public.account_ledger_entries
      SET debit = debit + (v_sum_credit - v_sum_debit),
          amount_in_base_currency = amount_in_base_currency + (v_sum_credit - v_sum_debit)
      WHERE journal_entry_id = v_je_id AND account_id = v_finished_inv_acc AND debit > 0;
    END IF;
  END IF;

  -- 4b. Sync crop waste into cost_center_transactions for target crop/variety
  DELETE FROM public.cost_center_transactions
  WHERE source_type = 'packing_crop_waste'
    AND source_id = 'po_' || p_packing_order_id::text || '_crop_waste';

  IF v_tot_waste_cost > 0 AND v_target_cc_id IS NOT NULL THEN
    INSERT INTO public.cost_center_transactions (
      cost_center_id,
      cost_center_name,
      cost_center_type,
      source_type,
      source_id,
      transaction_date,
      product_id,
      item_name,
      category,
      quantity,
      unit_price,
      currency,
      exchange_rate,
      total_in_currency,
      amount,
      notes,
      is_confirmed
    ) VALUES (
      v_target_cc_id,
      v_target_cc_name,
      'variety',
      'packing_crop_waste',
      'po_' || p_packing_order_id::text || '_crop_waste',
      COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, CURRENT_DATE),
      v_order.fruit_type_id,
      'هالك محصول - أمر #' || v_order_num,
      'تكلفة الهالك',
      COALESCE((v_notes->'waste_data'->>'quantity')::numeric, (v_notes->'waste_data'->>'waste_weight_kg')::numeric, 1),
      COALESCE((v_notes->'waste_data'->>'unit_price')::numeric, v_tot_waste_cost),
      'EGP',
      1.0,
      v_tot_waste_cost,
      v_tot_waste_cost,
      'أمر تعبئة #' || v_order_num || ' - تكلفة هالك المحصول لصنف ' || COALESCE(v_order.product_name, ''),
      true
    ) ON CONFLICT (source_type, source_id) DO UPDATE SET
      cost_center_id = EXCLUDED.cost_center_id,
      cost_center_name = EXCLUDED.cost_center_name,
      item_name = EXCLUDED.item_name,
      quantity = EXCLUDED.quantity,
      unit_price = EXCLUDED.unit_price,
      amount = EXCLUDED.amount,
      total_in_currency = EXCLUDED.total_in_currency,
      notes = EXCLUDED.notes,
      transaction_date = EXCLUDED.transaction_date,
      updated_at = now();
  END IF;

  -- 5. Update packing order status and stage tracking
  v_notes := jsonb_set(v_notes, '{workflow_stages,crops}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'raw_cost', v_tot_raw_cost,
    'sorting_cost', v_tot_sorting_cost,
    'waste_cost', v_tot_waste_cost
  ), true);

  UPDATE public.packing_orders
  SET status = CASE
        WHEN status IN ('packaging_confirmed', 'costs_confirmed', 'final_approved', 'completed') THEN status
        ELSE 'crops_confirmed'
      END,
      crops_confirmed_at = COALESCE(crops_confirmed_at, now()),
      crops_journal_entry_id = v_je_id,
      journal_entry_id = COALESCE(journal_entry_id, v_je_id),
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'status', 'crops_confirmed',
    'journal_entry_id', v_je_id,
    'raw_cost', v_tot_raw_cost,
    'sorting_cost', v_tot_sorting_cost,
    'waste_cost', v_tot_waste_cost,
    'fruit_net_cost', v_fruit_net_cost
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_crops(bigint) TO authenticated, service_role, anon;


-- ============================================================================

NOTIFY pgrst, 'reload_schema';
COMMIT;
