-- ============================================================================
-- Migration: Phase 3 - rpc_pay_shipment_cost_item
--
-- ما يفعله:
--   يُسدّد بنداً واحداً من تكاليف الشحنة نقداً من خزينة أو حساب بنكي.
--   يُسجّل القيد المحاسبي ويختم البند بـ treasury_transaction_id / bank_transaction_id.
--   ذري بالكامل: RAISE EXCEPTION عند أي فشل → rollback تلقائي.
--
-- Signature:
--   rpc_pay_shipment_cost_item(
--     p_cost_item_id      bigint,
--     p_source_type       text,    -- 'treasury' | 'bank'
--     p_source_id         bigint
--   ) RETURNS json
--
-- Logic:
--   1. تحميل البند والتحقق منه (موجود؟ مدفوع مسبقاً؟)
--   2. تحميل مصدر الدفع والتحقق من الرصيد.
--   3. تنفيذ الخصم عبر spend_custody() أو withdraw_bank_account().
--   4. ختم البند بـ treasury_transaction_id أو bank_transaction_id.
--   5. إعادة {success: true, tx_id: ...}
-- ============================================================================

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
BEGIN
  -- ── 1. تحميل البند والتحقق منه ──
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  -- تحقق: هل البند مدفوع مسبقاً؟
  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'هذا البند مدفوع مسبقاً');
  END IF;

  -- تحقق: نوع المصدر صحيح؟
  IF p_source_type NOT IN ('treasury', 'bank') THEN
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح: ' || p_source_type);
  END IF;

  -- المبلغ الأصلي بعملة المورد (للخصم الفعلي)
  v_amount   := COALESCE(r_item.total_price, 0);
  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');
  v_tx_desc  := 'سداد بند تكلفة شحنة: ' || COALESCE(r_item.description, 'غير محدد')
                 || ' (بند ' || p_cost_item_id::text || ')';

  IF v_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  -- استخراج supplier_id من النص UUID (مخزون كـ text في الجدول)
  v_supplier_id := NULL;
  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      v_supplier_id := r_item.supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
    END;
  END IF;

  -- ── 2 & 3. خصم من المصدر المختار ──
  IF p_source_type = 'treasury' THEN
    -- قفل صف الرصيد لمنع Race Condition
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    -- الخصم عبر spend_custody (يُحدّث الرصيد + يُسجّل treasury_transaction + يُحدّث supplier)
    PERFORM public.spend_custody(
      p_source_id,
      v_currency,
      v_amount,
      v_tx_desc,
      NULL,           -- customer_id
      v_supplier_id,  -- supplier_id
      NULL,           -- clearing_agent_id
      NULL,           -- shipping_company_id
      NULL            -- shareholder_id
    );

    -- استرجاع الـ tx id المُنشأ
    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type        = 'expense'
      AND amount      = v_amount
      AND currency    = v_currency
      AND supplier_id IS NOT DISTINCT FROM v_supplier_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- ختم البند
    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_treasury_tx_id,
        payment_source_type     = 'treasury',
        payment_source_id       = p_source_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_treasury_tx_id, 'type', 'treasury');

  ELSIF p_source_type = 'bank' THEN
    -- قفل صف البنك
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    -- الخصم عبر withdraw_bank_account
    SELECT (public.withdraw_bank_account(
      p_source_id::integer,
      v_amount,
      v_tx_desc,
      CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
      v_supplier_id::text,
      NULL -- counterparty_name
    ) ->> 'id')::integer INTO v_bank_tx_id;

    -- ختم البند
    UPDATE public.shipment_cost_items
    SET bank_transaction_id     = v_bank_tx_id,
        payment_source_type     = 'bank',
        payment_source_id       = p_source_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_bank_tx_id, 'type', 'bank');
  END IF;

  -- مسار لا يُصل إليه نظرياً (تحقق النوع سابقاً)
  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

-- منح الصلاحيات
GRANT EXECUTE ON FUNCTION public.rpc_pay_shipment_cost_item(bigint, text, bigint)
  TO authenticated, service_role;
