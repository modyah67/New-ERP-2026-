-- Migration 107: Profitability GL Integration
--
-- 1. Add journal_entry_id to shipment_cost_items
-- 2. Update rpc_pay_shipment_cost_item to capture journal_entry_id
-- 3. Create rpc_save_profitability_expense: atomic cost item + payment + GL entry
-- 4. Create rpc_reverse_profitability_expense: reversal entry for editing

-- ============================================================================
-- SECTION 1: ALTER TABLE
-- ============================================================================

ALTER TABLE public.shipment_cost_items
  ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT;

-- ============================================================================
-- SECTION 2: Updated rpc_pay_shipment_cost_item (captures journal_entry_id)
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_pay_shipment_cost_item(bigint, text, bigint);

CREATE OR REPLACE FUNCTION public.rpc_pay_shipment_cost_item(
  p_cost_item_id bigint,
  p_source_type  text,
  p_source_id    bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r_item           RECORD;
  v_supplier_id    UUID;
  v_amount         NUMERIC;
  v_currency       TEXT;
  v_current_bal    NUMERIC;
  v_treasury_tx_id BIGINT;
  v_bank_tx_id     INTEGER;
  v_tx_desc        TEXT;
  v_je_id          BIGINT;
  v_company_id     UUID;
  v_bank_res       JSONB;
BEGIN
  -- 1. Load and validate cost item
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'هذا البند مدفوع مسبقاً');
  END IF;

  IF p_source_type NOT IN ('treasury', 'bank') THEN
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح: ' || p_source_type);
  END IF;

  v_amount   := COALESCE(r_item.total_price, 0);
  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');
  v_tx_desc  := 'سداد بند تكلفة شحنة: ' || COALESCE(r_item.description, 'غير محدد')
                 || ' (بند ' || p_cost_item_id::text || ')';

  IF v_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  v_supplier_id := NULL;
  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      v_supplier_id := r_item.supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
    END;
  END IF;

  -- Resolve company_id
  SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_source_id;
  IF v_company_id IS NULL THEN
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_source_id::integer;
  END IF;

  IF p_source_type = 'treasury' THEN
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    PERFORM public.spend_custody(
      p_source_id,
      v_currency,
      v_amount,
      v_tx_desc,
      NULL,
      v_supplier_id,
      NULL,
      NULL,
      NULL
    );

    -- Get treasury transaction id
    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type        = 'expense'
      AND amount      = v_amount
      AND currency    = v_currency
      AND supplier_id IS NOT DISTINCT FROM v_supplier_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Capture journal_entry_id from the most recent journal entry matching this payment
    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id IS NOT DISTINCT FROM v_company_id
      AND je.entry_date = CURRENT_DATE
      AND je.description LIKE '%' || LEFT(v_tx_desc, 30) || '%'
    ORDER BY je.id DESC
    LIMIT 1;

    -- Fallback: find by amount+date if description match fails
    IF v_je_id IS NULL THEN
      SELECT je.id INTO v_je_id
      FROM public.journal_entries je
      WHERE je.source_type IN ('expense_payment', 'purchase_payment')
        AND je.company_id IS NOT DISTINCT FROM v_company_id
        AND je.entry_date = CURRENT_DATE
      ORDER BY je.id DESC
      LIMIT 1;
    END IF;

    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_treasury_tx_id,
        payment_source_type     = 'treasury',
        payment_source_id       = p_source_id,
        journal_entry_id        = v_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_treasury_tx_id, 'type', 'treasury', 'journal_entry_id', v_je_id);

  ELSIF p_source_type = 'bank' THEN
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    v_bank_res := public.withdraw_bank_account(
      p_source_id::integer,
      v_amount,
      v_tx_desc,
      CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
      v_supplier_id::text,
      NULL
    );

    v_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
    v_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

    UPDATE public.shipment_cost_items
    SET bank_transaction_id     = v_bank_tx_id,
        payment_source_type     = 'bank',
        payment_source_id       = p_source_id,
        journal_entry_id        = v_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_bank_tx_id, 'type', 'bank', 'journal_entry_id', v_je_id);
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_pay_shipment_cost_item(bigint, text, bigint)
  TO authenticated, service_role;

-- ============================================================================
-- SECTION 3: rpc_save_profitability_expense — atomic save + pay + GL entry
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_save_profitability_expense(
  p_shipment_id       INTEGER,
  p_category          TEXT,
  p_report_category_id INTEGER,
  p_description       TEXT,
  p_quantity          NUMERIC,
  p_unit_price        NUMERIC,
  p_exchange_rate     NUMERIC,
  p_original_currency TEXT,
  p_supplier_id       TEXT,
  p_supplier_currency TEXT,
  p_source_type       TEXT,        -- 'treasury' | 'bank'
  p_source_id         BIGINT       -- treasury_id or bank_account_id
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cost_item_id  BIGINT;
  v_total_price   NUMERIC;
  v_currency      TEXT;
  v_supplier_uuid UUID;
  v_company_id    UUID;
  v_treasury_tx_id BIGINT;
  v_bank_tx_id    INTEGER;
  v_je_id         BIGINT;
  v_tx_desc       TEXT;
  v_current_bal   NUMERIC;
  v_new_item_id   BIGINT;
BEGIN
  -- Validate inputs
  IF p_shipment_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'رقم الشحنة مطلوب');
  END IF;
  IF p_source_type NOT IN ('treasury', 'bank') THEN
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح');
  END IF;
  IF p_source_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'مصدر الدفع مطلوب');
  END IF;

  v_total_price := COALESCE(p_quantity, 1) * COALESCE(p_unit_price, 0);
  IF v_total_price <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  v_currency := COALESCE(NULLIF(p_original_currency, ''), 'EGP');

  -- Resolve supplier uuid
  v_supplier_uuid := NULL;
  IF p_supplier_id IS NOT NULL AND p_supplier_id != '' THEN
    BEGIN
      v_supplier_uuid := p_supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_uuid := NULL;
    END;
  END IF;

  -- Resolve company_id
  IF p_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_source_id;
  ELSE
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_source_id::integer;
  END IF;

  IF v_company_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم العثور على الشركة');
  END IF;

  -- 1. Insert the cost item
  INSERT INTO public.shipment_cost_items (
    shipment_id, category, report_category_id, description,
    quantity, unit_price, exchange_rate, original_currency,
    supplier_id, supplier_currency,
    payment_source_type, payment_source_id,
    sort_order
  ) VALUES (
    p_shipment_id, COALESCE(p_category, 'other'), p_report_category_id, p_description,
    COALESCE(p_quantity, 1), COALESCE(p_unit_price, 0), COALESCE(p_exchange_rate, 1),
    v_currency, p_supplier_id, p_supplier_currency,
    p_source_type, p_source_id,
    (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM public.shipment_cost_items WHERE shipment_id = p_shipment_id)
  ) RETURNING id INTO v_new_item_id;

  -- 2. Pay the item via treasury or bank
  v_tx_desc := 'سداد بند تكلفة شحنة: ' || COALESCE(p_description, 'غير محدد')
               || ' (بند ' || v_new_item_id::text || ')';

  IF p_source_type = 'treasury' THEN
    -- Check balance
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_total_price THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_total_price;
    END IF;

    -- Spend from custody (creates GL entry + treasury transaction)
    PERFORM public.spend_custody(
      p_source_id, v_currency, v_total_price, v_tx_desc,
      NULL, v_supplier_uuid, NULL, NULL, NULL
    );

    -- Get treasury transaction id
    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type = 'expense' AND amount = v_total_price AND currency = v_currency
      AND supplier_id IS NOT DISTINCT FROM v_supplier_uuid
    ORDER BY created_at DESC LIMIT 1;

    -- Capture journal_entry_id
    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id = v_company_id
      AND je.entry_date = CURRENT_DATE
    ORDER BY je.id DESC LIMIT 1;

    -- Stamp cost item
    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_treasury_tx_id,
        payment_source_type = 'treasury',
        payment_source_id = p_source_id,
        journal_entry_id = v_je_id
    WHERE id = v_new_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', v_new_item_id,
      'tx_id', v_treasury_tx_id,
      'type', 'treasury',
      'journal_entry_id', v_je_id
    );

  ELSIF p_source_type = 'bank' THEN
    -- Check balance
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_total_price THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_total_price;
    END IF;

    -- Withdraw from bank (creates GL entry + bank transaction)
    DECLARE v_bank_res JSONB;
    BEGIN
      v_bank_res := public.withdraw_bank_account(
        p_source_id::integer, v_total_price, v_tx_desc,
        CASE WHEN v_supplier_uuid IS NOT NULL THEN 'supplier' ELSE NULL END,
        v_supplier_uuid::text, NULL
      );

      v_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
      v_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

      UPDATE public.shipment_cost_items
      SET bank_transaction_id = v_bank_tx_id,
          payment_source_type = 'bank',
          payment_source_id = p_source_id,
          journal_entry_id = v_je_id
      WHERE id = v_new_item_id;

      RETURN json_build_object(
        'success', true,
        'cost_item_id', v_new_item_id,
        'tx_id', v_bank_tx_id,
        'type', 'bank',
        'journal_entry_id', v_je_id
      );
    END;
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_profitability_expense(
  INTEGER, TEXT, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, BIGINT
) TO authenticated, service_role;

-- ============================================================================
-- SECTION 4: Backfill journal_entry_id for existing paid items
-- ============================================================================

-- For treasury-paid items: find matching journal entries
UPDATE public.shipment_cost_items sci
SET journal_entry_id = (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.source_type IN ('expense_payment', 'purchase_payment')
    AND je.description LIKE '%سداد بند تكلفة شحنة%'
  ORDER BY je.id DESC
  LIMIT 1
)
WHERE sci.treasury_transaction_id IS NOT NULL
  AND sci.journal_entry_id IS NULL;

-- For bank-paid items: look up from bank_account_transactions
UPDATE public.shipment_cost_items sci
SET journal_entry_id = bat.journal_entry_id
FROM public.bank_account_transactions bat
WHERE sci.bank_transaction_id = bat.id
  AND sci.journal_entry_id IS NULL
  AND bat.journal_entry_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
