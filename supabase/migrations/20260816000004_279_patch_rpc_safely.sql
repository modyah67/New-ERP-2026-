BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order               RECORD;
  v_notes               JSONB;
  v_station_id          INTEGER;
  v_el                  JSONB;
  v_rate                NUMERIC;
  v_amt_egp             NUMERIC;
  v_amt_foreign         NUMERIC;
  v_curr                TEXT;
  v_supplier_id         UUID;
  v_target_line_idx     INTEGER;
  v_lines               RECORD;
  v_n                   INTEGER;
  v_line_ids            BIGINT[];
  v_line_raw            NUMERIC[];
  v_line_net            NUMERIC[];
  v_line_overhead       NUMERIC[];
  v_tot_final_cost      NUMERIC;
  v_tot_raw_cost        NUMERIC;
  v_tot_pkg_cost        NUMERIC;
  v_tot_cost_items      NUMERIC;
  v_assigned            NUMERIC;
  v_part                NUMERIC;
  v_amount              NUMERIC;
  v_je_id               BIGINT;
  v_company_id          UUID;
  v_finished_inv_acc    BIGINT;
  v_raw_inv_acc         BIGINT;
  v_pkg_inv_acc         BIGINT;
  v_expense_acc         BIGINT;
  v_credit_acc          BIGINT;
  v_credit_currency     TEXT;
  v_sum_debit           NUMERIC := 0;
  v_sum_credit          NUMERIC := 0;
  r_cost                RECORD;
  v_max_cost_item_id    BIGINT;
  v_entry_num           TEXT;
  v_tx_desc             TEXT;
  v_treasury_tx_id      BIGINT;
  v_bank_tx_id          BIGINT;
  v_current_balance     NUMERIC;
  v_i                   INTEGER;
  v_shares              NUMERIC[];
  v_method              TEXT;
  v_bases               NUMERIC[];
BEGIN
  -- ── A. Basic Validation ──
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;
  IF v_order.status = 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة معتمد مسبقاً');
  END IF;
  IF v_order.status = 'cancelled' THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة ملغي');
  END IF;

  v_notes := v_order.notes;

  -- Handle Dart encoding an object containing stringified JSON under 'notes'
  IF jsonb_typeof(v_notes) = 'object' AND v_notes ? 'notes' AND jsonb_typeof(v_notes->'notes') = 'string' THEN
    BEGIN
      v_notes := (v_notes->>'notes')::jsonb;
    EXCEPTION WHEN OTHERS THEN
      -- ignore
    END;
  END IF;

  -- Handle direct stringified JSON
  IF jsonb_typeof(v_notes) = 'string' THEN
    BEGIN
      v_notes := (v_notes#>>'{}')::jsonb;
    EXCEPTION WHEN OTHERS THEN
      v_notes := '{}'::jsonb;
    END;
  END IF;

  IF v_notes IS NULL THEN
    v_notes := '{}'::jsonb;
  END IF;

  -- ── B. Deduct Inventory (Materials & Fruits) ──
  IF v_notes ? 'materials' THEN
    WITH updated_batches AS (
      SELECT
        (el->>'batch_id')::bigint AS batch_id,
        (el->>'used_qty')::numeric AS used_qty
      FROM jsonb_array_elements(v_notes->'materials') el
      WHERE (el->>'used_qty')::numeric > 0
    )
    UPDATE public.station_product_batches b
    SET
      remaining_quantity = b.remaining_quantity - u.used_qty
    FROM updated_batches u
    WHERE b.id = u.batch_id;
  END IF;

  IF v_notes ? 'fruit_allocation' THEN
    UPDATE public.station_product_batches b
    SET remaining_quantity = b.remaining_quantity - (v_notes->'fruit_allocation'->>'quantity')::numeric
    WHERE b.id = (v_notes->'fruit_allocation'->>'batch_id')::bigint;
  END IF;

  -- ── C. Rebuild cost items from notes ──
  IF v_notes ? 'cost_items' THEN
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
        IF v_el ? 'supplier_id' AND v_el->>'supplier_id' != '' THEN
          v_supplier_id := (v_el->>'supplier_id')::uuid;
        END IF;

        v_target_line_idx := NULL;
        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' THEN
          v_target_line_idx := (v_el->>'target_line_index')::integer;
        END IF;

        INSERT INTO public.packing_order_cost_items (
          packing_order_id, name, category,
          base_amount, original_amount, original_currency,
          payment_source_type, payment_source_id,
          allocation_method, target_line_id,
          currency_snapshot
        ) VALUES (
          p_packing_order_id,
          v_el->>'name',
          -- ENFORCE VALID ENUM VALUE FOR CATEGORY OR DEFAULT TO 'other' --
          CASE WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'other') THEN v_el->>'category' ELSE 'other' END,
          v_amt_egp,
          COALESCE((v_el->>'total')::numeric, v_amt_egp),
          COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
          v_el->>'payment_source_type',
          NULLIF(v_el->>'payment_source_id', '')::integer,
          v_el->>'allocation_method',
          v_target_line_idx,
          jsonb_build_object(
            'supplier_id', v_supplier_id,
            'supplier_name', v_el->>'supplier_name',
            'target_line_index', v_target_line_idx
          )
        );
      END IF;
    END LOOP;
  END IF;

  -- ── D. Prepare for allocation ──
  v_n := 0;
  v_bases := ARRAY[]::NUMERIC[];
  FOR v_lines IN
    SELECT id, COALESCE(raw_material_cost, 0) as rc, COALESCE(total_net_weight, 0) as nw
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id
    ORDER BY id
  LOOP
    v_n := v_n + 1;
    v_line_ids[v_n] := v_lines.id;
    v_line_raw[v_n] := v_lines.rc;
    v_line_net[v_n] := v_lines.nw;
    v_line_overhead[v_n] := 0;
    v_bases[v_n] := v_lines.rc;
  END LOOP;

  -- ── E. Allocate cost items ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_amount := COALESCE(r_cost.base_amount, 0);
    IF v_amount <= 0 THEN CONTINUE; END IF;

    IF r_cost.target_line_id IS NOT NULL THEN
      IF r_cost.target_line_id >= 0 AND r_cost.target_line_id < v_n THEN
        v_line_overhead[r_cost.target_line_id + 1] := v_line_overhead[r_cost.target_line_id + 1] + v_amount;
      END IF;
      CONTINUE;
    END IF;

    v_method := COALESCE(r_cost.allocation_method, 'EQUAL');
    IF v_method = 'WEIGHT' THEN
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_net[v_i]; END LOOP;
    ELSIF v_method = 'COST' THEN
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_raw[v_i]; END LOOP;
    ELSE
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := 1; END LOOP;
    END IF;

    IF v_n > 0 THEN
      v_shares := public._packing_allocate_shares(v_method, v_bases);
      v_assigned := 0;
      FOR v_i IN 1..v_n LOOP
        IF v_i = v_n THEN
          v_part := ROUND(v_amount - v_assigned, 2);
        ELSE
          v_part := ROUND(v_amount * v_shares[v_i], 2);
        END IF;
        v_line_overhead[v_i] := v_line_overhead[v_i] + v_part;
        v_assigned := v_assigned + v_part;
      END LOOP;
    END IF;
  END LOOP;

  -- ── F. Calculate Totals ──
  v_tot_final_cost := 0;
  v_tot_raw_cost := 0;
  FOR v_i IN 1..v_n LOOP
    v_tot_raw_cost := v_tot_raw_cost + v_line_raw[v_i];
    v_tot_final_cost := v_tot_final_cost + v_line_raw[v_i] + v_line_overhead[v_i];
  END LOOP;

  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;

  IF v_tot_final_cost = 0 THEN
    v_tot_raw_cost   := COALESCE(v_order.fruit_cost_allocated, v_order.fruit_cost_base, 0);
    v_tot_pkg_cost   := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
    v_tot_final_cost := COALESCE(v_order.total_packing_cost, (v_tot_raw_cost + v_tot_pkg_cost + v_tot_cost_items));
  ELSE
    v_tot_pkg_cost := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_tot_final_cost := v_tot_final_cost + v_tot_pkg_cost;
  END IF;

  -- ── G. Process Payments for Treasury/Bank ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    IF r_cost.payment_source_id IS NOT NULL AND r_cost.payment_source_type IN ('treasury', 'bank') THEN
      v_tx_desc := 'مصروف أمر تعبئة: ' || COALESCE(r_cost.name, 'بند تكلفة');
      v_supplier_id := NULL;
      IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
        v_supplier_id := (r_cost.currency_snapshot->>'supplier_id')::uuid;
      END IF;

      IF r_cost.payment_source_type = 'treasury' AND r_cost.treasury_transaction_id IS NULL THEN
        SELECT balance INTO v_current_balance
        FROM public.treasury_balances
        WHERE treasury_id = r_cost.payment_source_id AND currency = r_cost.original_currency
        FOR UPDATE;
        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة للبند %', r_cost.name;
        END IF;
        PERFORM public.spend_custody(r_cost.payment_source_id, r_cost.original_currency, r_cost.original_amount, v_tx_desc, NULL, v_supplier_id, NULL, NULL, NULL);
        SELECT id INTO v_treasury_tx_id FROM public.treasury_transactions
        WHERE treasury_id = r_cost.payment_source_id AND type = 'expense' AND amount = r_cost.original_amount AND currency = r_cost.original_currency
        ORDER BY created_at DESC LIMIT 1;
        UPDATE public.packing_order_cost_items SET treasury_transaction_id = v_treasury_tx_id WHERE id = r_cost.id;
      ELSIF r_cost.payment_source_type = 'bank' AND r_cost.bank_transaction_id IS NULL THEN
        SELECT balance INTO v_current_balance FROM public.bank_accounts WHERE id = r_cost.payment_source_id FOR UPDATE;
        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في البنك للبند %', r_cost.name;
        END IF;
        SELECT (public.withdraw_bank_account(r_cost.payment_source_id::integer, r_cost.original_amount, v_tx_desc, CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END, v_supplier_id::text, NULL)->>'bank_tx_id')::integer INTO v_bank_tx_id;
        UPDATE public.packing_order_cost_items SET bank_transaction_id = v_bank_tx_id WHERE id = r_cost.id;
      END IF;
    END IF;
  END LOOP;

  -- ── H. Resolve GL accounts ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;
  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;
  SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
  SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;
  SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '5040' LIMIT 1;
  IF v_expense_acc IS NULL THEN SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '51101' LIMIT 1; END IF;
  IF v_expense_acc IS NULL THEN SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '6000' LIMIT 1; END IF;
  IF v_finished_inv_acc IS NULL OR v_raw_inv_acc IS NULL THEN
    RAISE EXCEPTION 'حسابات المخزون (1030/1031) غير موجودة في شجرة الحسابات';
  END IF;

  IF v_order.journal_entry_id IS NOT NULL THEN
    DELETE FROM account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;
    DELETE FROM journal_entries WHERE id = v_order.journal_entry_id;
  END IF;

  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status,
    is_auto_generated, source_type, source_id, company_id,
    created_by, created_at, updated_at
  ) VALUES (
    'PENDING',
    COALESCE(v_order.packed_at::date, v_order.created_at::date, CURRENT_DATE),
    'قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text),
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    auth.uid(), now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- DR Finished Goods
  IF v_tot_final_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_je_id, v_finished_inv_acc, v_tot_final_cost, 0, 'EGP', v_tot_final_cost, 'مخزون تام - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);
    v_sum_debit := v_sum_debit + v_tot_final_cost;
  END IF;

  -- CR Raw Materials
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost, 'تحويل مواد خام - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- CR Packaging Materials
  IF v_tot_pkg_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_cost, 'EGP', v_tot_pkg_cost, 'تكلفة تعبئة - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);
    v_sum_credit := v_sum_credit + v_tot_pkg_cost;
  END IF;

  -- CR Overheads (Suppliers/AP or Capitalized Expense)
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;
    v_credit_currency := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');

    IF r_cost.payment_source_type IN ('treasury', 'bank') THEN
       -- Already paid, credit the clearing/expense account to balance the capitalized debit
       v_credit_acc := v_expense_acc;
    ELSE
       -- Unpaid -> Supplier or AP
       IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
         SELECT a.id INTO v_credit_acc
         FROM public.suppliers s
         JOIN public.accounts a ON a.id = s.account_id
         WHERE s.id = (r_cost.currency_snapshot->>'supplier_id')::uuid;
       END IF;
       IF v_credit_acc IS NULL THEN
         SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' LIMIT 1;
       END IF;
    END IF;

    IF v_credit_acc IS NOT NULL THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, r_cost.original_amount,
        v_credit_currency, r_cost.base_amount,
        'مصروفات أمر تعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ' - ' || COALESCE(r_cost.name, ''),
        v_company_id
      );
      v_sum_credit := v_sum_credit + r_cost.base_amount;
    END IF;
  END LOOP;

  -- Balance check
  IF ABS(ROUND(v_sum_debit, 2) - ROUND(v_sum_credit, 2)) > 0.01 THEN
    RAISE EXCEPTION
      'قيد أمر التعبئة غير متوازن: مدين=% دائن=% فرق=%',
      ROUND(v_sum_debit, 2), ROUND(v_sum_credit, 2),
      ROUND(v_sum_debit - v_sum_credit, 2);
  END IF;

  UPDATE public.packing_orders
  SET status = 'completed', journal_entry_id = v_je_id, updated_at = now()
  WHERE id = p_packing_order_id;

  FOR i IN 1..v_n LOOP
    UPDATE public.packing_order_lines
    SET allocated_cost_items = COALESCE(v_line_overhead[i], 0),
        final_cost = COALESCE(v_line_raw[i], 0) + COALESCE(v_line_overhead[i], 0),
        final_unit_cost = CASE WHEN COALESCE(v_line_net[i], 0) > 0 THEN (COALESCE(v_line_raw[i], 0) + COALESCE(v_line_overhead[i], 0)) / v_line_net[i] ELSE 0 END
    WHERE id = v_line_ids[i];
  END LOOP;

  RETURN json_build_object(
    'success', true, 'journal_entry_id', v_je_id,
    'total_final_cost', v_tot_final_cost, 'total_raw_cost', v_tot_raw_cost,
    'total_packaging_cost', v_tot_pkg_cost, 'total_overhead', v_tot_cost_items,
    'lines_count', v_n, 'debit', v_tot_final_cost, 'credit', v_tot_raw_cost + v_tot_pkg_cost + v_tot_cost_items
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
