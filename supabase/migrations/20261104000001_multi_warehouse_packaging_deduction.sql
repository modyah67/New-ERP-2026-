-- ============================================================================
-- Migration: 20261104000001_multi_warehouse_packaging_deduction.sql
-- Description: Enable multi-warehouse packaging material stock deduction in packing orders.
--              Ensures each batch is deducted from its respective warehouse and
--              recalculates station_products for every affected warehouse.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_packaging(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_station_id INT;
  v_company_id UUID;

  v_tot_pkg_drawn NUMERIC := 0;
  v_mat_waste_pct NUMERIC := 0;
  v_tot_pkg_waste NUMERIC := 0;
  v_tot_pkg_consumed NUMERIC := 0;

  v_finished_inv_acc INT;
  v_pkg_inv_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_el JSONB;
  v_batch_id BIGINT;
  v_used_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_el_station_id INT;
  v_batch_st_id INT;
  v_deducted_station_id INT;
  v_curr_rem NUMERIC;
  v_rem_needed NUMERIC;
  r_b RECORD;
  v_take NUMERIC;
  v_sp_qty NUMERIC;

  v_target_cc_id TEXT;
  v_target_cc_name TEXT;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Validate prerequisite: crops must be confirmed first
  IF v_order.status IN ('draft', 'pending') THEN
    RETURN json_build_object('success', false, 'error', 'يجب تأكيد المحصول أولاً قبل تأكيد مواد التعبئة');
  END IF;

  -- Idempotency check: only block if the order has already been final approved / completed
  IF v_order.status IN ('final_approved', 'completed') THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة معتمد نهائياً ومقفل بالكامل',
      'status', v_order.status,
      'journal_entry_id', v_order.packaging_journal_entry_id
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
  v_station_id := v_order.station_id;

  -- Resolve Target Variety Cost Center
  v_target_cc_id := NULL;
  v_target_cc_name := NULL;

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' AND jsonb_array_length(v_notes->'materials') > 0 THEN
    v_target_cc_id := v_notes->'materials'->0->>'cost_center_id';
    v_target_cc_name := v_notes->'materials'->0->>'cost_center_name';
  END IF;

  IF v_target_cc_id IS NULL OR v_target_cc_id = '' THEN
    SELECT id, name_ar INTO v_target_cc_id, v_target_cc_name
    FROM public.cost_centers
    WHERE (name_ar = v_order.product_name OR name_ar ILIKE '%' || v_order.product_name || '%')
      AND (is_closed IS FALSE OR is_closed IS NULL)
    ORDER BY id ASC LIMIT 1;
  END IF;

  IF v_target_cc_id IS NULL OR v_target_cc_id = '' THEN
    SELECT id, name_ar INTO v_target_cc_id, v_target_cc_name
    FROM public.cost_centers
    WHERE name_ar = v_order.product_name OR name_ar ILIKE '%' || v_order.product_name || '%'
    ORDER BY id ASC LIMIT 1;
  END IF;

  -- 1. Deduct Materials Inventory (Multi-Warehouse Supported)
  DECLARE
    v_mat_array JSONB := '[]'::jsonb;
  BEGIN
    IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
      v_mat_array := v_notes->'materials';
    ELSIF v_notes ? 'material_items' AND jsonb_typeof(v_notes->'material_items') = 'array' THEN
      v_mat_array := v_notes->'material_items';
    END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_mat_array)
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'used_qty')::numeric, (v_el->>'quantity')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';
      v_el_station_id := (v_el->>'station_id')::int;
      v_deducted_station_id := COALESCE(v_el_station_id, v_station_id);

      IF v_used_qty > 0 THEN
        IF v_batch_id IS NOT NULL AND v_batch_id > 0 THEN
          SELECT remaining_quantity, station_id INTO v_curr_rem, v_batch_st_id
          FROM public.station_product_batches
          WHERE id = v_batch_id
          FOR UPDATE;

          IF FOUND THEN
            v_deducted_station_id := COALESCE(v_batch_st_id, v_deducted_station_id);
            IF v_curr_rem >= v_used_qty THEN
              UPDATE public.station_product_batches
              SET remaining_quantity = remaining_quantity - v_used_qty
              WHERE id = v_batch_id;
            ELSE
              -- Deduct remaining available in this batch
              UPDATE public.station_product_batches
              SET remaining_quantity = 0
              WHERE id = v_batch_id;

              v_rem_needed := v_used_qty - v_curr_rem;
              FOR r_b IN (
                SELECT id, remaining_quantity
                FROM public.station_product_batches
                WHERE station_id = v_deducted_station_id
                  AND id != v_batch_id
                  AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode))
                  AND remaining_quantity > 0
                ORDER BY id ASC
                FOR UPDATE
              ) LOOP
                IF v_rem_needed <= 0 THEN EXIT; END IF;
                v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
                UPDATE public.station_product_batches
                SET remaining_quantity = remaining_quantity - v_take
                WHERE id = r_b.id;
                v_rem_needed := v_rem_needed - v_take;
              END LOOP;
            END IF;
          END IF;
        ELSE
          v_rem_needed := v_used_qty;
          FOR r_b IN (
            SELECT id, remaining_quantity
            FROM public.station_product_batches
            WHERE station_id = v_deducted_station_id
              AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode))
              AND remaining_quantity > 0
            ORDER BY id ASC
            FOR UPDATE
          ) LOOP
            IF v_rem_needed <= 0 THEN EXIT; END IF;
            v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
            UPDATE public.station_product_batches
            SET remaining_quantity = remaining_quantity - v_take
            WHERE id = r_b.id;
            v_rem_needed := v_rem_needed - v_take;
          END LOOP;
        END IF;

        -- Update station_products card for the specific warehouse where the batch was deducted
        IF v_deducted_station_id IS NOT NULL THEN
          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
          FROM public.station_product_batches
          WHERE station_id = v_deducted_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

          UPDATE public.station_products
          SET quantity = v_sp_qty, updated_at = NOW()
          WHERE station_id = v_deducted_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
        END IF;

        -- Also sync the order station's product card if different
        IF v_station_id IS NOT NULL AND v_deducted_station_id != v_station_id THEN
          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
          FROM public.station_product_batches
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

          UPDATE public.station_products
          SET quantity = v_sp_qty, updated_at = NOW()
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
        END IF;
      END IF;
    END LOOP;

    -- 2. Calculate Packaging Costs
    v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
    v_tot_pkg_drawn := 0;

    IF jsonb_array_length(v_mat_array) > 0 THEN
      DECLARE
        v_m_el JSONB;
      BEGIN
        FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_mat_array) LOOP
          v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE(
            (v_m_el->>'total')::numeric,
            (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) *
             COALESCE((v_m_el->>'unit_cost')::numeric, 0))
          );
        END LOOP;
      END;
    END IF;

    IF v_tot_pkg_drawn = 0 THEN
      v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
      IF v_mat_waste_pct > 0 THEN
        v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 4);
      END IF;
    END IF;

    v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 4);
    v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;

    -- 3. Resolve GL Accounts
    SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

    v_finished_inv_acc    := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));
    v_pkg_inv_acc         := COALESCE(public.resolve_gl_account('12411', v_company_id), public.resolve_gl_account('1040', v_company_id));

    -- 4. Create or Update Packaging Confirmation Journal Entry
    IF v_tot_pkg_consumed > 0 THEN
      IF v_order.packaging_journal_entry_id IS NOT NULL THEN
        v_je_id := v_order.packaging_journal_entry_id;
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        UPDATE public.journal_entries
        SET description = 'قيد صرف مواد تعبئة وتغليف لأمر تعبئة رقم ' || v_order_num,
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
          'قيد صرف مواد تعبئة وتغليف لأمر تعبئة رقم ' || v_order_num,
          'posted', true, 'packing_order_packaging', p_packing_order_id::text, v_company_id,
          auth.uid(), now(), now()
        ) RETURNING id INTO v_je_id;

        v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_pkg', NULL, NULL);
        IF v_entry_num IS NULL OR v_entry_num = '' THEN
          v_entry_num := 'POP-' || LPAD(v_je_id::text, 5, '0');
        END IF;
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
      END IF;

      -- DR Finished Goods Inventory (12413 / 1031) tagged with target cost center
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id, cost_center_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, v_tot_pkg_consumed, 0, 'EGP', v_tot_pkg_consumed,
        'تكلفة مواد التعبئة والتغليف والهالك - أمر ' || v_order_num, v_company_id, v_target_cc_id
      );
      v_sum_debit := v_sum_debit + v_tot_pkg_consumed;

      -- CR Packaging Materials Inventory (12411 / 1040)
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_consumed, 'EGP', v_tot_pkg_consumed,
        'صرف مواد تعبئة وتغليف من المخزن - أمر ' || v_order_num, v_company_id
      );
      v_sum_credit := v_sum_credit + v_tot_pkg_consumed;

      -- Balance check
      IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
        RAISE EXCEPTION 'فشل تأكيد قيد مواد التعبئة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
      END IF;
    END IF;

    -- 4b. Sync consumed packaging materials into cost_center_transactions for target crop/variety
    DELETE FROM public.cost_center_transactions
    WHERE source_type IN ('packing_material', 'packing_material_waste')
      AND source_id LIKE 'po_' || p_packing_order_id::text || '_%';

    IF jsonb_array_length(v_mat_array) > 0 THEN
      DECLARE
        v_idx INT := 0;
        v_m JSONB;
        v_m_pname TEXT;
        v_m_used NUMERIC;
        v_m_unit NUMERIC;
        v_m_tot NUMERIC;
        v_m_curr TEXT;
        v_m_rate NUMERIC;
        v_m_tot_for NUMERIC;
        v_m_target_prod TEXT;
        v_m_cc_id TEXT;
        v_m_cc_name TEXT;
        v_m_supp TEXT;
      BEGIN
        FOR v_m IN SELECT * FROM jsonb_array_elements(v_mat_array) LOOP
          v_idx := v_idx + 1;
          v_m_pname := v_m->>'product_name';
          v_m_used := COALESCE((v_m->>'used_qty')::numeric, (v_m->>'quantity')::numeric, 0);
          v_m_unit := COALESCE((v_m->>'unit_cost')::numeric, 0);
          v_m_tot := COALESCE((v_m->>'total')::numeric, (v_m_used * v_m_unit));
          v_m_curr := COALESCE(v_m->>'currency', 'EGP');
          v_m_rate := COALESCE((v_m->>'exchange_rate')::numeric, 1.0);
          v_m_tot_for := COALESCE((v_m->>'total_foreign')::numeric, (v_m_tot / NULLIF(v_m_rate, 0)), v_m_tot);
          v_m_target_prod := COALESCE(v_m->>'target_product_name', v_order.product_name, '');
          v_m_supp := COALESCE(v_m->>'supplier_name', 'محطة التعبئة والتجهيز');

          -- Resolve line cost center
          v_m_cc_id := v_m->>'cost_center_id';
          v_m_cc_name := v_m->>'cost_center_name';

          IF v_m_cc_id IS NULL OR v_m_cc_id = '' THEN
            SELECT id, name_ar INTO v_m_cc_id, v_m_cc_name
            FROM public.cost_centers
            WHERE name_ar = v_m_target_prod
               OR name_ar ILIKE '%' || v_m_target_prod || '%'
               OR code = 'CC-' || UPPER(v_m_target_prod)
            LIMIT 1;
          END IF;

          IF v_m_cc_id IS NULL OR v_m_cc_id = '' THEN
            v_m_cc_id := v_target_cc_id;
            v_m_cc_name := v_target_cc_name;
          END IF;

          IF v_m_tot > 0 AND v_m_cc_id IS NOT NULL THEN
            INSERT INTO public.cost_center_transactions (
              cost_center_id,
              cost_center_name,
              cost_center_type,
              source_type,
              source_id,
              transaction_date,
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
              is_confirmed
            ) VALUES (
              v_m_cc_id,
              v_m_cc_name,
              'variety',
              'packing_material',
              'po_' || p_packing_order_id::text || '_mat_' || v_idx::text,
              COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, CURRENT_DATE),
              v_m_supp,
              (v_m->>'target_product_id')::bigint,
              COALESCE(v_m_pname, 'مادة تعبئة'),
              'مواد التعبئة',
              v_m_used,
              v_m_unit,
              v_m_curr,
              v_m_rate,
              v_m_tot_for,
              v_m_tot,
              'أمر تعبئة #' || v_order_num || ' - استهلاك مادة تعبئة (' || COALESCE(v_m_pname, '') || ') لصنف ' || v_m_target_prod,
              true
            ) ON CONFLICT (source_type, source_id) DO UPDATE SET
              cost_center_id = EXCLUDED.cost_center_id,
              cost_center_name = EXCLUDED.cost_center_name,
              item_name = EXCLUDED.item_name,
              quantity = EXCLUDED.quantity,
              unit_price = EXCLUDED.unit_price,
              currency = EXCLUDED.currency,
              exchange_rate = EXCLUDED.exchange_rate,
              total_in_currency = EXCLUDED.total_in_currency,
              amount = EXCLUDED.amount,
              notes = EXCLUDED.notes,
              transaction_date = EXCLUDED.transaction_date,
              updated_at = now();
          END IF;
        END LOOP;
      END;
    END IF;

    -- Packaging Material Waste
    IF v_tot_pkg_waste > 0 AND v_target_cc_id IS NOT NULL THEN
      INSERT INTO public.cost_center_transactions (
        cost_center_id,
        cost_center_name,
        cost_center_type,
        source_type,
        source_id,
        transaction_date,
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
        is_confirmed
      ) VALUES (
        v_target_cc_id,
        v_target_cc_name,
        'variety',
        'packing_material_waste',
        'po_' || p_packing_order_id::text || '_mat_waste',
        COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, CURRENT_DATE),
        'محطة التعبئة والتجهيز',
        v_order.fruit_type_id,
        'هالك مواد تعبئة (' || v_mat_waste_pct::text || '%)',
        'تكلفة الهالك',
        1,
        v_tot_pkg_waste,
        'EGP',
        1.0,
        v_tot_pkg_waste,
        v_tot_pkg_waste,
        'أمر تعبئة #' || v_order_num || ' - هالك مواد التعبئة والتغليف (' || v_mat_waste_pct::text || '%) لصنف ' || COALESCE(v_order.product_name, ''),
        true
      ) ON CONFLICT (source_type, source_id) DO UPDATE SET
        cost_center_id = EXCLUDED.cost_center_id,
        cost_center_name = EXCLUDED.cost_center_name,
        item_name = EXCLUDED.item_name,
        quantity = EXCLUDED.quantity,
        unit_price = EXCLUDED.unit_price,
        amount = EXCLUDED.amount,
        total_in_currency = EXCLUDED.total_in_currency,
        notes = EXCLUDED.notes,
        transaction_date = EXCLUDED.transaction_date,
        updated_at = now();
    END IF;
  END;

  -- 5. Update packing order status and stage tracking
  v_notes := jsonb_set(v_notes, '{workflow_stages,packaging}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'pkg_drawn_cost', v_tot_pkg_drawn,
    'pkg_waste_cost', v_tot_pkg_waste,
    'pkg_total_cost', v_tot_pkg_consumed
  ), true);

  UPDATE public.packing_orders
  SET status = CASE
        WHEN status IN ('costs_confirmed', 'final_approved', 'completed') THEN status
        ELSE 'packaging_confirmed'
      END,
      packaging_confirmed_at = COALESCE(packaging_confirmed_at, now()),
      packaging_journal_entry_id = v_je_id,
      actual_material_cost = v_tot_pkg_consumed,
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'status', 'packaging_confirmed',
    'journal_entry_id', v_je_id,
    'drawn_cost', v_tot_pkg_drawn,
    'waste_cost', v_tot_pkg_waste,
    'total_consumed', v_tot_pkg_consumed
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_packaging(bigint) TO authenticated, service_role, anon;

