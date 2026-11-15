-- ============================================================================
-- Migration: 20261103000001_fix_decimal_truck_counts.sql
-- Description:
-- 1. Ensure columns support exact decimal fractions (e.g. 0.5, 1.25) across:
--    - public.packing_order_cost_items (truck_count, quantity NUMERIC(12, 4))
--    - public.transport_transactions (truck_count NUMERIC(12, 4))
--    - public.transport_suppliers (truck_balance, initial_truck_balance NUMERIC(12, 4))
-- 2. Explicitly store truck_count, quantity, unit_price, cost_status, expected/actual amounts
--    into packing_order_cost_items when posting/rebuilding cost items.
-- 3. In rpc_confirm_packing_costs, prioritize exact decimal truck_count from currency_snapshot
--    and ensure trip stock is deducted with full decimal precision (0.5 instead of 1.0).
-- 4. Reconcile existing historical transport_transactions where truck_count defaulted to 1.0
--    while currency_snapshot had a decimal fraction (e.g. 0.5), restoring over-deducted quota.
-- ============================================================================

BEGIN;

-- ── 1. Column Type Assurance for Decimal Numbers ──
ALTER TABLE IF EXISTS public.transport_transactions 
  ALTER COLUMN truck_count TYPE NUMERIC(12, 4) USING truck_count::numeric;

ALTER TABLE IF EXISTS public.packing_order_cost_items 
  ALTER COLUMN truck_count TYPE NUMERIC(12, 4) USING truck_count::numeric,
  ALTER COLUMN quantity TYPE NUMERIC(12, 4) USING quantity::numeric;

ALTER TABLE IF EXISTS public.transport_suppliers 
  ALTER COLUMN truck_balance TYPE NUMERIC(12, 4) USING truck_balance::numeric,
  ALTER COLUMN initial_truck_balance TYPE NUMERIC(12, 4) USING initial_truck_balance::numeric;

-- ── 2. Historical Reconcilation for Previous Truncated Transactions ──
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tt.id AS trans_id, tt.supplier_id, tt.truck_count AS old_trucks,
           COALESCE(
             NULLIF((ci.currency_snapshot->>'truck_count')::numeric, 0),
             NULLIF((ci.currency_snapshot->>'quantity')::numeric, 0)
           ) AS correct_trucks
    FROM public.transport_transactions tt
    JOIN public.packing_order_cost_items ci
      ON ci.packing_order_id::text = tt.reference_id
     AND (ci.transport_supplier_id = tt.supplier_id OR ci.supplier_id = tt.supplier_id::text)
    WHERE tt.type = 'packing_consumption'
      AND tt.truck_count = 1.0
      AND (ci.currency_snapshot->>'truck_count')::numeric IS NOT NULL
      AND (ci.currency_snapshot->>'truck_count')::numeric <> 1.0
  LOOP
    IF r.correct_trucks IS NOT NULL AND r.correct_trucks > 0 THEN
      -- Update transaction truck_count and description
      UPDATE public.transport_transactions
      SET truck_count = r.correct_trucks,
          description = regexp_replace(description, '\(1\.0+ نقلة\)', '(' || r.correct_trucks::text || ' نقلة)'),
          notes = regexp_replace(notes, '1\.0+ نقلة', r.correct_trucks::text || ' نقلة')
      WHERE id = r.trans_id;

      -- Update packing_order_cost_items truck_count
      UPDATE public.packing_order_cost_items
      SET truck_count = r.correct_trucks
      WHERE packing_order_id::text = (SELECT reference_id FROM public.transport_transactions WHERE id = r.trans_id)
        AND (transport_supplier_id = r.supplier_id OR supplier_id = r.supplier_id::text);

      -- Restore over-deducted quota on transport supplier
      UPDATE public.transport_suppliers
      SET truck_balance = truck_balance + (r.old_trucks - r.correct_trucks),
          updated_at = NOW()
      WHERE id = r.supplier_id;
    END IF;
  END LOOP;
END $$;

-- ── 3. Canonical rpc_confirm_packing_costs Definition ──
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

  -- 1. Rebuild Cost Items from Notes

  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN

    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;

    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;

    IF v_max_cost_item_id > 0 THEN

      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);

    ELSE

      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), 1, false);

    END IF;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')

    LOOP

      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);

      IF v_amt_egp > 0 THEN

        v_supplier_id := NULL;

        v_supp_str := v_el->>'supplier_id';

        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN

          BEGIN

            v_supplier_id := v_supp_str::uuid;

          EXCEPTION WHEN OTHERS THEN

            v_supplier_id := NULL;

          END;

        END IF;

        v_target_line_idx := NULL;

        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' AND v_el->>'target_line_index' != 'null' THEN

          v_target_line_idx := (v_el->>'target_line_index')::integer;

        END IF;

        INSERT INTO public.packing_order_cost_items (
          packing_order_id, name, category,
          base_amount, original_amount, original_currency,
          payment_source_type, payment_source_id,
          allocation_method, target_line_id,
          currency_snapshot, supplier_id, payment_status, paid_amount,
          truck_count, quantity, unit_price, cost_status,
          expected_amount, actual_amount, variance_amount,
          report_category_id, transport_supplier_id
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
            'supplier_id', COALESCE(v_supplier_id::text, v_supp_str),
            'supplier_name', v_el->>'supplier_name',
            'target_line_index', v_target_line_idx,
            'transport_supplier_id', COALESCE(v_el->>'transport_supplier_id', CASE WHEN v_el->>'category' = 'logistics' OR v_el->>'supplier_type' = 'transport' THEN v_supp_str ELSE NULL END),
            'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
            'quantity', COALESCE((v_el->>'quantity')::numeric, (v_el->>'truck_count')::numeric, 1.0),
            'supplier_type', v_el->>'supplier_type'
          ),
          COALESCE(v_supplier_id::text, v_supp_str),
          'unpaid',
          0,
          COALESCE(NULLIF((v_el->>'truck_count')::numeric, 0), NULLIF((v_el->>'quantity')::numeric, 0), 1.0),
          COALESCE(NULLIF((v_el->>'quantity')::numeric, 0), NULLIF((v_el->>'truck_count')::numeric, 0), 1.0),
          COALESCE((v_el->>'unit_price')::numeric, (v_el->>'rate')::numeric, (v_el->>'total')::numeric, v_amt_egp),
          'actual',
          COALESCE((v_el->>'expected_amount')::numeric, (v_el->>'total')::numeric, v_amt_egp),
          COALESCE((v_el->>'actual_amount')::numeric, (v_el->>'total')::numeric, v_amt_egp),
          COALESCE((v_el->>'variance_amount')::numeric, 0.00),
          NULLIF(v_el->>'report_category_id', '')::integer,
          COALESCE(NULLIF(v_el->>'transport_supplier_id', '')::integer, CASE WHEN v_el->>'category' = 'logistics' OR v_el->>'supplier_type' = 'transport' THEN NULLIF(v_supp_str, '')::integer ELSE NULL END)
        );

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

      -- =========================================================================

      -- CASE A: TRANSPORT SUPPLIER / TRANSPORT COST -> Route to 21111 or Supplier Account

      -- =========================================================================

      IF v_is_transport THEN

        -- 1. Try transport supplier's direct account_id if configured

        IF v_trans_supplier_id IS NOT NULL THEN

          SELECT account_id INTO v_credit_acc

          FROM public.transport_suppliers

          WHERE id = v_trans_supplier_id;

        END IF;

        -- 2. If general supplier UUID was used with transport type, check suppliers.account_id

        IF v_credit_acc IS NULL AND v_supplier_id IS NOT NULL THEN

          SELECT account_id INTO v_credit_acc

          FROM public.suppliers

          WHERE id = v_supplier_id;

        END IF;

        -- 3. Resolve the Transport Suppliers Sub-ledger account: Code '21111'

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

        -- Hard safety check: NEVER allow 2112 (Notes Payable / أوراق الدفع)!

        IF v_credit_acc = (SELECT id FROM public.accounts WHERE account_code = '2112' LIMIT 1) THEN

          v_credit_acc := (SELECT id FROM public.accounts WHERE account_code = '21111' LIMIT 1);

        END IF;

        -- Fallback to master suppliers control (2111) if 21111 somehow missing

        IF v_credit_acc IS NULL THEN

          v_credit_acc := public.resolve_gl_account('2111', v_company_id);

        END IF;

        -- Post GL Ledger Entry for Transport Cost -> Account 21111 / Supplier account

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,

          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id

        );

        v_sum_credit := v_sum_credit + r_cost.base_amount;

        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        -- Operational Truck Deduction & Financial Entitlement Posting

        IF v_trans_supplier_id IS NOT NULL THEN

          v_consumed_trucks := COALESCE(
            NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
            NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
            NULLIF(r_cost.truck_count, 0),
            1.0
          );

          -- 1. Update Transport Supplier Balances (Trucks & Financial)

          UPDATE public.transport_suppliers

          SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks,

              updated_at = now()

          WHERE id = v_trans_supplier_id;

          -- 2. Insert Transport Transaction (operational consumption, amount = 0)

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

        -- Priority 1: Check category mapped account (e.g. 31331 for مصاريف إدارية)

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

COMMIT;
