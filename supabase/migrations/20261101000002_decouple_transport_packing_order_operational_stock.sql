-- ============================================================================
-- Migration: 20261101000002_decouple_transport_packing_order_operational_stock.sql
-- Description:
-- 1. Decouple Packing Order Transport Costs from Transporter Financial Balance:
--    - Transport costs on packing orders act as OPERATIONAL / QUOTA CONSUMPTION ONLY.
--    - Deducts consumed trips from transport_suppliers.truck_balance with full decimal precision (e.g. 0.5 نقلة).
--    - Transporter financial ledger (balance / current_balance) is NOT modified or credited.
--    - Records a 'packing_consumption' transaction in transport_transactions with amount = 0.
--    - Eliminates duplicate financial accrual / liability entries on transport suppliers.
-- 2. Alter truck_count and truck_balance columns to NUMERIC(12, 4) to support exact fractions (e.g. 0.5).
-- 3. Update get_transport_supplier_true_balances():
--    - Only 'invoice' transactions create financial liability (credit).
--    - 'packing_consumption', 'packing_order_consumption', 'packing_order_invoice' are operational movements.
-- 4. Clean up existing testing data:
--    - Reverts any financial balance added by legacy 'packing_order_invoice' transactions.
--    - Normalizes legacy 'packing_order_invoice' transactions to 'packing_consumption' with amount = 0.
-- ============================================================================

BEGIN;

-- ── 1. Update Column Data Types to support Decimal Fractions (e.g. 0.5, 1.25) ──
ALTER TABLE public.transport_transactions 
  ALTER COLUMN truck_count TYPE NUMERIC(12, 4) USING truck_count::numeric;

ALTER TABLE public.packing_order_cost_items 
  ALTER COLUMN truck_count TYPE NUMERIC(12, 4) USING truck_count::numeric;

ALTER TABLE public.transport_suppliers 
  ALTER COLUMN truck_balance TYPE NUMERIC(12, 4) USING truck_balance::numeric,
  ALTER COLUMN initial_truck_balance TYPE NUMERIC(12, 4) USING initial_truck_balance::numeric;

-- ── 2. Revert Financial Impact of Legacy Packing Order Invoices & Normalize to Consumption ──
UPDATE public.transport_suppliers ts
SET balance = balance - COALESCE(sub.total_amt, 0),
    current_balance = current_balance - COALESCE(sub.total_amt, 0)
FROM (
  SELECT supplier_id, SUM(amount) AS total_amt
  FROM public.transport_transactions
  WHERE type = 'packing_order_invoice' AND amount > 0
  GROUP BY supplier_id
) sub
WHERE ts.id = sub.supplier_id;

UPDATE public.transport_transactions
SET type = 'packing_consumption',
    amount = 0,
    notes = COALESCE(notes, '') || ' (استهلاك تشغيلي بدون أثر مالي)'
WHERE type = 'packing_order_invoice';

-- ── 3. Update get_transport_supplier_true_balances Function ──
DROP FUNCTION IF EXISTS public.get_transport_supplier_true_balances();

CREATE OR REPLACE FUNCTION public.get_transport_supplier_true_balances()
RETURNS TABLE (
  supplier_id integer,
  true_balance numeric,
  financial_balance numeric,
  truck_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  SELECT
    ts.id AS supplier_id,
    (
      (CASE WHEN ts.initial_balance_direction = 'CREDIT' THEN COALESCE(ts.initial_balance, 0) ELSE -COALESCE(ts.initial_balance, 0) END)
      + COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type = 'invoice'
        ), 0)
      - COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('cash_payment', 'bank_payment')
        ), 0)
    )::numeric AS true_balance,

    (
      (CASE WHEN ts.initial_balance_direction = 'CREDIT' THEN COALESCE(ts.initial_balance, 0) ELSE -COALESCE(ts.initial_balance, 0) END)
      + COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type = 'invoice'
        ), 0)
      - COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('cash_payment', 'bank_payment')
        ), 0)
    )::numeric AS financial_balance,

    (
      COALESCE(ts.initial_truck_balance, 0)
      + COALESCE((
          SELECT SUM(COALESCE(tt.truck_count, 1))
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type = 'invoice'
        ), 0)
      - COALESCE((
          SELECT SUM(COALESCE(tt.truck_count, 1))
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('packing_consumption', 'packing_order_consumption', 'packing_order_invoice')
        ), 0)
    )::numeric AS truck_balance
  FROM public.transport_suppliers ts;
$func$;

GRANT EXECUTE ON FUNCTION public.get_transport_supplier_true_balances() TO authenticated, anon, service_role;

-- ── 4. Update rpc_confirm_packing_costs Function ──
DROP FUNCTION IF EXISTS public.rpc_confirm_packing_costs(bigint);

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
  v_transport_default_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_el JSONB;
  r_cost RECORD;
  r_prev_trans RECORD;
  r_prev_supp RECORD;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_max_cost_item_id BIGINT;
  v_consumed_trucks NUMERIC;
  v_category_account_id BIGINT;
  v_is_transport BOOLEAN;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Validate prerequisite: packaging must be confirmed first
  IF v_order.status IN ('draft', 'pending', 'crops_confirmed') THEN
    RETURN json_build_object('success', false, 'error', 'يجب تأكيد مواد التعبئة أولاً قبل تأكيد بنود التكلفة');
  END IF;

  -- Idempotency check: only block if the order has already been final approved / completed
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

  -- A. Revert previously recorded truck deductions for this packing order (Idempotency)
  -- Note: We only revert consumed truck quota; financial balance is never modified by packing transport
  FOR r_prev_trans IN 
    SELECT supplier_id, 
           SUM(COALESCE(truck_count, 0)) AS total_prev_trucks 
    FROM public.transport_transactions 
    WHERE reference_id = p_packing_order_id::text 
      AND type IN ('packing_order_invoice', 'packing_consumption', 'packing_order_consumption')
    GROUP BY supplier_id
  LOOP
    UPDATE public.transport_suppliers
    SET truck_balance = COALESCE(truck_balance, 0) + r_prev_trans.total_prev_trucks,
        updated_at = now()
    WHERE id = r_prev_trans.supplier_id;
  END LOOP;

  DELETE FROM public.transport_transactions 
  WHERE reference_id = p_packing_order_id::text 
    AND type IN ('packing_order_invoice', 'packing_consumption', 'packing_order_consumption');

  -- B. Revert generic supplier ledger entries and outstanding balance if any
  FOR r_prev_supp IN
    SELECT entity_id, SUM(COALESCE(amount, 0)) AS total_prev_amount
    FROM public.ledger_entries
    WHERE reference_id = p_packing_order_id
      AND reference_type = 'packing_cost'
      AND entry_type = 'credit'
    GROUP BY entity_id
  LOOP
    BEGIN
      UPDATE public.suppliers
      SET outstanding_balance = COALESCE(outstanding_balance, 0) - r_prev_supp.total_prev_amount
      WHERE id = r_prev_supp.entity_id::uuid;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  DELETE FROM public.ledger_entries
  WHERE reference_id = p_packing_order_id
    AND reference_type = 'packing_cost';

  -- 1. Rebuild Cost Items from Notes
  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;
    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_amt_egp := COALESCE(
        NULLIF((v_el->>'actual_amount')::numeric, 0),
        NULLIF((v_el->>'total_egp')::numeric, 0),
        NULLIF((v_el->>'total')::numeric, 0),
        NULLIF((v_el->>'base_amount')::numeric, 0),
        0
      );

      BEGIN
        v_target_line_idx := (v_el->>'target_line_index')::integer;
      EXCEPTION WHEN OTHERS THEN
        v_target_line_idx := NULL;
      END;

      v_max_cost_item_id := v_max_cost_item_id + 1;
      INSERT INTO public.packing_order_cost_items (
        id,
        packing_order_id,
        name,
        category,
        category_name,
        report_category_id,
        supplier_id,
        transport_supplier_id,
        truck_count,
        quantity,
        unit_price,
        allocation_method,
        target_product_name,
        target_product_id,
        target_line_index,
        cost_center_id,
        cost_center_name,
        cost_status,
        expected_amount,
        actual_amount,
        variance_amount,
        base_amount,
        original_amount,
        original_currency,
        currency_snapshot,
        notes
      ) VALUES (
        v_max_cost_item_id,
        p_packing_order_id,
        COALESCE(v_el->>'name', 'بند تكلفة'),
        COALESCE(v_el->>'category', 'other'),
        v_el->>'category_name',
        (v_el->>'report_category_id')::integer,
        v_el->>'supplier_id',
        (v_el->>'transport_supplier_id')::integer,
        COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
        (v_el->>'quantity')::numeric,
        (v_el->>'unit_price')::numeric,
        COALESCE(v_el->>'allocation_method', 'EQUAL'),
        v_el->>'target_product_name',
        v_el->>'target_product_id',
        v_target_line_idx,
        v_el->>'cost_center_id',
        v_el->>'cost_center_name',
        COALESCE(v_el->>'cost_status', 'actual'),
        COALESCE((v_el->>'expected_amount')::numeric, v_amt_egp),
        v_amt_egp,
        0,
        v_amt_egp,
        v_amt_egp,
        COALESCE(v_el->>'supplier_currency', 'EGP'),
        jsonb_build_object(
          'supplier_name', v_el->>'supplier_name',
          'supplier_type', v_el->>'supplier_type',
          'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
          'transport_supplier_id', COALESCE(v_el->>'transport_supplier_id', CASE WHEN v_el->>'category' = 'logistics' THEN v_el->>'supplier_id' ELSE NULL END),
          'exchange_rate', COALESCE((v_el->>'exchange_rate')::numeric, 1.0)
        ),
        v_el->>'notes'
      );
    END LOOP;
  END IF;

  -- Calculate Total Cost Items
  SELECT COALESCE(SUM(base_amount), 0) INTO v_tot_cost_items
  FROM public.packing_order_cost_items
  WHERE packing_order_id = p_packing_order_id;

  v_company_id := v_order.company_id;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;

  -- 2. Resolve Debit Account: 12413 (Finished Goods / الإنتاج التام)
  SELECT id INTO v_finished_inv_acc
  FROM public.accounts
  WHERE (account_code = '12413' OR code = '12413')
    AND is_active = true
    AND (company_id = v_company_id OR company_id IS NULL)
  ORDER BY (company_id = v_company_id) DESC NULLS LAST, id ASC
  LIMIT 1;

  IF v_finished_inv_acc IS NULL THEN
    v_finished_inv_acc := public.resolve_gl_account('12413', v_company_id);
  END IF;
  IF v_finished_inv_acc IS NULL THEN
    v_finished_inv_acc := public.resolve_gl_account('1241', v_company_id);
  END IF;

  -- Resolve Transport Default Account (21111: موردي النقل والسيارات)
  SELECT id INTO v_transport_default_acc FROM public.accounts WHERE (account_code = '21111' OR code = '21111') LIMIT 1;
  IF v_transport_default_acc IS NULL THEN
    v_transport_default_acc := public.resolve_gl_account('21111', v_company_id);
  END IF;
  IF v_transport_default_acc IS NULL THEN
    v_transport_default_acc := public.resolve_gl_account('2111', v_company_id);
  END IF;

  -- 3. Create Costs Journal Entry if total costs > 0
  IF v_tot_cost_items > 0 THEN
    v_entry_num := public.generate_journal_entry_number('POC-EXP');

    INSERT INTO public.journal_entries (
      entry_number, date, description, status, reference_type, reference_id, company_id, created_at
    ) VALUES (
      v_entry_num,
      COALESCE(v_order.order_date, CURRENT_DATE),
      'إثبات التكاليف الإضافية والتشغيلية لأمر التعبئة رقم: ' || v_order_num,
      'posted',
      'packing_order_costs',
      p_packing_order_id::text,
      v_company_id,
      now()
    ) RETURNING id INTO v_je_id;

    -- Debit Entry: Finished Goods Inventory (12413)
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'تحميل تكاليف إضافية على مخزون الإنتاج التام لأمر التعبئة ' || v_order_num, v_company_id
    );
    v_sum_debit := v_tot_cost_items;

    -- Credit Entries: Loop per cost item
    FOR r_cost IN
      SELECT * FROM public.packing_order_cost_items
      WHERE packing_order_id = p_packing_order_id AND base_amount > 0
    LOOP
      v_credit_acc := NULL;
      v_supplier_id := NULL;
      v_trans_supplier_id := NULL;
      v_category_account_id := NULL;
      v_is_transport := false;

      v_supp_str := r_cost.supplier_id;
      IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' AND v_supp_str <> 'none' THEN
        BEGIN
          v_supplier_id := v_supp_str::uuid;
        EXCEPTION WHEN OTHERS THEN
          v_supplier_id := NULL;
        END;

        IF v_supplier_id IS NULL AND v_supp_str ~ '^[0-9]+$' THEN
          BEGIN
            v_trans_supplier_id := v_supp_str::integer;
          EXCEPTION WHEN OTHERS THEN
            v_trans_supplier_id := NULL;
          END;
        END IF;
      END IF;

      -- Check explicit transport_supplier_id column or snapshot
      IF v_trans_supplier_id IS NULL THEN
        IF r_cost.transport_supplier_id IS NOT NULL THEN
          v_trans_supplier_id := r_cost.transport_supplier_id;
        ELSIF r_cost.currency_snapshot IS NOT NULL AND (r_cost.currency_snapshot ? 'transport_supplier_id') 
              AND (r_cost.currency_snapshot->>'transport_supplier_id') IS NOT NULL 
              AND (r_cost.currency_snapshot->>'transport_supplier_id') <> '' 
              AND (r_cost.currency_snapshot->>'transport_supplier_id') <> 'null' THEN
          BEGIN
            v_trans_supplier_id := (r_cost.currency_snapshot->>'transport_supplier_id')::integer;
          EXCEPTION WHEN OTHERS THEN
            v_trans_supplier_id := NULL;
          END;
        END IF;
      END IF;

      -- Determine if this item represents transport / logistics
      v_is_transport := (
        v_trans_supplier_id IS NOT NULL
        OR r_cost.category = 'logistics'
        OR (r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot->>'supplier_type' = 'transport')
        OR r_cost.name ILIKE '%نقل%'
        OR r_cost.name ILIKE '%شحن%'
        OR r_cost.name ILIKE '%نولون%'
        OR (v_supplier_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.suppliers 
              WHERE id = v_supplier_id AND (supplier_type = 'transport' OR code LIKE '6%')
           ))
      );

      -- =========================================================================
      -- CASE A: TRANSPORT COST (Operational Movement - NO duplicate financial liability)
      -- =========================================================================
      IF v_is_transport THEN
        -- Resolve the Credit Account to balance inventory debit
        IF v_trans_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_credit_acc FROM public.transport_suppliers WHERE id = v_trans_supplier_id;
        END IF;

        IF v_credit_acc IS NULL THEN
          v_credit_acc := v_transport_default_acc;
        END IF;

        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('21111', v_company_id);
        END IF;

        -- Post GL Ledger Entry WITHOUT entity_type: 'transport_supplier' to avoid duplicate subledger liability
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        -- Trip Quota Deduction (allows exact decimal fractions, e.g. 0.5 نقلة):
        IF v_trans_supplier_id IS NOT NULL THEN
          v_consumed_trucks := COALESCE(
            NULLIF(r_cost.truck_count, 0),
            NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
            NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
            1.0
          );

          -- 1. Deduct from trip stock ONLY without touching financial balance:
          UPDATE public.transport_suppliers
          SET truck_balance = truck_balance - v_consumed_trucks,
              updated_at = NOW()
          WHERE id = v_trans_supplier_id;

          -- 2. Insert operational consumption transaction (amount = 0, no financial impact):
          INSERT INTO public.transport_transactions (
            supplier_id,
            type,
            amount,
            truck_count,
            reference_id,
            journal_entry_id,
            description,
            notes,
            date
          ) VALUES (
            v_trans_supplier_id,
            'packing_consumption',
            0,
            v_consumed_trucks,
            v_order.id::text,
            v_je_id,
            'استهلاك نقل أمر تعبئة ' || v_order.order_number || ' - ' || COALESCE(r_cost.name, ''),
            'استهلاك تشغيلي ' || v_consumed_trucks || ' نقلة من الرصيد بدون أثر مالي على كشف الحساب (تكلفة تشغيلية موزعة: ' || r_cost.base_amount || ' ج.م)',
            COALESCE(v_order.order_date, CURRENT_DATE)
          );
        END IF;

      -- =========================================================================
      -- CASE B: Standard Supplier (General, Station, Deduction, Packaging)
      -- =========================================================================
      ELSIF v_supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
        IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;

        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('21113', v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2111', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id,
          'supplier', v_supplier_id::text
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        -- Post Sub-Ledger Entry for Supplier
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

      -- =========================================================================
      -- CASE C: Administrative / Category-Mapped / Unassigned General Cost
      -- =========================================================================
      ELSE
        IF r_cost.report_category_id IS NOT NULL THEN
          SELECT account_id INTO v_category_account_id
          FROM public.cost_report_categories
          WHERE id = r_cost.report_category_id;
        END IF;

        IF v_category_account_id IS NULL THEN
          SELECT account_id INTO v_category_account_id
          FROM public.cost_report_categories
          WHERE name = r_cost.name
          LIMIT 1;
        END IF;

        IF v_category_account_id IS NOT NULL THEN
          v_credit_acc := v_category_account_id;
        ELSIF r_cost.category = 'admin' OR r_cost.name ILIKE '%إدار%' OR r_cost.name ILIKE '%ادار%' THEN
          v_credit_acc := public.resolve_gl_account('31331', v_company_id);
        ELSE
          v_credit_acc := public.resolve_gl_account('2111', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;
      END IF;
    END LOOP;

    -- Balance check
    IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
      RAISE EXCEPTION 'قيد التكاليف غير متزن: المدين (%) لا يساوي الدائن (%)', v_sum_debit, v_sum_credit;
    END IF;
  END IF;

  -- 4. Update Packing Order Status to costs_confirmed
  v_notes := jsonb_set(v_notes, '{workflow_stages,costs_confirmed}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'total_costs', v_tot_cost_items
  ), true);

  UPDATE public.packing_orders
  SET status = 'costs_confirmed',
      costs_confirmed_at = now(),
      costs_journal_entry_id = v_je_id,
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'status', 'costs_confirmed',
    'journal_entry_id', v_je_id,
    'total_costs', v_tot_cost_items,
    'message', 'تم تأكيد وترحيل التكاليف الإضافية وتحديث رصيد النقلات بنجاح'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_costs(bigint) TO authenticated, service_role, anon;

COMMIT;

