-- Migration 123: Standalone Export Discount Journal Entry
--
-- Dedicated RPC for discount that doesn't depend on the complex ledger sync.
-- All account lookups validate is_leaf=true, allow_posting=true, is_active=true.

CREATE OR REPLACE FUNCTION public.rpc_apply_export_discount(
  p_shipment_id BIGINT,
  p_discount_amount NUMERIC,
  p_discount_reason TEXT DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue NUMERIC := 0;
  v_company_id UUID;
  v_ar_acct BIGINT;
  v_rev_acct BIGINT;
  v_disc_acct BIGINT;
  v_currency TEXT;
  v_desc TEXT;
  v_raw_ar BIGINT;
  v_sale_je_id BIGINT := NULL;
  v_disc_je_id BIGINT := NULL;
BEGIN
  SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No customer assigned');
  END IF;

  SELECT COALESCE(
    SUM(COALESCE(NULLIF(amount, 0), quantity * COALESCE(export_price_per_carton, 0))),
    0
  )
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  v_currency := COALESCE(v_shipment.currency_code, 'USD');
  v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no;

  -- Reverse old sale + discount JEs
  FOR v_sale_je_id IN
    SELECT id FROM journal_entries
    WHERE source_type IN ('export_shipment', 'export_discount')
      AND source_id = p_shipment_id::text
  LOOP
    PERFORM public.reverse_journal_entry(v_sale_je_id, p_user_id, 'تحديث الخصم');
  END LOOP;
  DELETE FROM account_ledger_entries
  WHERE journal_entry_id IN (
    SELECT id FROM journal_entries
    WHERE source_type IN ('export_shipment', 'export_discount')
      AND source_id = p_shipment_id::text
  );
  DELETE FROM journal_entries
  WHERE source_type IN ('export_shipment', 'export_discount')
    AND source_id = p_shipment_id::text;

  -- Resolve company
  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No company found');
  END IF;

  -- AR: customer leaf account only
  SELECT c.account_id INTO v_raw_ar
  FROM customers c
  WHERE c.id = v_shipment.customer_id;

  IF v_raw_ar IS NOT NULL THEN
    SELECT id INTO v_ar_acct
    FROM accounts
    WHERE id = v_raw_ar
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true;
  END IF;

  IF v_ar_acct IS NULL THEN
    SELECT a.id INTO v_ar_acct
    FROM customers c
    JOIN accounts a ON a.id = c.account_id
    WHERE c.id = v_shipment.customer_id
      AND a.is_leaf = true
      AND a.is_active = true
      AND a.allow_posting = true
    LIMIT 1;
  END IF;

  IF v_ar_acct IS NULL THEN
    SELECT a.id INTO v_ar_acct
    FROM customers c
    JOIN accounts a ON (
      a.name ILIKE 'Customer - ' || COALESCE(c.name, '') || '%'
      OR a.account_name ILIKE 'عميل - ' || COALESCE(c.name, '') || '%'
    )
    WHERE c.id = v_shipment.customer_id
      AND a.is_leaf = true
      AND a.is_active = true
      AND a.allow_posting = true
    ORDER BY a.id DESC
    LIMIT 1;
  END IF;

  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND account_code LIKE '102%'
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true
    ORDER BY account_code ASC
    LIMIT 1;
  END IF;

  IF v_ar_acct IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على حساب عميل ورقي');
  END IF;

  -- Revenue: leaf account only
  SELECT id INTO v_rev_acct
  FROM accounts
  WHERE company_id = v_company_id
    AND account_code = '4200'
    AND is_leaf = true
    AND is_active = true
    AND allow_posting = true
  LIMIT 1;

  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND account_type = 'revenue'
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true
    ORDER BY
      CASE
        WHEN account_code = '4200' THEN 0
        WHEN account_code LIKE '42%' THEN 1
        WHEN account_code LIKE '43%' THEN 2
        ELSE 3
      END,
      account_code ASC
    LIMIT 1;
  END IF;

  IF v_rev_acct IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على حساب إيرادات ورقي');
  END IF;

  -- Discount: leaf account only
  SELECT id INTO v_disc_acct
  FROM accounts
  WHERE company_id = v_company_id
    AND account_code = '4105'
    AND is_leaf = true
    AND is_active = true
    AND allow_posting = true
  LIMIT 1;

  IF v_disc_acct IS NULL THEN
    SELECT id INTO v_disc_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND (account_name ILIKE '%خصم%' OR account_name ILIKE '%discount%')
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true
    LIMIT 1;
  END IF;

  IF v_disc_acct IS NULL AND p_discount_amount > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على حساب خصم مبيعات ورقي (4105)');
  END IF;

  -- 1. Sale JE: Dr. AR = total_revenue, Cr. Revenue = total_revenue
  IF v_total_revenue > 0 THEN
    v_sale_je_id := public.post_journal_entry(
      'export_shipment', v_desc || ' - قيد البيع', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
      v_company_id, p_user_id,
      jsonb_build_array(
        jsonb_build_object('account_id', v_ar_acct, 'debit', v_total_revenue, 'credit', 0,
          'currency', v_currency, 'description', v_desc),
        jsonb_build_object('account_id', v_rev_acct, 'debit', 0, 'credit', v_total_revenue,
          'currency', v_currency, 'description', v_desc)
      ),
      p_shipment_id::TEXT
    );
    UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_sale_je_id;
  END IF;

  -- 2. Discount JE: Dr. Discount, Cr. AR
  IF p_discount_amount > 0 THEN
    v_desc := 'خصم شحنة تصدير رقم ' || v_shipment.shipment_no;
    IF p_discount_reason IS NOT NULL AND p_discount_reason != '' THEN
      v_desc := v_desc || ' — ' || p_discount_reason;
    END IF;

    v_disc_je_id := public.post_journal_entry(
      'export_discount', v_desc || ' - قيد الخصم', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
      v_company_id, p_user_id,
      jsonb_build_array(
        jsonb_build_object('account_id', v_disc_acct, 'debit', p_discount_amount, 'credit', 0,
          'currency', v_currency, 'description', v_desc),
        jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_discount_amount,
          'currency', v_currency, 'description', v_desc)
      ),
      p_shipment_id::TEXT
    );
    UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_disc_je_id;
  END IF;

  UPDATE export_shipments
  SET applied_discount_amount = p_discount_amount
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'total_revenue', v_total_revenue,
    'discount', p_discount_amount,
    'sale_journal_entry_id', v_sale_je_id,
    'discount_journal_entry_id', v_disc_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_apply_export_discount(BIGINT, NUMERIC, TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
