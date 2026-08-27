-- Migration 288: Register export_cost document type and fix account codes & sequences

BEGIN;

-- 1. Insert export_cost into sys_document_types
INSERT INTO public.sys_document_types (code, name, description, prefix, is_active)
VALUES 
  ('export_cost', 'Export Shipment Costs', 'تكاليف شحنة تصدير', 'EXPC', true),
  ('EXPORT_COST', 'Export Shipment Costs', 'تكاليف شحنة تصدير', 'EXPC', true)
ON CONFLICT (code) DO UPDATE
SET is_active = true, prefix = EXCLUDED.prefix;

-- Ensure sequences exist for all companies
INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
SELECT c.id, 'export_cost', 0, 5
FROM public.sys_companies c
ON CONFLICT DO NOTHING;

INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
SELECT c.id, 'EXPORT_COST', 0, 5
FROM public.sys_companies c
ON CONFLICT DO NOTHING;

-- 2. Correct account codes in accounts table for shipping companies and clearing agents
DO $$
DECLARE
  v_parent_2103_id BIGINT;
  v_parent_2104_id BIGINT;
  v_sc RECORD;
  v_ca RECORD;
  v_sc_num INT;
  v_ca_num INT;
  v_code TEXT;
  v_acc_id BIGINT;
BEGIN
  SELECT id INTO v_parent_2103_id FROM public.accounts WHERE account_code = '2103' LIMIT 1;
  SELECT id INTO v_parent_2104_id FROM public.accounts WHERE account_code = '2104' LIMIT 1;

  -- Delete wrong temporary codes if any (like 210300, 210400)
  UPDATE public.shipping_companies SET account_id = NULL WHERE account_id IN (SELECT id FROM public.accounts WHERE account_code = '210300');
  UPDATE public.clearing_agents SET account_id = NULL WHERE account_id IN (SELECT id FROM public.accounts WHERE account_code = '210400');
  DELETE FROM public.accounts WHERE account_code IN ('210300', '210400');

  -- Fix Shipping Companies -> 210301, 210302, ...
  FOR v_sc IN SELECT * FROM public.shipping_companies ORDER BY id ASC LOOP
    v_sc_num := COALESCE(NULLIF(regexp_replace(v_sc.code, '[^0-9]', '', 'g'), '')::int, v_sc.id);
    v_code := '2103' || LPAD(v_sc_num::text, 2, '0');

    INSERT INTO public.accounts (
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
    )
    ON CONFLICT (account_code) DO UPDATE
    SET name = EXCLUDED.name,
        account_name = EXCLUDED.account_name,
        parent_id = v_parent_2103_id,
        is_leaf = true,
        allow_posting = true,
        is_active = true
    RETURNING id INTO v_acc_id;

    IF v_acc_id IS NULL THEN
      SELECT id INTO v_acc_id FROM public.accounts WHERE account_code = v_code LIMIT 1;
    END IF;

    UPDATE public.shipping_companies
    SET account_id = v_acc_id
    WHERE id = v_sc.id;
  END LOOP;

  -- Fix Clearing Agents -> 210401, 210402, ...
  FOR v_ca IN SELECT * FROM public.clearing_agents ORDER BY id ASC LOOP
    v_ca_num := COALESCE(NULLIF(regexp_replace(v_ca.code, '[^0-9]', '', 'g'), '')::int, v_ca.id);
    v_code := '2104' || LPAD(v_ca_num::text, 2, '0');

    INSERT INTO public.accounts (
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
    )
    ON CONFLICT (account_code) DO UPDATE
    SET name = EXCLUDED.name,
        account_name = EXCLUDED.account_name,
        parent_id = v_parent_2104_id,
        is_leaf = true,
        allow_posting = true,
        is_active = true
    RETURNING id INTO v_acc_id;

    IF v_acc_id IS NULL THEN
      SELECT id INTO v_acc_id FROM public.accounts WHERE account_code = v_code LIMIT 1;
    END IF;

    UPDATE public.clearing_agents
    SET account_id = v_acc_id
    WHERE id = v_ca.id;
  END LOOP;

END $$;

-- 3. Re-execute rpc_process_export_shipment_ledger for all shipments
DO $$
DECLARE
  v_s RECORD;
BEGIN
  FOR v_s IN SELECT id FROM public.export_shipments ORDER BY id ASC LOOP
    PERFORM public.rpc_process_export_shipment_ledger(v_s.id);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
