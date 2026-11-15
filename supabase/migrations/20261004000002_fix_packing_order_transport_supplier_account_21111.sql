-- ============================================================================
-- Migration: 20261004000002_fix_packing_order_transport_supplier_account_21111.sql
-- Description: Direct packing order transport cost liabilities to Transport
--              Suppliers Sub-ledger account (21111) instead of Notes Payable (2112).
-- ============================================================================

-- ── 1. Fix legacy code mapping in resolve_gl_account ──
-- 2000 is legacy Accounts Payable control, which should resolve to 2111 (or 21113),
-- NEVER 2112 (which is Notes Payable / أوراق الدفع).
CREATE OR REPLACE FUNCTION public.resolve_gl_account(
    p_account_code TEXT,
    p_company_id   UUID DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id BIGINT;
    v_target_code TEXT := p_account_code;
BEGIN
    IF v_target_code IS NULL OR v_target_code = '' THEN
        RETURN NULL;
    END IF;

    -- 1. Direct match by code and company
    SELECT id INTO v_id FROM public.accounts 
    WHERE account_code = v_target_code 
      AND (company_id = p_company_id OR company_id IS NULL)
    ORDER BY (company_id = p_company_id) DESC NULLS LAST, id ASC
    LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 2. General match by code
    SELECT id INTO v_id FROM public.accounts WHERE account_code = v_target_code LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 3. Legacy and alternative code translations
    v_target_code := CASE p_account_code
        WHEN '1020' THEN '1221'
        WHEN '2000' THEN '2111'   -- Accounts Payable control (NOT 2112 Notes Payable)
        WHEN '2101' THEN '9121'
        WHEN '9101' THEN '9121'
        WHEN '2102' THEN '9122'
        WHEN '9102' THEN '9122'
        WHEN '2103' THEN '21115'
        WHEN '2104' THEN '21116'
        WHEN '2105' THEN '9123'
        WHEN '9105' THEN '9123'
        WHEN '2106' THEN '9111'
        WHEN '9106' THEN '9111'
        WHEN '2107' THEN '9112'
        WHEN '9107' THEN '9112'
        WHEN '3000' THEN '23111'
        WHEN '3101' THEN '2321'
        WHEN '5000' THEN '3111'
        WHEN '1030' THEN '12412'
        WHEN '1031' THEN '12413'
        WHEN '1040' THEN '12411'
        WHEN '1050' THEN '12414'
        WHEN '1060' THEN '12415'
        WHEN '21311' THEN '21111' -- Transport suppliers legacy code -> 21111
        ELSE p_account_code
    END;

    IF v_target_code <> p_account_code THEN
        SELECT id INTO v_id FROM public.accounts 
        WHERE account_code = v_target_code 
          AND (company_id = p_company_id OR company_id IS NULL)
        ORDER BY (company_id = p_company_id) DESC NULLS LAST, id ASC
        LIMIT 1;
        IF v_id IS NOT NULL THEN RETURN v_id; END IF;

        SELECT id INTO v_id FROM public.accounts WHERE account_code = v_target_code LIMIT 1;
        IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    END IF;

    RETURN NULL;
END;
$$;

-- ── 2. Update fn_resolve_packing_cost_supplier_account ──
CREATE OR REPLACE FUNCTION public.fn_resolve_packing_cost_supplier_account(
    p_supplier_id UUID,
    p_company_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_acc_id BIGINT;
    v_supp_type TEXT;
    v_supp_code TEXT;
    v_target_code TEXT;
BEGIN
    IF p_supplier_id IS NULL THEN
        RETURN public.resolve_gl_account('2111', p_company_id);
    END IF;

    SELECT account_id, supplier_type, code INTO v_acc_id, v_supp_type, v_supp_code
    FROM public.suppliers
    WHERE id = p_supplier_id;

    IF v_acc_id IS NOT NULL THEN
        RETURN v_acc_id;
    END IF;

    -- Infer code from supplier_type
    IF v_supp_type = 'station' OR v_supp_code LIKE '8%' THEN
        v_target_code := '21117';
    ELSIF v_supp_type IN ('deduction', 'deductions') OR v_supp_code LIKE '4%' THEN
        v_target_code := '21118';
    ELSIF v_supp_type = 'transport' OR v_supp_code LIKE '6%' THEN
        v_target_code := '21111';
    ELSIF v_supp_type = 'packaging' OR v_supp_code LIKE '70%' OR v_supp_code LIKE '71%' THEN
        v_target_code := '21112';
    ELSIF v_supp_type = 'shared' OR v_supp_code LIKE '75%' THEN
        v_target_code := '21114';
    ELSIF v_supp_type = 'shipping' OR v_supp_code LIKE '9%' THEN
        v_target_code := '21115';
    ELSE
        v_target_code := '21113';
    END IF;

    v_acc_id := public.resolve_gl_account(v_target_code, p_company_id);
    IF v_acc_id IS NULL THEN
        SELECT id INTO v_acc_id FROM public.accounts 
        WHERE account_code = v_target_code 
        LIMIT 1;
    END IF;

    RETURN v_acc_id;
END;
$$;

-- ── 3. Canonical rpc_confirm_packing_costs Function ──
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
  r_prev_trans RECORD;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_max_cost_item_id BIGINT;
  v_existing_item RECORD;
  v_status_to_set TEXT;
  v_expected_to_set NUMERIC;
  v_actual_to_set NUMERIC;
  v_variance_to_set NUMERIC;
  v_consumed_trucks NUMERIC;
  v_category_account_id BIGINT;
  v_is_transport BOOLEAN;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Validate prerequisite: packaging must be confirmed first
  IF (v_order.status IN ('draft', 'pending', 'crops_confirmed')) AND v_order.packaging_confirmed_at IS NULL AND v_order.packaging_journal_entry_id IS NULL THEN
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

  -- A. Revert previously deducted trip stock for idempotency if re-confirming this order
  FOR r_prev_trans IN 
    SELECT supplier_id, SUM(truck_count) as total_prev_trucks 
    FROM public.transport_transactions 
    WHERE reference_id = p_packing_order_id::text 
      AND type IN ('packing_consumption', 'packing_order_consumption')
    GROUP BY supplier_id
  LOOP
    UPDATE public.transport_suppliers
    SET truck_balance = COALESCE(truck_balance, 0) + r_prev_trans.total_prev_trucks,
        updated_at = now()
    WHERE id = r_prev_trans.supplier_id;
  END LOOP;

  DELETE FROM public.transport_transactions 
  WHERE reference_id = p_packing_order_id::text 
    AND type IN ('packing_consumption', 'packing_order_consumption');

  -- B. Rebuild Cost Items from Notes preserving any existing actual settlements
  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
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
        v_trans_supplier_id := NULL;
        v_supp_str := v_el->>'supplier_id';
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

        IF v_trans_supplier_id IS NULL AND v_el ? 'transport_supplier_id' 
           AND (v_el->>'transport_supplier_id') IS NOT NULL 
           AND (v_el->>'transport_supplier_id') <> '' 
           AND (v_el->>'transport_supplier_id') <> 'null' THEN
          BEGIN
            v_trans_supplier_id := (v_el->>'transport_supplier_id')::integer;
          EXCEPTION WHEN OTHERS THEN
            v_trans_supplier_id := NULL;
          END;
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
          AND (
            supplier_id = COALESCE(v_supp_str, v_supplier_id::text) 
            OR transport_supplier_id = v_trans_supplier_id
            OR (supplier_id IS NULL AND v_supp_str IS NULL AND transport_supplier_id IS NULL)
          )
        LIMIT 1;

        IF v_existing_item.id IS NOT NULL THEN
          UPDATE public.packing_order_cost_items
          SET base_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.base_amount ELSE v_amt_egp END,
              original_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.original_amount ELSE COALESCE((v_el->>'total')::numeric, v_amt_egp) END,
              expected_amount = COALESCE(v_existing_item.expected_amount, v_amt_egp),
              truck_count = COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
              quantity = (v_el->>'quantity')::numeric,
              unit_price = (v_el->>'unit_price')::numeric,
              transport_supplier_id = COALESCE(v_trans_supplier_id, (v_el->>'transport_supplier_id')::integer),
              report_category_id = COALESCE((v_el->>'report_category_id')::integer, v_existing_item.report_category_id),
              currency_snapshot = jsonb_build_object(
                'supplier_id', COALESCE(v_supp_str, v_supplier_id::text),
                'supplier_name', v_el->>'supplier_name',
                'supplier_type', CASE 
                  WHEN v_trans_supplier_id IS NOT NULL OR (v_el->>'category') = 'logistics' OR (v_el->>'name') ILIKE '%نقل%' THEN 'transport'
                  ELSE v_el->>'supplier_type'
                END,
                'transport_supplier_id', v_trans_supplier_id,
                'report_category_id', v_el->>'report_category_id',
                'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
                'quantity', (v_el->>'quantity')::numeric,
                'unit_price', (v_el->>'unit_price')::numeric,
                'target_line_index', v_target_line_idx,
                'cost_status', v_status_to_set,
                'expected_amount', v_expected_to_set
              )
          WHERE id = v_existing_item.id;
        ELSE
          INSERT INTO public.packing_order_cost_items (
            packing_order_id, name, category,
            base_amount, original_amount, original_currency,
            payment_source_type, payment_source_id,
            allocation_method, target_line_id,
            currency_snapshot, supplier_id, payment_status, paid_amount,
            cost_status, expected_amount, actual_amount, variance_amount, invoice_ref,
            truck_count, quantity, unit_price, transport_supplier_id, report_category_id
          ) VALUES (
            p_packing_order_id,
            v_el->>'name',
            CASE 
              WHEN v_trans_supplier_id IS NOT NULL OR (v_el->>'supplier_type') = 'transport' OR (v_el->>'category') = 'logistics' OR (v_el->>'name') ILIKE '%نقل%' THEN 'logistics'
              WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'admin', 'other') THEN v_el->>'category' 
              WHEN (v_el->>'supplier_type') = 'admin' OR (v_el->>'name') = 'مصاريف إدارية' THEN 'admin'
              ELSE 'other' 
            END,
            v_amt_egp,
            COALESCE((v_el->>'total')::numeric, v_amt_egp),
            COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
            'none',
            NULL,
            v_el->>'allocation_method',
            v_target_line_idx,
            jsonb_build_object(
              'supplier_id', COALESCE(v_supp_str, v_supplier_id::text),
              'supplier_name', v_el->>'supplier_name',
              'supplier_type', CASE 
                WHEN v_trans_supplier_id IS NOT NULL OR (v_el->>'category') = 'logistics' OR (v_el->>'name') ILIKE '%نقل%' THEN 'transport'
                ELSE v_el->>'supplier_type'
              END,
              'transport_supplier_id', v_trans_supplier_id,
              'report_category_id', v_el->>'report_category_id',
              'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
              'quantity', (v_el->>'quantity')::numeric,
              'unit_price', (v_el->>'unit_price')::numeric,
              'target_line_index', v_target_line_idx,
              'cost_status', v_status_to_set,
              'expected_amount', v_expected_to_set
            ),
            COALESCE(v_supp_str, v_supplier_id::text),
            'unpaid',
            0,
            v_status_to_set,
            v_expected_to_set,
            v_actual_to_set,
            v_variance_to_set,
            v_el->>'invoice_ref',
            COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
            (v_el->>'quantity')::numeric,
            (v_el->>'unit_price')::numeric,
            v_trans_supplier_id,
            (v_el->>'report_category_id')::integer
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

  -- 4. Create Costs Confirmation Journal Entry & Post Liabilities
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

    -- CR Balancing Accounts & Sub-Ledger Posting
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
      -- CASE A: TRANSPORT SUPPLIER / TRANSPORT COST -> Route to 21111
      -- =========================================================================
      IF v_is_transport THEN
        -- 1. Try transport supplier's direct account_id if available
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

        -- Fallback to master suppliers control (2111), NEVER 2112!
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2111', v_company_id);
        END IF;

        -- Post GL Ledger Entry for Transport Cost -> Account 21111
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id,
          'transport_supplier', COALESCE(v_trans_supplier_id::text, v_supplier_id::text, '')
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        -- Operational Truck Deduction & Transaction Tracking
        IF v_trans_supplier_id IS NOT NULL THEN
          v_consumed_trucks := COALESCE(
            NULLIF(r_cost.truck_count, 0),
            NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
            NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
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
            'استهلاك نقلات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'),
            v_consumed_trucks,
            'استهلاك تشغيلي ' || v_consumed_trucks::text || ' نقلة من الرصيد بدون أثر مالي على كشف الحساب',
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

    -- Sub-cent penny rounding absorption
    IF v_sum_debit != v_sum_credit AND v_tot_cost_items > 0 THEN
      UPDATE public.account_ledger_entries
      SET amount_in_base_currency = amount_in_base_currency + (v_sum_debit - v_sum_credit),
          credit = credit + (v_sum_debit - v_sum_credit)
      WHERE id = (
        SELECT id FROM public.account_ledger_entries
        WHERE journal_entry_id = v_je_id AND credit > 0
        ORDER BY id DESC LIMIT 1
      );
      v_sum_credit := v_sum_debit;
    END IF;

    -- Balance check
    IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
      RAISE EXCEPTION 'فشل تأكيد قيد بنود التكلفة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
    END IF;

    -- 5. Mark Costs Stage Confirmed
    UPDATE public.packing_orders
    SET costs_journal_entry_id = v_je_id,
        costs_confirmed_at = COALESCE(costs_confirmed_at, now()),
        status = CASE 
          WHEN status IN ('draft', 'pending', 'crops_confirmed', 'packaging_confirmed') THEN 'costs_confirmed'
          ELSE status 
        END,
        updated_at = now()
    WHERE id = p_packing_order_id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'تم تأكيد بنود التكاليف وإثبات قيود الموردين بنجاح',
    'status', 'costs_confirmed',
    'journal_entry_id', v_je_id,
    'total_costs', v_tot_cost_items
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_costs(bigint) TO authenticated, service_role, anon;

-- ── 4. Backfill historical packing order cost ledger entries ──
-- Correct any existing entries erroneously routed to 2112 (Notes Payable)
-- to 21111 (Transport Suppliers Sub-ledger)
DO $$
DECLARE
  v_correct_acc BIGINT;
  v_wrong_acc   BIGINT;
BEGIN
  SELECT id INTO v_correct_acc FROM public.accounts WHERE account_code = '21111' LIMIT 1;
  SELECT id INTO v_wrong_acc FROM public.accounts WHERE account_code = '2112' LIMIT 1;

  IF v_correct_acc IS NOT NULL AND v_wrong_acc IS NOT NULL THEN
    UPDATE public.account_ledger_entries
    SET account_id = v_correct_acc,
        entity_type = 'transport_supplier'
    WHERE account_id = v_wrong_acc
      AND (
        description LIKE '%نقل%'
        OR journal_entry_id IN (
          SELECT id FROM public.journal_entries WHERE source_type = 'packing_order_costs'
        )
      );
  END IF;
END $$;
