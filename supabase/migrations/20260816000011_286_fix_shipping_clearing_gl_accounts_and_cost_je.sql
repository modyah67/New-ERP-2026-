-- Migration 286: Fix Shipping Companies & Clearing Agents GL Accounts and Export Shipment Cost Journal Entries
-- 1. Ensure parent accounts 2103 (شركات الشحن) and 2104 (التخليص الجمركي) exist in accounts table under 20 (الخصوم)
-- 2. Ensure child accounts exist for all shipping companies (2103xx) and clearing agents (2104xx) and link FKs
-- 3. Update triggers trg_create_shipping_company_account and trg_create_clearing_agent_account
-- 4. Upgrade rpc_process_export_shipment_ledger to post Export Shipment Cost Journal Entries (export_cost)
-- 5. Backfill and link existing shipment cost items to journal entries

BEGIN;

-- ── 1. Create Parent Accounts 2103 and 2104 in accounts table ──
DO $$
DECLARE
  v_parent_20_id BIGINT;
  v_company_id UUID;
  v_parent_2103_id BIGINT;
  v_parent_2104_id BIGINT;
  v_expense_6130_id BIGINT;
  v_parent_6_id BIGINT;
  v_sc RECORD;
  v_ca RECORD;
  v_code TEXT;
  v_new_acc_id BIGINT;
  v_shipment RECORD;
BEGIN
  -- Resolve default company
  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  -- Resolve parent 20 (الخصوم)
  SELECT id INTO v_parent_20_id FROM public.accounts WHERE account_code = '20' LIMIT 1;

  -- Insert/Ensure 2103 (شركات الشحن)
  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, level,
    is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
  ) VALUES (
    '2103', 'Shipping Companies', 'شركات الشحن', 'liability', 1,
    false, false, true, true, v_parent_20_id, v_company_id, 2103
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      parent_id = COALESCE(public.accounts.parent_id, EXCLUDED.parent_id),
      company_id = COALESCE(public.accounts.company_id, EXCLUDED.company_id)
  RETURNING id INTO v_parent_2103_id;

  IF v_parent_2103_id IS NULL THEN
    SELECT id INTO v_parent_2103_id FROM public.accounts WHERE account_code = '2103' LIMIT 1;
  END IF;

  -- Insert/Ensure 2104 (التخليص الجمركي)
  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, level,
    is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
  ) VALUES (
    '2104', 'Customs Clearance', 'التخليص الجمركي', 'liability', 1,
    false, false, true, true, v_parent_20_id, v_company_id, 2104
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      parent_id = COALESCE(public.accounts.parent_id, EXCLUDED.parent_id),
      company_id = COALESCE(public.accounts.company_id, EXCLUDED.company_id)
  RETURNING id INTO v_parent_2104_id;

  IF v_parent_2104_id IS NULL THEN
    SELECT id INTO v_parent_2104_id FROM public.accounts WHERE account_code = '2104' LIMIT 1;
  END IF;

  -- Ensure 6130 (Operating Expenses) exists under 6 (Expenses)
  SELECT id INTO v_parent_6_id FROM public.accounts WHERE account_code = '6' LIMIT 1;
  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, level,
    is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
  ) VALUES (
    '6130', 'Operating Expenses', 'مصروفات تشغيل وشحن وتخليص', 'expense', 2,
    true, true, true, true, v_parent_6_id, v_company_id, 6130
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      is_leaf = true,
      allow_posting = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name;

  -- ── 2. Sync Child Accounts for Shipping Companies ──
  FOR v_sc IN SELECT * FROM public.shipping_companies ORDER BY id ASC LOOP
    -- Compute code: 210301, 210302, ...
    v_code := '2103' || LPAD(COALESCE(NULLIF(regexp_replace(v_sc.code, '[^0-9]', '', 'g'), ''), v_sc.id::text), 2, '0');

    INSERT INTO public.accounts (
      account_code, name, account_name, account_type, sort_order,
      company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
    ) VALUES (
      v_code,
      'Shipping - ' || COALESCE(v_sc.name, ''),
      'شركة شحن - ' || COALESCE(v_sc.name, ''),
      'liability',
      COALESCE(v_code::bigint, 210399),
      v_sc.company_id,
      v_parent_2103_id,
      2,
      true,
      true,
      false,
      true
    )
    ON CONFLICT (account_code) DO UPDATE
    SET is_active = true,
        is_leaf = true,
        allow_posting = true,
        name = EXCLUDED.name,
        account_name = EXCLUDED.account_name,
        parent_id = v_parent_2103_id
    RETURNING id INTO v_new_acc_id;

    UPDATE public.shipping_companies
    SET account_id = v_new_acc_id
    WHERE id = v_sc.id;
  END LOOP;

  -- ── 3. Sync Child Accounts for Clearing Agents ──
  FOR v_ca IN SELECT * FROM public.clearing_agents ORDER BY id ASC LOOP
    -- Compute code: 210401, 210402, ...
    v_code := '2104' || LPAD(COALESCE(NULLIF(regexp_replace(v_ca.code, '[^0-9]', '', 'g'), ''), v_ca.id::text), 2, '0');

    INSERT INTO public.accounts (
      account_code, name, account_name, account_type, sort_order,
      company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
    ) VALUES (
      v_code,
      'Clearing - ' || COALESCE(v_ca.name, ''),
      'مخلص جمركي - ' || COALESCE(v_ca.name, ''),
      'liability',
      COALESCE(v_code::bigint, 210499),
      v_ca.company_id,
      v_parent_2104_id,
      2,
      true,
      true,
      false,
      true
    )
    ON CONFLICT (account_code) DO UPDATE
    SET is_active = true,
        is_leaf = true,
        allow_posting = true,
        name = EXCLUDED.name,
        account_name = EXCLUDED.account_name,
        parent_id = v_parent_2104_id
    RETURNING id INTO v_new_acc_id;

    UPDATE public.clearing_agents
    SET account_id = v_new_acc_id
    WHERE id = v_ca.id;
  END LOOP;

END $$;


-- ── 4. Upgrade Trigger Functions for Shipping Companies & Clearing Agents ──
CREATE OR REPLACE FUNCTION public.create_shipping_company_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_parent_20_id BIGINT;
  v_code TEXT;
BEGIN
  -- Resolve or create parent 2103
  SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '2103' LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_20_id FROM public.accounts WHERE account_code = '20' LIMIT 1;
    INSERT INTO public.accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '2103', 'Shipping Companies', 'شركات الشحن', 'liability', 1,
      false, false, true, true, v_parent_20_id, NEW.company_id, 2103
    ) RETURNING id INTO v_parent_id;
  END IF;

  v_code := public.get_next_entity_account_code('shipping_company', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Shipping - ' || COALESCE(NEW.name, ''),
    'شركة شحن - ' || COALESCE(NEW.name, ''),
    'liability',
    COALESCE(v_code::bigint, 210399),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      is_leaf = true,
      allow_posting = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      parent_id = v_parent_id,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.shipping_companies
  SET account_id = v_new_account_id,
      code = COALESCE(NEW.code, v_code)
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_create_shipping_company_account ON public.shipping_companies;
CREATE TRIGGER trg_create_shipping_company_account
AFTER INSERT ON public.shipping_companies
FOR EACH ROW
EXECUTE FUNCTION public.create_shipping_company_account();


CREATE OR REPLACE FUNCTION public.create_clearing_agent_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_parent_20_id BIGINT;
  v_code TEXT;
BEGIN
  -- Resolve or create parent 2104
  SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '2104' LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_20_id FROM public.accounts WHERE account_code = '20' LIMIT 1;
    INSERT INTO public.accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '2104', 'Customs Clearance', 'التخليص الجمركي', 'liability', 1,
      false, false, true, true, v_parent_20_id, NEW.company_id, 2104
    ) RETURNING id INTO v_parent_id;
  END IF;

  v_code := public.get_next_entity_account_code('clearing_agent', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Clearing - ' || COALESCE(NEW.name, ''),
    'مخلص جمركي - ' || COALESCE(NEW.name, ''),
    'liability',
    COALESCE(v_code::bigint, 210499),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      is_leaf = true,
      allow_posting = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      parent_id = v_parent_id,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.clearing_agents
  SET account_id = v_new_account_id,
      code = COALESCE(NEW.code, v_code)
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_create_clearing_agent_account ON public.clearing_agents;
CREATE TRIGGER trg_create_clearing_agent_account
AFTER INSERT ON public.clearing_agents
FOR EACH ROW
EXECUTE FUNCTION public.create_clearing_agent_account();


-- ── 5. Upgrade rpc_process_export_shipment_ledger to post Export Shipment Cost Journal Entries ──
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
  v_lines jsonb;
  v_cost_lines jsonb;
  v_sale_je_id bigint;
  v_disc_je_id bigint;
  v_cost_je_id bigint;
  v_je_id bigint;
  v_raw_ar bigint;
  v_cost_item RECORD;
  v_item_currency text;
  v_item_amount numeric;
  v_item_desc text;
  v_vendor_acct bigint;
  v_expense_acct bigint;
  v_default_expense_acct bigint;
  v_accrued_liability_acct bigint;
  v_has_costs boolean := false;
BEGIN
  -- Get Company ID from user or system default
  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
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

  -- Handle old legacy ledger_entries reverse
  IF v_shipment.customer_id IS NOT NULL THEN
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
  END IF;

  -- Reverse any existing JEs for this shipment (sales, discount, and costs)
  FOR v_je_id IN
      SELECT id FROM journal_entries
      WHERE source_type IN ('export_shipment', 'export_discount', 'export_cost')
        AND source_id = p_shipment_id::text
  LOOP
      PERFORM public.reverse_journal_entry(v_je_id, p_user_id, 'تحديث الشحنة');
  END LOOP;

  DELETE FROM account_ledger_entries
  WHERE journal_entry_id IN (
    SELECT id FROM journal_entries
    WHERE source_type IN ('export_shipment', 'export_discount', 'export_cost')
      AND source_id = p_shipment_id::text
  );
  DELETE FROM journal_entries
  WHERE source_type IN ('export_shipment', 'export_discount', 'export_cost')
    AND source_id = p_shipment_id::text;

  -- Post New Sale & Discount JEs
  IF v_total_revenue > 0 AND v_shipment.customer_id IS NOT NULL THEN
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

    -- Revenue: prefer 4101 or 4200, leaf only
    SELECT id INTO v_rev_acct
    FROM accounts
    WHERE company_id = v_company_id
      AND account_code IN ('4101', '4200')
      AND is_leaf = true
      AND is_active = true
      AND allow_posting = true
    ORDER BY account_code ASC
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

    -- JOURNAL ENTRY 1: Sale
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

    -- JOURNAL ENTRY 2: Discount
    IF v_discount > 0 THEN
      v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_disc_acct, 'debit', v_discount, 'credit', 0,
          'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc || ' (خصم)'),
        jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', v_discount,
          'currency', COALESCE(v_shipment.currency_code, 'EGP'), 'description', v_desc || ' (خصم)')
      );

      v_disc_je_id := public.post_journal_entry(
        'export_discount', v_desc || ' - خصم مسموح به', COALESCE(v_shipment.shipment_date, CURRENT_DATE),
        v_company_id, p_user_id, v_lines
      );
      UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_disc_je_id;
    END IF;

  END IF;

  -- ── 3. JOURNAL ENTRY 3: Shipment Costs (Freight, Clearance, Logistics, etc.) ──
  SELECT id INTO v_default_expense_acct
  FROM accounts
  WHERE company_id = v_company_id AND account_code = '6130' AND is_leaf = true AND is_active = true
  LIMIT 1;

  IF v_default_expense_acct IS NULL THEN
    SELECT id INTO v_default_expense_acct
    FROM accounts
    WHERE account_type = 'expense' AND is_leaf = true AND is_active = true
    ORDER BY account_code ASC LIMIT 1;
  END IF;

  SELECT id INTO v_accrued_liability_acct
  FROM accounts
  WHERE company_id = v_company_id AND account_code IN ('2300', '2000') AND is_leaf = true AND is_active = true
  ORDER BY account_code ASC LIMIT 1;

  v_cost_lines := '[]'::jsonb;
  v_has_costs := false;

  FOR v_cost_item IN
    SELECT * FROM public.shipment_cost_items
    WHERE shipment_id = p_shipment_id AND COALESCE(total_price, 0) > 0
    ORDER BY sort_order ASC, id ASC
  LOOP
    v_vendor_acct := NULL;
    v_expense_acct := v_cost_item.expense_account_id;
    IF v_expense_acct IS NULL THEN
      v_expense_acct := v_default_expense_acct;
    END IF;

    -- Resolve Vendor Account (Shipping Company, Clearing Agent, Supplier, or Accrued Liability)
    IF v_cost_item.shipping_company_id IS NOT NULL OR v_cost_item.vendor_type = 'shipping_company' THEN
      SELECT sc.account_id INTO v_vendor_acct
      FROM public.shipping_companies sc
      WHERE sc.id = COALESCE(v_cost_item.shipping_company_id, v_cost_item.vendor_id);
    ELSIF v_cost_item.clearing_agent_id IS NOT NULL OR v_cost_item.vendor_type = 'clearing_agent' THEN
      SELECT ca.account_id INTO v_vendor_acct
      FROM public.clearing_agents ca
      WHERE ca.id = COALESCE(v_cost_item.clearing_agent_id, v_cost_item.vendor_id);
    ELSIF v_cost_item.supplier_id IS NOT NULL AND v_cost_item.supplier_id != '' THEN
      SELECT s.account_id INTO v_vendor_acct
      FROM public.suppliers s
      WHERE s.id::text = v_cost_item.supplier_id;
    END IF;

    IF v_vendor_acct IS NULL THEN
      v_vendor_acct := v_accrued_liability_acct;
    END IF;

    v_item_currency := COALESCE(NULLIF(v_cost_item.supplier_currency, ''), NULLIF(v_cost_item.original_currency, ''), 'EGP');
    
    IF v_item_currency != 'EGP' AND COALESCE(v_cost_item.exchange_rate, 1) > 0 THEN
      v_item_amount := v_cost_item.total_price / v_cost_item.exchange_rate;
    ELSE
      v_item_amount := v_cost_item.total_price;
    END IF;

    v_item_desc := 'تكلفة شحنة ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text) || ' - ' || COALESCE(v_cost_item.description, 'مصروف');

    -- Debit Expense
    v_cost_lines := v_cost_lines || jsonb_build_object(
      'account_id', v_expense_acct,
      'debit', v_item_amount,
      'credit', 0,
      'currency', v_item_currency,
      'description', v_item_desc
    );

    -- Credit Vendor Liability
    v_cost_lines := v_cost_lines || jsonb_build_object(
      'account_id', v_vendor_acct,
      'debit', 0,
      'credit', v_item_amount,
      'currency', v_item_currency,
      'description', v_item_desc
    );

    v_has_costs := true;
  END LOOP;

  IF v_has_costs AND jsonb_array_length(v_cost_lines) > 0 THEN
    v_cost_je_id := public.post_journal_entry(
      'export_cost',
      'تكاليف شحنة تصدير رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
      COALESCE(v_shipment.shipment_date, CURRENT_DATE),
      v_company_id, p_user_id, v_cost_lines
    );
    UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_cost_je_id;

    -- Link journal_entry_id to shipment_cost_items
    UPDATE public.shipment_cost_items
    SET journal_entry_id = v_cost_je_id
    WHERE shipment_id = p_shipment_id;
  END IF;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;


-- ── 6. Backfill All Confirmed Shipments ──
DO $$
DECLARE
  v_s RECORD;
BEGIN
  FOR v_s IN SELECT id FROM public.export_shipments LOOP
    PERFORM public.rpc_process_export_shipment_ledger(v_s.id);
  END LOOP;
END $$;

COMMIT;
