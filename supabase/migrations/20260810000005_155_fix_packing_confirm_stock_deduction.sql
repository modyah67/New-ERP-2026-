-- Migration 155: Restore stock deduction logic in rpc_confirm_packing_order
-- This fixes the bug where confirming a packing order did not deduct crops and packaging materials.

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
  r_cost                RECORD;
  v_supplier_id         UUID;
  v_tx_desc             TEXT;
  v_current_balance     NUMERIC;
  v_treasury_tx_id      BIGINT;
  v_bank_tx_id          INTEGER;
  v_company_id          UUID;
  v_je_id               BIGINT;
  v_entry_num           TEXT;
  v_finished_inv_acc    BIGINT;
  v_raw_inv_acc         BIGINT;
  v_pkg_inv_acc         BIGINT;
  v_expense_acc         BIGINT;
  v_tot_raw_cost        NUMERIC := 0;
  v_tot_pkg_cost        NUMERIC := 0;
  v_tot_cost_items      NUMERIC := 0;
  v_tot_final_cost      NUMERIC := 0;
  v_line_ids            BIGINT[];
  v_line_raw            NUMERIC[];
  v_line_net            NUMERIC[];
  v_line_specific       NUMERIC[];
  v_line_shared         NUMERIC[];
  v_line_overhead       NUMERIC[];
  v_bases               NUMERIC[];
  v_n                   INT;
  v_i                   INT;
  v_apply_to            TEXT;
  v_amount              NUMERIC;
  v_part                NUMERIC;
  v_assigned            NUMERIC;
  v_target_idx          INT;
  v_sum_debit           NUMERIC := 0;
  v_max_cost_item_id    BIGINT;
  v_product_cost_per_kg NUMERIC;
  v_fruit_qty           NUMERIC;
  v_fruit_cartons       INT;
  v_fruit_net_per_carton NUMERIC;
  v_alloc_el            JSONB;
  v_fruit_alloc         JSONB;
  v_fruit_alloc_arr     JSONB;
  v_allocations         JSONB := '[]'::jsonb;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status NOT IN ('pending', 'in_progress') THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تأكيد أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- ── 0. Deduct Stock Allocations (Fruit and Materials) ──
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR v_i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->v_i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  END IF;

  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id', v_el->>'batch_id',
          'quantity', v_el->>'used_qty',
          'product_name', v_el->>'product_name',
          'product_code', COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM deduct_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- ── A. Sync cost items from notes ──
  IF v_notes ? 'cost_items' THEN
    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;
    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;
    PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_rate := COALESCE(NULLIF((v_el->>'exchange_rate')::numeric, 0), 1.0);
      v_curr := COALESCE(NULLIF(v_el->>'supplier_currency', ''), 'EGP');
      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);
      IF v_amt_egp = 0 THEN v_amt_egp := COALESCE((v_el->>'total')::numeric, 0); END IF;
      IF v_curr = 'EGP' THEN v_amt_foreign := v_amt_egp;
      ELSIF v_rate > 0 THEN v_amt_foreign := ROUND(v_amt_egp / v_rate, 2);
      ELSE v_amt_foreign := v_amt_egp; END IF;

      INSERT INTO public.packing_order_cost_items (
        packing_order_id, name, category, report_category_id,
        original_currency, original_amount, exchange_rate, base_amount,
        currency_snapshot, payment_source_type, payment_source_id,
        allocation_method, target_line_id
      ) VALUES (
        p_packing_order_id,
        COALESCE(v_el->>'name', 'بند تكلفة'),
        CASE
          WHEN v_el->>'category' SIMILAR TO '%(محصول|fruit)%' THEN 'fruit'
          WHEN v_el->>'category' SIMILAR TO '%(تعبئة|تعبئة وتغليف|packing|material)%' THEN 'material'
          WHEN v_el->>'category' SIMILAR TO '%(نقل|شحن|logistics|transport)%' THEN 'logistics'
          ELSE 'other'
        END,
        (v_el->>'report_category_id')::integer,
        v_curr, v_amt_foreign, v_rate, v_amt_egp, v_el,
        v_el->>'payment_source_type',
        NULLIF(v_el->>'payment_source_id', '')::bigint,
        COALESCE(v_el->>'allocation_method', 'BY_NET_WEIGHT'),
        NULLIF(v_el->>'target_line_id', '')::bigint
      );
    END LOOP;
  END IF;

  -- ── B. Load lines ──
  SELECT
    COALESCE(array_agg(pol.id ORDER BY pol.id), ARRAY[]::BIGINT[]),
    COALESCE(array_agg(COALESCE(pol.raw_material_cost, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
    COALESCE(array_agg(COALESCE(pol.total_net_weight, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[])
  INTO v_line_ids, v_line_raw, v_line_net
  FROM public.packing_order_lines pol
  WHERE pol.packing_order_id = p_packing_order_id;

  v_n := array_length(v_line_ids, 1);
  IF v_n IS NULL OR v_n = 0 THEN
    v_fruit_alloc := v_notes->'fruit_allocation';
    IF v_fruit_alloc IS NOT NULL AND jsonb_array_length(v_fruit_alloc) > 0 THEN
      v_fruit_alloc_arr := v_fruit_alloc;
      IF jsonb_typeof(v_fruit_alloc) = 'object' THEN
        v_fruit_alloc_arr := jsonb_build_array(v_fruit_alloc);
      END IF;
      FOR v_alloc_el IN SELECT jsonb_array_elements(v_fruit_alloc_arr)
      LOOP
        v_product_cost_per_kg := COALESCE((v_alloc_el->>'cost_per_kg')::numeric, 0);
        v_fruit_qty := COALESCE((v_alloc_el->>'quantity')::numeric, 0);
        v_fruit_cartons := COALESCE((v_alloc_el->>'cartons')::integer, 0);
        IF v_fruit_cartons > 0 AND COALESCE((v_alloc_el->>'weight_per_carton')::numeric, 0) > 0 THEN
          v_fruit_net_per_carton := (v_alloc_el->>'weight_per_carton')::numeric;
          v_fruit_qty := v_fruit_cartons::numeric * v_fruit_net_per_carton;
        END IF;
        IF v_fruit_qty > 0 AND v_product_cost_per_kg > 0 THEN
          INSERT INTO public.packing_order_lines (
            packing_order_id, product_name, grade, quantity, raw_material_cost,
            total_net_weight, total_gross_weight, carton_count, net_weight_per_carton, gross_weight_per_carton
          ) VALUES (
            p_packing_order_id,
            COALESCE(v_alloc_el->>'product_name', 'محصول'),
            COALESCE(v_alloc_el->>'grade', 'A'),
            v_fruit_qty, v_fruit_qty * v_product_cost_per_kg,
            v_fruit_qty, COALESCE((v_alloc_el->>'gross_weight')::numeric, v_fruit_qty),
            v_fruit_cartons,
            CASE WHEN v_fruit_cartons > 0 THEN v_fruit_qty / v_fruit_cartons ELSE 0 END,
            CASE WHEN v_fruit_cartons > 0 THEN v_fruit_qty / v_fruit_cartons ELSE 0 END
          );
        END IF;
      END LOOP;
      SELECT
        COALESCE(array_agg(pol.id ORDER BY pol.id), ARRAY[]::BIGINT[]),
        COALESCE(array_agg(COALESCE(pol.raw_material_cost, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
        COALESCE(array_agg(COALESCE(pol.total_net_weight, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[])
      INTO v_line_ids, v_line_raw, v_line_net
      FROM public.packing_order_lines pol WHERE pol.packing_order_id = p_packing_order_id;
      v_n := array_length(v_line_ids, 1);
    END IF;
  END IF;

  IF v_n IS NULL OR v_n = 0 THEN
    RETURN json_build_object('success', false, 'error', 'لا توجد خطوط في أمر التعبئة');
  END IF;

  -- ── C. Compute raw cost ──
  FOR i IN 1..v_n LOOP
    v_tot_raw_cost := v_tot_raw_cost + COALESCE(v_line_raw[i], 0);
  END LOOP;

  -- ── D. Initialize allocation arrays ──
  v_line_specific := ARRAY[]::NUMERIC[];
  v_line_shared := ARRAY[]::NUMERIC[];
  v_line_overhead := ARRAY[]::NUMERIC[];
  FOR i IN 1..v_n LOOP
    v_line_specific := array_append(v_line_specific, 0);
    v_line_shared := array_append(v_line_shared, 0);
    v_line_overhead := array_append(v_line_overhead, 0);
  END LOOP;

  -- ── E. Allocate cost items ──
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
    v_amount := COALESCE(r_cost.base_amount, 0);
    v_apply_to := r_cost.category;

    v_bases := ARRAY[]::NUMERIC[];
    FOR i IN 1..v_n LOOP
      IF v_apply_to = 'fruit' THEN
        v_bases := array_append(v_bases, COALESCE(v_line_net[i], 0));
      ELSIF v_apply_to = 'material' THEN
        v_bases := array_append(v_bases, COALESCE(v_line_raw[i], 0));
      ELSE
        v_bases := array_append(v_bases, COALESCE(v_line_net[i], 0) + COALESCE(v_line_raw[i], 0));
      END IF;
    END LOOP;

    IF r_cost.target_line_id IS NOT NULL THEN
      v_target_idx := NULL;
      FOR i IN 1..v_n LOOP
        IF v_line_ids[i] = r_cost.target_line_id THEN v_target_idx := i; EXIT; END IF;
      END LOOP;
      IF v_target_idx IS NOT NULL THEN
        v_line_specific[v_target_idx] := v_line_specific[v_target_idx] + v_amount;
        CONTINUE;
      END IF;
    END IF;

    v_assigned := 0;
    v_sum_debit := 0;
    FOR i IN 1..v_n LOOP v_sum_debit := v_sum_debit + v_bases[i]; END LOOP;
    IF v_sum_debit > 0 THEN
      FOR i IN 1..v_n LOOP
        v_part := ROUND(v_amount * v_bases[i] / v_sum_debit, 2);
        v_line_shared[i] := v_line_shared[i] + v_part;
        v_assigned := v_assigned + v_part;
      END LOOP;
      IF v_assigned != v_amount THEN
        v_line_shared[v_n] := v_line_shared[v_n] + (v_amount - v_assigned);
      END IF;
    END IF;
  END LOOP;

  -- ── F. Compute final cost ──
  v_tot_final_cost := 0;
  FOR i IN 1..v_n LOOP
    v_line_overhead[i] := v_line_specific[i] + v_line_shared[i];
    v_tot_final_cost := v_tot_final_cost + v_line_raw[i] + v_line_overhead[i];
  END LOOP;

  -- ── G. Process payments ──
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL THEN
      v_supplier_id := (r_cost.currency_snapshot->>'supplier_id')::uuid;
    END IF;
    v_tx_desc := COALESCE(r_cost.name, 'تكلفة') || ' - أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text);

    IF v_supplier_id IS NOT NULL THEN
      UPDATE public.suppliers
      SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.original_amount, updated_at = now()
      WHERE id = v_supplier_id;
    END IF;

    IF r_cost.payment_source_type IS NOT NULL AND r_cost.payment_source_id IS NOT NULL
       AND r_cost.treasury_transaction_id IS NULL AND r_cost.bank_transaction_id IS NULL THEN
      IF r_cost.payment_source_type = 'treasury' THEN
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
      ELSIF r_cost.payment_source_type = 'bank' THEN
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

  INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
  VALUES (v_je_id, v_finished_inv_acc, v_tot_final_cost, 0, 'EGP', v_tot_final_cost, '成品库存 - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);

  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost, 'تحويل مواد خام - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);
  END IF;

  IF v_tot_cost_items > 0 THEN
    v_tot_pkg_cost := 0;
    FOR r_cost IN SELECT base_amount FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id AND category = 'material'
    LOOP v_tot_pkg_cost := v_tot_pkg_cost + COALESCE(r_cost.base_amount, 0); END LOOP;
    IF v_tot_pkg_cost > 0 THEN
      INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
      VALUES (v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_cost, 'EGP', v_tot_pkg_cost, 'تكلفة تعبئة - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);
    END IF;
    IF v_tot_cost_items - v_tot_pkg_cost > 0 THEN
      INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
      VALUES (v_je_id, v_expense_acc, 0, v_tot_cost_items - v_tot_pkg_cost, 'EGP', v_tot_cost_items - v_tot_pkg_cost, 'مصاريف أخرى - أمر تعبئة ' || COALESCE(v_order.order_number, ''), v_company_id);
    END IF;
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
    'total_packaging_cost', v_tot_pkg_cost, 'total_overhead', v_tot_cost_items - v_tot_pkg_cost,
    'lines_count', v_n, 'debit', v_tot_final_cost, 'credit', v_tot_raw_cost + v_tot_cost_items
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated;
