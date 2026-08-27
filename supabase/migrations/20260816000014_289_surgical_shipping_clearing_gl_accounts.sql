-- Migration 289: Surgical Fix for Shipping Companies & Clearing Agents GL Accounts & Linkage
-- 1. Restore rpc_process_export_shipment_ledger to standard (Sales + Discount only, NO cost JEs)
-- 2. Cleanup temporary test JEs and reset journal_entry_id on unpaid shipment_cost_items
-- 3. Ensure parent accounts 2103 (شركات الشحن) and 2104 (التخليص الجمركي) exist in accounts table
-- 4. Ensure leaf accounts exist for shipping companies (210301) and clearing agents (210401)
-- 5. Fix account_id on shipping_companies and clearing_agents
-- 6. Ensure triggers trg_create_shipping_company_account and trg_create_clearing_agent_account work with parents 2103/2104
-- 7. Drop temporary diagnostic functions

BEGIN;

-- ── 1. Restore standard rpc_process_export_shipment_ledger (Migration 211 version) ──
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
  v_sale_je_id bigint;
  v_disc_je_id bigint;
  v_je_id bigint;
  v_raw_ar bigint;
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

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;


-- ── 2. Clean up any temporary export_cost JEs and reset journal_entry_id on unpaid items ──
UPDATE public.shipment_cost_items
SET journal_entry_id = NULL
WHERE treasury_transaction_id IS NULL AND bank_transaction_id IS NULL;

DELETE FROM public.account_ledger_entries
WHERE journal_entry_id IN (
  SELECT id FROM public.journal_entries WHERE source_type = 'export_cost'
);

DELETE FROM public.journal_entries
WHERE source_type = 'export_cost';


-- ── 3. Ensure Parent Accounts 2103 & 2104 exist under 20 (الخصوم) ──
DO $$
DECLARE
  v_company_id UUID;
  v_parent_20_id BIGINT;
  v_parent_2103_id BIGINT;
  v_parent_2104_id BIGINT;
  v_sc RECORD;
  v_ca RECORD;
  v_sc_num INT;
  v_ca_num INT;
  v_code TEXT;
  v_acc_id BIGINT;
BEGIN
  SELECT id INTO v_company_id FROM sys_companies ORDER BY created_at ASC LIMIT 1;
  SELECT id INTO v_parent_20_id FROM accounts WHERE account_code = '20' LIMIT 1;

  -- 2103 (شركات الشحن)
  SELECT id INTO v_parent_2103_id FROM accounts WHERE account_code = '2103' LIMIT 1;
  IF v_parent_2103_id IS NULL THEN
    INSERT INTO accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '2103', 'Shipping Companies', 'شركات الشحن', 'liability', 1,
      false, false, true, true, v_parent_20_id, v_company_id, 2103
    ) RETURNING id INTO v_parent_2103_id;
  ELSE
    UPDATE accounts
    SET is_active = true, is_leaf = false, allow_posting = false, parent_id = v_parent_20_id
    WHERE id = v_parent_2103_id;
  END IF;

  -- 2104 (التخليص الجمركي)
  SELECT id INTO v_parent_2104_id FROM accounts WHERE account_code = '2104' LIMIT 1;
  IF v_parent_2104_id IS NULL THEN
    INSERT INTO accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '2104', 'Customs Clearance', 'التخليص الجمركي', 'liability', 1,
      false, false, true, true, v_parent_20_id, v_company_id, 2104
    ) RETURNING id INTO v_parent_2104_id;
  ELSE
    UPDATE accounts
    SET is_active = true, is_leaf = false, allow_posting = false, parent_id = v_parent_20_id
    WHERE id = v_parent_2104_id;
  END IF;

  -- ── 4. Ensure Leaf Accounts exist and link to shipping_companies ──
  FOR v_sc IN SELECT * FROM shipping_companies ORDER BY id ASC LOOP
    v_sc_num := COALESCE(NULLIF(regexp_replace(v_sc.code, '[^0-9]', '', 'g'), '')::int, v_sc.id);
    v_code := '2103' || LPAD(v_sc_num::text, 2, '0');

    SELECT id INTO v_acc_id FROM accounts WHERE account_code = v_code LIMIT 1;
    IF v_acc_id IS NULL THEN
      INSERT INTO accounts (
        account_code, name, account_name, account_type, sort_order,
        company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
      ) VALUES (
        v_code,
        'Shipping - ' || COALESCE(v_sc.name, ''),
        'شركة شحن - ' || COALESCE(v_sc.name, ''),
        'liability',
        v_code::bigint,
        v_sc.company_id,
        v_parent_2103_id,
        2,
        true,
        true,
        false,
        true
      ) RETURNING id INTO v_acc_id;
    ELSE
      UPDATE accounts
      SET name = 'Shipping - ' || COALESCE(v_sc.name, ''),
          account_name = 'شركة شحن - ' || COALESCE(v_sc.name, ''),
          parent_id = v_parent_2103_id,
          is_leaf = true,
          allow_posting = true,
          is_active = true
      WHERE id = v_acc_id;
    END IF;

    UPDATE shipping_companies
    SET account_id = v_acc_id
    WHERE id = v_sc.id;
  END LOOP;

  -- ── 5. Ensure Leaf Accounts exist and link to clearing_agents ──
  FOR v_ca IN SELECT * FROM clearing_agents ORDER BY id ASC LOOP
    v_ca_num := COALESCE(NULLIF(regexp_replace(v_ca.code, '[^0-9]', '', 'g'), '')::int, v_ca.id);
    v_code := '2104' || LPAD(v_ca_num::text, 2, '0');

    SELECT id INTO v_acc_id FROM accounts WHERE account_code = v_code LIMIT 1;
    IF v_acc_id IS NULL THEN
      INSERT INTO accounts (
        account_code, name, account_name, account_type, sort_order,
        company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
      ) VALUES (
        v_code,
        'Clearing - ' || COALESCE(v_ca.name, ''),
        'مخلص جمركي - ' || COALESCE(v_ca.name, ''),
        'liability',
        v_code::bigint,
        v_ca.company_id,
        v_parent_2104_id,
        2,
        true,
        true,
        false,
        true
      ) RETURNING id INTO v_acc_id;
    ELSE
      UPDATE accounts
      SET name = 'Clearing - ' || COALESCE(v_ca.name, ''),
          account_name = 'مخلص جمركي - ' || COALESCE(v_ca.name, ''),
          parent_id = v_parent_2104_id,
          is_leaf = true,
          allow_posting = true,
          is_active = true
      WHERE id = v_acc_id;
    END IF;

    UPDATE clearing_agents
    SET account_id = v_acc_id
    WHERE id = v_ca.id;
  END LOOP;

END $$;


-- ── 6. Update Triggers to ensure future entities are created under 2103 & 2104 ──
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
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

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
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

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

-- ── 7. Drop temporary diagnostic functions ──
DROP FUNCTION IF EXISTS public.rpc_fix_shipping_clearing_accounts();

NOTIFY pgrst, 'reload schema';

COMMIT;
