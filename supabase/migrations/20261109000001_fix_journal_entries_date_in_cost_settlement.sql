-- ============================================================================
-- Migration: Fix Journal Entries Date Column and Admin Expense Reset in Cost Settlement
-- Date: 2026-11-09
-- Description:
--   1. Corrects column reference from `date` and `source` to `entry_date` and `source_type`
--      in rpc_settle_packing_cost_variances.
--   2. Resets erroneous copies of estimated cost to actual for administrative expenses.
-- ============================================================================

-- 1. Update check constraint to safely allow 'actual', 'settled', 'expected', 'locked'
ALTER TABLE public.packing_order_cost_items
  DROP CONSTRAINT IF EXISTS packing_order_cost_items_status_chk;
ALTER TABLE public.packing_order_cost_items
  ADD CONSTRAINT packing_order_cost_items_status_chk
  CHECK (cost_status IN ('expected', 'actual', 'settled', 'locked'));

-- 2. One-time Data Repair: Reset admin cost items to pending settlement ('expected')
UPDATE public.packing_order_cost_items
SET cost_status = 'expected',
    actual_amount = NULL,
    actual_quantity = 1,
    actual_unit_price = NULL,
    variance_amount = 0,
    is_locked = FALSE,
    locked_at = NULL,
    reconciled_at = NULL,
    variance_journal_entry_id = NULL
WHERE (category = 'admin' OR name ILIKE '%إدار%' OR name ILIKE '%ادار%')
  AND (cost_status <> 'settled' OR variance_journal_entry_id IS NULL OR actual_amount = expected_amount);

-- 2. Update rpc_settle_packing_cost_variances with correct journal_entries schema
CREATE OR REPLACE FUNCTION public.rpc_settle_packing_cost_variances(
  p_packing_order_id bigint,
  p_settlements jsonb,
  p_general_notes text DEFAULT NULL,
  p_settled_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  r_order RECORD;
  r_item RECORD;
  v_company_id UUID;
  v_order_num TEXT;
  v_finished_inv_acc INT;
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
  v_total_inc_variance NUMERIC := 0;

  v_is_engineer BOOLEAN;
  v_is_admin BOOLEAN;
  v_is_transport BOOLEAN;
  v_custody_id INT;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_supplier RECORD;
  v_target_acc INT;
  v_debit_acc INT;
  v_treasury_acct INT;

  v_amount_to_deduct NUMERIC;
  v_cur_bal NUMERIC;
  v_new_bal NUMERIC;
  v_note_text TEXT;
  v_existing_tx_id BIGINT;
  v_tx_status TEXT;

  v_cartons_count NUMERIC := 0;
  v_new_other_cost_base NUMERIC := 0;
  v_new_total_cost NUMERIC := 0;
  v_new_carton_cost NUMERIC := 0;
BEGIN
  IF p_settlements IS NULL OR jsonb_typeof(p_settlements) <> 'array' OR jsonb_array_length(p_settlements) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'قائمة تسوية البنود فارغة');
  END IF;

  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  v_company_id := r_order.company_id;
  v_order_num := COALESCE(r_order.order_number, r_order.id::text);

  -- 1. GL account resolution
  v_finished_inv_acc := public.resolve_gl_account('1241', v_company_id);
  IF v_finished_inv_acc IS NULL THEN v_finished_inv_acc := public.resolve_gl_account('124', v_company_id); END IF;
  IF v_finished_inv_acc IS NULL THEN v_finished_inv_acc := public.resolve_gl_account('12', v_company_id); END IF;

  v_engineer_exp_acc := public.resolve_gl_account('31251', v_company_id);
  IF v_engineer_exp_acc IS NULL THEN v_engineer_exp_acc := public.resolve_gl_account('3125', v_company_id); END IF;

  -- Create master journal entry header using entry_date and source_type
  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status, is_auto_generated,
    source_type, source_id, company_id, created_by
  ) VALUES (
    'PENDING',
    CURRENT_DATE,
    COALESCE(p_general_notes, 'تسوية تكاليف أمر التعبئة #' || v_order_num),
    'posted',
    true,
    'packing_cost_settlement',
    p_packing_order_id::text,
    v_company_id,
    COALESCE(p_settled_by, auth.uid())
  ) RETURNING id INTO v_je_id;

  v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- 2. Process each settlement item
  FOR v_item_elem IN SELECT * FROM jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    v_actual_qty := (v_item_elem->>'actual_quantity')::numeric;
    v_unit_price := (v_item_elem->>'unit_price')::numeric;
    v_actual_dt  := (v_item_elem->>'actual_date_time')::timestamptz;
    v_inv_ref := v_item_elem->>'invoice_ref';
    v_item_notes := v_item_elem->>'notes';

    IF v_cost_item_id IS NULL OR v_actual_amt IS NULL THEN
      CONTINUE;
    END IF;

    SELECT * INTO r_item FROM public.packing_order_cost_items
    WHERE id = v_cost_item_id AND packing_order_id = p_packing_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);
    v_old_actual := r_item.actual_amount;
    v_baseline := COALESCE(v_old_actual, v_expected);
    v_incremental_variance := v_actual_amt - v_baseline;
    v_total_variance := v_actual_amt - v_expected;
    v_abs_variance := ABS(v_incremental_variance);
    v_total_inc_variance := v_total_inc_variance + v_incremental_variance;

    v_is_engineer := (r_item.category = 'engineer_expenses' OR (r_item.category IS NULL AND r_item.name ILIKE '%مهندس%'));
    v_is_admin := (r_item.category = 'admin' OR r_item.name ILIKE '%إداري%' OR r_item.name ILIKE '%عمومية%');
    v_is_transport := (r_item.category = 'logistics' OR r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%شحن%');

    v_existing_tx_id := NULL;
    v_custody_id := NULL;
    v_supplier_id := NULL;
    v_target_acc := NULL;
    v_debit_acc := v_finished_inv_acc;

    -- Case A: Engineer Expenses
    IF v_is_engineer THEN
      v_custody_id := (v_item_elem->>'custody_id')::integer;
      IF v_custody_id IS NULL THEN v_custody_id := r_item.custody_id; END IF;
      IF v_custody_id IS NULL AND r_item.currency_snapshot IS NOT NULL AND (r_item.currency_snapshot ? 'custody_id') THEN
        v_custody_id := (r_item.currency_snapshot->>'custody_id')::integer;
      END IF;
      IF v_custody_id IS NULL AND r_item.engineer_name IS NOT NULL THEN
        SELECT id INTO v_custody_id FROM public.treasuries WHERE name ILIKE '%' || r_item.engineer_name || '%' LIMIT 1;
      END IF;
      IF v_custody_id IS NULL THEN
        SELECT id INTO v_custody_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        IF v_custody_id IS NULL THEN
          SELECT id INTO v_custody_id FROM public.treasuries WHERE type IN ('employee', 'custody') LIMIT 1;
        END IF;
      END IF;

      v_treasury_acct := public.resolve_treasury_account(v_custody_id, 'EGP', v_company_id);
      IF v_treasury_acct IS NULL THEN
        SELECT account_id INTO v_treasury_acct FROM public.treasuries WHERE id = v_custody_id;
      END IF;
      IF v_treasury_acct IS NULL THEN
        v_treasury_acct := public.resolve_gl_account('12211', v_company_id);
      END IF;

      IF v_item_elem ? 'expense_account_id' AND (v_item_elem->>'expense_account_id') IS NOT NULL THEN
        v_debit_acc := (v_item_elem->>'expense_account_id')::integer;
      ELSIF r_item.expense_account_id IS NOT NULL THEN
        v_debit_acc := r_item.expense_account_id::integer;
      ELSE
        v_debit_acc := v_engineer_exp_acc;
      END IF;

      IF r_item.is_engineer_cost_settled AND r_item.treasury_transaction_id IS NOT NULL THEN
        v_amount_to_deduct := v_incremental_variance;
      ELSE
        v_amount_to_deduct := v_actual_amt;
      END IF;

      SELECT balance INTO v_cur_bal FROM public.treasuries WHERE id = v_custody_id FOR UPDATE;
      v_cur_bal := COALESCE(v_cur_bal, 0);
      v_new_bal := v_cur_bal - v_amount_to_deduct;

      UPDATE public.treasuries
      SET balance = v_new_bal, updated_at = now()
      WHERE id = v_custody_id;

      v_note_text := 'تسوية مصاريف مهندسين وإشراف - ' || r_item.name || ' (أمر ' || v_order_num || ')';
      IF v_item_notes IS NOT NULL AND v_item_notes <> '' THEN
        v_note_text := v_note_text || ' - ' || v_item_notes;
      END IF;

      INSERT INTO public.treasury_transactions (
        treasury_id, transaction_type, amount, balance_after,
        reference_type, reference_id, description, transaction_date,
        created_at, updated_at
      ) VALUES (
        v_custody_id,
        CASE WHEN v_amount_to_deduct >= 0 THEN 'expense' ELSE 'income' END,
        ABS(v_amount_to_deduct),
        v_new_bal,
        'packing_order_cost_item',
        v_cost_item_id,
        v_note_text,
        COALESCE(v_actual_dt, now()),
        now(),
        now()
      ) RETURNING id INTO v_existing_tx_id;

      -- GL Lines: Debit Expense Account / Credit Treasury Account
      IF v_amount_to_deduct <> 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_debit_acc,
          CASE WHEN v_amount_to_deduct > 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          CASE WHEN v_amount_to_deduct < 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          'EGP', ABS(v_amount_to_deduct),
          v_note_text, v_company_id
        );

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_treasury_acct,
          CASE WHEN v_amount_to_deduct < 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          CASE WHEN v_amount_to_deduct > 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          'EGP', ABS(v_amount_to_deduct),
          v_note_text, v_company_id,
          'treasury', v_custody_id::text
        );
      END IF;

    -- Case B: Admin / Overhead Expenses
    ELSIF v_is_admin THEN
      IF v_item_elem ? 'expense_account_id' AND (v_item_elem->>'expense_account_id') IS NOT NULL THEN
        v_debit_acc := (v_item_elem->>'expense_account_id')::integer;
      ELSIF r_item.expense_account_id IS NOT NULL THEN
        v_debit_acc := r_item.expense_account_id::integer;
      ELSE
        v_debit_acc := public.resolve_gl_account('31331', v_company_id);
        IF v_debit_acc IS NULL THEN v_debit_acc := public.resolve_gl_account('313', v_company_id); END IF;
      END IF;

      -- GL lines for variance
      IF v_incremental_variance <> 0 AND v_debit_acc IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_finished_inv_acc,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مصاريف إدارية (مخزون إنتاج تام) - ' || r_item.name || ' (أمر ' || v_order_num || ')',
          v_company_id
        );

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_debit_acc,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مصاريف إدارية - ' || r_item.name || ' (أمر ' || v_order_num || ')',
          v_company_id
        );
      END IF;

    -- Case C: Supplier / Logistics / Material Expenses
    ELSE
      v_supp_str := NULL;
      IF r_item.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_item.currency_snapshot->>'supplier_id';
      END IF;

      IF v_supp_str IS NOT NULL AND v_supp_str <> '' THEN
        BEGIN
          v_supplier_id := v_supp_str::uuid;
        EXCEPTION WHEN OTHERS THEN
          v_supplier_id := NULL;
        END;
      END IF;

      IF v_supplier_id IS NOT NULL THEN
        IF v_is_transport THEN
          SELECT gl_account_id INTO v_target_acc FROM public.transport_suppliers WHERE id = v_supplier_id;
        ELSE
          v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
        END IF;
      END IF;

      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('21118', v_company_id); END IF;
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

      IF v_incremental_variance <> 0 AND v_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_incremental_variance
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type,
          reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', v_abs_variance, 'EGP',
          CASE WHEN v_incremental_variance > 0 THEN 'credit' ELSE 'debit' END,
          p_packing_order_id, 'cost_settlement', COALESCE(v_inv_ref, r_item.name),
          CASE WHEN v_incremental_variance > 0 
            THEN 'تسوية تكلفة فعلية (زيادة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
            ELSE 'تسوية تكلفة فعلية (وفر) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
          END, now()
        );

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_finished_inv_acc,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مورد - ' || r_item.name || ' (أمر ' || v_order_num || ')',
          v_company_id
        );

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_target_acc,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مورد - ' || r_item.name || ' (أمر ' || v_order_num || ')',
          v_company_id, 'supplier', v_supplier_id::text
        );
      END IF;
    END IF;

    -- Update cost item status, amounts, and itemized invoice details
    UPDATE public.packing_order_cost_items
    SET actual_amount = v_actual_amt,
        actual_quantity = COALESCE(v_actual_qty, actual_quantity, 1),
        actual_unit_price = COALESCE(v_unit_price, actual_unit_price, CASE WHEN COALESCE(v_actual_qty, 1) > 0 THEN v_actual_amt / COALESCE(v_actual_qty, 1) ELSE v_actual_amt END),
        actual_date_time = COALESCE(v_actual_dt, actual_date_time, now()),
        variance_amount = v_total_variance,
        cost_status = 'actual',
        is_locked = TRUE,
        locked_at = now(),
        is_engineer_cost_settled = TRUE,
        treasury_transaction_id = COALESCE(v_existing_tx_id, treasury_transaction_id),
        custody_id = COALESCE(v_custody_id, custody_id),
        invoice_ref = COALESCE(v_inv_ref, invoice_ref),
        settlement_notes = COALESCE(v_item_notes, settlement_notes),
        detailed_notes = COALESCE(v_item_notes, settlement_notes, detailed_notes),
        reconciled_at = now()
    WHERE id = v_cost_item_id;
  END LOOP;

  -- 3. Clean up empty Journal Entry if no GL lines were inserted
  IF NOT EXISTS (SELECT 1 FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id) THEN
    DELETE FROM public.journal_entries WHERE id = v_je_id;
    v_je_id := NULL;
  END IF;

  -- 4. Recalculate packing order carton costs
  SELECT COALESCE(SUM(actual_cartons), 0) INTO v_cartons_count
  FROM public.packing_order_items
  WHERE packing_order_id = p_packing_order_id;

  SELECT COALESCE(SUM(COALESCE(actual_amount, expected_amount, base_amount, 0)), 0)
  INTO v_new_other_cost_base
  FROM public.packing_order_cost_items
  WHERE packing_order_id = p_packing_order_id;

  v_new_total_cost := COALESCE(r_order.fruit_cost_egp, 0) + COALESCE(r_order.packaging_cost_egp, 0) + v_new_other_cost_base;
  v_new_carton_cost := CASE WHEN v_cartons_count > 0 THEN ROUND(v_new_total_cost / v_cartons_count, 4) ELSE 0 END;

  UPDATE public.packing_orders
  SET other_costs_egp = v_new_other_cost_base,
      total_cost_egp = v_new_total_cost,
      cost_per_carton = v_new_carton_cost,
      is_engineer_cost_settled = TRUE,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تمت تسوية التكاليف وتحديث الفواتير والقيود المحاسبية بنجاح',
    'journal_entry_id', v_je_id,
    'new_other_costs', v_new_other_cost_base,
    'new_carton_cost', v_new_carton_cost
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_variances(BIGINT, JSONB, TEXT, UUID) TO authenticated, service_role, anon;

