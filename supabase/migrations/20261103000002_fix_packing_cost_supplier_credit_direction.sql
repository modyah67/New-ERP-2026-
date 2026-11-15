-- ============================================================================
-- Migration: 20261103000002_fix_packing_cost_supplier_credit_direction.sql
-- Description:
--   1. Ensures category 19 (مصاريف مهندسين وإشراف) exists in cost_report_categories.
--   2. Hardens rpc_confirm_packing_costs with safe foreign-key check on report_category_id.
--   3. Fixes cost settlement baseline logic in rpc_settle_packing_cost_item and
--      rpc_settle_packing_cost_variances so unconfirmed orders do not deduct expected
--      costs that were never credited to the supplier.
--   4. Populates entity_type and entity_id on account_ledger_entries in settlements.
--   5. Enhances get_supplier_true_balances_by_currency with packing costs & entity isolation.
-- ============================================================================

-- 1. Ensure category 19 exists in cost_report_categories
INSERT INTO public.cost_report_categories (id, name, scope, supplier_type, is_system, type)
VALUES (19, 'مصاريف مهندسين وإشراف', 'packing', 'admin', false, 'direct')
ON CONFLICT (id) DO UPDATE 
SET name = EXCLUDED.name, scope = EXCLUDED.scope, supplier_type = EXCLUDED.supplier_type;

-- Ensure sequence is ahead of max ID
SELECT setval(pg_get_serial_sequence('public.cost_report_categories', 'id'), COALESCE((SELECT MAX(id) FROM public.cost_report_categories), 1));

-- 2. Updated rpc_confirm_packing_costs
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
          CASE WHEN (v_el->>'report_category_id') ~ '^[0-9]+$' AND EXISTS (SELECT 1 FROM public.cost_report_categories c WHERE c.id = (v_el->>'report_category_id')::integer) THEN (v_el->>'report_category_id')::integer ELSE NULL END,
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

-- 3. Updated rpc_settle_packing_cost_item
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



  SELECT * INTO r_item 

  FROM public.packing_order_cost_items 

  WHERE id = p_cost_item_id 

  FOR UPDATE;



  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'بند التكلفة غير موجود');

  END IF;



  SELECT * INTO r_order 

  FROM public.packing_orders 

  WHERE id = r_item.packing_order_id 

  FOR UPDATE;



  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة المرتبط غير موجود');

  END IF;



  v_order_num := COALESCE(r_order.order_number, r_order.id::text);



  v_expected := COALESCE(

    NULLIF(r_item.expected_amount, 0),

    NULLIF((r_item.currency_snapshot->'settlement'->>'expected_amount')::numeric, 0),

    NULLIF(r_item.base_amount, 0),

    NULLIF((r_item.currency_snapshot->>'total_egp')::numeric, 0),

    NULLIF((r_item.currency_snapshot->>'total')::numeric, 0),

    NULLIF(r_item.original_amount, 0),

    0

  );

  v_old_actual := r_item.actual_amount;



  IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
    v_baseline := v_old_actual;
  ELSIF r_order.costs_journal_entry_id IS NOT NULL THEN
    v_baseline := v_expected;
  ELSE
    v_baseline := 0;
  END IF;



  v_incremental_variance := ROUND(p_actual_amount - v_baseline, 2);

  v_total_variance := ROUND(p_actual_amount - v_expected, 2);

  v_abs_variance := ABS(v_incremental_variance);



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

    END;

  END IF;



  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;

  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;



  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));



  -- Determine balancing account

  v_supp_acc := NULL;

  IF LOWER(COALESCE(r_item.category, '')) = 'logistics' OR r_item.name ILIKE '%نقل%' THEN

    v_supp_acc := public.resolve_gl_account('21111', v_company_id);

    IF v_supp_acc IS NULL THEN v_supp_acc := public.resolve_gl_account('2111', v_company_id); END IF;

  ELSIF LOWER(COALESCE(r_item.category, '')) = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%' THEN

    v_supp_acc := public.resolve_gl_account('31331', v_company_id);

  ELSIF v_supplier_id IS NOT NULL THEN

    SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;

    IF FOUND AND v_supplier.account_id IS NOT NULL THEN

      v_supp_acc := v_supplier.account_id;

    ELSE

      v_supp_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);

    END IF;

  END IF;



  IF v_supp_acc IS NULL THEN

    v_supp_acc := public.resolve_gl_account('2000', v_company_id);

  END IF;

  IF v_supp_acc IS NULL THEN

    v_supp_acc := public.resolve_gl_account('2111', v_company_id);

  END IF;



  IF v_incremental_variance <> 0 THEN

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

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

        'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_supp_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

        'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

    ELSE

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_supp_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

        'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

        'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

    END IF;

  END IF;



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

-- 4. Updated rpc_settle_packing_cost_variances
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



  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;

  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  v_order_num := COALESCE(r_order.order_number, p_packing_order_id::text);



  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;

  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;



  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));



  -- Pre-calculate total variance to see if journal entry needed

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
  ELSIF r_order.costs_journal_entry_id IS NOT NULL THEN
    v_baseline := v_expected;
  ELSE
    v_baseline := 0;
  END IF;

        v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);

        v_total_inc_variance := v_total_inc_variance + v_incremental_variance;

      END IF;

    END IF;

  END LOOP;



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
  ELSIF r_order.costs_journal_entry_id IS NOT NULL THEN
    v_baseline := v_expected;
  ELSE
    v_baseline := 0;
  END IF;



    v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);

    v_total_variance := ROUND(v_actual_amt - v_expected, 2);

    v_abs_variance := ABS(v_incremental_variance);



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

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

          'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_target_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

          'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

      ELSE

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_target_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

          'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

          'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

      END IF;

    END IF;



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



  -- Update Linked Export Shipments

  FOR r_shipment IN

    SELECT DISTINCT shipment_id

    FROM public.export_shipment_items

    WHERE packing_order_id = p_packing_order_id

  LOOP

    v_shipments_affected := v_shipments_affected + 1;



    UPDATE public.export_shipment_items

    SET price = v_new_carton_cost,

        amount = ROUND(quantity * v_new_carton_cost, 2)

    WHERE shipment_id = r_shipment.shipment_id AND packing_order_id = p_packing_order_id;



    UPDATE public.shipment_cost_items sci

    SET unit_price = v_new_carton_cost

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = sci.shipment_id::text

      AND esi.packing_order_id = p_packing_order_id

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

-- 5. Updated get_supplier_true_balances_by_currency
CREATE OR REPLACE FUNCTION public.get_supplier_true_balances_by_currency()

RETURNS TABLE (

    supplier_id        uuid,

    supplier_code      text,

    supplier_name      text,

    currency           text,

    true_balance       numeric,   -- native currency amount

    true_balance_egp   numeric    -- converted to EGP using latest rate

)

LANGUAGE sql

SECURITY DEFINER

STABLE

AS $func$

  WITH rates AS (

    SELECT DISTINCT ON (currency_code) currency_code, rate_to_egp 

    FROM (

      SELECT currency_code, rate_to_egp, updated_at FROM exchange_rates

      UNION ALL

      SELECT 'EGP'::character varying(10), 1.0::numeric(10,4), NOW()

    ) r_all

    ORDER BY currency_code, updated_at DESC NULLS LAST

  ),

  -- 1. Initial Balances

  init_balances AS (

    -- Multi-currency suppliers with initial_balances_by_currency

    SELECT 

      s.id AS supplier_id,

      UPPER(COALESCE(elem.value->>'currency', elem.key)) AS currency,

      COALESCE((elem.value->>'amount')::numeric, 0) * (CASE WHEN UPPER(COALESCE(elem.value->>'direction', 'CREDIT')) = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt

    FROM suppliers s,

    LATERAL jsonb_each(s.initial_balances_by_currency) elem

    WHERE s.is_multi_currency = true 

      AND s.initial_balances_by_currency IS NOT NULL 

      AND jsonb_typeof(s.initial_balances_by_currency) = 'object'

      AND COALESCE((elem.value->>'amount')::numeric, 0) > 0

    

    UNION ALL

    

    -- Single-currency suppliers or multi without JSON map

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(s.currency, ''), 'EGP') AS currency,

      COALESCE(s.initial_balance, 0) * (CASE WHEN s.initial_balance_direction = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt

    FROM suppliers s

    WHERE (s.is_multi_currency = false OR s.initial_balances_by_currency IS NULL OR s.initial_balances_by_currency = '{}'::jsonb)

      AND COALESCE(s.initial_balance, 0) <> 0

  ),

  

  -- 2. Purchase Invoices (credit to supplier: increases payable)

  purchases AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      SUM(total_amount) AS net_amt

    FROM purchase_invoices

    WHERE status = 'confirmed' AND supplier_id IS NOT NULL

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 3. Treasury Transactions (payments to supplier and supplier advance deposits reduce liability: -amount)

  treasury AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      -SUM(amount) AS net_amt

    FROM treasury_transactions

    WHERE supplier_id IS NOT NULL 

      AND (status = 'confirmed' OR status IS NULL)

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 4. Bank Account Transactions (payments to supplier and supplier advance deposits reduce liability: -amount)

  bank_tx AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(ba.currency, ''), 'EGP') AS currency,

      -SUM(bat.amount) AS net_amt

    FROM bank_account_transactions bat

    JOIN suppliers s ON (s.id::text = bat.entity_id OR s.code = bat.entity_id OR s.supplier_code = bat.entity_id)

    LEFT JOIN bank_accounts ba ON ba.id = bat.bank_account_id

    WHERE bat.entity_type = 'supplier' 

      AND (bat.status = 'confirmed' OR bat.status IS NULL)

    GROUP BY s.id, COALESCE(NULLIF(ba.currency, ''), 'EGP')

  ),

  

  -- 5. Cheques (cheques linked to supplier reduce liability: -amount)

  cheque_tx AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      -SUM(amount) AS net_amt

    FROM cheques

    WHERE supplier_id IS NOT NULL 

      AND status IN ('cleared', 'collected')

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 6. Lot Receipts / Enterprise Account Ledger Entries (excluding lot_returns to avoid double counting with direct purchase_returns below)

  lot_tx AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(ale.currency, ''), 'EGP') AS currency,

      SUM(ale.credit - ale.debit) AS net_amt

    FROM account_ledger_entries ale

    JOIN journal_entries je ON je.id = ale.journal_entry_id

    JOIN suppliers s ON s.account_id = ale.account_id

    WHERE je.source_type IN ('lot_receipt','lot_adjustment','lot_price_adjustment','manual')

    GROUP BY s.id, COALESCE(NULLIF(ale.currency, ''), 'EGP')

  ),

  

  -- 7. Purchase Returns / Lot Returns (reduces supplier payable)

  purchase_returns AS (

    SELECT 

      lr.supplier_id,

      COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP'))) AS currency,

      -SUM(lr.return_value) AS net_amt

    FROM lot_returns lr

    LEFT JOIN lot_receipts rec ON rec.id = lr.lot_receipt_id

    JOIN suppliers s ON s.id = lr.supplier_id

    WHERE lr.supplier_id IS NOT NULL

    GROUP BY lr.supplier_id, COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP')))

  ),



  -- 8. Standalone Purchase Returns from Ledger Entries (if any not linked to lot_returns)

  ledger_returns AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,

      -SUM(le.amount) AS net_amt

    FROM ledger_entries le

    JOIN suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)

    WHERE le.entity_type = 'supplier'

      AND le.reference_type = 'purchase_return'

    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')

  ),

  

  -- Combine all activity

  combined AS (

    SELECT supplier_id, currency, net_amt FROM init_balances

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM purchases

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM treasury

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM bank_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM cheque_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM lot_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM purchase_returns

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM ledger_returns

  ),

  

  aggregated AS (

    SELECT 

      supplier_id,

      currency,

      SUM(net_amt) AS true_balance

    FROM combined

    GROUP BY supplier_id, currency

    HAVING SUM(net_amt) <> 0

  )

  

  SELECT 

    s.id AS supplier_id,

    COALESCE(s.code, s.supplier_code, '') AS supplier_code,

    s.name AS supplier_name,

    a.currency,

    a.true_balance,

    a.true_balance * COALESCE(r.rate_to_egp, 1.0) AS true_balance_egp

  FROM aggregated a

  JOIN suppliers s ON s.id = a.supplier_id

  LEFT JOIN rates r ON r.currency_code = a.currency;

$func$;
