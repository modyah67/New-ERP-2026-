-- ============================================================================
-- Migration: 20261002000003_fix_packing_costs_uuid_and_transport_suppliers.sql
-- Description:
-- 1. Decouple Transport Costs from Transporter Financial Balance:
--    - Freight cost is charged only to packing order cost & finished goods inventory.
--    - Transport supplier financial ledger (balance / current_balance) is NOT credited or modified.
-- 2. Deduct from Trip Quotas / Stock Only:
--    - Deducts consumed trips from transport_suppliers.truck_balance.
--    - Records a 'packing_consumption' transaction in transport_transactions with amount = 0.
--    - Reverts previously consumed trips if order is re-confirmed for idempotency.
-- 3. Allow Decimal / Fractional Trips (e.g. 0.5 trip):
--    - Alters truck_balance, initial_truck_balance, and truck_count columns to NUMERIC(12,2).
--    - Updates get_transport_supplier_true_balances to return truck_balance as NUMERIC.
--    - Safely parses UUID vs Integer IDs for suppliers in packing costs confirmation & reconciliation.
-- ============================================================================

BEGIN;

-- ── 1. Update Column Data Types to support Decimal Trips (e.g., 0.5, 1.5) ──
ALTER TABLE public.transport_suppliers 
  ALTER COLUMN truck_balance TYPE NUMERIC(12,2) USING truck_balance::numeric,
  ALTER COLUMN initial_truck_balance TYPE NUMERIC(12,2) USING initial_truck_balance::numeric;

ALTER TABLE public.transport_transactions 
  ALTER COLUMN truck_count TYPE NUMERIC(12,2) USING truck_count::numeric;

ALTER TABLE public.packing_order_cost_items 
  ADD COLUMN IF NOT EXISTS truck_count NUMERIC(12,2) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS quantity NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS unit_price NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS transport_supplier_id INTEGER;

-- ── 2. Update get_transport_supplier_true_balances with NUMERIC truck_balance ──
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
          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice', 'packing_order_invoice')
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
          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice', 'packing_order_invoice')
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
          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice')
        ), 0)
      - COALESCE((
          SELECT SUM(COALESCE(tt.truck_count, 1))
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('packing_consumption', 'packing_order_consumption')
        ), 0)
    )::numeric AS truck_balance
  FROM public.transport_suppliers ts;
$func$;

GRANT EXECUTE ON FUNCTION public.get_transport_supplier_true_balances() TO authenticated, anon, service_role;

-- ── 3. Update rpc_confirm_packing_costs ──
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

        v_status_to_set := COALESCE(NULLIF(v_el->>'cost_status', ''), 'expected');
        v_expected_to_set := COALESCE((v_el->>'expected_amount')::numeric, v_amt_egp);
        v_actual_to_set := (v_el->>'actual_amount')::numeric;
        v_variance_to_set := COALESCE((v_el->>'variance_amount')::numeric, 0);

        -- Check if an item already exists with this name and supplier to avoid duplicate insert
        SELECT * INTO v_existing_item 
        FROM public.packing_order_cost_items 
        WHERE packing_order_id = p_packing_order_id 
          AND name = (v_el->>'name')
          AND (supplier_id = COALESCE(v_supp_str, v_supplier_id::text) OR (supplier_id IS NULL AND v_supp_str IS NULL))
        LIMIT 1;

        IF v_existing_item.id IS NOT NULL THEN
          -- Keep existing reconciled data while updating quantities and snapshot
          UPDATE public.packing_order_cost_items
          SET base_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.base_amount ELSE v_amt_egp END,
              original_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.original_amount ELSE COALESCE((v_el->>'total')::numeric, v_amt_egp) END,
              expected_amount = COALESCE(v_existing_item.expected_amount, v_amt_egp),
              truck_count = COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
              quantity = (v_el->>'quantity')::numeric,
              unit_price = (v_el->>'unit_price')::numeric,
              transport_supplier_id = (v_el->>'transport_supplier_id')::integer,
              currency_snapshot = jsonb_build_object(
                'supplier_id', COALESCE(v_supp_str, v_supplier_id::text),
                'supplier_name', v_el->>'supplier_name',
                'supplier_type', v_el->>'supplier_type',
                'transport_supplier_id', v_el->>'transport_supplier_id',
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
            truck_count, quantity, unit_price, transport_supplier_id
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
              'supplier_id', COALESCE(v_supp_str, v_supplier_id::text),
              'supplier_name', v_el->>'supplier_name',
              'supplier_type', v_el->>'supplier_type',
              'transport_supplier_id', v_el->>'transport_supplier_id',
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
            (v_el->>'transport_supplier_id')::integer
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

      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      END IF;
      IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
        v_supp_str := r_cost.supplier_id;
      END IF;

      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        BEGIN
          v_supplier_id := v_supp_str::uuid;
        EXCEPTION WHEN OTHERS THEN
          v_supplier_id := NULL;
        END;

        IF v_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
        ELSE
          -- Check transport supplier (integer ID)
          BEGIN
            v_trans_supplier_id := v_supp_str::integer;
          EXCEPTION WHEN OTHERS THEN
            v_trans_supplier_id := NULL;
          END;
        END IF;
      END IF;

      -- CASE 1: Standard Supplier (General, Station, Deduction, Packaging)
      IF v_supplier_id IS NOT NULL THEN
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

      -- CASE 2: Transport Supplier
      -- RULE: Decouple from financial balance (no supplier liability credit),
      -- Deduct from trip quota ONLY, support fractional trips (0.5).
      ELSIF v_trans_supplier_id IS NOT NULL THEN
        -- In GL: credit absorbed transport expense account (51311) to balance inventory debit
        SELECT id INTO v_credit_acc
        FROM public.accounts
        WHERE (code = '51311' OR account_code = '51311' OR name ILIKE '%مصاريف نقل%' OR name ILIKE '%نقل%')
          AND is_active = true
        ORDER BY CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END
        LIMIT 1;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('51311', v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('5100', v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2000', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        -- Trip Quota Deduction (allows decimal, e.g. 0.5 نقلة):
        v_consumed_trucks := COALESCE(
          NULLIF(r_cost.truck_count, 0),
          NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
          NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
          1.0
        );

        -- Deduct from trip stock without touching financial balance:
        UPDATE public.transport_suppliers
        SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks,
            updated_at = now()
        WHERE id = v_trans_supplier_id;

        -- Record operational consumption in transport_transactions with amount = 0 (no financial impact):
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

      -- CASE 3: General Unassigned Cost
      ELSE
        v_credit_acc := public.resolve_gl_account('2000', v_company_id);
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

-- ── 4. Update rpc_reconcile_packing_cost_item with Decoupled Transport Logic ──
CREATE OR REPLACE FUNCTION public.rpc_reconcile_packing_cost_item(
  p_cost_item_id BIGINT,
  p_actual_amount NUMERIC,
  p_invoice_ref TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  r_item RECORD;
  r_order RECORD;
  v_order_num TEXT;
  v_company_id UUID;
  v_finished_inv_acc INT;
  v_supp_acc INT;
  v_je_id INT;
  v_entry_num TEXT;
  v_supplier RECORD;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_supp_str TEXT;
  v_expected NUMERIC;
  v_old_actual NUMERIC;
  v_baseline NUMERIC;
  v_incremental_variance NUMERIC;
  v_total_variance NUMERIC;
  v_abs_variance NUMERIC;
BEGIN
  -- 1. Lock and retrieve the cost item
  SELECT * INTO r_item 
  FROM public.packing_order_cost_items 
  WHERE id = p_cost_item_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  -- 2. Lock and retrieve parent order
  SELECT * INTO r_order 
  FROM public.packing_orders 
  WHERE id = r_item.packing_order_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة التابع للبند غير موجود');
  END IF;

  v_order_num := COALESCE(r_order.order_number, r_order.id::text);

  -- 3. Calculate Variance
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
  v_trans_supplier_id := NULL;
  v_supp_str := r_item.supplier_id;
  IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
    IF r_item.currency_snapshot IS NOT NULL THEN
      v_supp_str := r_item.currency_snapshot->>'supplier_id';
    END IF;
  END IF;

  IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN
    BEGIN
      v_supplier_id := v_supp_str::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
    END;

    IF v_supplier_id IS NULL THEN
      BEGIN
        v_trans_supplier_id := v_supp_str::integer;
      EXCEPTION WHEN OTHERS THEN
        v_trans_supplier_id := NULL;
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
  ELSIF v_supplier_id IS NOT NULL THEN
    v_supp_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
  ELSIF v_trans_supplier_id IS NOT NULL THEN
    -- Transport: adjust against absorbed transport expense account
    SELECT id INTO v_supp_acc
    FROM public.accounts
    WHERE (code = '51311' OR account_code = '51311' OR name ILIKE '%مصاريف نقل%' OR name ILIKE '%نقل%')
      AND is_active = true
    ORDER BY CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END
    LIMIT 1;
    IF v_supp_acc IS NULL THEN v_supp_acc := public.resolve_gl_account('51311', v_company_id); END IF;
    IF v_supp_acc IS NULL THEN v_supp_acc := public.resolve_gl_account('5100', v_company_id); END IF;
  END IF;

  IF v_supp_acc IS NULL THEN
    v_supp_acc := public.resolve_gl_account('2000', v_company_id);
  END IF;

  -- 6. Accounting Adjustment (if incremental variance != 0)
  IF v_incremental_variance <> 0 THEN
    -- A. Update Supplier Balance & Sub-Ledger Entry for STANDARD suppliers ONLY
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
    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date,
      CASE 
        WHEN v_incremental_variance > 0 THEN 
          'قيد تسوية تكلفة فعلية (زيادة) بند ' || r_item.name || ' - أمر تعبئة ' || v_order_num
        ELSE 
          'قيد تسوية تكلفة فعلية (وفر) بند ' || r_item.name || ' - أمر تعبئة ' || v_order_num
      END,
      'posted', true, 'packing_cost_settlement', r_item.id::text, v_company_id,
      auth.uid(), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'cost_settle', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
      v_entry_num := 'STL-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    IF v_incremental_variance > 0 THEN
      -- Additional Cost: DR Finished Goods Inventory, CR Offset Account
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
        'فروق تسوية تكلفة فعلية بند ' || r_item.name, v_company_id
      );

      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_supp_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
        'تسوية فروق تكلفة بند ' || r_item.name || ' أمر تعبئة ' || v_order_num, v_company_id
      );
    ELSE
      -- Cost Savings: DR Offset Account, CR Finished Goods Inventory
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_supp_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
        'وفر تكلفة بند ' || r_item.name || ' أمر تعبئة ' || v_order_num, v_company_id
      );

      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
        'تخفيض تكلفة مخزون تام ناتج عن وفر بند ' || r_item.name, v_company_id
      );
    END IF;
  END IF;

  -- 7. Update the cost item itself
  UPDATE public.packing_order_cost_items
  SET cost_status = 'actual',
      actual_amount = p_actual_amount,
      variance_amount = v_total_variance,
      invoice_ref = COALESCE(p_invoice_ref, invoice_ref),
      reconciled_at = now(),
      reconciled_by = auth.uid(),
      base_amount = p_actual_amount
  WHERE id = p_cost_item_id;

  -- 8. Recalculate packing order other_cost_base & update notes
  PERFORM public.fn_recalculate_packing_order_costs(r_order.id);

  RETURN json_build_object(
    'success', true,
    'message', 'تمت تسوية بند التكلفة بنجاح',
    'cost_item_id', p_cost_item_id,
    'expected_amount', v_expected,
    'actual_amount', p_actual_amount,
    'variance_amount', v_total_variance,
    'incremental_variance', v_incremental_variance,
    'settlement_journal_entry_id', v_je_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_reconcile_packing_cost_item(bigint, numeric, text, text) TO authenticated, service_role, anon;

-- ── 5. Update rpc_add_transport_invoice to support NUMERIC truck counts ──
DROP FUNCTION IF EXISTS public.rpc_add_transport_invoice(
    integer, numeric, integer, integer, text, text, date, text, integer, text, text
);
DROP FUNCTION IF EXISTS public.rpc_add_transport_invoice(
    integer, numeric, numeric, numeric, text, text, date, text, integer, text, text
);

CREATE OR REPLACE FUNCTION public.rpc_add_transport_invoice(
    p_supplier_id        integer,
    p_amount             numeric,
    p_number_of_trucks   numeric DEFAULT 1,
    p_truck_count        numeric DEFAULT 1,
    p_route_from         text    DEFAULT NULL,
    p_route_to           text    DEFAULT NULL,
    p_date               date    DEFAULT NULL,
    p_description        text    DEFAULT NULL,
    p_expense_account_id integer DEFAULT NULL,
    p_reference_number   text    DEFAULT NULL,
    p_notes              text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date             date;
    v_truck_count      numeric;
    v_desc             text;
    v_supplier         RECORD;
    v_journal_id       bigint;
    v_entry_number     text;
    v_transaction_id   integer;
    v_expense_acct_id  bigint;
    v_supplier_acct_id bigint;
BEGIN
    v_date := COALESCE(p_date, (NOW() AT TIME ZONE 'Africa/Cairo')::date);
    v_truck_count := COALESCE(NULLIF(p_truck_count, 0), NULLIF(p_number_of_trucks, 0), 1.0);

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
    END IF;

    SELECT id, name, account_id, balance, truck_balance
    INTO v_supplier
    FROM public.transport_suppliers
    WHERE id = p_supplier_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'مورد النقل غير موجود');
    END IF;

    v_desc := COALESCE(p_description, 'فاتورة نقل - ' || v_supplier.name);
    IF p_route_from IS NOT NULL AND p_route_to IS NOT NULL THEN
        v_desc := v_desc || ' (' || p_route_from || ' → ' || p_route_to || ')';
    END IF;

    v_expense_acct_id := p_expense_account_id;
    IF v_expense_acct_id IS NULL THEN
        SELECT id INTO v_expense_acct_id
        FROM public.accounts
        WHERE (code = '51311' OR account_code = '51311'
               OR name ILIKE '%مصاريف نقل%' OR name ILIKE '%نقل%')
          AND is_active = true
        ORDER BY
            CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END
        LIMIT 1;
    END IF;

    v_supplier_acct_id := v_supplier.account_id;
    IF v_supplier_acct_id IS NULL THEN
        SELECT id INTO v_supplier_acct_id
        FROM public.accounts
        WHERE (code = '21311' OR account_code = '21311'
               OR name ILIKE '%موردي نقل%' OR name ILIKE '%دائنو نقل%')
          AND is_active = true
        ORDER BY id ASC
        LIMIT 1;
    END IF;

    IF v_expense_acct_id IS NOT NULL AND v_supplier_acct_id IS NOT NULL THEN
        v_entry_number := 'TI-' || to_char(v_date, 'YYYYMMDD') || '-' ||
                          lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, source_type, source_id
        ) VALUES (
            v_entry_number, v_date, v_desc, 'posted',
            'transport_invoice', 'transport_suppliers_' || p_supplier_id::text
        ) RETURNING id INTO v_journal_id;

        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_expense_acct_id, p_amount, 0,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );

        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_supplier_acct_id, 0, p_amount,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );
    END IF;

    INSERT INTO public.transport_transactions (
        supplier_id, type, amount, truck_count, description,
        notes, journal_entry_id, date, reference_id, route_from, route_to
    ) VALUES (
        p_supplier_id, 'invoice', p_amount, v_truck_count, v_desc,
        p_notes, v_journal_id, v_date, p_reference_number, p_route_from, p_route_to
    ) RETURNING id INTO v_transaction_id;

    UPDATE public.transport_suppliers
    SET balance = COALESCE(balance, 0) + p_amount,
        current_balance = COALESCE(current_balance, 0) + p_amount,
        truck_balance = COALESCE(truck_balance, 0) + v_truck_count,
        updated_at = NOW()
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number,
        'amount', p_amount,
        'truck_count', v_truck_count
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_add_transport_invoice(
    integer, numeric, numeric, numeric, text, text, date, text, integer, text, text
) TO authenticated, service_role, anon;

COMMIT;
