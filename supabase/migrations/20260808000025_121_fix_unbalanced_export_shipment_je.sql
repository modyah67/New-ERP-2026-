-- Migration 121: Fix unbalanced export shipment journal entries
--
-- Root cause: Sale entry was UNBALANCED (Dr. AR = net_amount, Cr. Revenue = total_revenue)
-- post_journal_entry requires debit == credit, so it silently failed.
-- The BEGIN/EXCEPTION block swallowed the error.
--
-- Fix:
-- 1. Sale entry: Dr. AR = total_revenue, Cr. Revenue = total_revenue (balanced)
-- 2. Discount entry: Dr. Discount = discount, Cr. AR = discount (balanced)
-- 3. Remove silent EXCEPTION swallowing — let errors propagate

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

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  v_discount := COALESCE(v_shipment.discount_amount, 0);

  -- Legacy customer balance
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

  -- Delete legacy ledger entries
  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Reverse ALL old enterprise journal entries (sale + discount)
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

    -- Legacy ledger entries
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      COALESCE(v_shipment.currency_code, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );

    IF v_discount > 0 THEN
      INSERT INTO ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_text, description, created_by
      ) VALUES (
        'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
        COALESCE(v_shipment.currency_code, 'USD'),
        'export_shipment', p_shipment_id::TEXT, v_desc || ' (خصم)', p_user_id
      );
    END IF;

    -- Resolve company
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    IF v_company_id IS NULL THEN
      RAISE EXCEPTION 'No company found in sys_companies';
    END IF;

    -- Resolve GL Accounts
    SELECT account_id INTO v_ar_acct FROM customers WHERE id = v_shipment.customer_id;
    IF v_ar_acct IS NULL THEN
        v_ar_acct := public.resolve_gl_account('1020', v_company_id);
    END IF;

    SELECT id INTO v_rev_acct FROM accounts
    WHERE company_id = v_company_id AND account_type = 'revenue' ORDER BY account_code ASC LIMIT 1;
    IF v_rev_acct IS NULL THEN v_rev_acct := v_ar_acct; END IF;

    SELECT id INTO v_disc_acct FROM accounts
    WHERE company_id = v_company_id AND (account_code = '4105' OR account_name ILIKE '%خصم%') LIMIT 1;
    IF v_disc_acct IS NULL THEN v_disc_acct := v_rev_acct; END IF;

    -- ===== JOURNAL ENTRY 1: Sale (Dr. AR = total_revenue, Cr. Revenue = total_revenue) =====
    -- MUST be balanced: debit == credit
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v_ar_acct, 'debit', v_total_revenue, 'credit', 0,
        'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc),
      jsonb_build_object('account_id', v_rev_acct, 'debit', 0, 'credit', v_total_revenue,
        'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc)
    );

    v_sale_je_id := public.post_journal_entry(
      'export_shipment', v_desc, COALESCE(v_shipment.shipment_date, CURRENT_DATE),
      v_company_id, p_user_id, v_lines
    );
    UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_sale_je_id;

    -- ===== JOURNAL ENTRY 2: Discount (Dr. Discount, Cr. AR) =====
    -- MUST be balanced: debit == credit
    IF v_discount > 0 THEN
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_disc_acct, 'debit', v_discount, 'credit', 0,
          'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc || ' (خصم)'),
        jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', v_discount,
          'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc || ' (خصم)')
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
