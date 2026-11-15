-- ============================================================================
-- Migration: 20261111000002_station_supplier_actual_cost_balance_only.sql
-- Purpose:
--   Decouple Variance (الوفر / الزيادة) and Unapproved Estimated Costs from
--   Station & Deduction Suppliers' Financial Statements, Journal Lines, and
--   Final Account Balances.
--
-- Accounting Guarantees:
--   1. Supplier financial liability (دائن) relies EXCLUSIVELY on Approved
--      Actual Costs (actual_amount) once settled.
--   2. Unsettled Stage-3 estimates (تقديري) remain cost_status = 'expected'
--      in pending_expected_balance and credit GL clearing account 21313
--      (Accrued Estimated Supplier Costs) WITHOUT creating supplier debt or
--      appearing on the supplier's statement.
--   3. Upon settlement (rpc_settle_packing_cost_variances / rpc_settle_packing_cost_item):
--      - Variance (actual - expected) and Variance % remain purely analytical on
--        packing_order_cost_items and adjust Finished Goods Inventory (12413) &
--        Export Shipment profitability.
--      - GL Journal Entry reverses 21313 (expected) + adjusts 12413 (variance)
--        and credits the Station Supplier account (21117 / leaf) with the
--        EXACT Approved Actual Cost (actual_amount) ONLY.
--      - Sub-ledger (ledger_entries) holds ONE clean credit row equal to
--        actual_amount ONLY (zero estimated row, zero variance debit/credit).
--   4. get_supplier_true_balances_by_currency() computes Station/Deduction
--      supplier obligations strictly from settled actual_amount records.
--   5. Historical data for existing Station/Deduction items is repaired cleanly.
-- ============================================================================

-- 1. Ensure Accrued Estimated Supplier Costs Clearing Account ('21313') exists
DO $$
DECLARE
  v_parent_id BIGINT;
  v_company_id UUID;
  v_path_ids TEXT;
  v_parent_level INT;
  v_parent_codes TEXT;
BEGIN
  SELECT id, company_id, path_ids, level, path_codes
  INTO v_parent_id, v_company_id, v_path_ids, v_parent_level, v_parent_codes
  FROM public.accounts
  WHERE account_code = '2131'
  LIMIT 1;

  IF v_parent_id IS NULL THEN
    SELECT id, company_id, path_ids, level, path_codes
    INTO v_parent_id, v_company_id, v_path_ids, v_parent_level, v_parent_codes
    FROM public.accounts
    WHERE account_code = '213'
    LIMIT 1;
  END IF;

  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '21313') THEN
    INSERT INTO public.accounts (
      account_code, name, account_name, parent_id, account_type, sort_order,
      company_id, level, path_ids, path_codes, allow_posting, is_leaf, is_active, normal_balance
    ) VALUES (
      '21313',
      'Accrued Estimated Supplier Costs',
      'مخصص تكاليف تقديرية معلقة التسوية',
      v_parent_id,
      'liability',
      21313,
      v_company_id,
      COALESCE(v_parent_level + 1, 5),
      CASE WHEN v_path_ids IS NOT NULL THEN v_path_ids || '/' ELSE NULL END,
      CASE WHEN v_parent_codes IS NOT NULL THEN v_parent_codes || '/21313' ELSE '2/21/213/2131/21313' END,
      true,
      true,
      true,
      'Credit'
    );
  END IF;
END $$;

-- 2. Helper to check whether a supplier/item is Station or Deduction (Dual-Cost)
CREATE OR REPLACE FUNCTION public.fn_is_dual_cost_supplier(
  p_supplier_id UUID,
  p_category TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_type TEXT;
  v_code TEXT;
BEGIN
  IF LOWER(COALESCE(p_category, '')) IN ('station', 'station_supplier', 'station_cost', 'deduction', 'deductions') THEN
    RETURN TRUE;
  END IF;

  IF p_supplier_id IS NOT NULL THEN
    SELECT LOWER(COALESCE(supplier_type, '')), COALESCE(code, supplier_code, '')
    INTO v_type, v_code
    FROM public.suppliers
    WHERE id = p_supplier_id;

    IF v_type IN ('station', 'deduction', 'deductions') THEN
      RETURN TRUE;
    END IF;

    IF v_code ~ '^(85|86|87|88|89|40|41|42|43|44)' THEN
      RETURN TRUE;
    END IF;
  END IF;

  RETURN FALSE;
END;
$$;

-- 3. Canonical rpc_confirm_packing_costs:
--    - Keeps Station, Deduction, and Admin items as 'expected' until settled.
--    - Routes unsettled Station/Deduction Stage-3 accruals to 21313 (NOT supplier 21117/ledger_entries).
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_costs(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_company_id UUID;

  v_tot_cost_items NUMERIC := 0;
  v_posted_cost_items NUMERIC := 0;
  v_stage3_amt NUMERIC := 0;

  v_finished_inv_acc INT;
  v_est_clearing_acc INT;
  v_credit_acc INT;
  v_supp_leaf_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  r_cost RECORD;
  r_prev_trans RECORD;
  r_prev_supp RECORD;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_supp_str TEXT;
  v_consumed_trucks NUMERIC;
  v_category_account_id BIGINT;
  v_is_transport BOOLEAN;
  v_is_station_or_deduction BOOLEAN;
  v_is_reconciled BOOLEAN;
  v_settlement_debited_clearing BOOLEAN;
  v_settlement_already_posted BOOLEAN;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status IN ('draft', 'pending', 'crops_confirmed') THEN
    RETURN json_build_object('success', false, 'error', 'يجب تأكيد مواد التعبئة أولاً قبل تأكيد بنود التكلفة');
  END IF;

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

  -- A. Revert previously recorded transport amounts & truck counts for idempotency
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

  -- B. Revert prior Stage-3 generic supplier ledger entries ONLY (preserve genuine settled cost_settlement rows)
  FOR r_prev_supp IN
    SELECT entity_id, SUM(CASE WHEN entry_type = 'credit' THEN COALESCE(amount, 0) ELSE -COALESCE(amount, 0) END) AS total_prev_amount
    FROM public.ledger_entries
    WHERE reference_id = p_packing_order_id
      AND reference_type IN ('packing_cost', 'packing_cost_item')
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
    AND reference_type IN ('packing_cost', 'packing_cost_item');

  -- 1. Idempotent Status Initialization:
  --    Keep Admin, Station, and Deduction cost items as 'expected' until genuinely settled!
  UPDATE public.packing_order_cost_items ci
  SET expected_amount = COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount),
      cost_status = CASE
        WHEN ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL THEN 'actual'
        WHEN ci.category = 'admin' OR ci.name ILIKE '%إدار%' OR ci.name ILIKE '%ادار%' THEN
          CASE WHEN ci.cost_status = 'settled' AND ci.actual_amount IS NOT NULL THEN 'actual' ELSE 'expected' END
        WHEN public.fn_is_dual_cost_supplier(
          COALESCE(
            CASE WHEN NULLIF(ci.supplier_id, '') ~ '^[0-9a-fA-F-]{36}$' THEN ci.supplier_id::uuid ELSE NULL END,
            CASE WHEN NULLIF(ci.currency_snapshot->>'supplier_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN (ci.currency_snapshot->>'supplier_id')::uuid ELSE NULL END
          ),
          ci.category
        ) THEN 'expected'
        ELSE 'actual'
      END,
      actual_amount = CASE
        WHEN ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL THEN COALESCE(ci.actual_amount, ci.base_amount)
        WHEN ci.category = 'admin' OR ci.name ILIKE '%إدار%' OR ci.name ILIKE '%ادار%' THEN
          CASE WHEN ci.cost_status = 'settled' THEN ci.actual_amount ELSE NULL END
        WHEN public.fn_is_dual_cost_supplier(
          COALESCE(
            CASE WHEN NULLIF(ci.supplier_id, '') ~ '^[0-9a-fA-F-]{36}$' THEN ci.supplier_id::uuid ELSE NULL END,
            CASE WHEN NULLIF(ci.currency_snapshot->>'supplier_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN (ci.currency_snapshot->>'supplier_id')::uuid ELSE NULL END
          ),
          ci.category
        ) THEN NULL
        ELSE COALESCE(ci.actual_amount, NULLIF(ci.expected_amount, 0), ci.base_amount)
      END,
      is_engineer_cost_settled = CASE
        WHEN ci.category IN ('engineer', 'engineer_expenses') THEN TRUE
        ELSE ci.is_engineer_cost_settled
      END,
      is_locked = CASE
        WHEN ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL THEN TRUE
        WHEN ci.category = 'admin' OR ci.name ILIKE '%إدار%' OR ci.name ILIKE '%ادار%' THEN FALSE
        WHEN public.fn_is_dual_cost_supplier(
          COALESCE(
            CASE WHEN NULLIF(ci.supplier_id, '') ~ '^[0-9a-fA-F-]{36}$' THEN ci.supplier_id::uuid ELSE NULL END,
            CASE WHEN NULLIF(ci.currency_snapshot->>'supplier_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN (ci.currency_snapshot->>'supplier_id')::uuid ELSE NULL END
          ),
          ci.category
        ) THEN FALSE
        ELSE TRUE
      END,
      locked_at = CASE
        WHEN ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL THEN COALESCE(ci.locked_at, now())
        WHEN ci.category = 'admin' OR ci.name ILIKE '%إدار%' OR ci.name ILIKE '%ادار%' THEN NULL
        WHEN public.fn_is_dual_cost_supplier(
          COALESCE(
            CASE WHEN NULLIF(ci.supplier_id, '') ~ '^[0-9a-fA-F-]{36}$' THEN ci.supplier_id::uuid ELSE NULL END,
            CASE WHEN NULLIF(ci.currency_snapshot->>'supplier_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN (ci.currency_snapshot->>'supplier_id')::uuid ELSE NULL END
          ),
          ci.category
        ) THEN NULL
        ELSE COALESCE(ci.locked_at, now())
      END
  WHERE ci.packing_order_id = p_packing_order_id
    AND ci.deleted_at IS NULL
    AND ci.base_amount > 0;

  -- Resolve Company & GL Accounts
  SELECT COALESCE(v_order.company_id, a.company_id) INTO v_company_id
  FROM public.accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;

  v_finished_inv_acc := COALESCE(
    public.resolve_gl_account('12413', v_company_id),
    public.resolve_gl_account('1241', v_company_id),
    public.resolve_gl_account('1031', v_company_id)
  );
  v_est_clearing_acc := COALESCE(
    public.resolve_gl_account('21313', v_company_id),
    public.resolve_gl_account('21311', v_company_id),
    public.resolve_gl_account('9124', v_company_id)
  );

  -- 2. Calculate Total Cost Items requiring Stage-3 GL posting
  v_tot_cost_items := 0;
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id
      AND deleted_at IS NULL
      AND COALESCE(base_amount, 0) > 0
  LOOP
    v_supplier_id := NULL;
    v_supp_str := COALESCE(NULLIF(r_cost.currency_snapshot->>'supplier_id', ''), NULLIF(r_cost.supplier_id, ''));
    IF v_supp_str IS NOT NULL AND v_supp_str ~ '^[0-9a-fA-F-]{36}$' THEN
      v_supplier_id := v_supp_str::uuid;
    END IF;

    v_is_station_or_deduction := public.fn_is_dual_cost_supplier(v_supplier_id, r_cost.category);
    v_is_reconciled := (r_cost.reconciled_at IS NOT NULL OR r_cost.variance_journal_entry_id IS NOT NULL);

    IF v_is_station_or_deduction AND v_is_reconciled AND r_cost.variance_journal_entry_id IS NOT NULL THEN
      SELECT EXISTS (
        SELECT 1 FROM public.account_ledger_entries ale
        WHERE ale.journal_entry_id = r_cost.variance_journal_entry_id
          AND ale.account_id = v_est_clearing_acc
          AND ale.debit > 0
      ) INTO v_settlement_debited_clearing;

      SELECT EXISTS (
        SELECT 1 FROM public.account_ledger_entries ale
        WHERE ale.journal_entry_id = r_cost.variance_journal_entry_id
          AND ale.entity_type = 'supplier'
          AND ale.credit > 0
      ) INTO v_settlement_already_posted;

      IF v_settlement_debited_clearing THEN
        v_stage3_amt := COALESCE(NULLIF(r_cost.expected_amount, 0), r_cost.base_amount);
      ELSIF v_settlement_already_posted THEN
        v_stage3_amt := 0; -- Already debited 12413 and credited supplier directly during settlement
      ELSE
        v_stage3_amt := COALESCE(r_cost.base_amount, 0);
      END IF;
    ELSE
      v_stage3_amt := COALESCE(r_cost.base_amount, 0);
    END IF;

    v_tot_cost_items := v_tot_cost_items + v_stage3_amt;
  END LOOP;

  IF v_tot_cost_items = 0 AND NOT EXISTS (
    SELECT 1 FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND deleted_at IS NULL AND COALESCE(base_amount, 0) > 0
  ) THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 3. Create / Refresh Stage-3 Costs Confirmation Journal Entry
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

    -- DR Finished Goods Inventory
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'تكاليف ومصروفات أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_cost_items;

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

      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      END IF;
      IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
        v_supp_str := r_cost.supplier_id;
      END IF;

      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        IF v_supp_str ~ '^[0-9a-fA-F-]{36}$' THEN
          v_supplier_id := v_supp_str::uuid;
        ELSIF v_supp_str ~ '^[0-9]+$' THEN
          v_trans_supplier_id := v_supp_str::integer;
        END IF;
      END IF;

      IF v_trans_supplier_id IS NULL THEN
        IF r_cost.transport_supplier_id IS NOT NULL THEN
          v_trans_supplier_id := r_cost.transport_supplier_id;
        ELSIF r_cost.currency_snapshot IS NOT NULL AND (r_cost.currency_snapshot->>'transport_supplier_id') ~ '^[0-9]+$' THEN
          v_trans_supplier_id := (r_cost.currency_snapshot->>'transport_supplier_id')::integer;
        END IF;
      END IF;

      v_is_station_or_deduction := public.fn_is_dual_cost_supplier(v_supplier_id, r_cost.category);

      v_is_transport := (NOT v_is_station_or_deduction) AND (
        v_trans_supplier_id IS NOT NULL
        OR r_cost.category = 'logistics'
        OR (r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot->>'supplier_type' = 'transport')
        OR r_cost.name ILIKE '%نقل%'
        OR r_cost.name ILIKE '%شحن%'
        OR r_cost.name ILIKE '%نولون%'
        OR (v_supplier_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.suppliers
              WHERE id = v_supplier_id AND (supplier_type = 'transport' OR COALESCE(code, supplier_code, '') LIKE '6%')
           ))
      );

      -- CASE A: Transport Supplier
      IF v_is_transport THEN
        IF v_trans_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_credit_acc FROM public.transport_suppliers WHERE id = v_trans_supplier_id;
        END IF;
        IF v_credit_acc IS NULL AND v_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_credit_acc FROM public.suppliers WHERE id = v_supplier_id;
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('21111', v_company_id);
        END IF;
        IF v_credit_acc = (SELECT id FROM public.accounts WHERE account_code = '2112' LIMIT 1) THEN
          v_credit_acc := COALESCE(public.resolve_gl_account('21111', v_company_id), v_credit_acc);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2111', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'تكلفة ونقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id,
          CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE 'transport_supplier' END,
          COALESCE(v_supplier_id::text, v_trans_supplier_id::text)
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        IF v_trans_supplier_id IS NOT NULL THEN
          v_consumed_trucks := COALESCE(
            NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
            NULLIF(r_cost.truck_count, 0),
            1
          );
          UPDATE public.transport_suppliers
          SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks, updated_at = now()
          WHERE id = v_trans_supplier_id;

          INSERT INTO public.transport_transactions (
            supplier_id, type, amount, currency, reference_id,
            description, truck_count, notes, journal_entry_id, date, created_at
          ) VALUES (
            v_trans_supplier_id, 'packing_consumption', 0, 'EGP', p_packing_order_id::text,
            'تكلفة ونقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل') || ' (' || v_consumed_trucks::text || ' نقلة)',
            v_consumed_trucks,
            'استحقاق مالي ' || r_cost.base_amount::text || ' ج.م وسحب ' || v_consumed_trucks::text || ' نقلة لأمر تعبئة ' || v_order_num,
            v_je_id, (COALESCE(v_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date, now()
          );
        ELSIF v_supplier_id IS NOT NULL THEN
          INSERT INTO public.ledger_entries (
            entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
          ) VALUES (
            v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
            'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
            'بند تكلفة نقل: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
          );
          UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
        END IF;

      -- CASE B1: Station / Deduction Supplier (Accrued Estimates -> 21313 ONLY, zero premature supplier liability)
      ELSIF v_is_station_or_deduction AND v_supplier_id IS NOT NULL THEN
        v_is_reconciled := (r_cost.reconciled_at IS NOT NULL OR r_cost.variance_journal_entry_id IS NOT NULL);
        v_stage3_amt := r_cost.base_amount;

        IF v_is_reconciled AND r_cost.variance_journal_entry_id IS NOT NULL THEN
          SELECT EXISTS (
            SELECT 1 FROM public.account_ledger_entries ale
            WHERE ale.journal_entry_id = r_cost.variance_journal_entry_id
              AND ale.account_id = v_est_clearing_acc
              AND ale.debit > 0
          ) INTO v_settlement_debited_clearing;

          SELECT EXISTS (
            SELECT 1 FROM public.account_ledger_entries ale
            WHERE ale.journal_entry_id = r_cost.variance_journal_entry_id
              AND ale.entity_type = 'supplier'
              AND ale.credit > 0
          ) INTO v_settlement_already_posted;

          IF v_settlement_debited_clearing THEN
            v_stage3_amt := COALESCE(NULLIF(r_cost.expected_amount, 0), r_cost.base_amount);
          ELSIF v_settlement_already_posted THEN
            v_stage3_amt := 0;
          END IF;
        END IF;

        IF v_stage3_amt > 0 THEN
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_est_clearing_acc, 0, v_stage3_amt, 'EGP', v_stage3_amt,
            'مخصص تكاليف تقديرية (معلّقة التسوية) - ' || COALESCE(r_cost.name, 'تكلفة محطة') || ' (أمر ' || v_order_num || ')',
            v_company_id
          );
          v_sum_credit := v_sum_credit + v_stage3_amt;
          v_posted_cost_items := v_posted_cost_items + v_stage3_amt;
        END IF;

      -- CASE B2: Regular Direct Supplier (General, Packaging)
      ELSIF v_supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
        v_credit_acc := COALESCE(
          v_supp_leaf_acc,
          public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id),
          public.resolve_gl_account('21113', v_company_id),
          public.resolve_gl_account('2111', v_company_id)
        );

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

        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
          'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
          'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
        );
        UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;

      -- CASE C: Admin / Category-Mapped / Unassigned Cost
      ELSE
        IF r_cost.report_category_id IS NOT NULL THEN
          SELECT account_id INTO v_category_account_id FROM public.cost_report_categories WHERE id = r_cost.report_category_id;
        END IF;
        IF v_category_account_id IS NULL THEN
          SELECT account_id INTO v_category_account_id FROM public.cost_report_categories WHERE name = r_cost.name LIMIT 1;
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

    IF v_tot_cost_items > v_posted_cost_items THEN
      v_credit_acc := COALESCE(
        public.resolve_gl_account('2111', v_company_id),
        public.resolve_gl_account('21113', v_company_id)
      );
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, (v_tot_cost_items - v_posted_cost_items), 'EGP', (v_tot_cost_items - v_posted_cost_items),
        'مصروفات إضافية أمر تعبئة ' || v_order_num, v_company_id
      );
      v_sum_credit := v_sum_credit + (v_tot_cost_items - v_posted_cost_items);
    END IF;

    IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
      RAISE EXCEPTION 'فشل تأكيد قيد بنود التكلفة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
    END IF;

    IF v_sum_debit != v_sum_credit THEN
      UPDATE public.account_ledger_entries
      SET debit = debit + (v_sum_credit - v_sum_debit),
          amount_in_base_currency = amount_in_base_currency + (v_sum_credit - v_sum_debit)
      WHERE journal_entry_id = v_je_id AND account_id = v_finished_inv_acc AND debit > 0;
    END IF;
  END IF;

  v_notes := jsonb_set(v_notes, '{workflow_stages,costs}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items
  ), true);

  UPDATE public.packing_orders
  SET status = CASE WHEN status IN ('final_approved', 'completed') THEN status ELSE 'costs_confirmed' END,
      costs_confirmed_at = COALESCE(costs_confirmed_at, now()),
      costs_journal_entry_id = COALESCE(v_je_id, costs_journal_entry_id),
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  BEGIN
    UPDATE public.packing_orders SET is_costs_confirmed = true WHERE id = p_packing_order_id;
  EXCEPTION WHEN undefined_column THEN NULL;
  END;

  RETURN json_build_object(
    'success', true,
    'status', 'costs_confirmed',
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_costs(bigint) TO authenticated, service_role, anon;

-- 4. Canonical rpc_settle_packing_cost_variances:
--    For Station & Deduction suppliers, posts APPROVED ACTUAL COST ONLY to supplier GL & ledger_entries.
--    Variance remains strictly analytical on cost item + inventory/profitability side.
CREATE OR REPLACE FUNCTION public.rpc_settle_packing_cost_variances(
  p_packing_order_id bigint,
  p_settlements jsonb,
  p_general_notes text DEFAULT NULL,
  p_settled_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r_order RECORD;
  r_item RECORD;
  r_shipment RECORD;
  v_company_id UUID;
  v_order_num TEXT;
  v_finished_inv_acc INT;
  v_est_clearing_acc INT;
  v_engineer_exp_acc INT;
  v_je_id BIGINT;
  v_entry_num TEXT;

  v_item_elem JSONB;
  v_cost_item_id BIGINT;
  v_actual_amt NUMERIC;
  v_actual_qty NUMERIC;
  v_unit_price NUMERIC;
  v_actual_dt TIMESTAMPTZ;
  v_inv_ref TEXT;
  v_item_notes TEXT;

  v_expected NUMERIC;
  v_old_actual NUMERIC;
  v_baseline NUMERIC;
  v_incremental_variance NUMERIC;
  v_total_variance NUMERIC;
  v_abs_variance NUMERIC;
  v_prev_ledger_net NUMERIC;
  v_diff_actual NUMERIC;

  v_is_engineer BOOLEAN;
  v_is_admin BOOLEAN;
  v_is_transport BOOLEAN;
  v_is_station_or_deduction BOOLEAN;
  v_was_settled_on_supplier BOOLEAN;
  v_has_stage3_clearing BOOLEAN;

  v_custody_id INT;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_supp_type TEXT;
  v_target_acc INT;
  v_debit_acc INT;
  v_treasury_acct INT;

  v_amount_to_deduct NUMERIC;
  v_cur_bal NUMERIC;
  v_new_bal NUMERIC;
  v_note_text TEXT;
  v_supplier_ledger_desc TEXT;
  v_existing_tx_id BIGINT;

  v_cartons_count NUMERIC := 0;
  v_new_other_cost_base NUMERIC := 0;
  v_new_total_cost NUMERIC := 0;
  v_new_carton_cost NUMERIC := 0;
  v_new_shipment_carton_cost NUMERIC := 0;
  v_new_shipment_landed NUMERIC := 0;
BEGIN
  IF p_settlements IS NULL OR jsonb_typeof(p_settlements) <> 'array' OR jsonb_array_length(p_settlements) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'قائمة تسوية البنود فارغة');
  END IF;

  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  v_company_id := r_order.company_id;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;
  v_order_num := COALESCE(r_order.order_number, r_order.id::text);

  v_finished_inv_acc := COALESCE(
    public.resolve_gl_account('12413', v_company_id),
    public.resolve_gl_account('1241', v_company_id),
    public.resolve_gl_account('124', v_company_id),
    public.resolve_gl_account('1031', v_company_id)
  );
  v_est_clearing_acc := COALESCE(
    public.resolve_gl_account('21313', v_company_id),
    public.resolve_gl_account('21311', v_company_id),
    public.resolve_gl_account('9124', v_company_id)
  );
  v_engineer_exp_acc := COALESCE(
    public.resolve_gl_account('31251', v_company_id),
    public.resolve_gl_account('3125', v_company_id)
  );

  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status, is_auto_generated,
    source_type, source_id, company_id, created_by
  ) VALUES (
    'PENDING',
    (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date,
    COALESCE(NULLIF(p_general_notes, ''), 'تسوية تكاليف أمر التعبئة #' || v_order_num),
    'posted', true, 'packing_cost_settlement', p_packing_order_id::text,
    v_company_id, COALESCE(p_settled_by, auth.uid())
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'settlement', NULL, NULL);
  IF v_entry_num IS NULL OR v_entry_num = '' THEN
    v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
  END IF;
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  FOR v_item_elem IN SELECT * FROM jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    v_actual_qty := (v_item_elem->>'actual_quantity')::numeric;
    v_unit_price := (v_item_elem->>'unit_price')::numeric;
    BEGIN
      v_actual_dt := (v_item_elem->>'actual_date_time')::timestamptz;
    EXCEPTION WHEN OTHERS THEN
      v_actual_dt := NULL;
    END;
    v_inv_ref := v_item_elem->>'invoice_ref';
    v_item_notes := COALESCE(NULLIF(v_item_elem->>'detailed_notes', ''), NULLIF(v_item_elem->>'notes', ''));

    IF v_cost_item_id IS NULL OR v_actual_amt IS NULL THEN
      CONTINUE;
    END IF;

    SELECT * INTO r_item FROM public.packing_order_cost_items
    WHERE id = v_cost_item_id AND packing_order_id = p_packing_order_id
    FOR UPDATE;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_expected := COALESCE(NULLIF(r_item.expected_amount, 0), r_item.base_amount, 0);
    v_old_actual := r_item.actual_amount;
    v_total_variance := ROUND(v_actual_amt - v_expected, 2);

    -- Resolve supplier UUID first so category & type classification is exact
    v_supplier_id := NULL;
    v_supp_str := COALESCE(NULLIF(r_item.supplier_id, ''), r_item.currency_snapshot->>'supplier_id');
    IF v_supp_str IS NOT NULL AND v_supp_str ~ '^[0-9a-fA-F-]{36}$' THEN
      v_supplier_id := v_supp_str::uuid;
    END IF;

    v_supp_type := NULL;
    IF v_supplier_id IS NOT NULL THEN
      SELECT LOWER(COALESCE(supplier_type, '')) INTO v_supp_type FROM public.suppliers WHERE id = v_supplier_id;
    END IF;

    v_is_engineer := (r_item.category IN ('engineer', 'engineer_expenses') OR r_item.custody_id IS NOT NULL OR (r_item.category IS NULL AND r_item.name ILIKE '%مهندس%'));
    v_is_admin := (NOT v_is_engineer) AND (r_item.category = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%عمومية%');
    v_is_station_or_deduction := (NOT v_is_engineer AND NOT v_is_admin) AND public.fn_is_dual_cost_supplier(v_supplier_id, r_item.category);
    v_is_transport := (NOT v_is_engineer AND NOT v_is_admin AND NOT v_is_station_or_deduction) AND (
      r_item.category = 'logistics' OR r_item.transport_supplier_id IS NOT NULL OR v_supp_type = 'transport'
      OR r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%شحن%'
    );

    -- Detailed descriptive label (preserving full notes for statements)
    v_note_text := r_item.name || ' (أمر ' || v_order_num || ')';
    IF v_inv_ref IS NOT NULL AND v_inv_ref <> '' THEN
      v_note_text := v_note_text || ' - مستند: ' || v_inv_ref;
    END IF;
    IF v_item_notes IS NOT NULL AND v_item_notes <> '' THEN
      v_note_text := v_note_text || ' - ' || v_item_notes;
    ELSIF p_general_notes IS NOT NULL AND p_general_notes <> '' THEN
      v_note_text := v_note_text || ' - ' || p_general_notes;
    END IF;

    v_existing_tx_id := NULL;
    v_custody_id := NULL;
    v_target_acc := NULL;
    v_debit_acc := v_finished_inv_acc;

    -- Case A: Engineer Expenses (Petty Cash Custody)
    IF v_is_engineer THEN
      v_baseline := COALESCE(v_old_actual, v_expected);
      v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);

      v_custody_id := COALESCE(
        (v_item_elem->>'custody_id')::integer,
        r_item.custody_id,
        (r_item.currency_snapshot->>'custody_id')::integer
      );
      IF v_custody_id IS NULL AND r_item.engineer_name IS NOT NULL THEN
        SELECT id INTO v_custody_id FROM public.treasuries WHERE name ILIKE '%' || r_item.engineer_name || '%' LIMIT 1;
      END IF;
      IF v_custody_id IS NULL THEN
        SELECT id INTO v_custody_id FROM public.treasuries WHERE type IN ('main', 'employee', 'custody') LIMIT 1;
      END IF;

      v_treasury_acct := COALESCE(
        public.resolve_treasury_account(v_custody_id, 'EGP', v_company_id),
        (SELECT account_id FROM public.treasuries WHERE id = v_custody_id),
        public.resolve_gl_account('12211', v_company_id)
      );
      v_debit_acc := COALESCE(
        (v_item_elem->>'expense_account_id')::integer,
        r_item.expense_account_id::integer,
        v_engineer_exp_acc
      );

      IF r_item.is_engineer_cost_settled AND r_item.treasury_transaction_id IS NOT NULL THEN
        v_amount_to_deduct := v_incremental_variance;
      ELSE
        v_amount_to_deduct := v_actual_amt;
      END IF;

      SELECT balance INTO v_cur_bal FROM public.treasuries WHERE id = v_custody_id FOR UPDATE;
      v_new_bal := COALESCE(v_cur_bal, 0) - v_amount_to_deduct;
      UPDATE public.treasuries SET balance = v_new_bal, updated_at = now() WHERE id = v_custody_id;

      v_note_text := 'تسوية مصاريف مهندسين وإشراف - ' || v_note_text;

      INSERT INTO public.treasury_transactions (
        treasury_id, transaction_type, amount, balance_after,
        reference_type, reference_id, description, transaction_date,
        created_at, updated_at
      ) VALUES (
        v_custody_id,
        CASE WHEN v_amount_to_deduct >= 0 THEN 'expense' ELSE 'income' END,
        ABS(v_amount_to_deduct), v_new_bal,
        'packing_order_cost_item', v_cost_item_id, v_note_text,
        COALESCE(v_actual_dt, now()), now(), now()
      ) RETURNING id INTO v_existing_tx_id;

      IF v_amount_to_deduct <> 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_debit_acc,
          CASE WHEN v_amount_to_deduct > 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          CASE WHEN v_amount_to_deduct < 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          'EGP', ABS(v_amount_to_deduct), v_note_text, v_company_id
        );
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_treasury_acct,
          CASE WHEN v_amount_to_deduct < 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          CASE WHEN v_amount_to_deduct > 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          'EGP', ABS(v_amount_to_deduct), v_note_text, v_company_id, 'treasury', v_custody_id::text
        );
      END IF;

    -- Case B: Admin / Overhead Expenses
    ELSIF v_is_admin THEN
      v_baseline := COALESCE(v_old_actual, v_expected);
      v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);
      v_abs_variance := ABS(v_incremental_variance);

      v_debit_acc := COALESCE(
        (v_item_elem->>'expense_account_id')::integer,
        r_item.expense_account_id::integer,
        public.resolve_gl_account('31331', v_company_id),
        public.resolve_gl_account('313', v_company_id)
      );

      IF v_incremental_variance <> 0 AND v_debit_acc IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_finished_inv_acc,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مصاريف إدارية (مخزون إنتاج تام) - ' || v_note_text, v_company_id
        );
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_debit_acc,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مصاريف إدارية - ' || v_note_text, v_company_id
        );
      END IF;

    -- Case C1: Station & Deduction Suppliers -> APPROVED ACTUAL COST ONLY!
    ELSIF v_is_station_or_deduction AND v_supplier_id IS NOT NULL THEN
      v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
      IF v_target_acc IS NULL THEN
        v_target_acc := CASE
          WHEN v_supp_type IN ('deduction', 'deductions') THEN public.resolve_gl_account('21118', v_company_id)
          ELSE public.resolve_gl_account('21117', v_company_id)
        END;
      END IF;
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

      v_supplier_ledger_desc := 'اعتماد تكلفة فعلية بند: ' || v_note_text;

      -- Clean up any prior estimated ('packing_cost') or variance ('cost_settlement') sub-ledger entries for this cost item
      SELECT COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN COALESCE(amount, 0) ELSE -COALESCE(amount, 0) END), 0)
      INTO v_prev_ledger_net
      FROM public.ledger_entries
      WHERE entity_id = v_supplier_id::text
        AND entity_type = 'supplier'
        AND reference_type IN ('packing_cost', 'packing_cost_item', 'packing_order_costs', 'cost_settlement', 'packing_cost_settlement')
        AND (
          currency_snapshot->>'cost_item_id' = v_cost_item_id::text
          OR (reference_id = p_packing_order_id AND (description LIKE '%' || r_item.name || '%' OR reference_text = r_item.name))
        );

      DELETE FROM public.ledger_entries
      WHERE entity_id = v_supplier_id::text
        AND entity_type = 'supplier'
        AND reference_type IN ('packing_cost', 'packing_cost_item', 'packing_order_costs', 'cost_settlement', 'packing_cost_settlement')
        AND (
          currency_snapshot->>'cost_item_id' = v_cost_item_id::text
          OR (reference_id = p_packing_order_id AND (description LIKE '%' || r_item.name || '%' OR reference_text = r_item.name))
        );

      -- Insert EXACTLY ONE clean credit entry equal to Approved Actual Cost
      IF v_actual_amt > 0 THEN
        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type,
          reference_id, reference_type, reference_text, description, currency_snapshot, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', v_actual_amt, 'EGP', 'credit',
          p_packing_order_id, 'cost_settlement', COALESCE(NULLIF(v_inv_ref, ''), r_item.name),
          v_supplier_ledger_desc,
          jsonb_build_object(
            'cost_item_id', v_cost_item_id,
            'packing_order_id', p_packing_order_id,
            'expected_amount', v_expected,
            'actual_amount', v_actual_amt,
            'variance_amount', v_total_variance
          ),
          COALESCE(v_actual_dt, r_item.actual_date_time, now())
        );
      END IF;

      UPDATE public.suppliers
      SET outstanding_balance = COALESCE(outstanding_balance, 0) + (v_actual_amt - COALESCE(v_prev_ledger_net, 0))
      WHERE id = v_supplier_id;

      -- Check if item already had a clean supplier settlement posted previously
      v_was_settled_on_supplier := (
        r_item.reconciled_at IS NOT NULL
        AND v_old_actual IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.account_ledger_entries ale
          WHERE ale.journal_entry_id = r_item.variance_journal_entry_id
            AND ale.entity_id = v_supplier_id::text
            AND ale.credit > 0
        )
      );

      IF NOT v_was_settled_on_supplier THEN
        -- Check whether Stage-3 credited Estimated Clearing 21313 for this order
        v_has_stage3_clearing := (
          r_order.costs_journal_entry_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM public.account_ledger_entries ale
            WHERE ale.journal_entry_id = r_order.costs_journal_entry_id
              AND ale.account_id = v_est_clearing_acc
              AND ale.credit > 0
          )
        );

        IF v_has_stage3_clearing THEN
          -- Clear expected accrual (21313) & post analytical variance strictly to Finished Goods Inventory (12413)
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_est_clearing_acc, v_expected, 0, 'EGP', v_expected,
            'إقفال مخصص تكلفة تقديرية عند التسوية - ' || r_item.name || ' (أمر ' || v_order_num || ')',
            v_company_id
          );

          IF v_total_variance <> 0 THEN
            INSERT INTO public.account_ledger_entries (
              journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
              v_je_id, v_finished_inv_acc,
              CASE WHEN v_total_variance > 0 THEN ABS(v_total_variance) ELSE 0 END,
              CASE WHEN v_total_variance < 0 THEN ABS(v_total_variance) ELSE 0 END,
              'EGP', ABS(v_total_variance),
              'تعديل تكلفة المخزون بالفرق عن التقديري - ' || r_item.name || ' (أمر ' || v_order_num || ')',
              v_company_id
            );
          END IF;

          IF v_actual_amt > 0 THEN
            INSERT INTO public.account_ledger_entries (
              journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
              entity_type, entity_id
            ) VALUES (
              v_je_id, v_target_acc, 0, v_actual_amt, 'EGP', v_actual_amt,
              v_supplier_ledger_desc, v_company_id, 'supplier', v_supplier_id::text
            );
          END IF;
        ELSE
          -- Direct settlement without Stage-3 21313 clearing: DR Inventory / CR Supplier for exact actual_amount
          IF v_actual_amt > 0 THEN
            INSERT INTO public.account_ledger_entries (
              journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
              v_je_id, v_finished_inv_acc, v_actual_amt, 0, 'EGP', v_actual_amt,
              'تكلفة مورد محطة فعلية - ' || v_note_text, v_company_id
            );
            INSERT INTO public.account_ledger_entries (
              journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
              entity_type, entity_id
            ) VALUES (
              v_je_id, v_target_acc, 0, v_actual_amt, 'EGP', v_actual_amt,
              v_supplier_ledger_desc, v_company_id, 'supplier', v_supplier_id::text
            );
          END IF;
        END IF;
      ELSE
        -- Amending an already-settled actual invoice: adjust strictly by (new_actual - old_actual)
        v_diff_actual := ROUND(v_actual_amt - COALESCE(v_old_actual, 0), 2);
        IF v_diff_actual <> 0 THEN
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_finished_inv_acc,
            CASE WHEN v_diff_actual > 0 THEN ABS(v_diff_actual) ELSE 0 END,
            CASE WHEN v_diff_actual < 0 THEN ABS(v_diff_actual) ELSE 0 END,
            'EGP', ABS(v_diff_actual),
            'تعديل قيمة فاتورة فعلية (مخزون) - ' || v_note_text, v_company_id
          );
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
            entity_type, entity_id
          ) VALUES (
            v_je_id, v_target_acc,
            CASE WHEN v_diff_actual < 0 THEN ABS(v_diff_actual) ELSE 0 END,
            CASE WHEN v_diff_actual > 0 THEN ABS(v_diff_actual) ELSE 0 END,
            'EGP', ABS(v_diff_actual),
            'تعديل اعتماد تكلفة فعلية - ' || v_note_text, v_company_id, 'supplier', v_supplier_id::text
          );
        END IF;
      END IF;

    -- Case C2: Transport / Non-Dual-Cost Suppliers
    ELSE
      v_baseline := COALESCE(v_old_actual, v_expected);
      v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);
      v_abs_variance := ABS(v_incremental_variance);

      IF v_supplier_id IS NOT NULL THEN
        IF v_is_transport THEN
          SELECT COALESCE(account_id, gl_account_id) INTO v_target_acc FROM public.transport_suppliers WHERE id = v_supplier_id;
        END IF;
        IF v_target_acc IS NULL THEN
          v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
        END IF;
      END IF;
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

      IF v_incremental_variance <> 0 AND v_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_incremental_variance WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type,
          reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', v_abs_variance, 'EGP',
          CASE WHEN v_incremental_variance > 0 THEN 'credit' ELSE 'debit' END,
          p_packing_order_id, 'cost_settlement', COALESCE(NULLIF(v_inv_ref, ''), r_item.name),
          'تسوية تكلفة فعلية بند: ' || v_note_text,
          COALESCE(v_actual_dt, now())
        );

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_finished_inv_acc,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance, 'تسوية تكلفة مورد - ' || v_note_text, v_company_id
        );
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_target_acc,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance, 'تسوية تكلفة مورد - ' || v_note_text, v_company_id, 'supplier', v_supplier_id::text
        );
      END IF;
    END IF;

    -- Update cost item: preserve expected_amount, record actual_amount & analytical variance
    UPDATE public.packing_order_cost_items
    SET expected_amount = v_expected,
        actual_amount = v_actual_amt,
        base_amount = v_actual_amt,
        original_amount = v_actual_amt,
        actual_quantity = COALESCE(v_actual_qty, actual_quantity, 1),
        actual_unit_price = COALESCE(v_unit_price, actual_unit_price, CASE WHEN COALESCE(v_actual_qty, 1) > 0 THEN v_actual_amt / COALESCE(v_actual_qty, 1) ELSE v_actual_amt END),
        actual_date_time = COALESCE(v_actual_dt, actual_date_time, now()),
        variance_amount = v_total_variance,
        cost_status = 'actual',
        is_locked = TRUE,
        locked_at = COALESCE(locked_at, now()),
        is_engineer_cost_settled = TRUE,
        treasury_transaction_id = COALESCE(v_existing_tx_id, treasury_transaction_id),
        custody_id = COALESCE(v_custody_id, custody_id),
        invoice_ref = COALESCE(NULLIF(v_inv_ref, ''), invoice_ref),
        settlement_notes = COALESCE(NULLIF(v_item_notes, ''), settlement_notes),
        detailed_notes = COALESCE(NULLIF(v_item_notes, ''), settlement_notes, detailed_notes),
        variance_journal_entry_id = COALESCE(v_je_id, variance_journal_entry_id),
        reconciled_at = now(),
        reconciled_by = COALESCE(p_settled_by, auth.uid())
    WHERE id = v_cost_item_id;
  END LOOP;

  -- Clean up empty Journal Entry if no GL lines were inserted
  IF NOT EXISTS (SELECT 1 FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id) THEN
    DELETE FROM public.journal_entries WHERE id = v_je_id;
    v_je_id := NULL;
  END IF;

  -- Recalculate packing order carton costs safely using real schema columns
  SELECT COALESCE(SUM(carton_count), 0) INTO v_cartons_count
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;
  IF COALESCE(v_cartons_count, 0) <= 0 THEN
    v_cartons_count := COALESCE(r_order.carton_count, 0);
  END IF;

  SELECT COALESCE(SUM(COALESCE(actual_amount, NULLIF(expected_amount, 0), base_amount, 0)), 0)
  INTO v_new_other_cost_base
  FROM public.packing_order_cost_items
  WHERE packing_order_id = p_packing_order_id AND deleted_at IS NULL;

  v_new_total_cost := COALESCE(r_order.fruit_cost_base, 0) + COALESCE(r_order.actual_material_cost, 0) + v_new_other_cost_base;
  v_new_carton_cost := CASE WHEN v_cartons_count > 0 THEN ROUND(v_new_total_cost / v_cartons_count, 4) ELSE COALESCE(r_order.packing_cost_per_carton, 0) END;

  UPDATE public.packing_orders
  SET other_cost_base = v_new_other_cost_base,
      total_packing_cost = v_new_total_cost,
      packing_cost_per_carton = v_new_carton_cost,
      is_engineer_cost_settled = TRUE,
      updated_at = now()
  WHERE id = p_packing_order_id;

  -- Update Linked Export Shipments profitability using actual carton cost
  FOR r_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.export_shipment_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
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

    SELECT COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0)
    INTO v_new_shipment_carton_cost
    FROM public.export_shipment_items esi
    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;

    SELECT COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +
           COALESCE((SELECT ROUND(SUM(sci.total_price), 2) FROM public.shipment_cost_items sci WHERE sci.shipment_id::text = r_shipment.shipment_id::text AND sci.category <> 'packing'), 0)
    INTO v_new_shipment_landed
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
    'message', 'تمت تسوية التكاليف واعتماد المبالغ الفعلية بنجاح',
    'journal_entry_id', v_je_id,
    'new_other_costs', v_new_other_cost_base,
    'new_carton_cost', v_new_carton_cost
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_variances(BIGINT, JSONB, TEXT, UUID) TO authenticated, service_role, anon;

-- 5. Canonical rpc_settle_packing_cost_item: delegates cleanly through the same unified batch settlement engine
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
  v_res JSONB;
BEGIN
  IF p_actual_amount IS NULL OR p_actual_amount < 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال تكلفة فعلية صالحة أكبر من أو تساوي صفر');
  END IF;

  SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = p_cost_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  v_res := public.rpc_settle_packing_cost_variances(
    r_item.packing_order_id,
    jsonb_build_array(
      jsonb_build_object(
        'cost_item_id', p_cost_item_id,
        'actual_amount', p_actual_amount,
        'invoice_ref', p_invoice_ref,
        'notes', p_notes,
        'detailed_notes', p_notes
      )
    ),
    p_notes,
    p_settled_by
  );

  RETURN v_res;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_item(BIGINT, NUMERIC, TEXT, TEXT, UUID) TO authenticated, service_role, anon;

-- 6. Updated get_supplier_true_balances_by_currency():
--    Computes Station & Deduction suppliers' packing costs strictly from approved
--    settled actual_amount values (ignoring unapproved estimates & variance deltas).
CREATE OR REPLACE FUNCTION public.get_supplier_true_balances_by_currency()
RETURNS TABLE (
    supplier_id        uuid,
    supplier_code      text,
    supplier_name      text,
    currency           text,
    true_balance       numeric,
    true_balance_egp   numeric
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public'
AS $func$
  WITH rates AS (
    SELECT DISTINCT ON (currency_code) currency_code, rate_to_egp
    FROM (
      SELECT currency_code, rate_to_egp, updated_at FROM public.exchange_rates
      UNION ALL
      SELECT 'EGP'::character varying(10), 1.0::numeric(10,4), NOW()
    ) r_all
    ORDER BY currency_code, updated_at DESC NULLS LAST
  ),
  -- 1. Initial Balances
  init_balances AS (
    SELECT
      s.id AS supplier_id,
      UPPER(COALESCE(elem.value->>'currency', elem.key)) AS currency,
      COALESCE((elem.value->>'amount')::numeric, 0) * (CASE WHEN UPPER(COALESCE(elem.value->>'direction', 'CREDIT')) = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt
    FROM public.suppliers s,
    LATERAL jsonb_each(s.initial_balances_by_currency) elem
    WHERE s.is_multi_currency = true
      AND s.initial_balances_by_currency IS NOT NULL
      AND jsonb_typeof(s.initial_balances_by_currency) = 'object'
      AND COALESCE((elem.value->>'amount')::numeric, 0) > 0

    UNION ALL

    SELECT
      s.id AS supplier_id,
      COALESCE(NULLIF(s.currency, ''), 'EGP') AS currency,
      COALESCE(s.initial_balance, 0) * (CASE WHEN s.initial_balance_direction = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt
    FROM public.suppliers s
    WHERE (s.is_multi_currency = false OR s.initial_balances_by_currency IS NULL OR s.initial_balances_by_currency = '{}'::jsonb)
      AND COALESCE(s.initial_balance, 0) <> 0
  ),
  -- 2. Purchase Invoices
  purchases AS (
    SELECT
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(total_amount) AS net_amt
    FROM public.purchase_invoices
    WHERE status = 'confirmed' AND supplier_id IS NOT NULL
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  -- 3. Treasury Transactions
  treasury AS (
    SELECT
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN LOWER(COALESCE(type, '')) IN ('deposit', 'receive', 'income', 'supplier_refund') THEN amount ELSE -amount END) AS net_amt
    FROM public.treasury_transactions
    WHERE supplier_id IS NOT NULL
      AND (status != 'draft' OR status IS NULL)
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  -- 4. Bank Account Transactions
  bank_tx AS (
    SELECT
      s.id AS supplier_id,
      COALESCE(NULLIF(ba.currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN LOWER(COALESCE(bat.type, '')) IN ('deposit', 'receive', 'income') THEN bat.amount ELSE -bat.amount END) AS net_amt
    FROM public.bank_account_transactions bat
    JOIN public.suppliers s ON (s.id::text = bat.entity_id OR s.code = bat.entity_id OR s.supplier_code = bat.entity_id)
    LEFT JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id
    WHERE bat.entity_type = 'supplier'
      AND (bat.status != 'cancelled' OR bat.status IS NULL)
    GROUP BY s.id, COALESCE(NULLIF(ba.currency, ''), 'EGP')
  ),
  -- 5. Cheques
  cheque_tx AS (
    SELECT
      supplier_id,
      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN LOWER(COALESCE(type, '')) = 'incoming' THEN amount ELSE -amount END) AS net_amt
    FROM public.cheques
    WHERE supplier_id IS NOT NULL
      AND status IN ('cleared', 'collected')
    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')
  ),
  -- 6. Lot Receipts & Manual Supplier Journals
  lot_tx AS (
    SELECT
      lr.supplier_id,
      COALESCE(NULLIF(lr.currency, ''), COALESCE(NULLIF(ale.currency, ''), 'USD')) AS currency,
      SUM(ale.credit - ale.debit) AS net_amt
    FROM public.account_ledger_entries ale
    JOIN public.journal_entries je ON je.id = ale.journal_entry_id
    JOIN public.lot_receipts lr ON lr.id::text = je.source_id
    WHERE je.source_type IN ('lot_receipt', 'lot_adjustment', 'lot_price_adjustment')
      AND lr.supplier_id IS NOT NULL
    GROUP BY lr.supplier_id, COALESCE(NULLIF(lr.currency, ''), COALESCE(NULLIF(ale.currency, ''), 'USD'))

    UNION ALL

    SELECT
      s.id AS supplier_id,
      COALESCE(NULLIF(ale.currency, ''), 'EGP') AS currency,
      SUM(ale.credit - ale.debit) AS net_amt
    FROM public.account_ledger_entries ale
    JOIN public.journal_entries je ON je.id = ale.journal_entry_id
    JOIN public.suppliers s ON (s.id::text = ale.entity_id OR s.code = ale.entity_id OR s.supplier_code = ale.entity_id)
    WHERE je.source_type = 'manual'
      AND ale.entity_type = 'supplier'
    GROUP BY s.id, COALESCE(NULLIF(ale.currency, ''), 'EGP')
  ),
  -- 7. Purchase Returns / Lot Returns
  purchase_returns AS (
    SELECT
      lr.supplier_id,
      COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP'))) AS currency,
      -SUM(lr.return_value) AS net_amt
    FROM public.lot_returns lr
    LEFT JOIN public.lot_receipts rec ON rec.id = lr.lot_receipt_id
    JOIN public.suppliers s ON s.id = lr.supplier_id
    WHERE lr.supplier_id IS NOT NULL
    GROUP BY lr.supplier_id, COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP')))
  ),
  -- 8. Standalone Purchase Returns from Ledger Entries
  ledger_returns AS (
    SELECT
      s.id AS supplier_id,
      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,
      -SUM(le.amount) AS net_amt
    FROM public.ledger_entries le
    JOIN public.suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)
    WHERE le.entity_type = 'supplier'
      AND le.reference_type = 'purchase_return'
    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')
  ),
  -- 9. Approved Actual Packing Costs for Station & Deduction Suppliers (EXCLUSIVE of variance & estimates)
  station_actual_costs AS (
    SELECT
      s.id AS supplier_id,
      COALESCE(NULLIF(ci.original_currency, ''), 'EGP') AS currency,
      SUM(ci.actual_amount) AS net_amt
    FROM public.packing_order_cost_items ci
    JOIN public.packing_orders po ON po.id = ci.packing_order_id
    JOIN public.suppliers s ON (
      s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
      OR s.code = ci.supplier_id
      OR s.supplier_code = ci.supplier_id
    )
    WHERE ci.deleted_at IS NULL
      AND po.status <> 'cancelled'
      AND ci.cost_status = 'actual'
      AND ci.actual_amount IS NOT NULL
      AND ci.actual_amount > 0
      AND (ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL)
      AND (
        LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
        OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
      )
    GROUP BY s.id, COALESCE(NULLIF(ci.original_currency, ''), 'EGP')
  ),
  -- 10. Non-Dual-Cost Packing Costs & Generic Sub-Ledger Adjustments
  other_packing_and_ledger AS (
    SELECT
      s.id AS supplier_id,
      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,
      SUM(CASE WHEN (le.entry_type = 'credit' OR le.reference_type IN ('supplier_deposit', 'export_return_expense', 'export_shipment_return_expense')) THEN le.amount ELSE -le.amount END) AS net_amt
    FROM public.ledger_entries le
    JOIN public.suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)
    WHERE le.entity_type = 'supplier'
      AND COALESCE(le.reference_type, '') NOT IN ('lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return', 'purchase_return')
      AND NOT EXISTS (SELECT 1 FROM public.treasury_transactions t WHERE t.id::text = le.reference_id::text)
      AND NOT EXISTS (SELECT 1 FROM public.bank_account_transactions b WHERE b.id::text = le.reference_id::text)
      -- Exclude packing_cost / cost_settlement rows for Station & Deduction suppliers (handled authoritatively by station_actual_costs CTE)
      AND NOT (
        COALESCE(le.reference_type, '') IN ('packing_cost', 'packing_cost_item', 'packing_order_costs', 'cost_settlement', 'packing_cost_settlement')
        AND (
          LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
          OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
        )
      )
    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')
  ),
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
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM station_actual_costs
    UNION ALL
    SELECT supplier_id, currency, net_amt FROM other_packing_and_ledger
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
  JOIN public.suppliers s ON s.id = a.supplier_id
  LEFT JOIN rates r ON r.currency_code = a.currency;
$func$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances_by_currency() TO authenticated, anon, service_role;

-- 7. Historical Data Repair for Existing Station & Deduction Suppliers:
--    a) Reset falsely auto-locked unsettled items back to 'expected'
--    b) Clean up mixed estimated + variance rows in ledger_entries and replace with exact actual_amount credits
--    c) Re-align GL lines in packing_order_costs & packing_cost_settlement JEs
--    d) Re-sync outstanding_balance on suppliers
DO $$
DECLARE
  v_est_clearing_acc INT;
  v_finished_inv_acc INT;
  v_company_id UUID;
  r_ci RECORD;
  r_je RECORD;
  v_target_acc INT;
  v_order_num TEXT;
  v_expected NUMERIC;
  v_actual NUMERIC;
  v_variance NUMERIC;
  v_desc TEXT;
  v_sje_id BIGINT;
  v_has_stage3 BOOLEAN;
  v_needs_je_repair BOOLEAN;
  v_has_non_dual BOOLEAN;
BEGIN
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  v_est_clearing_acc := COALESCE(
    public.resolve_gl_account('21313', v_company_id),
    public.resolve_gl_account('21311', v_company_id),
    public.resolve_gl_account('9124', v_company_id)
  );
  v_finished_inv_acc := COALESCE(
    public.resolve_gl_account('12413', v_company_id),
    public.resolve_gl_account('1241', v_company_id),
    public.resolve_gl_account('1031', v_company_id)
  );

  -- (a) Revert falsely auto-locked station/deduction items that were never genuinely reconciled
  UPDATE public.packing_order_cost_items ci
  SET expected_amount = COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount),
      cost_status = 'expected',
      actual_amount = NULL,
      variance_amount = 0,
      is_locked = FALSE,
      locked_at = NULL
  FROM public.suppliers s
  WHERE ci.deleted_at IS NULL
    AND (
      s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
      OR s.code = ci.supplier_id
      OR s.supplier_code = ci.supplier_id
    )
    AND (
      LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
      OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
    )
    AND ci.reconciled_at IS NULL
    AND ci.variance_journal_entry_id IS NULL
    AND NULLIF(TRIM(COALESCE(ci.invoice_ref, '')), '') IS NULL
    AND NULLIF(TRIM(COALESCE(ci.settlement_notes, '')), '') IS NULL;

  -- (b) Delete all mixed packing_cost / cost_settlement rows from ledger_entries for station/deduction suppliers
  DELETE FROM public.ledger_entries le
  USING public.suppliers s
  WHERE le.entity_type = 'supplier'
    AND le.entity_id IN (s.id::text, COALESCE(s.code, ''), COALESCE(s.supplier_code, ''))
    AND le.reference_type IN ('packing_cost', 'packing_cost_item', 'packing_order_costs', 'cost_settlement', 'packing_cost_settlement')
    AND (
      LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
      OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
    );

  -- (c) Move Stage-3 estimated supplier GL credits on packing_order_costs off supplier accounts onto 21313
  IF v_est_clearing_acc IS NOT NULL THEN
    UPDATE public.account_ledger_entries ale
    SET account_id = v_est_clearing_acc,
        entity_type = NULL,
        entity_id = NULL,
        description = 'مخصص تكاليف تقديرية (معلّقة التسوية) - ' || COALESCE(ale.description, '')
    FROM public.journal_entries je, public.suppliers s
    WHERE ale.journal_entry_id = je.id
      AND je.source_type = 'packing_order_costs'
      AND ale.entity_type = 'supplier'
      AND ale.credit > 0
      AND ale.entity_id IN (s.id::text, COALESCE(s.code, ''), COALESCE(s.supplier_code, ''))
      AND (
        LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
        OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
      );
  END IF;

  -- (d) Re-build clean actual-only sub-ledger entries (one row per settled cost item = exact actual_amount)
  --     and attach a settlement JE id if a Stage-3 settled item had none (e.g., variance = 0)
  FOR r_ci IN
    SELECT ci.*, po.order_number, po.costs_journal_entry_id, po.packed_at, po.created_at AS po_created_at,
           s.id AS resolved_supp_id, s.supplier_type, s.company_id AS supp_company_id
    FROM public.packing_order_cost_items ci
    JOIN public.packing_orders po ON po.id = ci.packing_order_id
    JOIN public.suppliers s ON (
      s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
      OR s.code = ci.supplier_id
      OR s.supplier_code = ci.supplier_id
    )
    WHERE ci.deleted_at IS NULL
      AND po.status <> 'cancelled'
      AND (ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL)
      AND ci.actual_amount IS NOT NULL
      AND ci.actual_amount > 0
      AND (
        LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
        OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
      )
  LOOP
    v_order_num := COALESCE(r_ci.order_number, r_ci.packing_order_id::text);
    v_expected := COALESCE(NULLIF(r_ci.expected_amount, 0), r_ci.base_amount, 0);
    v_actual := r_ci.actual_amount;
    v_variance := ROUND(v_actual - v_expected, 2);

    v_desc := 'اعتماد تكلفة فعلية بند: ' || COALESCE(r_ci.name, 'تكلفة') || ' (أمر ' || v_order_num || ')';
    IF NULLIF(TRIM(COALESCE(r_ci.invoice_ref, '')), '') IS NOT NULL THEN
      v_desc := v_desc || ' - مستند: ' || r_ci.invoice_ref;
    END IF;
    IF NULLIF(TRIM(COALESCE(r_ci.detailed_notes, r_ci.settlement_notes, '')), '') IS NOT NULL THEN
      v_desc := v_desc || ' - ' || COALESCE(NULLIF(r_ci.detailed_notes, ''), r_ci.settlement_notes);
    END IF;

    INSERT INTO public.ledger_entries (
      entity_id, entity_type, amount, currency, entry_type,
      reference_id, reference_type, reference_text, description, currency_snapshot, created_at
    ) VALUES (
      r_ci.resolved_supp_id::text, 'supplier', v_actual, COALESCE(NULLIF(r_ci.original_currency, ''), 'EGP'), 'credit',
      r_ci.packing_order_id, 'cost_settlement', COALESCE(NULLIF(r_ci.invoice_ref, ''), r_ci.name),
      v_desc,
      jsonb_build_object(
        'cost_item_id', r_ci.id,
        'packing_order_id', r_ci.packing_order_id,
        'expected_amount', v_expected,
        'actual_amount', v_actual,
        'variance_amount', v_variance
      ),
      COALESCE(r_ci.actual_date_time, r_ci.reconciled_at, r_ci.packed_at, r_ci.po_created_at, now())
    );

    -- If a settled Stage-3 item had no variance JE (e.g. historical variance = 0), create one so 21313 clears cleanly into 21117/21118
    IF r_ci.variance_journal_entry_id IS NULL
       AND r_ci.costs_journal_entry_id IS NOT NULL
       AND v_est_clearing_acc IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.account_ledger_entries ale
         WHERE ale.journal_entry_id = r_ci.costs_journal_entry_id
           AND ale.account_id = v_est_clearing_acc
           AND ale.credit > 0
       )
    THEN
      INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_at, updated_at
      ) VALUES (
        'PENDING',
        COALESCE((r_ci.actual_date_time AT TIME ZONE 'Africa/Cairo')::date, (r_ci.reconciled_at AT TIME ZONE 'Africa/Cairo')::date, (r_ci.packed_at AT TIME ZONE 'Africa/Cairo')::date, CURRENT_DATE),
        'تسوية واعتماد تكلفة فعلية أمر تعبئة ' || v_order_num,
        'posted', true, 'packing_cost_settlement', r_ci.packing_order_id::text,
        COALESCE(r_ci.supp_company_id, v_company_id), now(), now()
      ) RETURNING id INTO v_sje_id;

      UPDATE public.packing_order_cost_items
      SET variance_journal_entry_id = v_sje_id
      WHERE id = r_ci.id;
    END IF;
  END LOOP;

  -- (e) Normalize GL lines per distinct variance_journal_entry_id (multi-item & idempotent safe)
  IF v_est_clearing_acc IS NOT NULL AND v_finished_inv_acc IS NOT NULL THEN
    FOR r_je IN
      SELECT DISTINCT ci.variance_journal_entry_id AS sje_id
      FROM public.packing_order_cost_items ci
      JOIN public.packing_orders po ON po.id = ci.packing_order_id
      JOIN public.suppliers s ON (
        s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
        OR s.code = ci.supplier_id
        OR s.supplier_code = ci.supplier_id
      )
      WHERE ci.variance_journal_entry_id IS NOT NULL
        AND ci.deleted_at IS NULL
        AND po.status <> 'cancelled'
        AND (ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL)
        AND ci.actual_amount IS NOT NULL
        AND ci.actual_amount > 0
        AND (
          LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
          OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
        )
    LOOP
      v_sje_id := r_je.sje_id;

      -- Repair needed if JE has no lines yet, or any station/deduction supplier on it has debit > 0 or sum(credit) <> sum(actual_amount)
      SELECT (
        NOT EXISTS (SELECT 1 FROM public.account_ledger_entries ale WHERE ale.journal_entry_id = v_sje_id)
        OR EXISTS (
          SELECT 1
          FROM (
            SELECT s.id::text AS supp_id_text,
                   ROUND(COALESCE(SUM(ci.actual_amount), 0), 2) AS expected_actual
            FROM public.packing_order_cost_items ci
            JOIN public.suppliers s ON (
              s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
              OR s.code = ci.supplier_id
              OR s.supplier_code = ci.supplier_id
            )
            WHERE ci.variance_journal_entry_id = v_sje_id
              AND ci.deleted_at IS NULL
              AND (ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL)
              AND ci.actual_amount IS NOT NULL
              AND ci.actual_amount > 0
              AND (
                LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
                OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
              )
            GROUP BY s.id::text
          ) exp_s
          WHERE NOT EXISTS (
            SELECT 1
            FROM (
              SELECT ale.entity_id,
                     ROUND(COALESCE(SUM(ale.debit), 0), 2) AS sum_dr,
                     ROUND(COALESCE(SUM(ale.credit), 0), 2) AS sum_cr
              FROM public.account_ledger_entries ale
              WHERE ale.journal_entry_id = v_sje_id
                AND ale.entity_type = 'supplier'
              GROUP BY ale.entity_id
            ) cur_s
            WHERE cur_s.entity_id = exp_s.supp_id_text
              AND cur_s.sum_dr = 0
              AND cur_s.sum_cr = exp_s.expected_actual
          )
        )
      ) INTO v_needs_je_repair;

      IF NOT v_needs_je_repair THEN
        CONTINUE;
      END IF;

      -- Check if any non-station/non-deduction item shares this JE
      SELECT EXISTS (
        SELECT 1
        FROM public.packing_order_cost_items ci
        LEFT JOIN public.suppliers s ON (
          s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
          OR s.code = ci.supplier_id
          OR s.supplier_code = ci.supplier_id
        )
        WHERE ci.variance_journal_entry_id = v_sje_id
          AND ci.deleted_at IS NULL
          AND (
            s.id IS NULL
            OR NOT (
              LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
              OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
            )
          )
      ) INTO v_has_non_dual;

      IF NOT v_has_non_dual THEN
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_sje_id;
      ELSE
        DELETE FROM public.account_ledger_entries ale
        WHERE ale.journal_entry_id = v_sje_id
          AND (
            ale.account_id = v_est_clearing_acc
            OR (
              ale.entity_type = 'supplier'
              AND ale.entity_id IN (
                SELECT s.id::text
                FROM public.packing_order_cost_items ci
                JOIN public.suppliers s ON (
                  s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
                  OR s.code = ci.supplier_id
                  OR s.supplier_code = ci.supplier_id
                )
                WHERE ci.variance_journal_entry_id = v_sje_id
                  AND ci.deleted_at IS NULL
                  AND (
                    LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
                    OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
                  )
              )
            )
            OR (
              ale.account_id = v_finished_inv_acc
              AND EXISTS (
                SELECT 1
                FROM public.packing_order_cost_items ci
                JOIN public.suppliers s ON (
                  s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
                  OR s.code = ci.supplier_id
                  OR s.supplier_code = ci.supplier_id
                )
                WHERE ci.variance_journal_entry_id = v_sje_id
                  AND ci.deleted_at IS NULL
                  AND (
                    LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
                    OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
                  )
                  AND ale.description LIKE '%' || COALESCE(ci.name, '') || '%'
              )
            )
          );
      END IF;

      -- Re-insert balanced GL lines for ALL settled station/deduction items attached to v_sje_id
      FOR r_ci IN
        SELECT ci.*, po.order_number, po.costs_journal_entry_id,
               s.id AS resolved_supp_id, s.supplier_type, s.company_id AS supp_company_id
        FROM public.packing_order_cost_items ci
        JOIN public.packing_orders po ON po.id = ci.packing_order_id
        JOIN public.suppliers s ON (
          s.id::text = COALESCE(NULLIF(ci.supplier_id, ''), ci.currency_snapshot->>'supplier_id')
          OR s.code = ci.supplier_id
          OR s.supplier_code = ci.supplier_id
        )
        WHERE ci.variance_journal_entry_id = v_sje_id
          AND ci.deleted_at IS NULL
          AND po.status <> 'cancelled'
          AND (ci.reconciled_at IS NOT NULL OR ci.variance_journal_entry_id IS NOT NULL)
          AND ci.actual_amount IS NOT NULL
          AND ci.actual_amount > 0
          AND (
            LOWER(COALESCE(s.supplier_type, '')) IN ('station', 'deduction', 'deductions')
            OR COALESCE(s.code, s.supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)'
          )
      LOOP
        v_order_num := COALESCE(r_ci.order_number, r_ci.packing_order_id::text);
        v_expected := COALESCE(NULLIF(r_ci.expected_amount, 0), r_ci.base_amount, 0);
        v_actual := r_ci.actual_amount;
        v_variance := ROUND(v_actual - v_expected, 2);

        v_desc := 'اعتماد تكلفة فعلية بند: ' || COALESCE(r_ci.name, 'تكلفة') || ' (أمر ' || v_order_num || ')';
        IF NULLIF(TRIM(COALESCE(r_ci.invoice_ref, '')), '') IS NOT NULL THEN
          v_desc := v_desc || ' - مستند: ' || r_ci.invoice_ref;
        END IF;
        IF NULLIF(TRIM(COALESCE(r_ci.detailed_notes, r_ci.settlement_notes, '')), '') IS NOT NULL THEN
          v_desc := v_desc || ' - ' || COALESCE(NULLIF(r_ci.detailed_notes, ''), r_ci.settlement_notes);
        END IF;

        v_target_acc := public.fn_resolve_packing_cost_supplier_account(r_ci.resolved_supp_id, COALESCE(r_ci.supp_company_id, v_company_id));
        IF v_target_acc IS NULL THEN
          v_target_acc := CASE
            WHEN LOWER(COALESCE(r_ci.supplier_type, '')) IN ('deduction', 'deductions') THEN public.resolve_gl_account('21118', COALESCE(r_ci.supp_company_id, v_company_id))
            ELSE public.resolve_gl_account('21117', COALESCE(r_ci.supp_company_id, v_company_id))
          END;
        END IF;
        IF v_target_acc IS NULL THEN
          v_target_acc := public.resolve_gl_account('2111', COALESCE(r_ci.supp_company_id, v_company_id));
        END IF;

        v_has_stage3 := (
          r_ci.costs_journal_entry_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM public.account_ledger_entries ale
            WHERE ale.journal_entry_id = r_ci.costs_journal_entry_id
              AND ale.account_id = v_est_clearing_acc
              AND ale.credit > 0
          )
        );

        IF v_has_stage3 THEN
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_sje_id, v_est_clearing_acc, v_expected, 0, 'EGP', v_expected,
            'إقفال مخصص تكلفة تقديرية عند التسوية - ' || COALESCE(r_ci.name, '') || ' (أمر ' || v_order_num || ')',
            COALESCE(r_ci.supp_company_id, v_company_id)
          );
          IF v_variance <> 0 THEN
            INSERT INTO public.account_ledger_entries (
              journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
              v_sje_id, v_finished_inv_acc,
              CASE WHEN v_variance > 0 THEN ABS(v_variance) ELSE 0 END,
              CASE WHEN v_variance < 0 THEN ABS(v_variance) ELSE 0 END,
              'EGP', ABS(v_variance),
              'تعديل تكلفة المخزون بالفرق عن التقديري - ' || COALESCE(r_ci.name, '') || ' (أمر ' || v_order_num || ')',
              COALESCE(r_ci.supp_company_id, v_company_id)
            );
          END IF;
        ELSE
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_sje_id, v_finished_inv_acc, v_actual, 0, 'EGP', v_actual,
            'تكلفة مورد محطة فعلية - ' || v_desc,
            COALESCE(r_ci.supp_company_id, v_company_id)
          );
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_sje_id, v_target_acc, 0, v_actual, 'EGP', v_actual,
          v_desc, COALESCE(r_ci.supp_company_id, v_company_id), 'supplier', r_ci.resolved_supp_id::text
        );
      END LOOP;
    END LOOP;
  END IF;

  -- (f) Reset stale station/deduction supplier balances to 0 first so sync covers zero-balance suppliers too
  UPDATE public.suppliers
  SET outstanding_balance = 0,
      current_balances_by_currency = '{}'::jsonb
  WHERE LOWER(COALESCE(supplier_type, '')) IN ('station', 'deduction', 'deductions')
     OR COALESCE(code, supplier_code, '') ~ '^(85|86|87|88|89|40|41|42|43|44)';

  PERFORM public.sync_all_supplier_balances();
END $$;

NOTIFY pgrst, 'reload schema';
