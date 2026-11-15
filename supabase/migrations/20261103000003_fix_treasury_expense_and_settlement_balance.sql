-- ============================================================================
-- Migration: 20261103000003_fix_treasury_expense_and_settlement_balance.sql
-- Description:
--   1. Fix Main Treasury balance deduction when settling engineer expenses / cash items.
--   2. Ensure Journal Entry credits the Cash Treasury account (12211 / account_id 4566)
--      and debits the Expense account (31251).
--   3. Link journal_entry_id to treasury_transactions, and record accurate balance_before & balance_after.
--   4. Repair existing historical data for Treasury ID 1 and Transaction ID 3 (200 EGP expense).
-- ============================================================================

-- Step 1: Ensure Treasury 1 has account_id bound to 4566 (12211 - الخزينة الرئيسية)
UPDATE public.treasuries
SET account_id = 4566
WHERE id = 1 AND (account_id IS NULL OR account_id <> 4566);

-- Step 2: Repair existing data for Treasury 1 and transaction 3 (200 EGP engineer settlement)
DO $$
DECLARE
  v_company_id UUID;
  v_je_id BIGINT;
  v_entry_num TEXT;
  v_eng_acc BIGINT;
  v_treasury_acc BIGINT := 4566;
BEGIN
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1030' LIMIT 1;
  END IF;

  SELECT id INTO v_eng_acc FROM public.accounts WHERE account_code = '31251' LIMIT 1;
  IF v_eng_acc IS NULL THEN
    SELECT id INTO v_eng_acc FROM public.accounts WHERE account_code = '3125' LIMIT 1;
  END IF;

  -- 2.1 Update Treasury 1 EGP balance to 1200.00 (1400 deposits - 200 expense)
  UPDATE public.treasury_balances
  SET balance = 1200.00,
      updated_at = NOW()
  WHERE treasury_id = 1 AND currency = 'EGP';

  -- 2.2 Check if a journal entry already exists for transaction 3
  SELECT journal_entry_id INTO v_je_id
  FROM public.treasury_transactions
  WHERE id = 3;

  IF v_je_id IS NULL THEN
    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status, is_auto_generated,
      source_type, source_id, company_id
    ) VALUES (
      'PENDING', CURRENT_DATE,
      'تسوية عهدة ومصروفات مهندسين - أمر تعبئة 1 (الخزينة الرئيسية)',
      'posted', true, 'packing_cost_settlement', '1', v_company_id
    ) RETURNING id INTO v_je_id;

    v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    -- Debit 31251 (مصاريف مهندسين) 200.00
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency,
      description, company_id, cost_center_id
    ) VALUES (
      v_je_id, v_eng_acc, 200.00, 0.00, 'EGP', 200.00,
      'تسوية عهدة مهندس - مصاريف مهندسين وإشراف (أمر 1)', v_company_id, 'CC-ENG-EXP'
    );

    -- Credit 12211 (الخزينة الرئيسية - 4566) 200.00
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency,
      description, company_id, entity_type, entity_id
    ) VALUES (
      v_je_id, v_treasury_acc, 0.00, 200.00, 'EGP', 200.00,
      'صرف نقدي من الخزينة الرئيسية - تسوية عهدة مهندس (أمر 1)', v_company_id, 'treasury', '1'
    );
  END IF;

  -- 2.3 Update Transaction 3 with correct balance_before, balance_after and journal_entry_id
  UPDATE public.treasury_transactions
  SET balance_before = 1400.00,
      balance_after = 1200.00,
      status = 'confirmed',
      journal_entry_id = v_je_id
  WHERE id = 3;

  -- 2.4 Update packing_order_cost_items ID 4
  UPDATE public.packing_order_cost_items
  SET is_engineer_cost_settled = TRUE,
      treasury_transaction_id = 3,
      custody_id = 1
  WHERE id = 4;
END;
$$;

-- Step 3: Canonical rpc_settle_packing_cost_variances with flawless Treasury deduction & GL crediting
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

  v_order_num := COALESCE(r_order.order_number, '#' || p_packing_order_id::text);
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1030' LIMIT 1;
  END IF;

  SELECT id INTO v_finished_inv_acc FROM public.accounts WHERE account_code = '12413' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN v_finished_inv_acc := public.resolve_gl_account('12413', v_company_id); END IF;

  SELECT id INTO v_engineer_exp_acc FROM public.accounts WHERE account_code = '31251' LIMIT 1;
  IF v_engineer_exp_acc IS NULL THEN
    SELECT id INTO v_engineer_exp_acc FROM public.accounts WHERE account_code = '3125' LIMIT 1;
  END IF;
  IF v_engineer_exp_acc IS NULL THEN v_engineer_exp_acc := v_finished_inv_acc; END IF;

  -- 1. Ensure Journal Entry is created to anchor all financial postings
  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status, is_auto_generated,
    source_type, source_id, company_id, created_by
  ) VALUES (
    'PENDING', (COALESCE(r_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date,
    'قيد تسوية التكاليف الفعلية ومصروفات العهد - أمر تعبئة ' || v_order_num || COALESCE(' - ' || p_general_notes, ''),
    'posted', true, 'packing_cost_settlement', p_packing_order_id::text, v_company_id,
    COALESCE(p_settled_by, auth.uid())
  ) RETURNING id INTO v_je_id;

  v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- 2. Process settlements
  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    v_inv_ref := v_item_elem->>'invoice_ref';
    v_item_notes := v_item_elem->>'notes';

    IF v_actual_amt IS NULL OR v_actual_amt < 0 THEN CONTINUE; END IF;

    SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id FOR UPDATE;
    IF NOT FOUND THEN CONTINUE; END IF;

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

    -- Category Detection
    v_is_engineer := (
      LOWER(COALESCE(r_item.category, '')) = 'engineer_expenses'
      OR (r_item.currency_snapshot IS NOT NULL AND r_item.currency_snapshot->>'supplier_type' = 'engineer')
      OR r_item.name ILIKE '%مهندس%'
      OR r_item.name ILIKE '%اشراف%'
      OR r_item.name ILIKE '%إشراف%'
      OR r_item.custody_id IS NOT NULL
      OR (v_item_elem ? 'custody_id')
    );
    v_is_admin := NOT v_is_engineer AND (LOWER(COALESCE(r_item.category, '')) = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%');
    v_is_transport := NOT v_is_engineer AND NOT v_is_admin AND (LOWER(COALESCE(r_item.category, '')) = 'logistics' OR r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%سيار%' OR r_item.name ILIKE '%شحن%');

    v_custody_id := NULL;
    v_supplier_id := NULL;
    v_target_acc := NULL;
    v_debit_acc := v_finished_inv_acc;

    -- ── Case A: Engineer Expenses & Cash Custody / Treasury Settlement ──
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
        -- Default to Main Treasury (ID 1) or first treasury
        SELECT id INTO v_custody_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        IF v_custody_id IS NULL THEN
          SELECT id INTO v_custody_id FROM public.treasuries WHERE type IN ('employee', 'custody') LIMIT 1;
        END IF;
      END IF;

      -- Resolve Treasury GL Account (Credit side)
      v_treasury_acct := public.resolve_treasury_account(v_custody_id, 'EGP', v_company_id);
      IF v_treasury_acct IS NULL THEN
        SELECT account_id INTO v_treasury_acct FROM public.treasuries WHERE id = v_custody_id;
      END IF;
      IF v_treasury_acct IS NULL THEN
        v_treasury_acct := public.resolve_gl_account('12211', v_company_id);
      END IF;

      -- Resolve Debit Expense Account (31251)
      IF v_item_elem ? 'expense_account_id' AND (v_item_elem->>'expense_account_id') IS NOT NULL THEN
        v_debit_acc := (v_item_elem->>'expense_account_id')::integer;
      ELSIF r_item.expense_account_id IS NOT NULL THEN
        v_debit_acc := r_item.expense_account_id::integer;
      ELSE
        v_debit_acc := v_engineer_exp_acc;
      END IF;

      -- Determine amount to deduct from Treasury:
      -- If item was already settled against treasury, only deduct the incremental variance.
      -- If item was not yet settled against treasury, deduct full actual amount.
      IF r_item.is_engineer_cost_settled AND r_item.treasury_transaction_id IS NOT NULL THEN
        v_amount_to_deduct := v_incremental_variance;
      ELSE
        v_amount_to_deduct := v_actual_amt;
      END IF;

      -- Lock & update treasury balance
      SELECT balance INTO v_cur_bal
      FROM public.treasury_balances
      WHERE treasury_id = v_custody_id AND currency = 'EGP'
      FOR UPDATE;
      v_cur_bal := COALESCE(v_cur_bal, 0);

      v_new_bal := GREATEST(0, v_cur_bal - v_amount_to_deduct);

      UPDATE public.treasury_balances
      SET balance = v_new_bal,
          updated_at = NOW()
      WHERE treasury_id = v_custody_id AND currency = 'EGP';

      v_note_text := 'تسوية عهدة مهندس - مصاريف مهندسين وإشراف فعلية - بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-');

      -- Record Treasury Transaction
      v_existing_tx_id := r_item.treasury_transaction_id;
      IF v_existing_tx_id IS NOT NULL THEN
        UPDATE public.treasury_transactions
        SET amount = v_actual_amt,
            type = 'expense',
            status = 'confirmed',
            balance_before = v_cur_bal,
            balance_after = v_new_bal,
            journal_entry_id = v_je_id,
            description = v_note_text,
            notes = v_note_text,
            cost_center_id = 'CC-ENG-EXP'
        WHERE id = v_existing_tx_id;
      ELSE
        INSERT INTO public.treasury_transactions (
          treasury_id, amount, type, currency, balance_before, balance_after,
          description, reference_id, reference_type, notes, cost_center_id, created_at, status, journal_entry_id
        ) VALUES (
          v_custody_id, v_actual_amt,
          'expense', 'EGP', v_cur_bal, v_new_bal,
          v_note_text, p_packing_order_id::text, 'packing_order_cost', v_note_text, 'CC-ENG-EXP', now(), 'confirmed', v_je_id
        ) RETURNING id INTO v_existing_tx_id;
      END IF;

      -- Post GL double entries:
      -- DEBIT: Expense Account (31251)
      -- CREDIT: Treasury Account (12211 / v_treasury_acct)
      IF v_amount_to_deduct <> 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          cost_center_id
        ) VALUES (
          v_je_id, v_debit_acc,
          CASE WHEN v_amount_to_deduct > 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          CASE WHEN v_amount_to_deduct < 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          'EGP', ABS(v_amount_to_deduct),
          'تسوية عهدة مهندس - مصاريف مهندسين وإشراف (أمر ' || v_order_num || ') - بند: ' || r_item.name,
          v_company_id, 'CC-ENG-EXP'
        );

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_treasury_acct,
          CASE WHEN v_amount_to_deduct < 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          CASE WHEN v_amount_to_deduct > 0 THEN ABS(v_amount_to_deduct) ELSE 0 END,
          'EGP', ABS(v_amount_to_deduct),
          'صرف نقدي من الخزينة - تسوية عهدة مهندس (أمر ' || v_order_num || ') - بند: ' || r_item.name,
          v_company_id, 'treasury', v_custody_id::text
        );
      END IF;

    -- ── Case B: Transport Supplier Settlement ──
    ELSIF v_is_transport THEN
      v_target_acc := public.resolve_gl_account('21111', v_company_id);
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

    -- ── Case C: Administrative Expenses ──
    ELSIF v_is_admin THEN
      v_target_acc := public.resolve_gl_account('31331', v_company_id);

    -- ── Case D: Standard & Deductions Suppliers (Deduction 21118, etc.) ──
    ELSE
      v_supp_str := COALESCE(r_item.supplier_id, (r_item.currency_snapshot->>'supplier_id'));
      IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN
        BEGIN v_supplier_id := v_supp_str::uuid; EXCEPTION WHEN OTHERS THEN v_supplier_id := NULL; END;
      END IF;

      IF v_supplier_id IS NOT NULL THEN
        SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;
        IF v_supplier.account_id IS NOT NULL THEN
          v_target_acc := v_supplier.account_id;
        ELSE
          v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
        END IF;
      END IF;

      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('21118', v_company_id); END IF;
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

      -- Update Supplier balance & ledger entry (CREDIT increases liability)
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

        -- GL lines for supplier variance: Debit Finished Goods / Credit Supplier Liability
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          cost_center_id
        ) VALUES (
          v_je_id, v_finished_inv_acc,
          CASE WHEN v_incremental_variance > 0 THEN v_abs_variance ELSE 0 END,
          CASE WHEN v_incremental_variance < 0 THEN v_abs_variance ELSE 0 END,
          'EGP', v_abs_variance,
          'تسوية تكلفة مورد - ' || r_item.name || ' (أمر ' || v_order_num || ')',
          v_company_id, NULL
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

    -- Update cost item status & amounts
    UPDATE public.packing_order_cost_items
    SET actual_amount = v_actual_amt,
        variance_amount = v_total_variance,
        cost_status = 'actual',
        is_engineer_cost_settled = TRUE,
        treasury_transaction_id = COALESCE(v_existing_tx_id, treasury_transaction_id),
        custody_id = COALESCE(v_custody_id, custody_id),
        invoice_ref = COALESCE(v_inv_ref, invoice_ref),
        settlement_notes = COALESCE(v_item_notes, settlement_notes),
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
    'message', 'تمت تسوية التكاليف وتحديث رصيد الخزينة والقيود المحاسبية بنجاح',
    'journal_entry_id', v_je_id,
    'new_other_costs', v_new_other_cost_base,
    'new_carton_cost', v_new_carton_cost
  );
END;
$function$;

