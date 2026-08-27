-- Migration 122: Fix export shipment journal entries — use LEAF accounts only
--
-- Root cause: rpc_process_export_shipment_ledger picked parent revenue account
-- (account_code '4', is_leaf=false) which is blocked by trg_reject_non_leaf.
-- Error: "لا يمكن القيود على الحساب غير الورقي 4"
--
-- Fix:
-- 1. Ensure Sales Discount leaf account 4105 exists per company
-- 2. Resolve AR / Revenue / Discount accounts with is_leaf=true validation
-- 3. Use quantity * export_price_per_carton when item amount is zero

-- ============================================================
-- 1. Ensure Sales Discount account (4105) exists
-- ============================================================
DO $$
DECLARE
  v_company RECORD;
  v_parent_id BIGINT;
BEGIN
  FOR v_company IN SELECT id FROM sys_companies LOOP
    SELECT id INTO v_parent_id
    FROM accounts
    WHERE company_id = v_company.id
      AND account_code IN ('4', '4000')
    ORDER BY CASE WHEN account_code = '4' THEN 0 ELSE 1 END, id ASC
    LIMIT 1;

    IF v_parent_id IS NULL THEN
      SELECT id INTO v_parent_id
      FROM accounts
      WHERE company_id = v_company.id AND account_type = 'revenue' AND is_leaf = false
      ORDER BY account_code ASC
      LIMIT 1;
    END IF;

    INSERT INTO accounts (
      account_code, name, account_name, account_type, sort_order,
      company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active, normal_balance
    )
    SELECT
      '4105', 'Sales Discount Allowed', 'خصم مبيعات', 'expense', 4105,
      v_company.id, v_parent_id, 5, true, true, false, true, 'Debit'
    WHERE NOT EXISTS (
      SELECT 1 FROM accounts WHERE account_code = '4105'
    );
  END LOOP;
END $$;

-- ============================================================
-- 2. Fixed ledger RPC
-- ============================================================
CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_ledger(
  p_shipment_id BIGINT,
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
  v_discount NUMERIC := 0;
  v_old_amount NUMERIC := 0;
  v_desc TEXT;
  v_company_id UUID;
  v_je_id BIGINT;
  v_ar_acct BIGINT;
  v_rev_acct BIGINT;
  v_disc_acct BIGINT;
  v_lines JSONB := '[]'::jsonb;
  v_sale_je_id BIGINT := NULL;
  v_discount_je_id BIGINT := NULL;
  v_raw_ar BIGINT;
BEGIN
  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No customer assigned');
  END IF;

  SELECT COALESCE(
    SUM(COALESCE(NULLIF(amount, 0), quantity * COALESCE(export_price_per_carton, 0))),
    0
  )
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  v_discount := COALESCE(v_shipment.discount_amount, 0);

  SELECT
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  UPDATE customers
  SET balance = COALESCE(balance, 0) - v_old_amount + (v_total_revenue - v_discount),
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  FOR v_je_id IN
      SELECT id FROM journal_entries
      WHERE source_type IN ('export_shipment', 'export_discount')
        AND source_id = p_shipment_id::text
  LOOP
      PERFORM public.reverse_journal_entry(v_je_id, p_user_id, 'تحديث الشحنة');
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

  IF v_total_revenue > 0 THEN
    v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no;

    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      COALESCE(v_shipment.currency_code, 'EGP'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );

    IF v_discount > 0 THEN
      INSERT INTO ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_text, description, created_by
      ) VALUES (
        'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
        COALESCE(v_shipment.currency_code, 'EGP'),
        'export_shipment', p_shipment_id::TEXT, v_desc || ' (خصم)', p_user_id
      );
    END IF;

    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    IF v_company_id IS NULL THEN
      RAISE EXCEPTION 'No company found in sys_companies';
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
      RAISE EXCEPTION 'لم يتم العثور على حساب عميل ورقي للشحنة %', v_shipment.shipment_no;
    END IF;

    -- Revenue: prefer Export Revenue (4200), leaf only
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
      RAISE EXCEPTION 'لم يتم العثور على حساب إيرادات ورقي للشحنة %', v_shipment.shipment_no;
    END IF;

    -- Discount: prefer 4105, leaf only
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

    IF v_disc_acct IS NULL AND v_discount > 0 THEN
      RAISE EXCEPTION 'لم يتم العثور على حساب خصم مبيعات ورقي (4105) للشحنة %', v_shipment.shipment_no;
    END IF;

    -- JOURNAL ENTRY 1: Sale (Dr. AR = total_revenue, Cr. Revenue = total_revenue)
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v_ar_acct, 'debit', v_total_revenue, 'credit', 0,
        'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc),
      jsonb_build_object('account_id', v_rev_acct, 'debit', 0, 'credit', v_total_revenue,
        'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc)
    );

    v_sale_je_id := public.post_journal_entry(
      'export_shipment', v_desc || ' - قيد البيع', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
      v_company_id, p_user_id, v_lines
    );
    UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_sale_je_id;

    -- JOURNAL ENTRY 2: Discount (Dr. Discount, Cr. AR)
    IF v_discount > 0 THEN
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_disc_acct, 'debit', v_discount, 'credit', 0,
          'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc || ' (خصم)'),
        jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', v_discount,
          'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc || ' (خصم)')
      );

      v_discount_je_id := public.post_journal_entry(
        'export_discount', v_desc || ' - قيد الخصم', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
        v_company_id, p_user_id, v_lines
      );
      UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_discount_je_id;
    END IF;
  END IF;

  UPDATE export_shipments
  SET applied_discount_amount = v_discount
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'total_revenue', v_total_revenue,
    'discount', v_discount,
    'net_amount', v_total_revenue - v_discount,
    'sale_journal_entry_id', v_sale_je_id,
    'discount_journal_entry_id', v_discount_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(BIGINT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
