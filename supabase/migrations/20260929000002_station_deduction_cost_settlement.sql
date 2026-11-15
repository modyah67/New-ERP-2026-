-- ============================================================================
-- Migration: 20260929000002_station_deduction_cost_settlement.sql
-- Description:
-- 1. Add dual-cost tracking columns to public.packing_order_cost_items
--    (cost_status, expected_amount, actual_amount, variance_amount, invoice_ref, etc.)
-- 2. Update sync_packing_order_costs_to_export_shipments to automatically recalculate
--    net_profit_egp and net_profit on export_shipments when landed costs change.
-- 3. Update rpc_confirm_packing_costs to record cost_status = 'expected' and
--    expected_amount = base_amount for station and deduction suppliers.
-- 4. Create rpc_settle_packing_cost_item to settle actual costs, adjust supplier
--    balance/ledger entries, create balancing journal entries (12413 vs 21117/21118),
--    and dynamically update packing orders and export shipments profitability.
-- 5. Create rpc_get_supplier_expected_cost_items to support the settlement UI.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Dual-cost tracking columns on public.packing_order_cost_items
-- ----------------------------------------------------------------------------

ALTER TABLE public.packing_order_cost_items
  ADD COLUMN IF NOT EXISTS cost_status VARCHAR(20) NOT NULL DEFAULT 'expected',
  ADD COLUMN IF NOT EXISTS expected_amount NUMERIC(15, 2) DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS actual_amount NUMERIC(15, 2) NULL,
  ADD COLUMN IF NOT EXISTS variance_amount NUMERIC(15, 2) DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS invoice_ref TEXT NULL,
  ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS reconciled_by UUID NULL,
  ADD COLUMN IF NOT EXISTS variance_journal_entry_id BIGINT NULL,
  ADD COLUMN IF NOT EXISTS settlement_notes TEXT NULL;

-- Ensure constraint exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'packing_order_cost_items_status_chk'
  ) THEN
    ALTER TABLE public.packing_order_cost_items
      ADD CONSTRAINT packing_order_cost_items_status_chk
      CHECK (cost_status IN ('expected', 'actual'));
  END IF;
END $$;

-- Backfill existing rows
UPDATE public.packing_order_cost_items
SET expected_amount = COALESCE(expected_amount, base_amount, 0),
    cost_status = COALESCE(cost_status, 'expected')
WHERE expected_amount = 0 OR cost_status IS NULL;

-- ----------------------------------------------------------------------------
-- 2. Update trigger function: sync_packing_order_costs_to_export_shipments
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_packing_order_costs_to_export_shipments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment RECORD;
  v_new_cost NUMERIC;
  v_new_landed NUMERIC;
  v_new_carton_cost NUMERIC;
BEGIN
  v_new_cost := COALESCE(NEW.packing_cost_per_carton, 0);

  IF TG_OP = 'UPDATE' AND (OLD.packing_cost_per_carton IS NOT DISTINCT FROM NEW.packing_cost_per_carton) THEN
    RETURN NEW;
  END IF;

  IF v_new_cost <= 0 THEN
    RETURN NEW;
  END IF;

  -- 1. Update export_shipment_items prices linked to this packing order
  UPDATE public.export_shipment_items
  SET price = v_new_cost,
      amount = ROUND(quantity * v_new_cost, 2)
  WHERE packing_order_id = NEW.id;

  -- 2. Update read-only packing cost items in shipment_cost_items (total_price is generated automatically)
  UPDATE public.shipment_cost_items sci
  SET unit_price = v_new_cost
  FROM public.export_shipment_items esi
  WHERE esi.shipment_id::text = sci.shipment_id::text
    AND esi.packing_order_id = NEW.id
    AND sci.category = 'packing';

  -- 3. Recalculate cost_per_carton, total_landed_cost & net_profit for affected export_shipments
  FOR v_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.export_shipment_items
    WHERE packing_order_id = NEW.id
  LOOP
    SELECT
      COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0) INTO v_new_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = v_shipment.shipment_id::text;

    SELECT
      COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +
      COALESCE((
        SELECT ROUND(SUM(sci.total_price), 2)
        FROM public.shipment_cost_items sci
        WHERE sci.shipment_id::text = v_shipment.shipment_id::text
          AND sci.category <> 'packing'
      ), 0) INTO v_new_landed
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = v_shipment.shipment_id::text;

    UPDATE public.export_shipments s
    SET cost_per_carton = v_new_carton_cost,
        total_landed_cost = v_new_landed,
        net_profit_egp = COALESCE(s.total_revenue_egp, 0) - v_new_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),
        net_profit = COALESCE(s.total_revenue_egp, 0) - v_new_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),
        updated_at = now()
    WHERE s.id::text = v_shipment.shipment_id::text;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_packing_order_costs ON public.packing_orders;
CREATE TRIGGER trg_sync_packing_order_costs
AFTER UPDATE OF packing_cost_per_carton ON public.packing_orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_packing_order_costs_to_export_shipments();

-- ----------------------------------------------------------------------------
-- 3. Update rpc_confirm_packing_costs with expected cost initialization
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_costs(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_company_id UUID;

  v_tot_cost_items NUMERIC := 0;
  v_posted_cost_items NUMERIC := 0;

  v_finished_inv_acc INT;
  v_credit_acc INT;
  v_supp_leaf_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_el JSONB;
  r_cost RECORD;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_max_cost_item_id BIGINT;
  v_existing_item RECORD;
  v_status_to_set TEXT;
  v_expected_to_set NUMERIC;
  v_actual_to_set NUMERIC;
  v_variance_to_set NUMERIC;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Validate prerequisite: packaging must be confirmed first
  IF v_order.status IN ('draft', 'pending', 'crops_confirmed') THEN
    RETURN json_build_object('success', false, 'error', 'يجب تأكيد مواد التعبئة أولاً قبل تأكيد بنود التكلفة');
  END IF;

  -- Idempotency check: only block if final approved
  IF v_order.status IN ('final_approved', 'completed') THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة معتمد نهائياً ومقفل بالكامل',
      'status', v_order.status,
      'journal_entry_id', v_order.costs_journal_entry_id
    );
  END IF;

  BEGIN
    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_notes) = 'string' THEN
      v_notes := (v_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_notes := '{}'::jsonb;
  END;

  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);

  -- 1. Rebuild Cost Items from Notes preserving any existing actual settlements
  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
    -- Delete existing non-settled items, or cleanly refresh
    DELETE FROM public.packing_order_cost_items 
    WHERE packing_order_id = p_packing_order_id AND cost_status <> 'actual';

    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;
    IF v_max_cost_item_id > 0 THEN
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);
    ELSE
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), 1, false);
    END IF;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'total')::numeric, 0);
      IF v_amt_egp > 0 THEN
        v_supplier_id := NULL;
        v_supp_str := v_el->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
        END IF;

        v_target_line_idx := NULL;
        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' AND v_el->>'target_line_index' != 'null' THEN
          v_target_line_idx := (v_el->>'target_line_index')::integer;
        END IF;

        v_status_to_set := COALESCE(NULLIF(v_el->>'cost_status', ''), 'expected');
        v_expected_to_set := COALESCE((v_el->>'expected_amount')::numeric, v_amt_egp);
        v_actual_to_set := (v_el->>'actual_amount')::numeric;
        v_variance_to_set := COALESCE((v_el->>'variance_amount')::numeric, 0);

        -- Check if an item already exists with this name and supplier to avoid duplicate insert
        SELECT * INTO v_existing_item 
        FROM public.packing_order_cost_items 
        WHERE packing_order_id = p_packing_order_id 
          AND name = (v_el->>'name')
          AND (supplier_id = v_supplier_id::text OR (supplier_id IS NULL AND v_supplier_id IS NULL))
        LIMIT 1;

        IF v_existing_item.id IS NOT NULL THEN
          -- Keep existing reconciled data
          UPDATE public.packing_order_cost_items
          SET base_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.base_amount ELSE v_amt_egp END,
              original_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.original_amount ELSE COALESCE((v_el->>'total')::numeric, v_amt_egp) END,
              expected_amount = COALESCE(v_existing_item.expected_amount, v_amt_egp)
          WHERE id = v_existing_item.id;
        ELSE
          INSERT INTO public.packing_order_cost_items (
            packing_order_id, name, category,
            base_amount, original_amount, original_currency,
            payment_source_type, payment_source_id,
            allocation_method, target_line_id,
            currency_snapshot, supplier_id, payment_status, paid_amount,
            cost_status, expected_amount, actual_amount, variance_amount, invoice_ref
          ) VALUES (
            p_packing_order_id,
            v_el->>'name',
            CASE WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'other') THEN v_el->>'category' ELSE 'other' END,
            v_amt_egp,
            COALESCE((v_el->>'total')::numeric, v_amt_egp),
            COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
            'none',
            NULL,
            v_el->>'allocation_method',
            v_target_line_idx,
            jsonb_build_object(
              'supplier_id', v_supplier_id,
              'supplier_name', v_el->>'supplier_name',
              'supplier_type', v_el->>'supplier_type',
              'target_line_index', v_target_line_idx,
              'cost_status', v_status_to_set,
              'expected_amount', v_expected_to_set
            ),
            v_supplier_id::text,
            'unpaid',
            0,
            v_status_to_set,
            v_expected_to_set,
            v_actual_to_set,
            v_variance_to_set,
            v_el->>'invoice_ref'
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 2. Calculate Total Cost Items
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 3. Resolve GL Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));

  -- 4. Create Costs Confirmation Journal Entry & Post Supplier Liabilities
  IF v_tot_cost_items > 0 THEN
    IF v_order.costs_journal_entry_id IS NOT NULL THEN
      v_je_id := v_order.costs_journal_entry_id;
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      UPDATE public.journal_entries
      SET description = 'قيد إثبات تكاليف ومصروفات وموردي أمر تعبئة رقم ' || v_order_num,
          updated_at = now()
      WHERE id = v_je_id;
    ELSE
      INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
      ) VALUES (
        'PENDING',
        COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),
        'قيد إثبات تكاليف ومصروفات وموردي أمر تعبئة رقم ' || v_order_num,
        'posted', true, 'packing_order_costs', p_packing_order_id::text, v_company_id,
        auth.uid(), now(), now()
      ) RETURNING id INTO v_je_id;

      v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_cost', NULL, NULL);
      IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'POCST-' || LPAD(v_je_id::text, 5, '0');
      END IF;
      UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
    END IF;

    -- DR Finished Goods Inventory (12413 / 1031)
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'تكاليف ومصروفات أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_cost_items;

    -- CR Supplier Accounts & Sub-Ledger Posting
    v_posted_cost_items := 0;
    FOR r_cost IN
      SELECT * FROM public.packing_order_cost_items
      WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
    LOOP
      v_credit_acc := NULL;
      v_supplier_id := NULL;

      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
        END IF;
      END IF;

      IF v_credit_acc IS NULL THEN
        v_credit_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
      END IF;

      IF v_credit_acc IS NULL THEN
        v_credit_acc := public.resolve_gl_account('2000', v_company_id);
      END IF;

      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
        'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
      );
      v_sum_credit := v_sum_credit + r_cost.base_amount;
      v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

      -- Post Sub-Ledger Entry for Supplier
      IF v_supplier_id IS NOT NULL THEN
        -- Only post initial expected liability if not previously posted for this order
        IF NOT EXISTS (
          SELECT 1 FROM public.ledger_entries 
          WHERE entity_id = v_supplier_id::text 
            AND reference_type = 'packing_cost' 
            AND reference_id = p_packing_order_id
            AND description LIKE '%' || COALESCE(r_cost.name, '') || '%'
        ) THEN
          INSERT INTO public.ledger_entries (
            entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
          ) VALUES (
            v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
            'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
            'بند تكلفة تقديرية: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
          );
          UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
        END IF;
      END IF;
    END LOOP;

    -- Fallback for unallocated general costs
    IF v_tot_cost_items > v_posted_cost_items THEN
      v_credit_acc := public.resolve_gl_account('2000', v_company_id);
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, (v_tot_cost_items - v_posted_cost_items), 'EGP', (v_tot_cost_items - v_posted_cost_items),
        'مصروفات إضافية أمر تعبئة ' || v_order_num, v_company_id
      );
      v_sum_credit := v_sum_credit + (v_tot_cost_items - v_posted_cost_items);
    END IF;

    -- Balance check
    IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
      RAISE EXCEPTION 'فشل تأكيد قيد بنود التكلفة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
    END IF;

    -- Penny rounding absorption
    IF v_sum_debit != v_sum_credit THEN
      UPDATE public.account_ledger_entries
      SET debit = debit + (v_sum_credit - v_sum_debit),
          amount_in_base_currency = amount_in_base_currency + (v_sum_credit - v_sum_debit)
      WHERE journal_entry_id = v_je_id AND account_id = v_finished_inv_acc AND debit > 0;
    END IF;
  END IF;

  -- 5. Update packing order status and stage tracking
  v_notes := jsonb_set(v_notes, '{workflow_stages,costs}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items
  ), true);

  UPDATE public.packing_orders
  SET status = CASE
        WHEN status IN ('final_approved', 'completed') THEN status
        ELSE 'costs_confirmed'
      END,
      other_cost_base = v_tot_cost_items,
      costs_confirmed_at = COALESCE(costs_confirmed_at, now()),
      costs_journal_entry_id = v_je_id,
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'status', 'costs_confirmed',
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_costs(bigint) TO authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 4. RPC: rpc_settle_packing_cost_item (Automated Reconciliation & Profitability)
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
  v_supp_str TEXT;
  v_supplier RECORD;

  v_expected NUMERIC := 0;
  v_old_actual NUMERIC := NULL;
  v_baseline NUMERIC := 0;
  v_incremental_variance NUMERIC := 0;
  v_total_variance NUMERIC := 0;
  v_abs_variance NUMERIC := 0;

  v_finished_inv_acc INT;
  v_supp_acc INT;
  v_supp_leaf_acc INT;
  v_je_id BIGINT := NULL;
  v_entry_num TEXT;

  v_new_other_cost_base NUMERIC := 0;
  v_new_total_cost NUMERIC := 0;
  v_new_carton_cost NUMERIC := 0;
  v_cartons_count NUMERIC := 0;

  v_order_notes JSONB;
  v_cost_items_arr JSONB;
  v_idx INT;
  v_ci_elem JSONB;
  v_shipments_affected INT := 0;
  r_shipment RECORD;
  v_new_shipment_landed NUMERIC;
  v_new_shipment_carton_cost NUMERIC;
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

  -- 4. Identify Supplier
  v_supplier_id := NULL;
  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id <> '' AND r_item.supplier_id <> 'null' THEN
    BEGIN
      v_supplier_id := r_item.supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
    END;
  END IF;

  IF v_supplier_id IS NULL AND r_item.currency_snapshot IS NOT NULL THEN
    v_supp_str := r_item.currency_snapshot->>'supplier_id';
    IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN
      BEGIN
        v_supplier_id := v_supp_str::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_supplier_id := NULL;
      END;
    END IF;
  END IF;

  IF v_supplier_id IS NOT NULL THEN
    SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;
  END IF;

  -- 5. Resolve Company & Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));

  IF v_supplier.account_id IS NOT NULL THEN
    v_supp_acc := v_supplier.account_id;
  ELSE
    v_supp_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
  END IF;

  IF v_supp_acc IS NULL THEN
    v_supp_acc := public.resolve_gl_account('2000', v_company_id);
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
            'تسوية تكلفة فعلية (زيادة تكلفة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - فاتورة: ' || COALESCE(p_invoice_ref, '-')
          ELSE 
            'تسوية تكلفة فعلية (وفر تكلفة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - فاتورة: ' || COALESCE(p_invoice_ref, '-')
        END,
        now()
      );
    END IF;

    -- B. Post Balancing General Ledger Journal Entry
    -- If variance > 0: Dr Finished Goods Warehouse (12413), Cr Supplier Liability
    -- If variance < 0: Dr Supplier Liability, Cr Finished Goods Warehouse (12413)
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
      -- Cr Supplier Account
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_supp_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
        'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
      );
    ELSE
      -- Dr Supplier Account (reduce liability)
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_supp_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
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

  -- Get carton count from lines or packing order
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

  -- 10. Update All Linked Export Shipments & Recalculate Final Net Profitability
  FOR r_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.export_shipment_items
    WHERE packing_order_id = r_order.id
  LOOP
    v_shipments_affected := v_shipments_affected + 1;

    -- Update item prices in shipment
    UPDATE public.export_shipment_items
    SET price = v_new_carton_cost,
        amount = ROUND(quantity * v_new_carton_cost, 2)
    WHERE shipment_id = r_shipment.shipment_id AND packing_order_id = r_order.id;

    -- Update packing cost line in shipment_cost_items (total_price is generated automatically)
    UPDATE public.shipment_cost_items sci
    SET unit_price = v_new_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = sci.shipment_id::text
      AND esi.packing_order_id = r_order.id
      AND sci.category = 'packing';

    -- Recalculate total landed cost for shipment
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

    -- Recalculate profitability
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
-- 5. RPC: rpc_get_supplier_expected_cost_items
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_get_supplier_expected_cost_items(
  p_supplier_type TEXT DEFAULT NULL,
  p_supplier_id UUID DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INT DEFAULT 200,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(item_row), '[]'::jsonb) INTO v_result
  FROM (
    SELECT
      ci.id AS cost_item_id,
      ci.packing_order_id,
      po.order_number,
      po.status AS order_status,
      po.packed_at AS order_date,
      po.packing_cost_per_carton,
      ci.name AS item_name,
      ci.category,
      ci.report_category_id,
      COALESCE(rc.name, ci.category) AS report_category_name,
      ci.cost_status,
      COALESCE(
        NULLIF(ci.expected_amount, 0),
        NULLIF((ci.currency_snapshot->'settlement'->>'expected_amount')::numeric, 0),
        CASE WHEN ci.cost_status = 'expected' THEN NULLIF(ci.base_amount, 0) ELSE NULL END,
        NULLIF((ci.currency_snapshot->>'total_egp')::numeric, 0),
        NULLIF((ci.currency_snapshot->>'total')::numeric, 0),
        NULLIF(ci.original_amount, 0),
        ci.base_amount,
        0
      ) AS expected_amount,
      ci.actual_amount,
      COALESCE(ci.variance_amount, 0) AS variance_amount,
      ci.original_currency,
      ci.original_amount,
      ci.exchange_rate,
      ci.base_amount,
      COALESCE(
        NULLIF((ci.currency_snapshot->>'quantity')::numeric, 0),
        1.0
      ) AS quantity,
      COALESCE(
        NULLIF((ci.currency_snapshot->>'unit_price')::numeric, 0),
        CASE 
          WHEN COALESCE((ci.currency_snapshot->>'quantity')::numeric, 1.0) > 0 
          THEN COALESCE(NULLIF(ci.expected_amount, 0), NULLIF(ci.base_amount, 0), ci.original_amount, 0) / COALESCE((ci.currency_snapshot->>'quantity')::numeric, 1.0)
          ELSE COALESCE(NULLIF(ci.expected_amount, 0), NULLIF(ci.base_amount, 0), ci.original_amount, 0)
        END
      ) AS unit_price,
      ci.invoice_ref,
      ci.settlement_notes,
      ci.reconciled_at,
      ci.variance_journal_entry_id,
      s.id AS supplier_id,
      s.name AS supplier_name,
      s.code AS supplier_code,
      s.supplier_type,
      s.phone AS supplier_phone,
      s.outstanding_balance AS supplier_outstanding_balance,
      -- Linked export shipments info
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'shipment_id', es.id,
              'shipment_no', es.shipment_no,
              'status', es.status,
              'total_landed_cost', es.total_landed_cost,
              'net_profit_egp', es.net_profit_egp
            )
          )
          FROM public.export_shipment_items esi
          JOIN public.export_shipments es ON es.id::text = esi.shipment_id::text
          WHERE esi.packing_order_id = po.id
        ),
        '[]'::jsonb
      ) AS linked_shipments
    FROM public.packing_order_cost_items ci
    JOIN public.packing_orders po ON po.id = ci.packing_order_id
    LEFT JOIN public.cost_report_categories rc ON rc.id = ci.report_category_id
    LEFT JOIN public.suppliers s ON (
      s.id::text = ci.supplier_id 
      OR s.id::text = (ci.currency_snapshot->>'supplier_id')
    )
    WHERE 
      -- Supplier Type Filter
      (
        p_supplier_type IS NULL 
        OR p_supplier_type = 'all'
        OR (p_supplier_type = 'station' AND (s.supplier_type = 'station' OR s.code LIKE '8%' OR ci.name ILIKE '%تشغيل%' OR ci.name ILIKE '%تبريد%' OR ci.name ILIKE '%محطة%'))
        OR (p_supplier_type = 'deduction' AND (s.supplier_type IN ('deduction', 'deductions') OR s.code LIKE '4%' OR ci.name ILIKE '%تخصيم%' OR ci.name ILIKE '%فحص%'))
      )
      -- Specific Supplier Filter
      AND (
        p_supplier_id IS NULL 
        OR s.id = p_supplier_id
      )
      -- Cost Status Filter
      AND (
        p_status IS NULL 
        OR p_status = 'all'
        OR ci.cost_status = p_status
      )
      -- Search Filter
      AND (
        p_search IS NULL 
        OR p_search = ''
        OR ci.name ILIKE '%' || p_search || '%'
        OR po.order_number ILIKE '%' || p_search || '%'
        OR s.name ILIKE '%' || p_search || '%'
        OR s.code ILIKE '%' || p_search || '%'
        OR ci.invoice_ref ILIKE '%' || p_search || '%'
      )
    ORDER BY 
      CASE WHEN ci.cost_status = 'expected' THEN 0 ELSE 1 END,
      ci.id DESC
    LIMIT p_limit
    OFFSET p_offset
  ) item_row;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_supplier_expected_cost_items(TEXT, UUID, TEXT, TEXT, INT, INT) TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;
