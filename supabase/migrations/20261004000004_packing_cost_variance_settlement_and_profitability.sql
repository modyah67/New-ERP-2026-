-- ============================================================================
-- Migration: 20261004000004_packing_cost_variance_settlement_and_profitability.sql
-- Description:
-- 1. Create enhanced batch RPC rpc_settle_packing_cost_variances:
--    - Handles batch settlement of multiple cost items for a packing order.
--    - Calculates incremental and total variance (Actual - Estimated).
--    - Generates balanced double-entry Journal Entries:
--        * Dr/Cr Finished Goods Warehouse (12413)
--        * Cr/Dr Supplier Liability accounts (Transport 21111, Station 21117, Deduction 21118, etc.)
--        * Cr/Dr Administrative Expenses (31331) or Clearing Accounts
--    - Updates public.packing_order_cost_items with actual amounts, variances, invoice references, and reconciled metadata.
--    - Updates public.packing_orders (other_cost_base, total_cost, packing_cost_per_carton, notes).
--    - Automatically updates linked export_shipments (cost_per_carton, total_landed_cost, net_profit_egp, net_profit).
-- 2. Update rpc_settle_packing_cost_item to ensure 100% account parity with transport 21111 and admin 31331.
-- 3. Create helper RPC rpc_get_packing_order_variance_details to load full comparative data and shipment profit preview.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Enhanced RPC: rpc_settle_packing_cost_item
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_settle_packing_cost_item(
  p_cost_item_id BIGINT,
  p_actual_amount NUMERIC,
  p_invoice_ref TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_settled_by UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r_item RECORD;
  r_order RECORD;
  v_order_num TEXT;
  v_company_id UUID;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_supp_str TEXT;
  v_supplier RECORD;

  v_expected NUMERIC := 0;
  v_old_actual NUMERIC := NULL;
  v_baseline NUMERIC := 0;
  v_incremental_variance NUMERIC := 0;
  v_total_variance NUMERIC := 0;
  v_abs_variance NUMERIC := 0;

  v_finished_inv_acc INT;
  v_target_acc INT;
  v_category_acc INT;
  v_je_id BIGINT := NULL;
  v_entry_num TEXT;

  v_new_other_cost_base NUMERIC := 0;
  v_new_total_cost NUMERIC := 0;
  v_new_carton_cost NUMERIC := 0;
  v_cartons_count NUMERIC := 0;

  v_order_notes JSONB;
  v_cost_items_arr JSONB;
  v_ci_elem JSONB;
  v_shipments_affected INT := 0;
  r_shipment RECORD;
  v_new_shipment_landed NUMERIC;
  v_new_shipment_carton_cost NUMERIC;
  v_is_transport BOOLEAN := FALSE;
  v_is_admin BOOLEAN := FALSE;
BEGIN
  IF p_actual_amount IS NULL OR p_actual_amount < 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'المبلغ الفعلي غير صالح');
  END IF;

  -- 1. Lock and load Cost Item
  SELECT * INTO r_item 
  FROM public.packing_order_cost_items 
  WHERE id = p_cost_item_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  -- 2. Lock and load Packing Order
  SELECT * INTO r_order 
  FROM public.packing_orders 
  WHERE id = r_item.packing_order_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة المرتبط غير موجود');
  END IF;

  v_order_num := COALESCE(r_order.order_number, r_order.id::text);

  -- 3. Resolve baseline, incremental variance, and total variance
  v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);
  v_old_actual := r_item.actual_amount;

  IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
    v_baseline := v_old_actual;
  ELSE
    v_baseline := v_expected;
  END IF;

  v_incremental_variance := ROUND(p_actual_amount - v_baseline, 2);
  v_total_variance := ROUND(p_actual_amount - v_expected, 2);
  v_abs_variance := ABS(v_incremental_variance);

  -- 4. Identify Category and Supplier Types
  IF LOWER(COALESCE(r_item.category, '')) = 'admin' OR 
     r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%' THEN
    v_is_admin := TRUE;
  END IF;

  IF LOWER(COALESCE(r_item.category, '')) = 'logistics' OR 
     r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%سيار%' OR r_item.name ILIKE '%شحن داخلي%' THEN
    v_is_transport := TRUE;
  END IF;

  v_supplier_id := NULL;
  v_supp_str := NULL;
  IF r_item.currency_snapshot IS NOT NULL THEN
    v_supp_str := r_item.currency_snapshot->>'supplier_id';
  END IF;
  IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
    v_supp_str := r_item.supplier_id;
  END IF;

  IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN
    BEGIN
      v_supplier_id := v_supp_str::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
      BEGIN
        v_trans_supplier_id := v_supp_str::integer;
        v_is_transport := TRUE;
      EXCEPTION WHEN OTHERS THEN
        v_trans_supplier_id := NULL;
      END;
    END;
  END IF;

  IF v_supplier_id IS NOT NULL THEN
    SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;
    IF v_supplier.supplier_type = 'transport' THEN
      v_is_transport := TRUE;
    END IF;
  END IF;

  -- 5. Resolve Company & Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));

  -- Determine balancing account
  v_target_acc := NULL;
  IF v_is_transport THEN
    -- Strict Rule: Transport suppliers route to 21111 (Transport Suppliers Sub-ledger)
    v_target_acc := public.resolve_gl_account('21111', v_company_id);
    IF v_target_acc IS NULL THEN
      v_target_acc := public.resolve_gl_account('2111', v_company_id);
    END IF;
  ELSIF v_is_admin THEN
    -- Administrative Expenses 31331
    v_target_acc := public.resolve_gl_account('31331', v_company_id);
  ELSIF v_supplier_id IS NOT NULL THEN
    IF v_supplier.account_id IS NOT NULL THEN
      v_target_acc := v_supplier.account_id;
    ELSE
      v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
    END IF;
  ELSE
    -- Check category mapped account
    IF r_item.report_category_id IS NOT NULL THEN
      SELECT account_id INTO v_category_acc FROM public.cost_report_categories WHERE id = r_item.report_category_id;
      IF v_category_acc IS NOT NULL THEN v_target_acc := v_category_acc; END IF;
    END IF;
    IF v_target_acc IS NULL THEN
      SELECT account_id INTO v_category_acc FROM public.cost_report_categories WHERE name = r_item.name LIMIT 1;
      IF v_category_acc IS NOT NULL THEN v_target_acc := v_category_acc; END IF;
    END IF;
  END IF;

  IF v_target_acc IS NULL THEN
    v_target_acc := public.resolve_gl_account('2000', v_company_id);
  END IF;
  IF v_target_acc IS NULL THEN
    v_target_acc := public.resolve_gl_account('2111', v_company_id);
  END IF;

  -- 6. Accounting Adjustment (if incremental variance != 0)
  IF v_incremental_variance <> 0 THEN
    -- A. Update Supplier Balance & Sub-Ledger Entry
    IF v_supplier_id IS NOT NULL THEN
      UPDATE public.suppliers 
      SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_incremental_variance
      WHERE id = v_supplier_id;

      INSERT INTO public.ledger_entries (
        entity_id, entity_type, amount, currency, entry_type,
        reference_id, reference_type, reference_text, description, created_at
      ) VALUES (
        v_supplier_id::text,
        'supplier',
        v_abs_variance,
        'EGP',
        CASE WHEN v_incremental_variance > 0 THEN 'credit' ELSE 'debit' END,
        r_order.id,
        'cost_settlement',
        COALESCE(p_invoice_ref, r_item.name),
        CASE 
          WHEN v_incremental_variance > 0 THEN 
            'تسوية تكلفة فعلية (زيادة تكلفة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(p_invoice_ref, '-')
          ELSE 
            'تسوية تكلفة فعلية (وفر تكلفة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(p_invoice_ref, '-')
        END,
        now()
      );
    END IF;

    -- B. Post Balancing General Ledger Journal Entry
    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date,
      'قيد تسوية تكلفة فعلية - أمر تعبئة ' || v_order_num || ' (' || r_item.name || ')',
      'posted', true, 'packing_cost_settlement', p_cost_item_id::text, v_company_id,
      COALESCE(p_settled_by, auth.uid()), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'settlement', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
      v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    IF v_incremental_variance > 0 THEN
      -- Dr Inventory 12413
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
        'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
      );
      -- Cr Balancing Account
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_target_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
        'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
      );
    ELSE
      -- Dr Balancing Account (reduce liability / expense)
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_target_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
        'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
      );
      -- Cr Inventory 12413 (reduce inventory cost)
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
        'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
      );
    END IF;
  END IF;

  -- 7. Update packing_order_cost_items record
  UPDATE public.packing_order_cost_items
  SET cost_status = 'actual',
      actual_amount = p_actual_amount,
      base_amount = p_actual_amount,
      original_amount = p_actual_amount,
      expected_amount = v_expected,
      variance_amount = v_total_variance,
      invoice_ref = COALESCE(NULLIF(p_invoice_ref, ''), invoice_ref),
      settlement_notes = COALESCE(NULLIF(p_notes, ''), settlement_notes),
      reconciled_at = now(),
      reconciled_by = COALESCE(p_settled_by, auth.uid()),
      variance_journal_entry_id = COALESCE(v_je_id, variance_journal_entry_id),
      currency_snapshot = jsonb_set(
        COALESCE(currency_snapshot, '{}'::jsonb),
        '{settlement}',
        jsonb_build_object(
          'cost_status', 'actual',
          'expected_amount', v_expected,
          'actual_amount', p_actual_amount,
          'variance_amount', v_total_variance,
          'invoice_ref', p_invoice_ref,
          'settled_at', now(),
          'journal_entry_id', v_je_id
        ),
        true
      )
  WHERE id = p_cost_item_id;

  -- 8. Synchronize packing_orders.notes JSON array
  BEGIN
    v_order_notes := COALESCE(r_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_order_notes) = 'string' THEN
      v_order_notes := (v_order_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_order_notes := '{}'::jsonb;
  END;

  IF v_order_notes ? 'cost_items' AND jsonb_typeof(v_order_notes->'cost_items') = 'array' THEN
    v_cost_items_arr := '[]'::jsonb;
    FOR v_ci_elem IN SELECT jsonb_array_elements(v_order_notes->'cost_items')
    LOOP
      IF (v_ci_elem->>'name' = r_item.name) AND 
         ((v_supplier_id IS NOT NULL AND v_ci_elem->>'supplier_id' = v_supplier_id::text) OR (v_supplier_id IS NULL)) THEN
        v_ci_elem := v_ci_elem || jsonb_build_object(
          'cost_status', 'actual',
          'expected_amount', v_expected,
          'actual_amount', p_actual_amount,
          'variance_amount', v_total_variance,
          'total_egp', p_actual_amount,
          'total', p_actual_amount,
          'invoice_ref', p_invoice_ref,
          'reconciled_at', now()
        );
      END IF;
      v_cost_items_arr := v_cost_items_arr || jsonb_build_array(v_ci_elem);
    END LOOP;
    v_order_notes := jsonb_set(v_order_notes, '{cost_items}', v_cost_items_arr, true);
  END IF;

  -- 9. Recalculate Packing Order Costs & Carton Unit Cost
  SELECT COALESCE(SUM(base_amount), 0) INTO v_new_other_cost_base
  FROM public.packing_order_cost_items
  WHERE packing_order_id = r_order.id;

  v_new_total_cost := COALESCE(r_order.fruit_cost_base, 0) + COALESCE(r_order.actual_material_cost, 0) + v_new_other_cost_base;

  SELECT COALESCE(SUM(carton_count), 0) INTO v_cartons_count
  FROM public.packing_order_lines
  WHERE packing_order_id = r_order.id;

  IF v_cartons_count <= 0 THEN
    v_cartons_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);
  END IF;

  IF v_cartons_count > 0 THEN
    v_new_carton_cost := ROUND(v_new_total_cost / v_cartons_count, 2);
  ELSE
    v_new_carton_cost := r_order.packing_cost_per_carton;
  END IF;

  UPDATE public.packing_orders
  SET other_cost_base = v_new_other_cost_base,
      total_cost = v_new_total_cost,
      packing_cost_per_carton = v_new_carton_cost,
      notes = v_order_notes::text,
      updated_at = now()
  WHERE id = r_order.id;

  -- 10. Update All Linked Export Shipments & Recalculate Net Profitability
  FOR r_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.export_shipment_items
    WHERE packing_order_id = r_order.id
  LOOP
    v_shipments_affected := v_shipments_affected + 1;

    UPDATE public.export_shipment_items
    SET price = v_new_carton_cost,
        amount = ROUND(quantity * v_new_carton_cost, 2)
    WHERE shipment_id = r_shipment.shipment_id AND packing_order_id = r_order.id;

    UPDATE public.shipment_cost_items sci
    SET unit_price = v_new_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = sci.shipment_id::text
      AND esi.packing_order_id = r_order.id
      AND sci.category = 'packing';

    SELECT
      COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0) INTO v_new_shipment_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;

    SELECT
      COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +
      COALESCE((
        SELECT ROUND(SUM(sci.total_price), 2)
        FROM public.shipment_cost_items sci
        WHERE sci.shipment_id::text = r_shipment.shipment_id::text
          AND sci.category <> 'packing'
      ), 0) INTO v_new_shipment_landed
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;

    UPDATE public.export_shipments s
    SET cost_per_carton = v_new_shipment_carton_cost,
        total_landed_cost = v_new_shipment_landed,
        net_profit_egp = COALESCE(s.total_revenue_egp, 0) - v_new_shipment_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),
        net_profit = COALESCE(s.total_revenue_egp, 0) - v_new_shipment_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),
        updated_at = now()
    WHERE s.id::text = r_shipment.shipment_id::text;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'cost_item_id', p_cost_item_id,
    'item_name', r_item.name,
    'packing_order_id', r_order.id,
    'order_number', v_order_num,
    'supplier_id', v_supplier_id,
    'expected_amount', v_expected,
    'actual_amount', p_actual_amount,
    'variance_amount', v_total_variance,
    'incremental_variance', v_incremental_variance,
    'journal_entry_id', v_je_id,
    'new_packing_cost_per_carton', v_new_carton_cost,
    'affected_shipments_count', v_shipments_affected,
    'message', 'تمت تسوية التكلفة وتحديث أرصدة المورد وتكاليف الشحنات والربحية بنجاح'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_item(BIGINT, NUMERIC, TEXT, TEXT, UUID) TO authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 2. New Batch RPC: rpc_settle_packing_cost_variances
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_settle_packing_cost_variances(
  p_packing_order_id BIGINT,
  p_settlements JSONB,
  p_general_notes TEXT DEFAULT NULL,
  p_settled_by UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r_order RECORD;
  v_order_num TEXT;
  v_company_id UUID;
  v_finished_inv_acc INT;

  v_item_elem JSONB;
  v_cost_item_id BIGINT;
  v_actual_amt NUMERIC;
  v_inv_ref TEXT;
  v_item_notes TEXT;

  r_item RECORD;
  v_expected NUMERIC;
  v_old_actual NUMERIC;
  v_baseline NUMERIC;
  v_incremental_variance NUMERIC;
  v_total_variance NUMERIC;
  v_abs_variance NUMERIC;

  v_is_admin BOOLEAN;
  v_is_transport BOOLEAN;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_trans_supplier_id INT;
  v_supplier RECORD;
  v_target_acc INT;
  v_category_acc INT;

  v_je_id BIGINT := NULL;
  v_entry_num TEXT;
  v_total_inc_variance NUMERIC := 0;
  v_total_actual_costs NUMERIC := 0;
  v_total_expected_costs NUMERIC := 0;
  v_settled_count INT := 0;

  v_cartons_count NUMERIC := 0;
  v_new_other_cost_base NUMERIC := 0;
  v_new_total_cost NUMERIC := 0;
  v_new_carton_cost NUMERIC := 0;

  v_order_notes JSONB;
  v_cost_items_arr JSONB;
  v_ci_elem JSONB;

  v_shipments_affected INT := 0;
  r_shipment RECORD;
  v_new_shipment_landed NUMERIC;
  v_new_shipment_carton_cost NUMERIC;
  v_shipments_report JSONB := '[]'::jsonb;
  v_shipment_row RECORD;
BEGIN
  IF p_settlements IS NULL OR jsonb_typeof(p_settlements) <> 'array' OR jsonb_array_length(p_settlements) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'قائمة تسوية البنود فارغة');
  END IF;

  -- 1. Lock and load Packing Order
  SELECT * INTO r_order 
  FROM public.packing_orders 
  WHERE id = p_packing_order_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  v_order_num := COALESCE(r_order.order_number, p_packing_order_id::text);

  -- 2. Resolve Company & Inventory Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));

  -- 3. Pre-create Settlement Journal Entry header (to be populated if net variances exist)
  -- We will determine if any lines need to be posted
  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    IF v_actual_amt IS NOT NULL AND v_actual_amt >= 0 THEN
      SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id;
      IF FOUND THEN
        v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);
        v_old_actual := r_item.actual_amount;
        IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
          v_baseline := v_old_actual;
        ELSE
          v_baseline := v_expected;
        END IF;
        v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);
        v_total_inc_variance := v_total_inc_variance + v_incremental_variance;
      END IF;
    END IF;
  END LOOP;

  -- If there is any non-zero incremental variance, initialize unified journal entry
  IF v_total_inc_variance <> 0 THEN
    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date,
      'قيد تسوية فروق التكاليف الفعلية - أمر تعبئة ' || v_order_num,
      'posted', true, 'packing_cost_settlement', p_packing_order_id::text, v_company_id,
      COALESCE(p_settled_by, auth.uid()), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'settlement', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
      v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
  END IF;

  -- 4. Process each settlement item
  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    v_inv_ref := v_item_elem->>'invoice_ref';
    v_item_notes := v_item_elem->>'notes';

    IF v_actual_amt IS NULL OR v_actual_amt < 0 THEN
      CONTINUE;
    END IF;

    SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id FOR UPDATE;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);
    v_old_actual := r_item.actual_amount;
    IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
      v_baseline := v_old_actual;
    ELSE
      v_baseline := v_expected;
    END IF;

    v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);
    v_total_variance := ROUND(v_actual_amt - v_expected, 2);
    v_abs_variance := ABS(v_incremental_variance);

    -- Category / Supplier Detection
    v_is_admin := (LOWER(COALESCE(r_item.category, '')) = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%');
    v_is_transport := (LOWER(COALESCE(r_item.category, '')) = 'logistics' OR r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%سيار%' OR r_item.name ILIKE '%شحن داخلي%');

    v_supplier_id := NULL;
    v_supp_str := NULL;
    IF r_item.currency_snapshot IS NOT NULL THEN
      v_supp_str := r_item.currency_snapshot->>'supplier_id';
    END IF;
    IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
      v_supp_str := r_item.supplier_id;
    END IF;

    IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN
      BEGIN
        v_supplier_id := v_supp_str::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_supplier_id := NULL;
        BEGIN
          v_trans_supplier_id := v_supp_str::integer;
          v_is_transport := TRUE;
        EXCEPTION WHEN OTHERS THEN
          v_trans_supplier_id := NULL;
        END;
      END;
    END IF;

    IF v_supplier_id IS NOT NULL THEN
      SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;
      IF v_supplier.supplier_type = 'transport' THEN
        v_is_transport := TRUE;
      END IF;
    END IF;

    -- Resolve balancing account for this item
    v_target_acc := NULL;
    IF v_is_transport THEN
      v_target_acc := public.resolve_gl_account('21111', v_company_id);
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;
    ELSIF v_is_admin THEN
      v_target_acc := public.resolve_gl_account('31331', v_company_id);
    ELSIF v_supplier_id IS NOT NULL THEN
      IF v_supplier.account_id IS NOT NULL THEN
        v_target_acc := v_supplier.account_id;
      ELSE
        v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
      END IF;
    ELSE
      IF r_item.report_category_id IS NOT NULL THEN
        SELECT account_id INTO v_category_acc FROM public.cost_report_categories WHERE id = r_item.report_category_id;
        IF v_category_acc IS NOT NULL THEN v_target_acc := v_category_acc; END IF;
      END IF;
      IF v_target_acc IS NULL THEN
        SELECT account_id INTO v_category_acc FROM public.cost_report_categories WHERE name = r_item.name LIMIT 1;
        IF v_category_acc IS NOT NULL THEN v_target_acc := v_category_acc; END IF;
      END IF;
    END IF;

    IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2000', v_company_id); END IF;
    IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

    -- Post GL lines and Sub-ledger if incremental variance != 0
    IF v_incremental_variance <> 0 AND v_je_id IS NOT NULL THEN
      IF v_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_incremental_variance
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type,
          reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text,
          'supplier',
          v_abs_variance,
          'EGP',
          CASE WHEN v_incremental_variance > 0 THEN 'credit' ELSE 'debit' END,
          p_packing_order_id,
          'cost_settlement',
          COALESCE(v_inv_ref, r_item.name),
          CASE 
            WHEN v_incremental_variance > 0 THEN 
              'تسوية تكلفة فعلية (زيادة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
            ELSE 
              'تسوية تكلفة فعلية (وفر) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
          END,
          now()
        );
      END IF;

      IF v_incremental_variance > 0 THEN
        -- Dr Finished Goods Inventory 12413
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
          'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
        -- Cr Balancing Account
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_target_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
          'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
      ELSE
        -- Dr Balancing Account
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_target_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
          'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
        -- Cr Finished Goods Inventory 12413
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
          'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
      END IF;
    END IF;

    -- Update row
    UPDATE public.packing_order_cost_items
    SET cost_status = 'actual',
        actual_amount = v_actual_amt,
        base_amount = v_actual_amt,
        original_amount = v_actual_amt,
        expected_amount = v_expected,
        variance_amount = v_total_variance,
        invoice_ref = COALESCE(NULLIF(v_inv_ref, ''), invoice_ref),
        settlement_notes = COALESCE(NULLIF(v_item_notes, ''), settlement_notes),
        reconciled_at = now(),
        reconciled_by = COALESCE(p_settled_by, auth.uid()),
        variance_journal_entry_id = COALESCE(v_je_id, variance_journal_entry_id),
        currency_snapshot = jsonb_set(
          COALESCE(currency_snapshot, '{}'::jsonb),
          '{settlement}',
          jsonb_build_object(
            'cost_status', 'actual',
            'expected_amount', v_expected,
            'actual_amount', v_actual_amt,
            'variance_amount', v_total_variance,
            'invoice_ref', v_inv_ref,
            'settled_at', now(),
            'journal_entry_id', v_je_id
          ),
          true
        )
    WHERE id = v_cost_item_id;

    v_settled_count := v_settled_count + 1;
  END LOOP;

  -- 5. Recalculate Totals on packing_orders
  SELECT COALESCE(SUM(base_amount), 0) INTO v_new_other_cost_base
  FROM public.packing_order_cost_items
  WHERE packing_order_id = p_packing_order_id;

  v_new_total_cost := COALESCE(r_order.fruit_cost_base, 0) + COALESCE(r_order.actual_material_cost, 0) + v_new_other_cost_base;

  SELECT COALESCE(SUM(carton_count), 0) INTO v_cartons_count
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;

  IF v_cartons_count <= 0 THEN
    v_cartons_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);
  END IF;

  IF v_cartons_count > 0 THEN
    v_new_carton_cost := ROUND(v_new_total_cost / v_cartons_count, 2);
  ELSE
    v_new_carton_cost := r_order.packing_cost_per_carton;
  END IF;

  -- Sync notes JSON array
  BEGIN
    v_order_notes := COALESCE(r_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_order_notes) = 'string' THEN
      v_order_notes := (v_order_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_order_notes := '{}'::jsonb;
  END;

  IF v_order_notes ? 'cost_items' AND jsonb_typeof(v_order_notes->'cost_items') = 'array' THEN
    v_cost_items_arr := '[]'::jsonb;
    FOR v_ci_elem IN SELECT jsonb_array_elements(v_order_notes->'cost_items')
    LOOP
      SELECT * INTO r_item 
      FROM public.packing_order_cost_items 
      WHERE packing_order_id = p_packing_order_id AND name = (v_ci_elem->>'name')
      LIMIT 1;
      IF FOUND THEN
        v_ci_elem := v_ci_elem || jsonb_build_object(
          'cost_status', r_item.cost_status,
          'expected_amount', r_item.expected_amount,
          'actual_amount', r_item.actual_amount,
          'variance_amount', r_item.variance_amount,
          'total_egp', r_item.base_amount,
          'total', r_item.original_amount,
          'invoice_ref', r_item.invoice_ref,
          'reconciled_at', r_item.reconciled_at
        );
      END IF;
      v_cost_items_arr := v_cost_items_arr || jsonb_build_array(v_ci_elem);
    END LOOP;
    v_order_notes := jsonb_set(v_order_notes, '{cost_items}', v_cost_items_arr, true);
  END IF;

  UPDATE public.packing_orders
  SET other_cost_base = v_new_other_cost_base,
      total_cost = v_new_total_cost,
      packing_cost_per_carton = v_new_carton_cost,
      notes = v_order_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  -- 6. Recalculate Linked Export Shipments & Net Profitability
  FOR r_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.export_shipment_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
    v_shipments_affected := v_shipments_affected + 1;

    -- Update prices in export_shipment_items
    UPDATE public.export_shipment_items
    SET price = v_new_carton_cost,
        amount = ROUND(quantity * v_new_carton_cost, 2)
    WHERE shipment_id = r_shipment.shipment_id AND packing_order_id = p_packing_order_id;

    -- Update read-only packing unit price in shipment_cost_items
    UPDATE public.shipment_cost_items sci
    SET unit_price = v_new_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = sci.shipment_id::text
      AND esi.packing_order_id = p_packing_order_id
      AND sci.category = 'packing';

    -- Recalculate shipment landed cost
    SELECT
      COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0) INTO v_new_shipment_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;

    SELECT
      COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +
      COALESCE((
        SELECT ROUND(SUM(sci.total_price), 2)
        FROM public.shipment_cost_items sci
        WHERE sci.shipment_id::text = r_shipment.shipment_id::text
          AND sci.category <> 'packing'
      ), 0) INTO v_new_shipment_landed
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;

    -- Update export_shipments profitability
    UPDATE public.export_shipments s
    SET cost_per_carton = v_new_shipment_carton_cost,
        total_landed_cost = v_new_shipment_landed,
        net_profit_egp = COALESCE(s.total_revenue_egp, 0) - v_new_shipment_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),
        net_profit = COALESCE(s.total_revenue_egp, 0) - v_new_shipment_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),
        updated_at = now()
    WHERE s.id::text = r_shipment.shipment_id::text;

    SELECT id, shipment_no, total_revenue_egp, total_landed_cost, net_profit_egp 
    INTO v_shipment_row
    FROM public.export_shipments
    WHERE id::text = r_shipment.shipment_id::text;

    v_shipments_report := v_shipments_report || jsonb_build_array(jsonb_build_object(
      'shipment_id', v_shipment_row.id,
      'shipment_no', v_shipment_row.shipment_no,
      'total_revenue_egp', v_shipment_row.total_revenue_egp,
      'total_landed_cost', v_shipment_row.total_landed_cost,
      'net_profit_egp', v_shipment_row.net_profit_egp
    ));
  END LOOP;

  -- 7. Query Summary Stats
  SELECT 
    COALESCE(SUM(expected_amount), 0),
    COALESCE(SUM(actual_amount), 0)
  INTO v_total_expected_costs, v_total_actual_costs
  FROM public.packing_order_cost_items
  WHERE packing_order_id = p_packing_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'packing_order_id', p_packing_order_id,
    'order_number', v_order_num,
    'settled_items_count', v_settled_count,
    'total_expected_costs', v_total_expected_costs,
    'total_actual_costs', v_total_actual_costs,
    'total_variance', (v_total_actual_costs - v_total_expected_costs),
    'journal_entry_id', v_je_id,
    'journal_entry_number', v_entry_num,
    'new_packing_cost_per_carton', v_new_carton_cost,
    'affected_shipments_count', v_shipments_affected,
    'affected_shipments', v_shipments_report,
    'message', 'تم تأكيد التسوية الفعلية وتوليد القيود المحاسبية وتحديث ربحية الشحنات بنجاح'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_variances(BIGINT, JSONB, TEXT, UUID) TO authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 3. Helper RPC: rpc_get_packing_order_variance_details
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_get_packing_order_variance_details(p_packing_order_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r_order RECORD;
  v_items JSONB := '[]'::jsonb;
  v_shipments JSONB := '[]'::jsonb;
  v_total_expected NUMERIC := 0;
  v_total_actual NUMERIC := 0;
  v_total_variance NUMERIC := 0;
  v_carton_count NUMERIC := 0;
BEGIN
  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- 1. Get Cost Items
  SELECT COALESCE(jsonb_agg(item_row), '[]'::jsonb) INTO v_items
  FROM (
    SELECT 
      ci.id,
      ci.name,
      ci.category,
      ci.cost_status,
      COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0) AS expected_amount,
      ci.actual_amount,
      COALESCE(ci.variance_amount, CASE WHEN ci.actual_amount IS NOT NULL THEN ci.actual_amount - COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0) ELSE 0 END) AS variance_amount,
      ci.invoice_ref,
      ci.settlement_notes,
      ci.reconciled_at,
      ci.reconciled_by,
      ci.variance_journal_entry_id,
      ci.supplier_id,
      COALESCE(s.name, ci.currency_snapshot->>'supplier_name', 'مورد عام / بدون مورد') AS supplier_name,
      COALESCE(s.supplier_type, ci.currency_snapshot->>'supplier_type', 'general') AS supplier_type
    FROM public.packing_order_cost_items ci
    LEFT JOIN public.suppliers s ON (s.id::text = ci.supplier_id)
    WHERE ci.packing_order_id = p_packing_order_id
    ORDER BY ci.id
  ) item_row;

  -- 2. Get Linked Export Shipments with current profitability
  SELECT COALESCE(jsonb_agg(ship_row), '[]'::jsonb) INTO v_shipments
  FROM (
    SELECT DISTINCT
      s.id,
      s.shipment_no,
      s.status,
      s.destination_country,
      s.customer_name,
      COALESCE(s.total_revenue_egp, 0) AS total_revenue_egp,
      COALESCE(s.total_landed_cost, 0) AS total_landed_cost,
      COALESCE(s.cost_per_carton, 0) AS cost_per_carton,
      COALESCE(s.net_profit_egp, 0) AS net_profit_egp,
      COALESCE(s.allocated_admin_expenses, 0) AS allocated_admin_expenses,
      COALESCE(s.allocated_taxes, 0) AS allocated_taxes,
      esi.quantity AS order_cartons_in_shipment
    FROM public.export_shipments s
    JOIN public.export_shipment_items esi ON (esi.shipment_id::text = s.id::text)
    WHERE esi.packing_order_id = p_packing_order_id
  ) ship_row;

  -- 3. Calculate Carton Count
  SELECT COALESCE(SUM(carton_count), 0) INTO v_carton_count
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;
  IF v_carton_count <= 0 THEN
    v_carton_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'packing_order_id', p_packing_order_id,
    'order_number', COALESCE(r_order.order_number, p_packing_order_id::text),
    'order_status', r_order.status,
    'fruit_cost_base', COALESCE(r_order.fruit_cost_base, 0),
    'actual_material_cost', COALESCE(r_order.actual_material_cost, 0),
    'other_cost_base', COALESCE(r_order.other_cost_base, 0),
    'total_cost', COALESCE(r_order.total_cost, 0),
    'carton_count', v_carton_count,
    'packing_cost_per_carton', COALESCE(r_order.packing_cost_per_carton, 0),
    'items', v_items,
    'shipments', v_shipments
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_packing_order_variance_details(BIGINT) TO authenticated, service_role, anon;

COMMIT;
