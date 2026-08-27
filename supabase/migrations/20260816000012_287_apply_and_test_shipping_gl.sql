-- Migration 287: Explicitly insert and verify Shipping & Clearing GL Accounts

CREATE OR REPLACE FUNCTION public.rpc_fix_shipping_clearing_accounts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_company_id UUID;
  v_parent_20_id BIGINT;
  v_parent_6_id BIGINT;
  v_parent_2103_id BIGINT;
  v_parent_2104_id BIGINT;
  v_exp_6130_id BIGINT;
  v_sc RECORD;
  v_ca RECORD;
  v_code TEXT;
  v_sc_acc_id BIGINT;
  v_ca_acc_id BIGINT;
  v_log jsonb := '[]'::jsonb;
  v_s RECORD;
  v_shipment_res jsonb;
BEGIN
  -- 1. Get company
  SELECT id INTO v_company_id FROM sys_companies ORDER BY created_at ASC LIMIT 1;
  v_log := v_log || jsonb_build_object('step', 'get_company', 'company_id', v_company_id);

  -- 2. Get parent 20
  SELECT id INTO v_parent_20_id FROM accounts WHERE account_code = '20' LIMIT 1;
  v_log := v_log || jsonb_build_object('step', 'get_parent_20', 'parent_20_id', v_parent_20_id);

  -- 3. Get parent 6
  SELECT id INTO v_parent_6_id FROM accounts WHERE account_code = '6' LIMIT 1;

  -- 4. Ensure 2103
  SELECT id INTO v_parent_2103_id FROM accounts WHERE account_code = '2103' LIMIT 1;
  IF v_parent_2103_id IS NULL THEN
    INSERT INTO accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '2103', 'Shipping Companies', 'شركات الشحن', 'liability', 1,
      false, false, true, true, v_parent_20_id, v_company_id, 2103
    ) RETURNING id INTO v_parent_2103_id;
  END IF;
  v_log := v_log || jsonb_build_object('step', 'parent_2103', 'id', v_parent_2103_id);

  -- 5. Ensure 2104
  SELECT id INTO v_parent_2104_id FROM accounts WHERE account_code = '2104' LIMIT 1;
  IF v_parent_2104_id IS NULL THEN
    INSERT INTO accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '2104', 'Customs Clearance', 'التخليص الجمركي', 'liability', 1,
      false, false, true, true, v_parent_20_id, v_company_id, 2104
    ) RETURNING id INTO v_parent_2104_id;
  END IF;
  v_log := v_log || jsonb_build_object('step', 'parent_2104', 'id', v_parent_2104_id);

  -- 6. Ensure 6130
  SELECT id INTO v_exp_6130_id FROM accounts WHERE account_code = '6130' LIMIT 1;
  IF v_exp_6130_id IS NULL THEN
    INSERT INTO accounts (
      account_code, name, account_name, account_type, level,
      is_leaf, allow_posting, is_system, is_active, parent_id, company_id, sort_order
    ) VALUES (
      '6130', 'Operating Expenses', 'مصروفات تشغيل وشحن وتخليص', 'expense', 2,
      true, true, true, true, v_parent_6_id, v_company_id, 6130
    ) RETURNING id INTO v_exp_6130_id;
  END IF;
  v_log := v_log || jsonb_build_object('step', 'exp_6130', 'id', v_exp_6130_id);

  -- 7. Sync Shipping Companies
  FOR v_sc IN SELECT * FROM shipping_companies ORDER BY id ASC LOOP
    v_code := '2103' || LPAD(COALESCE(NULLIF(regexp_replace(v_sc.code, '[^0-9]', '', 'g'), ''), v_sc.id::text), 2, '0');
    
    SELECT id INTO v_sc_acc_id FROM accounts WHERE account_code = v_code LIMIT 1;
    IF v_sc_acc_id IS NULL THEN
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
      ) RETURNING id INTO v_sc_acc_id;
    ELSE
      UPDATE accounts
      SET name = 'Shipping - ' || COALESCE(v_sc.name, ''),
          account_name = 'شركة شحن - ' || COALESCE(v_sc.name, ''),
          parent_id = v_parent_2103_id,
          is_leaf = true,
          allow_posting = true,
          is_active = true
      WHERE id = v_sc_acc_id;
    END IF;

    UPDATE shipping_companies
    SET account_id = v_sc_acc_id
    WHERE id = v_sc.id;

    v_log := v_log || jsonb_build_object('sc_id', v_sc.id, 'code', v_code, 'account_id', v_sc_acc_id);
  END LOOP;

  -- 8. Sync Clearing Agents
  FOR v_ca IN SELECT * FROM clearing_agents ORDER BY id ASC LOOP
    v_code := '2104' || LPAD(COALESCE(NULLIF(regexp_replace(v_ca.code, '[^0-9]', '', 'g'), ''), v_ca.id::text), 2, '0');

    SELECT id INTO v_ca_acc_id FROM accounts WHERE account_code = v_code LIMIT 1;
    IF v_ca_acc_id IS NULL THEN
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
      ) RETURNING id INTO v_ca_acc_id;
    ELSE
      UPDATE accounts
      SET name = 'Clearing - ' || COALESCE(v_ca.name, ''),
          account_name = 'مخلص جمركي - ' || COALESCE(v_ca.name, ''),
          parent_id = v_parent_2104_id,
          is_leaf = true,
          allow_posting = true,
          is_active = true
      WHERE id = v_ca_acc_id;
    END IF;

    UPDATE clearing_agents
    SET account_id = v_ca_acc_id
    WHERE id = v_ca.id;

    v_log := v_log || jsonb_build_object('ca_id', v_ca.id, 'code', v_code, 'account_id', v_ca_acc_id);
  END LOOP;

  -- 9. Re-process export shipments
  FOR v_s IN SELECT id FROM export_shipments ORDER BY id ASC LOOP
    v_shipment_res := public.rpc_process_export_shipment_ledger(v_s.id);
    v_log := v_log || jsonb_build_object('shipment_id', v_s.id, 'res', v_shipment_res);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'log', v_log);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'log', v_log);
END;
$$;
