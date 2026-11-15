-- ==============================================================================
-- Migration: Fix Administrative Expenses Unsettled Status and Prevent Auto-Lock
-- Date: 2026-11-06
-- ==============================================================================

-- 1. One-time Data Repair:
-- Reset all administrative cost items that were erroneously marked as 'actual' or 'locked'
-- during packing cost confirmation, restoring them to 'expected' (pending settlement).
UPDATE public.packing_order_cost_items
SET cost_status = 'expected',
    actual_amount = NULL,
    variance_amount = 0,
    is_locked = FALSE,
    locked_at = NULL
WHERE (category = 'admin' OR name ILIKE '%إدار%' OR name ILIKE '%ادار%')
  AND reconciled_at IS NULL
  AND variance_journal_entry_id IS NULL;

-- 2. Update rpc_confirm_packing_costs to NEVER lock or populate actual_amount for administrative expenses
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

  -- A. Revert previously recorded transport amounts and truck counts for this packing order (Idempotency)
  FOR r_prev_trans IN 
    SELECT supplier_id, 
           SUM(COALESCE(amount, 0)) AS total_prev_amount,
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

  -- 1. Idempotent Confirmation & Locking of Active Cost Items
  -- Administrative expenses are strictly kept as 'expected' and unlocked (is_locked = FALSE)
  -- until an actual invoice is approved through their dedicated settlement dialog.
  UPDATE public.packing_order_cost_items
  SET cost_status = CASE
          WHEN category = 'admin' OR name ILIKE '%إدار%' OR name ILIKE '%ادار%' THEN
              CASE WHEN (reconciled_at IS NOT NULL OR cost_status = 'settled') AND actual_amount IS NOT NULL THEN 'actual' ELSE 'expected' END
          ELSE 'actual'
      END,
      actual_amount = CASE
          WHEN category = 'admin' OR name ILIKE '%إدار%' OR name ILIKE '%ادار%' THEN
              CASE WHEN (reconciled_at IS NOT NULL OR cost_status = 'settled') THEN actual_amount ELSE NULL END
          ELSE COALESCE(actual_amount, expected_amount, base_amount)
      END,
      is_engineer_cost_settled = CASE WHEN category IN ('engineer', 'engineer_expenses') THEN TRUE ELSE is_engineer_cost_settled END,
      is_locked = CASE
          WHEN category = 'admin' OR name ILIKE '%إدار%' OR name ILIKE '%ادار%' THEN
              CASE WHEN (reconciled_at IS NOT NULL OR cost_status = 'settled') AND actual_amount IS NOT NULL THEN TRUE ELSE FALSE END
          ELSE TRUE
      END,
      locked_at = CASE
          WHEN category = 'admin' OR name ILIKE '%إدار%' OR name ILIKE '%ادار%' THEN
              CASE WHEN (reconciled_at IS NOT NULL OR cost_status = 'settled') AND actual_amount IS NOT NULL THEN COALESCE(locked_at, now()) ELSE NULL END
          ELSE COALESCE(locked_at, now())
      END
  WHERE packing_order_id = p_packing_order_id
    AND deleted_at IS NULL
    AND base_amount > 0;

  -- 2. Calculate Total Cost Items
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id AND deleted_at IS NULL
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
      WHERE packing_order_id = p_packing_order_id AND deleted_at IS NULL AND COALESCE(base_amount, 0) > 0
    LOOP
      v_credit_acc := NULL;
      v_supplier_id := NULL;
      v_trans_supplier_id := NULL;
      v_supp_str := NULL;
      v_category_account_id := NULL;
      v_is_transport := false;

      -- 1. Extract supplier identifier
      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      END IF;
      IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
        v_supp_str := r_cost.supplier_id;
      END IF;

      -- Check if supp_str is UUID
      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
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

      -- CASE A: TRANSPORT SUPPLIER / TRANSPORT COST -> Route to 21111 or Supplier Account
      IF v_is_transport THEN
        IF v_trans_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_credit_acc
          FROM public.transport_suppliers
          WHERE id = v_trans_supplier_id;
        END IF;

        IF v_credit_acc IS NULL AND v_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_credit_acc
          FROM public.suppliers
          WHERE id = v_supplier_id;
        END IF;

        IF v_credit_acc IS NULL THEN
          SELECT id INTO v_credit_acc
          FROM public.accounts
          WHERE (account_code = '21111' OR code = '21111')
            AND is_active = true
            AND (company_id = v_company_id OR company_id IS NULL)
          ORDER BY (company_id = v_company_id) DESC NULLS LAST, id ASC
          LIMIT 1;
        END IF;

        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('21111', v_company_id);
        END IF;

        IF v_credit_acc IS NULL THEN
          SELECT id INTO v_credit_acc
          FROM public.accounts
          WHERE account_code = '21111'
          LIMIT 1;
        END IF;

        IF v_credit_acc = (SELECT id FROM public.accounts WHERE account_code = '2112' LIMIT 1) THEN
          v_credit_acc := (SELECT id FROM public.accounts WHERE account_code = '21111' LIMIT 1);
        END IF;

        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2111', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        IF v_trans_supplier_id IS NOT NULL THEN
          v_consumed_trucks := COALESCE(
            NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
            NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
            NULLIF(r_cost.truck_count, 0),
            1.0
          );

          UPDATE public.transport_suppliers
          SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks,
              updated_at = now()
          WHERE id = v_trans_supplier_id;

          INSERT INTO public.transport_transactions (
            supplier_id, type, amount, currency, reference_id,
            description, truck_count, notes, journal_entry_id, date, created_at
          ) VALUES (
            v_trans_supplier_id,
            'packing_consumption',
            0,
            'EGP',
            p_packing_order_id::text,
            'تكلفة ونقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل') || ' (' || v_consumed_trucks::text || ' نقلة)',
            v_consumed_trucks,
            'استحقاق مالي ' || r_cost.base_amount::text || ' ج.م وسحب ' || v_consumed_trucks::text || ' نقلة لأمر تعبئة ' || v_order_num,
            v_je_id,
            (COALESCE(v_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date,
            now()
          );
        ELSIF v_supplier_id IS NOT NULL THEN
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
              'بند تكلفة تقديرية نقل: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
            );
            UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
          END IF;
        END IF;

      -- CASE B: Standard Supplier (General, Station, Deduction, Packaging)
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

      -- CASE C: Administrative / Category-Mapped / Unassigned General Cost
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

    -- Fallback for unallocated general costs
    IF v_tot_cost_items > v_posted_cost_items THEN
      v_credit_acc := public.resolve_gl_account('2111', v_company_id);
      IF v_credit_acc IS NULL THEN
        v_credit_acc := public.resolve_gl_account('21113', v_company_id);
      END IF;
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
      SET amount_in_base_currency = amount_in_base_currency + (v_sum_debit - v_sum_credit),
          credit = credit + (v_sum_debit - v_sum_credit)
      WHERE id = (SELECT id FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id AND credit > 0 ORDER BY id DESC LIMIT 1);
    END IF;
  END IF;

  -- 5. Mark Order Stage as Costs Confirmed & Save Reference
  UPDATE public.packing_orders
  SET is_costs_confirmed = true,
      costs_confirmed_at = COALESCE(costs_confirmed_at, now()),
      costs_journal_entry_id = v_je_id,
      status = 'costs_confirmed',
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'message', 'تم تأكيد وترحيل بنود التكاليف بنجاح',
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items
  );
END;
$function$;

