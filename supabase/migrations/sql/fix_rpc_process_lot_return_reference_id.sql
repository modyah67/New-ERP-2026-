DROP FUNCTION IF EXISTS public.rpc_process_lot_return(bigint, numeric, numeric, text, uuid, bigint, text, bigint) CASCADE;
DROP FUNCTION IF EXISTS public.rpc_process_lot_return CASCADE;

CREATE OR REPLACE FUNCTION public.rpc_process_lot_return(
  p_lot_id bigint,
  p_return_quantity numeric,
  p_return_price numeric DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_user_id uuid DEFAULT NULL,
  p_batch_id bigint DEFAULT NULL,
  p_cost_center_id text DEFAULT NULL,
  p_station_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot record;
  v_unit_cost numeric;
  v_return_value numeric;
  v_return_value_egp numeric;
  v_return_id bigint;
  v_target_station bigint;
  v_product_name text;
  v_company_id uuid;
  v_inventory_account_id bigint;
  v_supplier_leaf_account_id bigint;
  v_je_id bigint;
  v_desc text;
  v_cur text;
  v_supplier_name text;
  v_cc_id text;
  v_cc_name text;
  v_net_qty numeric;
  v_already_returned numeric;
  v_available_qty numeric;
  v_rem_to_deduct numeric;
  v_deduct numeric;
  r_batch record;
  v_total_batch_remaining numeric;
  v_unit_label text;
BEGIN
  -- 1. Load lot and validate
  SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'اللوط رقم % غير موجود', p_lot_id;
  END IF;

  v_target_station := COALESCE(p_station_id, v_lot.station_id);

  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' AND COALESCE(v_lot.carton_count, 0) > 0 THEN
    v_unit_label := 'كرتونة';
    IF COALESCE(v_lot.weight_per_carton_kg, 0) > 0 AND COALESCE(v_lot.net_weight_kg, 0) > 0
       AND ROUND((v_lot.net_weight_kg / v_lot.weight_per_carton_kg)::numeric, 0) > 0
       AND ROUND((v_lot.net_weight_kg / v_lot.weight_per_carton_kg)::numeric, 0) <= COALESCE(v_lot.carton_count, 999999999) THEN
      v_net_qty := ROUND((v_lot.net_weight_kg / v_lot.weight_per_carton_kg)::numeric, 0);
    ELSE
      v_net_qty := v_lot.carton_count;
    END IF;
  ELSE
    v_unit_label := 'كجم';
    v_net_qty := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);
  END IF;

  SELECT COALESCE(SUM(returned_quantity), 0) INTO v_already_returned
  FROM lot_returns
  WHERE lot_receipt_id = p_lot_id;

  v_available_qty := GREATEST(0, v_net_qty - v_already_returned);

  IF p_return_quantity <= 0 THEN
    RAISE EXCEPTION 'يجب أن تكون الكمية المرتجعة أكبر من الصفر';
  END IF;

  IF p_return_quantity > v_available_qty THEN
    RAISE EXCEPTION 'الكمية المرتجعة (%) أكبر من الكمية المتاحة للإرجاع (%) بالصافي المخزني', p_return_quantity, v_available_qty;
  END IF;

  -- Compute unit cost & value
  IF p_return_price IS NOT NULL AND p_return_price > 0 THEN
    v_unit_cost := p_return_price;
  ELSIF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' AND COALESCE(v_lot.price_per_carton, 0) > 0 THEN
    v_unit_cost := v_lot.price_per_carton;
  ELSIF COALESCE(v_lot.total_fruit_cost, 0) > 0 AND v_net_qty > 0 THEN
    v_unit_cost := ROUND((v_lot.total_fruit_cost / v_net_qty)::numeric, 2);
  ELSIF COALESCE(v_lot.fruit_cost_per_kg, 0) > 0 THEN
    v_unit_cost := v_lot.fruit_cost_per_kg;
  ELSE
    v_unit_cost := 0;
  END IF;

  v_return_value := ROUND((p_return_quantity * v_unit_cost)::numeric, 2);
  v_product_name := COALESCE(v_lot.product_name, 'محصول');
  v_cur := COALESCE(NULLIF(v_lot.currency, ''), 'EGP');

  -- Resolve company_id reliably
  v_company_id := v_lot.company_id;
  IF v_company_id IS NULL AND v_lot.supplier_id IS NOT NULL THEN
    SELECT company_id INTO v_company_id FROM public.suppliers WHERE id = v_lot.supplier_id;
  END IF;
  IF v_company_id IS NULL AND v_target_station IS NOT NULL THEN
    SELECT company_id INTO v_company_id FROM public.stations WHERE id = v_target_station;
  END IF;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;

  -- 2. Insert lot_return record
  INSERT INTO lot_returns (
    lot_receipt_id,
    supplier_id,
    station_id,
    returned_quantity,
    return_value,
    notes,
    created_by,
    created_at,
    company_id,
    lot_number
  ) VALUES (
    v_lot.id,
    v_lot.supplier_id,
    v_target_station,
    p_return_quantity,
    v_return_value,
    p_notes,
    p_user_id,
    now(),
    v_company_id,
    COALESCE(v_lot.lot_number, v_lot.id::text)
  )
  RETURNING id INTO v_return_id;

  -- 2.b Deduct from FIFO station_product_batches (Precise Batch Reduction: ONLY remaining_quantity)
  v_rem_to_deduct := p_return_quantity;

  -- Substep A: Deduct from explicitly selected batch
  IF p_batch_id IS NOT NULL AND p_batch_id > 0 THEN
    SELECT id, quantity, remaining_quantity INTO r_batch
    FROM public.station_product_batches
    WHERE id = p_batch_id
    FOR UPDATE;

    IF FOUND THEN
      v_deduct := LEAST(r_batch.remaining_quantity, v_rem_to_deduct);
      IF v_deduct > 0 THEN
        UPDATE public.station_product_batches
        SET remaining_quantity = remaining_quantity - v_deduct,
            updated_at = NOW()
        WHERE id = r_batch.id;

        v_rem_to_deduct := v_rem_to_deduct - v_deduct;
      END IF;
    END IF;
  END IF;

  -- Substep B: If still needed (or p_batch_id was NULL), cascade across original purchase lot receipt batches
  IF v_rem_to_deduct > 0 THEN
    FOR r_batch IN (
      SELECT id, quantity, remaining_quantity
      FROM public.station_product_batches
      WHERE source_type = 'lot_receipt'
        AND (product_code = v_lot.lot_number OR product_code = v_lot.id::text)
        AND (p_batch_id IS NULL OR id <> p_batch_id)
        AND remaining_quantity > 0
      ORDER BY source_date ASC, created_at ASC, id ASC
      FOR UPDATE
    ) LOOP
      IF v_rem_to_deduct <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(r_batch.remaining_quantity, v_rem_to_deduct);
      IF v_deduct > 0 THEN
        UPDATE public.station_product_batches
        SET remaining_quantity = remaining_quantity - v_deduct,
            updated_at = NOW()
        WHERE id = r_batch.id;

        v_rem_to_deduct := v_rem_to_deduct - v_deduct;
      END IF;
    END LOOP;
  END IF;

  -- Substep C: If still needed, cascade across any remaining fruit batches at the target station
  IF v_rem_to_deduct > 0 AND v_target_station IS NOT NULL THEN
    FOR r_batch IN (
      SELECT id, quantity, remaining_quantity
      FROM public.station_product_batches
      WHERE (p_batch_id IS NULL OR id <> p_batch_id)
        AND station_id = v_target_station
        AND (
          (v_lot.fruit_type_id IS NOT NULL AND fruit_type_id = v_lot.fruit_type_id)
          OR product_name = v_lot.product_name
          OR product_code = v_lot.lot_number
        )
        AND remaining_quantity > 0
      ORDER BY source_date ASC, created_at ASC, id ASC
      FOR UPDATE
    ) LOOP
      IF v_rem_to_deduct <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(r_batch.remaining_quantity, v_rem_to_deduct);
      IF v_deduct > 0 THEN
        UPDATE public.station_product_batches
        SET remaining_quantity = remaining_quantity - v_deduct,
            updated_at = NOW()
        WHERE id = r_batch.id;

        v_rem_to_deduct := v_rem_to_deduct - v_deduct;
      END IF;
    END LOOP;
  END IF;

  -- Substep D: Synchronize station_products net quantity
  IF v_target_station IS NOT NULL THEN
    SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_total_batch_remaining
    FROM public.station_product_batches
    WHERE station_id = v_target_station
      AND (
        (v_lot.fruit_type_id IS NOT NULL AND fruit_type_id = v_lot.fruit_type_id)
        OR (v_lot.fruit_type_id IS NULL AND product_name = v_lot.product_name)
      );

    IF v_total_batch_remaining > 0 THEN
      UPDATE public.station_products
      SET quantity = v_total_batch_remaining,
          item_type = 'fruit',
          fruit_type_id = COALESCE(fruit_type_id, v_lot.fruit_type_id),
          updated_at = NOW()
      WHERE station_id = v_target_station
        AND (item_type = 'fruit' OR item_type IS NULL)
        AND raw_material_id IS NULL
        AND (
          (fruit_type_id IS NOT NULL AND fruit_type_id = v_lot.fruit_type_id)
          OR (v_lot.fruit_type_id IS NULL AND product_name = v_lot.product_name)
          OR (product_code = v_lot.lot_number AND product_name = v_lot.product_name)
        );

      IF NOT FOUND THEN
        IF v_lot.fruit_type_id IS NOT NULL THEN
          INSERT INTO public.station_products (
            station_id, item_type, fruit_type_id, product_name, product_code, quantity, unit, updated_at
          ) VALUES (
            v_target_station,
            'fruit',
            v_lot.fruit_type_id,
            v_lot.product_name,
            COALESCE(v_lot.lot_number, ''),
            v_total_batch_remaining,
            CASE WHEN COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN 'carton' ELSE 'kg' END,
            NOW()
          );
        ELSE
          INSERT INTO public.station_products (
            station_id, item_type, product_name, product_code, quantity, unit, updated_at
          ) VALUES (
            v_target_station,
            'fruit',
            v_lot.product_name,
            COALESCE(v_lot.lot_number, ''),
            v_total_batch_remaining,
            CASE WHEN COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN 'carton' ELSE 'kg' END,
            NOW()
          );
        END IF;
      END IF;
    ELSE
      -- Fallback decrement rather than zeroing out blindly
      UPDATE public.station_products
      SET quantity = GREATEST(0, quantity - p_return_quantity),
          item_type = 'fruit',
          fruit_type_id = COALESCE(fruit_type_id, v_lot.fruit_type_id),
          updated_at = NOW()
      WHERE station_id = v_target_station
        AND (item_type = 'fruit' OR item_type IS NULL)
        AND raw_material_id IS NULL
        AND (
          (fruit_type_id IS NOT NULL AND fruit_type_id = v_lot.fruit_type_id)
          OR (v_lot.fruit_type_id IS NULL AND product_name = v_lot.product_name)
          OR (product_code = v_lot.lot_number AND product_name = v_lot.product_name)
        );
    END IF;
  END IF;

  -- Substep E: Audit entry into stock_movements if available
  BEGIN
    INSERT INTO public.stock_movements (
      movement_type,
      product_id,
      batch_id,
      quantity,
      before_quantity,
      after_quantity,
      unit_cost,
      total_cost,
      reference_type,
      reference_id,
      description,
      user_id,
      created_at
    ) VALUES (
      'return',
      NULL,
      p_batch_id,
      -p_return_quantity,
      v_total_batch_remaining + p_return_quantity,
      v_total_batch_remaining,
      v_unit_cost,
      -v_return_value,
      'lot_return',
      v_return_id::text,
      'مرتجع شراء محصول (صافي المخزن) - ' || v_product_name || ' (' || p_return_quantity || ' ' || v_unit_label || ')',
      p_user_id,
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- 3. GL Accounting
  v_inventory_account_id := public.resolve_gl_account('1030', v_company_id);
  IF v_inventory_account_id IS NULL THEN
    SELECT a.id INTO v_inventory_account_id
    FROM accounts a
    WHERE a.account_code = '1030' AND a.company_id = v_company_id
    LIMIT 1;

    IF v_inventory_account_id IS NULL THEN
      SELECT a.id INTO v_inventory_account_id
      FROM accounts a
      WHERE a.account_code = '1030'
      LIMIT 1;
    END IF;
  END IF;

  v_supplier_leaf_account_id := NULL;
  IF v_lot.supplier_id IS NOT NULL THEN
    SELECT s.account_id INTO v_supplier_leaf_account_id
    FROM suppliers s
    WHERE s.id = v_lot.supplier_id;
  END IF;

  IF v_supplier_leaf_account_id IS NULL THEN
    SELECT a.id INTO v_supplier_leaf_account_id
    FROM accounts a
    WHERE a.account_code = '2000' AND a.company_id = v_company_id
    LIMIT 1;

    IF v_supplier_leaf_account_id IS NULL THEN
      SELECT a.id INTO v_supplier_leaf_account_id
      FROM accounts a
      WHERE a.account_code = '2000'
      LIMIT 1;
    END IF;
  END IF;

  IF v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN
    v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
    v_desc := 'مرتجع شراء محصول ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT) || ' (' || p_return_quantity || ' ' || v_unit_label || ' صافي مخزني)';

    v_je_id := public.post_journal_entry(
      p_company_id := v_company_id,
      p_entry_date := CURRENT_DATE,
      p_source_type := 'lot_return',
      p_description := v_desc,
      p_created_by := p_user_id,
      p_lines := jsonb_build_array(
        jsonb_build_object(
          'account_id', v_supplier_leaf_account_id,
          'debit', v_return_value,
          'credit', 0,
          'base_debit', v_return_value_egp,
          'base_credit', 0,
          'currency', v_cur,
          'amount_in_base_currency', v_return_value_egp,
          'description', 'تخفيض حساب المورد - ' || v_desc
        ),
        jsonb_build_object(
          'account_id', v_inventory_account_id,
          'debit', 0,
          'credit', v_return_value_egp,
          'base_debit', 0,
          'base_credit', v_return_value_egp,
          'currency', 'EGP',
          'amount_in_base_currency', v_return_value_egp,
          'description', 'تخفيض مخزون المحاصيل المرتجعة - ' || v_desc
        )
      ),
      p_source_id := v_return_id::TEXT
    );

    IF v_je_id IS NOT NULL THEN
      UPDATE lot_returns
      SET journal_entry_id = v_je_id
      WHERE id = v_return_id;
    END IF;
  END IF;

  -- 4. Supplier Ledger & Balance Update
  IF v_lot.supplier_id IS NOT NULL THEN
    v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    UPDATE public.suppliers
    SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - v_return_value_egp),
        current_balances_by_currency = jsonb_set(
          COALESCE(current_balances_by_currency, '{}'::jsonb),
          array[v_cur],
          to_jsonb(COALESCE((current_balances_by_currency->>v_cur)::numeric, 0) - v_return_value)
        ),
        updated_at = now()
    WHERE id = v_lot.supplier_id;

    -- Insert into ledger_entries (table queried by Supplier Statement)
    INSERT INTO public.ledger_entries (
      entity_type,
      entity_id,
      entry_type,
      amount,
      currency,
      reference_type,
      reference_id,
      reference_text,
      description,
      created_by,
      created_at
    ) VALUES (
      'supplier',
      v_lot.supplier_id::TEXT,
      'debit',
      v_return_value,
      v_cur,
      'lot_return',
      v_return_id::INTEGER,
      v_return_id::TEXT,
      COALESCE(p_notes, 'مرتجع شراء محصول - لوط #' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)),
      p_user_id,
      now()
    );

    BEGIN
      INSERT INTO public.supplier_ledger (
        supplier_id,
        transaction_date,
        transaction_type,
        amount,
        balance_after,
        reference_id,
        notes,
        created_at
      ) VALUES (
        v_lot.supplier_id,
        CURRENT_DATE,
        'lot_return',
        -v_return_value,
        0,
        v_return_id::text,
        COALESCE(p_notes, 'مرتجع شراء محصول - لوط #' || COALESCE(v_lot.lot_number, v_lot.id::text)),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  -- 5. Unified Cost Center Resolution
  v_cc_id := NULL;
  v_cc_name := NULL;

  SELECT cct.cost_center_id, cct.cost_center_name
  INTO v_cc_id, v_cc_name
  FROM public.cost_center_transactions cct
  WHERE cct.source_type = 'lot_receipt'
    AND cct.source_id = v_lot.id::text
    AND cct.cost_center_id IS NOT NULL
    AND cct.cost_center_name NOT LIKE 'خط %'
  LIMIT 1;

  IF v_cc_id IS NULL OR v_cc_id = '' THEN
    SELECT r.cost_center_id, r.cost_center_name
    INTO v_cc_id, v_cc_name
    FROM public.fn_resolve_active_crop_cost_center(
      COALESCE(v_lot.product_name, v_product_name, 'محصول'),
      v_lot.fruit_type_id
    ) r;
  END IF;

  IF (v_cc_id IS NULL OR v_cc_id = '') AND p_cost_center_id IS NOT NULL AND TRIM(p_cost_center_id) <> '' THEN
    SELECT code, name_ar INTO v_cc_id, v_cc_name
    FROM public.cost_centers
    WHERE (code = p_cost_center_id OR id::text = p_cost_center_id)
    LIMIT 1;
  END IF;

  IF v_cc_id IS NULL OR v_cc_id = '' THEN
    SELECT r.cost_center_id, r.cost_center_name
    INTO v_cc_id, v_cc_name
    FROM public.fn_resolve_active_crop_cost_center(
      COALESCE(v_lot.product_name, v_product_name, 'محصول'),
      v_lot.fruit_type_id
    ) r;
  END IF;

  UPDATE public.cost_center_transactions
  SET cost_center_id = v_cc_id,
      cost_center_name = v_cc_name,
      updated_at = NOW()
  WHERE source_type = 'lot_receipt'
    AND source_id = v_lot.id::text
    AND (cost_center_id <> v_cc_id OR cost_center_name LIKE 'خط %');

  -- 6. Offsetting Cost Center Transaction
  IF v_cc_id IS NOT NULL AND v_cc_id <> '' THEN
    IF v_lot.supplier_id IS NOT NULL THEN
      SELECT name INTO v_supplier_name FROM public.suppliers WHERE id = v_lot.supplier_id;
    END IF;

    v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    INSERT INTO public.cost_center_transactions (
      cost_center_id,
      cost_center_name,
      cost_center_type,
      source_type,
      source_id,
      transaction_date,
      supplier_id,
      supplier_name,
      product_id,
      item_name,
      category,
      quantity,
      unit_price,
      currency,
      exchange_rate,
      total_in_currency,
      amount,
      notes,
      is_confirmed,
      company_id
    ) VALUES (
      v_cc_id,
      v_cc_name,
      'variety',
      'lot_return',
      v_return_id::text,
      CURRENT_DATE,
      v_lot.supplier_id::text,
      v_supplier_name,
      v_lot.fruit_type_id,
      v_product_name,
      'تكلفة المحاصيل',
      -p_return_quantity,
      v_unit_cost,
      v_cur,
      COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0),
      -v_return_value,
      -v_return_value_egp,
      COALESCE(p_notes, 'مرتجع شراء محصول (صافي المخزن) - لوط #' || COALESCE(v_lot.lot_number, v_lot.id::text)),
      TRUE,
      v_company_id
    )
    ON CONFLICT (source_type, source_id) DO UPDATE SET
      cost_center_id = EXCLUDED.cost_center_id,
      cost_center_name = EXCLUDED.cost_center_name,
      cost_center_type = EXCLUDED.cost_center_type,
      quantity = EXCLUDED.quantity,
      unit_price = EXCLUDED.unit_price,
      total_in_currency = EXCLUDED.total_in_currency,
      amount = EXCLUDED.amount,
      company_id = EXCLUDED.company_id,
      updated_at = NOW();
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'return_id', v_return_id,
    'lot_id', p_lot_id,
    'returned_quantity', p_return_quantity,
    'unit_label', v_unit_label,
    'remaining_available_quantity', v_available_qty - p_return_quantity,
    'return_value', v_return_value,
    'journal_entry_id', v_je_id,
    'cost_center_id', v_cc_id,
    'cost_center_name', v_cc_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_lot_return(bigint, numeric, numeric, text, uuid, bigint, text, bigint) TO authenticated, anon, service_role;
