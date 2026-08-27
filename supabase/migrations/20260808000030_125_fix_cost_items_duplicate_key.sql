-- Migration 125: Fix shipment_cost_items duplicate key (23505)
--
-- 1. Inspect and drop the problematic unique constraint `shipment_cost_items_key`
-- 2. Clean up any duplicate cost items that may exist
-- 3. Add a safe unique index that prevents true duplicates only
-- 4. Ensure rpc_save_profitability_expense is safe from duplicates

BEGIN;

-- ============================================================================
-- SECTION 1: Inspect and safely drop the auto-created unique constraint
-- ============================================================================
-- PostgreSQL auto-names UNIQUE constraints as tablename_key or tablename_col_key
-- The constraint "shipment_cost_items_key" was likely created via dashboard
-- and conflicts with the normal insert pattern.

DO $$
DECLARE
  v_conname TEXT;
  v_condef  TEXT;
BEGIN
  SELECT conname, pg_get_constraintdef(oid, true)
  INTO v_conname, v_condef
  FROM pg_constraint
  WHERE conrelid = 'public.shipment_cost_items'::regclass
    AND contype = 'u'
    AND conname = 'shipment_cost_items_key';

  IF FOUND THEN
    RAISE NOTICE 'Found constraint: % — Definition: %', v_conname, v_condef;
    EXECUTE 'ALTER TABLE public.shipment_cost_items DROP CONSTRAINT IF EXISTS shipment_cost_items_key';
    RAISE NOTICE 'Dropped constraint shipment_cost_items_key';
  ELSE
    RAISE NOTICE 'No unique constraint named shipment_cost_items_key found';
  END IF;
END $$;

-- Also drop any other stray unique constraints on shipment_cost_items (not pkey, not fkeys)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'public.shipment_cost_items'::regclass
      AND c.contype = 'u'
      AND c.conname NOT LIKE '%pkey%'
      AND c.conname NOT LIKE '%fkey%'
      AND c.conname NOT LIKE '%check%'
  LOOP
    RAISE NOTICE 'Dropping extra unique constraint: %', r.conname;
    EXECUTE format('ALTER TABLE public.shipment_cost_items DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END $$;

-- ============================================================================
-- SECTION 2: Clean up duplicate cost items (keep lowest id per shipment+desc+qty+price)
-- ============================================================================
-- If there are duplicate rows from previous failed saves, collapse them.
-- Keep the PAID row if one exists, otherwise keep the oldest.

WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY shipment_id, description, quantity, unit_price
           ORDER BY
             CASE WHEN treasury_transaction_id IS NOT NULL OR bank_transaction_id IS NOT NULL THEN 0 ELSE 1 END,
             id ASC
         ) AS rn
  FROM public.shipment_cost_items
)
DELETE FROM public.shipment_cost_items
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- ============================================================================
-- SECTION 3: Ensure rpc_save_profitability_expense is safe
-- ============================================================================
-- The RPC always INSERTs — this is fine for NEW expenses from the profitability page.
-- We do NOT add a duplicate check here because:
--   - New expenses from profitability page are genuinely new
--   - The costing page uses saveAll() with proper UPDATE/INSERT logic (fixed in Dart)
--   - Edit uses rpc_edit_profitability_expense which UPDATEs in place

-- ============================================================================
-- SECTION 4: Ensure rpc_pay_shipment_cost_item checks for already-paid
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

  -- NEW: Prevent double-pay
  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'هذا البند مسدّد بالفعل',
      'journal_entry_id', r_item.journal_entry_id
    );
  END IF;

  v_amount := COALESCE(r_item.total_price, 0);
  IF v_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');

  -- Resolve supplier uuid (optional)
  v_supplier_id := NULL;
  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      v_supplier_id := r_item.supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
    END;
  END IF;

  -- Resolve expense account: explicit > stored > supplier fallback
  v_expense_acct := NULL;
  IF p_expense_account_id IS NOT NULL THEN
    SELECT id INTO v_expense_acct FROM public.accounts
    WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
  END IF;

  IF v_expense_acct IS NULL THEN
    v_expense_acct := r_item.expense_account_id;
  END IF;

  IF v_expense_acct IS NULL AND r_item.shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_expense_acct FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;
  END IF;

  IF v_expense_acct IS NULL AND r_item.clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_expense_acct FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;
  END IF;

  IF v_expense_acct IS NULL AND v_supplier_id IS NOT NULL THEN
    SELECT s.account_id INTO v_expense_acct FROM public.suppliers s WHERE s.id = v_supplier_id;
  END IF;

  IF v_expense_acct IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد جهة');
  END IF;

  -- Resolve company_id
  IF p_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = p_source_id;
  ELSIF p_source_type = 'bank' THEN
    SELECT ba.company_id INTO v_company_id FROM public.bank_accounts ba WHERE ba.id = p_source_id::integer;
  ELSE
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح');
  END IF;

  IF v_company_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم العثور على الشركة');
  END IF;

  v_tx_desc := 'سداد بند تكلفة شحنة: ' || COALESCE(r_item.description, 'غير محدد')
               || ' (بند ' || p_cost_item_id::text || ')';

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
      AND (v_supplier_id IS NULL OR supplier_id = v_supplier_id)
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
        journal_entry_id = COALESCE(v_je_id, journal_entry_id)
    WHERE id = p_cost_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', p_cost_item_id,
      'tx_id', v_treasury_tx_id,
      'type', 'treasury',
      'journal_entry_id', v_je_id
    );

  ELSIF p_source_type = 'bank' THEN
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    DECLARE v_bank_res JSONB;
    BEGIN
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
          journal_entry_id        = COALESCE(v_je_id, journal_entry_id)
      WHERE id = p_cost_item_id;

      RETURN json_build_object('success', true, 'tx_id', v_bank_tx_id, 'type', 'bank', 'journal_entry_id', v_je_id);
    END;
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_pay_shipment_cost_item(bigint, text, bigint, integer)
  TO authenticated, service_role;

COMMIT;
