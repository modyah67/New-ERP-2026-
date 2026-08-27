-- Migration 391: Fix Export Shipment COGS Amount (Fruit + Packing ONLY)

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_ledger(
    p_shipment_id bigint,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue numeric;
  v_discount numeric;
  v_desc text;
  v_old_amount numeric;
  v_company_id uuid;
  v_ar_acct bigint;
  v_rev_acct bigint;
  v_disc_acct bigint;
  v_cogs_acct bigint;
  v_inv_acct bigint;
  v_lines jsonb;
  v_sale_je_id bigint;
  v_disc_je_id bigint;
  v_je_id bigint;
  v_raw_ar bigint;
  v_base_revenue numeric;
  v_base_discount numeric;
  v_exch_rate numeric;
  v_cogs_amount numeric;
BEGIN
  -- Get Company ID from user or system default
  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No customer assigned');
  END IF;

  -- 1. Calculate Revenue from items
  SELECT COALESCE(
    SUM(COALESCE(NULLIF(amount, 0), quantity * COALESCE(export_price_per_carton, 0))),
    0
  )
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  -- FALLBACK: If items sum to 0 (or no items), fallback to total_revenue_foreign
  IF v_total_revenue = 0 THEN
    v_total_revenue := COALESCE(v_shipment.total_revenue_foreign, 0);
  END IF;

  v_discount := COALESCE(v_shipment.discount_amount, 0);

  -- Determine Exchange Rate
  v_exch_rate := COALESCE(v_shipment.exchange_rate, 1);
  IF v_exch_rate = 1 AND COALESCE(v_shipment.currency_code, 'EGP') != 'EGP' THEN
     SELECT exchange_rate INTO v_exch_rate
     FROM sys_currencies
     WHERE code = v_shipment.currency_code
     LIMIT 1;
     
     v_exch_rate := COALESCE(v_exch_rate, 1);
     
     -- Persist the fallback exchange rate to the shipment to keep it consistent
     UPDATE export_shipments 
     SET exchange_rate = v_exch_rate 
     WHERE id = p_shipment_id;
  END IF;

  v_base_revenue := v_total_revenue * v_exch_rate;
  v_base_discount := v_discount * v_exch_rate;

  -- Calculate true COGS (Fruit + Packing ONLY, excluding shipping/clearance/admin)
  v_cogs_amount := COALESCE(v_shipment.total_fruit_cost, 0) + COALESCE(v_shipment.total_packing_material_cost, 0);

  -- Handle old legacy ledger_entries reverse
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

  -- Reverse any existing JEs
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

  -- Post New JEs
  IF v_total_revenue > 0 THEN
    v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no;

    -- Also insert to legacy ledger_entries for backward compatibility if needed
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
        COALESCE(v_shipment.currency_code, 'USD'),
        'export_shipment', p_shipment_id::TEXT, v_desc || ' (خصم)', p_user_id
      );
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
        AND allow_posting = true
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
        AND a.company_id = v_company_id
        AND a.is_active = true
        AND a.allow_posting = true
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
      RAISE EXCEPTION 'لم يتم العثور على حساب عملاء (1020) ورقي للشحنة %', v_shipment.shipment_no;
    END IF;

    -- Revenue: prefer 4101, leaf only
    SELECT id INTO v_rev_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND account_code = '4101'
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
      ORDER BY account_code ASC
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

    -- COGS & Inventory Accounts
    SELECT id INTO v_cogs_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND account_code = '5000'
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true
    LIMIT 1;

    SELECT id INTO v_inv_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND account_code = '1031'
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true
    LIMIT 1;

    IF v_inv_acct IS NULL THEN
      SELECT id INTO v_inv_acct
      FROM accounts
      WHERE company_id = v_company_id
        AND account_code = '1030'
        AND is_leaf = true
        AND is_active = true
        AND allow_posting = true
      LIMIT 1;
    END IF;

    -- JOURNAL ENTRY 1: Sale & COGS
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v_ar_acct, 'debit', v_total_revenue, 'credit', 0,
        'base_debit', v_base_revenue, 'base_credit', 0,
        'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc),
      jsonb_build_object('account_id', v_rev_acct, 'debit', 0, 'credit', v_total_revenue,
        'base_debit', 0, 'base_credit', v_base_revenue,
        'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc)
    );

    IF v_cogs_amount > 0 AND v_cogs_acct IS NOT NULL AND v_inv_acct IS NOT NULL THEN
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account_id', v_cogs_acct, 'debit', v_cogs_amount, 'credit', 0,
          'base_debit', v_cogs_amount, 'base_credit', 0,
          'currency', 'EGP', 'description', v_desc || ' - تكلفة البضاعة المباعة'),
        jsonb_build_object('account_id', v_inv_acct, 'debit', 0, 'credit', v_cogs_amount,
          'base_debit', 0, 'base_credit', v_cogs_amount,
          'currency', 'EGP', 'description', v_desc || ' - منصرف من مخزن التام')
      );
    END IF;

    v_sale_je_id := public.post_journal_entry(
      'export_shipment', v_desc || ' - قيد البيع', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
      v_company_id, p_user_id, v_lines
    );
    UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_sale_je_id;

    -- JOURNAL ENTRY 2: Discount
    IF v_discount > 0 THEN
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_disc_acct, 'debit', v_discount, 'credit', 0,
          'base_debit', v_base_discount, 'base_credit', 0,
          'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc || ' (خصم)'),
        jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', v_discount,
          'base_debit', 0, 'base_credit', v_base_discount,
          'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc || ' (خصم)')
      );

      v_disc_je_id := public.post_journal_entry(
        'export_discount', v_desc || ' - خصم', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
        v_company_id, p_user_id, v_lines
      );
      UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_disc_je_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'sale_je_id', v_sale_je_id, 'disc_je_id', v_disc_je_id);
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'Zero revenue, no entries posted');
END;
$$;

COMMIT;