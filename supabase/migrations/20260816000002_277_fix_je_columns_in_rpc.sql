BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(p_packing_order_id BIGINT)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order               RECORD;
  v_notes               JSONB;
  v_el                  JSONB;
  v_line_ids            BIGINT[];
  v_line_net            NUMERIC[];
  v_line_raw            NUMERIC[];
  v_line_overhead       NUMERIC[];
  v_n                   INTEGER;
  v_tot_net             NUMERIC := 0;
  v_tot_raw_cost        NUMERIC := 0;
  v_tot_cost_items      NUMERIC := 0;
  v_tot_pkg_cost        NUMERIC := 0;
  v_tot_final_cost      NUMERIC := 0;
  v_amt_egp             NUMERIC := 0;
  v_target_line_idx     INTEGER;
  v_supplier_id         UUID;
  v_max_cost_item_id    BIGINT;

  v_company_id          UUID;
  v_season_id           UUID;
  v_je_id               BIGINT;
  v_entry_number        TEXT;
  v_sum_debit           NUMERIC := 0;
  v_sum_credit          NUMERIC := 0;
  
  -- Account mapping records
  r_stock               RECORD;
  r_sales_cost          RECORD;
  r_cost                RECORD;
  
  v_base_currency       TEXT;
  v_debit_currency      TEXT;
  v_credit_currency     TEXT;
  
  v_supplier_acct_id    BIGINT;
  v_expense_acct_id     BIGINT;
  v_bank_acct_id        BIGINT;
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
            'quantity', (v_el->>'quantity')::numeric,
            'unit_price', (v_el->>'unit_price')::numeric,
            'exchange_rate', (v_el->>'exchange_rate')::numeric
          )
        );
        v_tot_cost_items := v_tot_cost_items + v_amt_egp;
      END IF;
    END LOOP;
  ELSE
    -- If no cost items, calculate tot_cost_items from the existing table just in case they were added directly
    SELECT COALESCE(SUM(base_amount), 0) INTO v_tot_cost_items
    FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- ── D. Collect Lines & Distribute Costs ──
  SELECT
    array_agg(id ORDER BY id),
    array_agg(COALESCE(total_net_weight, 0) ORDER BY id),
    array_agg(COALESCE(raw_material_cost, 0) ORDER BY id)
  INTO v_line_ids, v_line_net, v_line_raw
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;

  v_n := COALESCE(array_length(v_line_ids, 1), 0);
  IF v_n = 0 THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة لا يحتوي على بنود مخرجات');
  END IF;

  FOR i IN 1..v_n LOOP
    v_tot_net := v_tot_net + v_line_net[i];
    v_tot_raw_cost := v_tot_raw_cost + v_line_raw[i];
    v_line_overhead[i] := 0;
  END LOOP;

  -- Accumulate overall packaging costs (from line.packaging_cost)
  SELECT COALESCE(SUM(COALESCE(specific_packaging_cost, 0) + COALESCE(allocated_shared_packaging, 0)), 0) INTO v_tot_pkg_cost
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;

  -- Distribute ALL cost items across lines
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_method := COALESCE(r_cost.allocation_method, 'BY_NET_WEIGHT');

    IF v_method = 'DIRECT' AND r_cost.target_line_id IS NOT NULL THEN
      IF r_cost.target_line_id >= 0 AND r_cost.target_line_id < v_n THEN
        v_line_overhead[r_cost.target_line_id + 1] := v_line_overhead[r_cost.target_line_id + 1] + r_cost.base_amount;
      END IF;
      CONTINUE;
    END IF;

    IF v_method = 'EQUAL' THEN
      FOR i IN 1..v_n LOOP
        v_shares[i] := 1.0;
      END LOOP;
    ELSIF v_method = 'BY_RAW_COST' THEN
      v_bases := v_line_raw;
    ELSE
      v_bases := v_line_net;
    END IF;

    IF v_method IN ('BY_RAW_COST', 'BY_NET_WEIGHT') THEN
      DECLARE
        sum_base NUMERIC := 0;
      BEGIN
        FOR i IN 1..v_n LOOP sum_base := sum_base + v_bases[i]; END LOOP;
        IF sum_base > 0 THEN
          FOR i IN 1..v_n LOOP v_shares[i] := v_bases[i] / sum_base; END LOOP;
        ELSE
          FOR i IN 1..v_n LOOP v_shares[i] := 1.0 / v_n; END LOOP;
        END IF;
      END;
    END IF;

    IF v_method = 'EQUAL' THEN
      FOR i IN 1..v_n LOOP v_shares[i] := 1.0 / v_n; END LOOP;
    END IF;

    FOR i IN 1..v_n LOOP
      v_line_overhead[i] := v_line_overhead[i] + (r_cost.base_amount * v_shares[i]);
    END LOOP;
  END LOOP;

  FOR i IN 1..v_n LOOP
    v_tot_final_cost := v_tot_final_cost + v_line_raw[i] + v_tot_pkg_cost/v_n + v_line_overhead[i];
  END LOOP;

  -- ── E. Create Journal Entry ──
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  SELECT base_currency INTO v_base_currency FROM public.accounting_settings LIMIT 1;

  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status,
    is_auto_generated, source_type, source_id, company_id,
    created_by, created_at, updated_at
  ) VALUES (
    'PENDING',
    COALESCE(v_order.packed_at::date, v_order.created_at::date, CURRENT_DATE),
    'قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text),
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    v_order.created_by, now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_number := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
  UPDATE public.journal_entries SET entry_number = v_entry_number WHERE id = v_je_id;

  -- 1) Debit: Finished Goods Inventory
  SELECT * INTO r_stock FROM public.accounts WHERE code = '1133' LIMIT 1;
  IF FOUND THEN
    v_debit_currency := COALESCE(r_stock.currency, v_base_currency);
    INSERT INTO public.journal_entry_lines (
      journal_entry_id, account_id, is_debit, currency, amount, description, company_id
    ) VALUES (
      v_je_id, r_stock.id, true, v_debit_currency, v_tot_final_cost,
      'تكلفة منتج تام لأمر التعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text),
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_final_cost;
  END IF;

  -- 2) Credit: Raw Materials/Fruits Cost
  SELECT * INTO r_sales_cost FROM public.accounts WHERE code = '1131' LIMIT 1;
  IF FOUND THEN
    v_credit_currency := COALESCE(r_sales_cost.currency, v_base_currency);
    INSERT INTO public.journal_entry_lines (
      journal_entry_id, account_id, is_debit, currency, amount, description, company_id
    ) VALUES (
      v_je_id, r_sales_cost.id, false, v_credit_currency, v_tot_raw_cost,
      'تكلفة محاصيل لأمر التعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text),
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- 3) Credit: Packaging Materials Cost
  SELECT * INTO r_stock FROM public.accounts WHERE code = '1132' LIMIT 1;
  IF FOUND THEN
    v_credit_currency := COALESCE(r_stock.currency, v_base_currency);
    INSERT INTO public.journal_entry_lines (
      journal_entry_id, account_id, is_debit, currency, amount, description, company_id
    ) VALUES (
      v_je_id, r_stock.id, false, v_credit_currency, v_tot_pkg_cost,
      'تكلفة مواد التعبئة لأمر التعبئة ' || COALESCE(v_order.order_number, p_packing_order_id::text),
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_cost;
  END IF;

  -- 4) Credit: Various Cost Items (Suppliers, Treasuries, etc)
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    IF r_cost.base_amount > 0 THEN
      v_supplier_id := (r_cost.currency_snapshot->>'supplier_id')::uuid;
      v_supplier_acct_id := NULL;
      
      -- Resolve Account
      IF r_cost.payment_source_type = 'treasury' THEN
        SELECT account_id INTO v_supplier_acct_id FROM public.treasuries WHERE id = r_cost.payment_source_id;
      ELSIF r_cost.payment_source_type = 'bank' THEN
        SELECT account_id INTO v_supplier_acct_id FROM public.bank_accounts WHERE id = r_cost.payment_source_id;
      ELSIF v_supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_supplier_acct_id FROM public.suppliers WHERE id = v_supplier_id;
      ELSE
        -- Fallback to default supplier accounts
        IF r_cost.category = 'logistics' THEN
          SELECT id INTO v_supplier_acct_id FROM public.accounts WHERE code = '2123' LIMIT 1;
        ELSIF r_cost.category = 'material' THEN
          SELECT id INTO v_supplier_acct_id FROM public.accounts WHERE code = '2122' LIMIT 1;
        ELSIF r_cost.category = 'fruit' THEN
          SELECT id INTO v_supplier_acct_id FROM public.accounts WHERE code = '2121' LIMIT 1;
        ELSE
          SELECT id INTO v_supplier_acct_id FROM public.accounts WHERE code = '2124' LIMIT 1;
        END IF;
      END IF;

      -- Determine currency
      SELECT currency INTO v_credit_currency FROM public.accounts WHERE id = v_supplier_acct_id;
      IF NOT FOUND THEN
        v_credit_currency := v_base_currency;
      END IF;

      INSERT INTO public.journal_entry_lines (
        journal_entry_id, account_id, is_debit, currency, amount, description, company_id
      ) VALUES (
        v_je_id, v_supplier_acct_id, false,
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

COMMIT;
