-- Migration 124: Phase Final — Context-Aware Expense Forms, Entity Accounts, GL Integration
--
-- 1. Add shipping_company_id, clearing_agent_id to shipment_cost_items
-- 2. Rewrite rpc_save_profitability_expense with entity type support
-- 3. Rewrite rpc_pay_shipment_cost_item with entity type support
-- 4. Rewrite rpc_edit_profitability_expense with entity type support
-- 5. Create rpc_get_expense_leaf_accounts
-- 6. Fix spend_custody type mismatches
-- 7. Backfill data

BEGIN;

-- ============================================================================
-- SECTION 0: Add entity columns to shipment_cost_items
-- ============================================================================

ALTER TABLE public.shipment_cost_items
  ADD COLUMN IF NOT EXISTS expense_account_id INTEGER,
  ADD COLUMN IF NOT EXISTS shipping_company_id BIGINT,
  ADD COLUMN IF NOT EXISTS clearing_agent_id BIGINT;

-- ============================================================================
-- SECTION 1: Create rpc_get_expense_leaf_accounts
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_expense_leaf_accounts(
  p_company_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id            INTEGER,
  account_code  TEXT,
  name          TEXT,
  account_name  TEXT,
  parent_id     INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  v_company := COALESCE(p_company_id, public.get_current_company_id());

  RETURN QUERY
  SELECT a.id, a.account_code::TEXT, a.name, a.account_name, a.parent_id
  FROM public.accounts a
  WHERE a.account_type = 'expense'
    AND a.is_leaf = true
    AND a.is_active = true
    AND (v_company IS NULL OR a.company_id = v_company)
  ORDER BY a.account_code;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_expense_leaf_accounts(UUID) TO authenticated, service_role;

-- ============================================================================
-- SECTION 2: Rewrite rpc_save_profitability_expense — full entity support
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_save_profitability_expense(
  INTEGER, TEXT, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, BIGINT, INTEGER
);

CREATE OR REPLACE FUNCTION public.rpc_save_profitability_expense(
  p_shipment_id          INTEGER,
  p_category             TEXT,
  p_report_category_id   INTEGER,
  p_description          TEXT,
  p_quantity             NUMERIC,
  p_unit_price           NUMERIC,
  p_exchange_rate        NUMERIC,
  p_original_currency    TEXT,
  p_supplier_id          TEXT,
  p_supplier_currency    TEXT,
  p_source_type          TEXT,
  p_source_id            BIGINT,
  p_expense_account_id   INTEGER DEFAULT NULL,
  p_shipping_company_id  BIGINT DEFAULT NULL,
  p_clearing_agent_id    BIGINT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_price      NUMERIC;
  v_currency         TEXT;
  v_supplier_uuid    UUID;
  v_company_id       UUID;
  v_treasury_tx_id   BIGINT;
  v_bank_tx_id       INTEGER;
  v_je_id            BIGINT;
  v_tx_desc          TEXT;
  v_current_bal      NUMERIC;
  v_new_item_id      BIGINT;
  v_resolved_acct    INTEGER;
  v_category         TEXT;
BEGIN
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

  -- Resolve supplier uuid (optional)
  v_supplier_uuid := NULL;
  IF p_supplier_id IS NOT NULL AND p_supplier_id != '' THEN
    BEGIN
      v_supplier_uuid := p_supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_uuid := NULL;
    END;
  END IF;

  -- Resolve expense account and category based on entity type
  v_resolved_acct := NULL;
  v_category := COALESCE(p_category, 'other');

  IF p_shipping_company_id IS NOT NULL THEN
    -- Shipping company: resolve from shipping company's account
    v_category := 'freight';
    SELECT sc.account_id INTO v_resolved_acct
    FROM public.shipping_companies sc WHERE sc.id = p_shipping_company_id;
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'شركة الشحن لا تمتلك حساب في شجرة الحسابات');
    END IF;

  ELSIF p_clearing_agent_id IS NOT NULL THEN
    -- Clearing agent: resolve from clearing agent's account
    v_category := 'clearance';
    SELECT ca.account_id INTO v_resolved_acct
    FROM public.clearing_agents ca WHERE ca.id = p_clearing_agent_id;
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'المخلص لا يمتلك حساب في شجرة الحسابات');
    END IF;

  ELSIF p_expense_account_id IS NOT NULL THEN
    -- Other: explicit expense account from Chart of Accounts
    SELECT id INTO v_resolved_acct FROM accounts
    WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'حساب المصروفات المحدد غير صالح');
    END IF;

  ELSIF v_supplier_uuid IS NOT NULL THEN
    -- Fallback: supplier's account
    SELECT s.account_id INTO v_resolved_acct FROM suppliers s WHERE s.id = v_supplier_uuid;
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'المورد لا يمتلك حساب في شجرة الحسابات');
    END IF;
  END IF;

  IF v_resolved_acct IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'يجب اختيار حساب مصروفات أو تحديد جهة');
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
    expense_account_id, shipping_company_id, clearing_agent_id,
    sort_order
  ) VALUES (
    p_shipment_id, v_category, p_report_category_id, p_description,
    COALESCE(p_quantity, 1), COALESCE(p_unit_price, 0), COALESCE(p_exchange_rate, 1),
    v_currency, p_supplier_id, p_supplier_currency,
    p_source_type, p_source_id,
    v_resolved_acct, p_shipping_company_id, p_clearing_agent_id,
    (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM public.shipment_cost_items WHERE shipment_id = p_shipment_id)
  ) RETURNING id INTO v_new_item_id;

  -- 2. Pay
  v_tx_desc := 'سداد بند تكلفة شحنة: ' || COALESCE(p_description, 'غير محدد')
               || ' (بند ' || v_new_item_id::text || ')';

  IF p_source_type = 'treasury' THEN
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_total_price THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_total_price;
    END IF;

    PERFORM public.spend_custody(
      p_source_id, v_currency, v_total_price, v_tx_desc,
      NULL, v_supplier_uuid, NULL, NULL, NULL,
      v_resolved_acct
    );

    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type = 'expense' AND amount = v_total_price AND currency = v_currency
    ORDER BY created_at DESC LIMIT 1;

    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id = v_company_id
      AND je.entry_date = CURRENT_DATE
    ORDER BY je.id DESC LIMIT 1;

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
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_total_price THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_total_price;
    END IF;

    DECLARE v_bank_res JSONB;
    BEGIN
      v_bank_res := public.withdraw_bank_account(
        p_source_id::integer, v_total_price, v_tx_desc,
        CASE WHEN v_supplier_uuid IS NOT NULL THEN 'supplier' ELSE NULL END,
        CASE WHEN v_supplier_uuid IS NOT NULL THEN v_supplier_uuid::text ELSE NULL END,
        NULL,
        v_resolved_acct
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
  INTEGER, TEXT, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, BIGINT, INTEGER, BIGINT, BIGINT
) TO authenticated, service_role;

-- ============================================================================
-- SECTION 3: Rewrite rpc_pay_shipment_cost_item — use stored entity info
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_pay_shipment_cost_item(bigint, text, bigint, integer);

CREATE OR REPLACE FUNCTION public.rpc_pay_shipment_cost_item(
  p_cost_item_id       bigint,
  p_source_type        text,
  p_source_id          bigint,
  p_expense_account_id integer DEFAULT NULL
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
  v_expense_acct   INTEGER;
BEGIN
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

  -- Resolve expense account from explicit > stored > entity accounts
  v_expense_acct := NULL;
  IF p_expense_account_id IS NOT NULL THEN
    v_expense_acct := p_expense_account_id;
  ELSIF r_item.expense_account_id IS NOT NULL THEN
    v_expense_acct := r_item.expense_account_id;
  ELSIF r_item.shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_expense_acct FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;
  ELSIF r_item.clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_expense_acct FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;
  ELSE
    -- Fallback to supplier's account
    v_supplier_id := NULL;
    IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
      BEGIN
        v_supplier_id := r_item.supplier_id::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_supplier_id := NULL;
      END;
    END IF;
    IF v_supplier_id IS NOT NULL THEN
      SELECT s.account_id INTO v_expense_acct FROM public.suppliers s WHERE s.id = v_supplier_id;
    END IF;
  END IF;

  -- Resolve company_id
  IF p_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_source_id;
  ELSE
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
      p_source_id, v_currency, v_amount, v_tx_desc,
      NULL, v_supplier_id, NULL, NULL, NULL,
      v_expense_acct
    );

    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type = 'expense' AND amount = v_amount AND currency = v_currency
    ORDER BY created_at DESC LIMIT 1;

    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id IS NOT DISTINCT FROM v_company_id
      AND je.entry_date = CURRENT_DATE
    ORDER BY je.id DESC LIMIT 1;

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
      p_source_id::integer, v_amount, v_tx_desc,
      CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
      CASE WHEN v_supplier_id IS NOT NULL THEN v_supplier_id::text ELSE NULL END,
      NULL,
      v_expense_acct
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

GRANT EXECUTE ON FUNCTION public.rpc_pay_shipment_cost_item(bigint, text, bigint, integer)
  TO authenticated, service_role;

-- ============================================================================
-- SECTION 4: Rewrite rpc_edit_profitability_expense — entity support
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_edit_profitability_expense(BIGINT, TEXT, NUMERIC, NUMERIC, TEXT, BIGINT, INTEGER);

CREATE OR REPLACE FUNCTION public.rpc_edit_profitability_expense(
  p_cost_item_id            BIGINT,
  p_new_description         TEXT,
  p_new_quantity            NUMERIC,
  p_new_unit_price          NUMERIC,
  p_new_source_type         TEXT,
  p_new_source_id           BIGINT,
  p_new_expense_account_id  INTEGER DEFAULT NULL,
  p_new_shipping_company_id BIGINT DEFAULT NULL,
  p_new_clearing_agent_id   BIGINT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r_item            RECORD;
  v_old_amount      NUMERIC;
  v_new_amount      NUMERIC;
  v_currency        TEXT;
  v_company_id      UUID;
  v_supplier_uuid   UUID;
  v_desc            TEXT;

  v_old_je_id       BIGINT;
  v_old_expense_acct BIGINT;
  v_old_treasury_acct BIGINT;
  v_reversal_je_id  BIGINT;
  v_reversal_desc   TEXT;

  v_new_treasury_tx_id BIGINT;
  v_new_bank_tx_id  INTEGER;
  v_new_je_id       BIGINT;
  v_new_tx_desc     TEXT;
  v_current_bal     NUMERIC;
  v_new_revision    INTEGER;
  v_bank_res        JSONB;
  v_resolved_acct   INTEGER;
BEGIN
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  IF r_item.treasury_transaction_id IS NULL AND r_item.bank_transaction_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تعديل بند لم يُسدّد بعد');
  END IF;

  v_old_amount := COALESCE(r_item.total_price, 0);
  v_new_amount := COALESCE(p_new_quantity, 1) * COALESCE(p_new_unit_price, 0);
  v_currency   := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');
  v_new_revision := COALESCE(r_item.revision_number, 0) + 1;

  IF v_new_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'المبلغ الجديد يجب أن يكون أكبر من صفر');
  END IF;

  -- Resolve supplier uuid
  v_supplier_uuid := NULL;
  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN v_supplier_uuid := r_item.supplier_id::uuid; EXCEPTION WHEN OTHERS THEN v_supplier_uuid := NULL; END;
  END IF;

  -- Resolve new expense account
  v_resolved_acct := NULL;
  IF p_new_shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_resolved_acct FROM public.shipping_companies sc WHERE sc.id = p_new_shipping_company_id;
  ELSIF p_new_clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_resolved_acct FROM public.clearing_agents ca WHERE ca.id = p_new_clearing_agent_id;
  ELSIF p_new_expense_account_id IS NOT NULL THEN
    SELECT id INTO v_resolved_acct FROM accounts WHERE id = p_new_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
  ELSE
    -- Keep existing
    v_resolved_acct := r_item.expense_account_id;
    IF v_resolved_acct IS NULL AND r_item.shipping_company_id IS NOT NULL THEN
      SELECT sc.account_id INTO v_resolved_acct FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;
    ELSIF v_resolved_acct IS NULL AND r_item.clearing_agent_id IS NOT NULL THEN
      SELECT ca.account_id INTO v_resolved_acct FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;
    ELSIF v_resolved_acct IS NULL AND v_supplier_uuid IS NOT NULL THEN
      SELECT s.account_id INTO v_resolved_acct FROM public.suppliers s WHERE s.id = v_supplier_uuid;
    END IF;
  END IF;

  -- Resolve company_id
  IF p_new_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_new_source_id;
  ELSE
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_new_source_id::integer;
  END IF;

  IF v_company_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم العثور على الشركة');
  END IF;

  -- REVERSAL of old payment
  IF r_item.journal_entry_id IS NOT NULL THEN
    v_old_je_id := r_item.journal_entry_id;

    SELECT ale.account_id INTO v_old_expense_acct
    FROM public.account_ledger_entries ale
    WHERE ale.journal_entry_id = v_old_je_id AND ale.debit > 0
    ORDER BY ale.id LIMIT 1;

    v_old_treasury_acct := public.resolve_gl_account(
      CASE v_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
      v_company_id
    );

    IF v_old_expense_acct IS NULL THEN
      v_old_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_reversal_desc := 'عكس سداد بند تكلفة: ' || COALESCE(r_item.description, '') || ' (بند ' || p_cost_item_id::text || ')';

    v_reversal_je_id := public.post_journal_entry(
      'expense_reversal',
      v_reversal_desc, CURRENT_DATE, v_company_id, auth.uid(),
      jsonb_build_array(
        jsonb_build_object('account_id', v_old_treasury_acct, 'debit', v_old_amount, 'credit', 0, 'currency', v_currency, 'description', v_reversal_desc),
        jsonb_build_object('account_id', v_old_expense_acct, 'debit', 0, 'credit', v_old_amount, 'currency', v_currency, 'description', v_reversal_desc)
      ),
      p_cost_item_id::TEXT
    );

    IF r_item.treasury_transaction_id IS NOT NULL AND r_item.payment_source_type = 'treasury' THEN
      UPDATE public.treasury_balances
      SET balance = balance + v_old_amount, updated_at = NOW()
      WHERE treasury_id = r_item.payment_source_id AND currency = v_currency;

      INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        journal_entry_id, created_by
      ) VALUES (
        r_item.payment_source_id, 'reversal', v_old_amount, v_currency,
        v_reversal_desc,
        (SELECT balance FROM public.treasury_balances WHERE treasury_id = r_item.payment_source_id AND currency = v_currency) - v_old_amount,
        (SELECT balance FROM public.treasury_balances WHERE treasury_id = r_item.payment_source_id AND currency = v_currency),
        v_reversal_je_id, auth.uid()
      );

    ELSIF r_item.bank_transaction_id IS NOT NULL AND r_item.payment_source_type = 'bank' THEN
      UPDATE public.bank_accounts
      SET balance = balance + v_old_amount, updated_at = NOW()
      WHERE id = r_item.payment_source_id::integer;

      INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, journal_entry_id, source_type, created_at, created_by
      ) VALUES (
        r_item.payment_source_id::integer, 'deposit', v_old_amount,
        (SELECT balance FROM public.bank_accounts WHERE id = r_item.payment_source_id::integer) - v_old_amount,
        (SELECT balance FROM public.bank_accounts WHERE id = r_item.payment_source_id::integer),
        v_reversal_desc, v_reversal_je_id, 'reversal', NOW(), auth.uid()
      );
    END IF;
  END IF;

  -- UPDATE cost item
  UPDATE public.shipment_cost_items
  SET description    = p_new_description,
      quantity       = COALESCE(p_new_quantity, 1),
      revision_number = v_new_revision,
      unit_price     = v_new_amount / GREATEST(COALESCE(p_new_quantity, 1), 0.0001),
      expense_account_id = COALESCE(v_resolved_acct, expense_account_id),
      shipping_company_id = COALESCE(p_new_shipping_company_id, shipping_company_id),
      clearing_agent_id = COALESCE(p_new_clearing_agent_id, clearing_agent_id)
  WHERE id = p_cost_item_id;

  -- NEW PAYMENT
  v_new_tx_desc := 'سداد بند تكلفة شحنة: ' || COALESCE(p_new_description, 'غير محدد')
                   || ' (بند ' || p_cost_item_id::text || ', تعديل ' || v_new_revision || ')';

  IF p_new_source_type = 'treasury' THEN
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_new_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_new_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_new_amount;
    END IF;

    PERFORM public.spend_custody(
      p_new_source_id, v_currency, v_new_amount, v_new_tx_desc,
      NULL, v_supplier_uuid, NULL, NULL, NULL,
      v_resolved_acct, 'shipment_expense', p_cost_item_id::TEXT
    );

    SELECT id INTO v_new_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_new_source_id
      AND type = 'expense' AND amount = v_new_amount AND currency = v_currency
    ORDER BY created_at DESC LIMIT 1;

    SELECT journal_entry_id INTO v_new_je_id
    FROM public.treasury_transactions WHERE id = v_new_treasury_tx_id;

    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_new_treasury_tx_id,
        payment_source_type     = 'treasury',
        payment_source_id       = p_new_source_id,
        journal_entry_id        = v_new_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', p_cost_item_id,
      'reversal_je_id', v_reversal_je_id,
      'new_je_id', v_new_je_id,
      'new_tx_id', v_new_treasury_tx_id,
      'revision', v_new_revision,
      'old_amount', v_old_amount,
      'new_amount', v_new_amount
    );

  ELSIF p_new_source_type = 'bank' THEN
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_new_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_new_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_new_amount;
    END IF;

    v_bank_res := public.withdraw_bank_account(
      p_new_source_id::integer, v_new_amount, v_new_tx_desc,
      CASE WHEN v_supplier_uuid IS NOT NULL THEN 'supplier' ELSE NULL END,
      CASE WHEN v_supplier_uuid IS NOT NULL THEN v_supplier_uuid::text ELSE NULL END,
      NULL,
      v_resolved_acct
    );

    v_new_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
    v_new_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

    UPDATE public.shipment_cost_items
    SET bank_transaction_id     = v_new_bank_tx_id,
        payment_source_type     = 'bank',
        payment_source_id       = p_new_source_id,
        journal_entry_id        = v_new_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', p_cost_item_id,
      'reversal_je_id', v_reversal_je_id,
      'new_je_id', v_new_je_id,
      'new_tx_id', v_new_bank_tx_id,
      'revision', v_new_revision,
      'old_amount', v_old_amount,
      'new_amount', v_new_amount
    );
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_edit_profitability_expense(
  BIGINT, TEXT, NUMERIC, NUMERIC, TEXT, BIGINT, INTEGER, BIGINT, BIGINT
) TO authenticated, service_role;

-- ============================================================================
-- SECTION 5: Backfill expense_account_id from entity accounts
-- ============================================================================

UPDATE public.shipment_cost_items sci
SET expense_account_id = sc.account_id, shipping_company_id = sci.vendor_id
FROM public.shipping_companies sc
WHERE sci.vendor_type = 'shipping_company'
  AND sci.vendor_id IS NOT NULL
  AND sci.vendor_id::bigint = sc.id
  AND sci.expense_account_id IS NULL;

UPDATE public.shipment_cost_items sci
SET expense_account_id = ca.account_id, clearing_agent_id = sci.vendor_id
FROM public.clearing_agents ca
WHERE sci.vendor_type = 'clearing_agent'
  AND sci.vendor_id IS NOT NULL
  AND sci.vendor_id::bigint = ca.id
  AND sci.expense_account_id IS NULL;

UPDATE public.shipment_cost_items sci
SET expense_account_id = s.account_id
FROM public.suppliers s
WHERE sci.supplier_id IS NOT NULL
  AND sci.supplier_id != ''
  AND sci.expense_account_id IS NULL
  AND sci.supplier_id = s.id::TEXT;

NOTIFY pgrst, 'reload schema';

COMMIT;
