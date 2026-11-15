BEGIN;



-- STAGE 2: Confirm Packaging Materials (تأكيد مواد التعبئة والتغليف)

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



  -- 1. Deduct Materials Inventory

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



      IF v_used_qty > 0 THEN

        IF v_batch_id IS NOT NULL AND v_batch_id > 0 THEN

          SELECT remaining_quantity INTO v_curr_rem

          FROM public.station_product_batches

          WHERE id = v_batch_id

          FOR UPDATE;



          IF FOUND AND v_curr_rem >= v_used_qty THEN

            UPDATE public.station_product_batches

            SET remaining_quantity = remaining_quantity - v_used_qty

            WHERE id = v_batch_id;

          ELSE

            v_rem_needed := v_used_qty;

            FOR r_b IN (

              SELECT id, remaining_quantity

              FROM public.station_product_batches

              WHERE station_id = v_station_id

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

        ELSE

          v_rem_needed := v_used_qty;

          FOR r_b IN (

            SELECT id, remaining_quantity

            FROM public.station_product_batches

            WHERE station_id = v_station_id

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



        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty

        FROM public.station_product_batches

        WHERE station_id = v_station_id

          AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));



        UPDATE public.station_products

        SET quantity = v_sp_qty, updated_at = NOW()

        WHERE station_id = v_station_id

          AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

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





-- ============================================================================

-- STAGE 3: Confirm Cost Items & Post Supplier Liabilities (تأكيد بنود التكلفة وترحيل حسابات الموردين)

-- ============================================================================

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

  v_transport_default_acc INT;



  v_je_id INT;

  v_entry_num TEXT;

  v_sum_debit NUMERIC := 0;

  v_sum_credit NUMERIC := 0;



  v_el JSONB;

  r_cost RECORD;

  r_prev_trans RECORD;

  r_prev_supp RECORD;

  v_supplier_id UUID;

  v_trans_supplier_id INT;

  v_supp_str TEXT;

  v_amt_egp NUMERIC;

  v_target_line_idx INT;

  v_max_cost_item_id BIGINT;

  v_consumed_trucks NUMERIC;

  v_category_account_id BIGINT;

  v_is_transport BOOLEAN;

BEGIN

  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;

  IF NOT FOUND THEN

    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  -- Validate prerequisite: packaging must be confirmed first

  IF v_order.status IN ('draft', 'pending', 'crops_confirmed') THEN

    RETURN json_build_object('success', false, 'error', 'يجب تأكيد مواد التعبئة أولاً قبل تأكيد بنود التكلفة');

  END IF;



  -- Idempotency check: only block if the order has already been final approved / completed

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



  -- A. Revert previously recorded transport amounts and truck counts for this packing order (Idempotency)

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



  -- B. Revert generic supplier ledger entries and outstanding balance if any

  FOR r_prev_supp IN

    SELECT entity_id, SUM(COALESCE(amount, 0)) AS total_prev_amount

    FROM public.ledger_entries

    WHERE reference_id = p_packing_order_id

      AND reference_type = 'packing_cost'

      AND entry_type = 'credit'

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

    AND reference_type = 'packing_cost';



  -- 1. Rebuild Cost Items from Notes

  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN

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



        INSERT INTO public.packing_order_cost_items (
          packing_order_id, name, category,
          base_amount, original_amount, original_currency,
          payment_source_type, payment_source_id,
          allocation_method, target_line_id,
          currency_snapshot, supplier_id, payment_status, paid_amount,
          truck_count, quantity, unit_price, cost_status,
          expected_amount, actual_amount, variance_amount,
          report_category_id, transport_supplier_id
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
            'supplier_id', COALESCE(v_supplier_id::text, v_supp_str),
            'supplier_name', v_el->>'supplier_name',
            'target_line_index', v_target_line_idx,
            'transport_supplier_id', COALESCE(v_el->>'transport_supplier_id', CASE WHEN v_el->>'category' = 'logistics' OR v_el->>'supplier_type' = 'transport' THEN v_supp_str ELSE NULL END),
            'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
            'quantity', COALESCE((v_el->>'quantity')::numeric, (v_el->>'truck_count')::numeric, 1.0),
            'supplier_type', v_el->>'supplier_type'
          ),
          COALESCE(v_supplier_id::text, v_supp_str),
          'unpaid',
          0,
          COALESCE(NULLIF((v_el->>'truck_count')::numeric, 0), NULLIF((v_el->>'quantity')::numeric, 0), 1.0),
          COALESCE(NULLIF((v_el->>'quantity')::numeric, 0), NULLIF((v_el->>'truck_count')::numeric, 0), 1.0),
          COALESCE((v_el->>'unit_price')::numeric, (v_el->>'rate')::numeric, (v_el->>'total')::numeric, v_amt_egp),
          'actual',
          COALESCE((v_el->>'expected_amount')::numeric, (v_el->>'total')::numeric, v_amt_egp),
          COALESCE((v_el->>'actual_amount')::numeric, (v_el->>'total')::numeric, v_amt_egp),
          COALESCE((v_el->>'variance_amount')::numeric, 0.00),
          CASE WHEN (v_el->>'report_category_id') ~ '^[0-9]+$' AND EXISTS (SELECT 1 FROM public.cost_report_categories c WHERE c.id = (v_el->>'report_category_id')::integer) THEN (v_el->>'report_category_id')::integer ELSE NULL END,
          COALESCE(NULLIF(v_el->>'transport_supplier_id', '')::integer, CASE WHEN v_el->>'category' = 'logistics' OR v_el->>'supplier_type' = 'transport' THEN NULLIF(v_supp_str, '')::integer ELSE NULL END)
        );

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



  -- 4. Create Costs Confirmation Journal Entry & Post Supplier Liabilities

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



    -- CR Supplier Accounts & Sub-Ledger Posting

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

      -- CASE A: TRANSPORT SUPPLIER / TRANSPORT COST -> Route to 21111 or Supplier Account

      -- =========================================================================

      IF v_is_transport THEN

        -- 1. Try transport supplier's direct account_id if configured

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



        -- Hard safety check: NEVER allow 2112 (Notes Payable / أوراق الدفع)!

        IF v_credit_acc = (SELECT id FROM public.accounts WHERE account_code = '2112' LIMIT 1) THEN

          v_credit_acc := (SELECT id FROM public.accounts WHERE account_code = '21111' LIMIT 1);

        END IF;



        -- Fallback to master suppliers control (2111) if 21111 somehow missing

        IF v_credit_acc IS NULL THEN

          v_credit_acc := public.resolve_gl_account('2111', v_company_id);

        END IF;



        -- Post GL Ledger Entry for Transport Cost -> Account 21111 / Supplier account

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,

          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id

        );

        v_sum_credit := v_sum_credit + r_cost.base_amount;

        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;



        -- Operational Truck Deduction & Financial Entitlement Posting

        IF v_trans_supplier_id IS NOT NULL THEN

          v_consumed_trucks := COALESCE(
            NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
            NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
            NULLIF(r_cost.truck_count, 0),
            1.0
          );



          -- 1. Update Transport Supplier Balances (Trucks & Financial)

          UPDATE public.transport_suppliers

          SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks,

              updated_at = now()

          WHERE id = v_trans_supplier_id;



          -- 2. Insert Transport Transaction (operational consumption, amount = 0)

          INSERT INTO public.transport_transactions (

            supplier_id, type, amount, currency, reference_id,

            description, truck_count, notes, journal_entry_id, date, created_at

          ) VALUES (

            v_trans_supplier_id,

            'packing_consumption',

            0,

            'EGP',

            p_packing_order_id::text,

            'تكلفة ونقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل') || ' (' || v_consumed_trucks::text || ' نقلة)',

            v_consumed_trucks,

            'استحقاق مالي ' || r_cost.base_amount::text || ' ج.م وسحب ' || v_consumed_trucks::text || ' نقلة لأمر تعبئة ' || v_order_num,

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





-- ============================================================================

-- STAGE 4: Final Approval & Close Order (الاعتماد النهائي وإغلاق أمر التعبئة)

-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_final(p_packing_order_id bigint)

RETURNS json

LANGUAGE plpgsql

SECURITY DEFINER

AS $function$

DECLARE

  v_order RECORD;

  v_notes JSONB;

BEGIN

  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;

  IF NOT FOUND THEN

    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  -- Check if already finalized

  IF v_order.status IN ('final_approved', 'completed') THEN

    RETURN json_build_object(

      'success', true,

      'message', 'أمر التعبئة معتمد نهائياً ومغلق بالفعل',

      'status', v_order.status

    );

  END IF;



  -- Ensure prior stages are executed if not already confirmed

  IF v_order.crops_confirmed_at IS NULL AND v_order.crops_journal_entry_id IS NULL THEN

    PERFORM public.rpc_confirm_packing_crops(p_packing_order_id);

  END IF;



  IF v_order.packaging_confirmed_at IS NULL AND v_order.packaging_journal_entry_id IS NULL THEN

    PERFORM public.rpc_confirm_packing_packaging(p_packing_order_id);

  END IF;



  IF v_order.costs_confirmed_at IS NULL AND v_order.costs_journal_entry_id IS NULL THEN

    PERFORM public.rpc_confirm_packing_costs(p_packing_order_id);

  END IF;



  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;



  BEGIN

    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);

    IF jsonb_typeof(v_notes) = 'string' THEN

      v_notes := (v_notes #>> '{}')::jsonb;

    END IF;

  EXCEPTION WHEN OTHERS THEN

    v_notes := '{}'::jsonb;

  END;



  v_notes := jsonb_set(v_notes, '{workflow_stages,final_approved}', jsonb_build_object(

    'approved_at', now(),

    'approved_by', auth.uid()

  ), true);



  UPDATE public.packing_orders

  SET status = 'final_approved',

      final_approved_at = now(),

      packed_at = COALESCE(packed_at, now()),

      notes = v_notes::text,

      updated_at = now()

  WHERE id = p_packing_order_id;



  RETURN json_build_object(

    'success', true,

    'status', 'final_approved',

    'message', 'تم الاعتماد النهائي وإغلاق أمر التعبئة بنجاح'

  );

END;

$function$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_final(bigint) TO authenticated, service_role, anon;





-- ============================================================================

-- Canonical / Cascade rpc_confirm_packing_order (Full Backward Compatibility)

-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(p_packing_order_id bigint)

RETURNS json

LANGUAGE plpgsql

SECURITY DEFINER

AS $function$

DECLARE

  v_status TEXT;

  v_res JSON;

BEGIN

  SELECT status INTO v_status FROM public.packing_orders WHERE id = p_packing_order_id;

  IF NOT FOUND THEN

    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  IF v_status IN ('final_approved', 'completed') THEN

    RETURN json_build_object('success', true, 'message', 'أمر التعبئة مؤكد بالفعل', 'status', v_status);

  END IF;



  -- 1. Cascade Crops Stage

  IF v_status IN ('draft', 'pending', 'in_progress') THEN

    v_res := public.rpc_confirm_packing_crops(p_packing_order_id);

    IF (v_res->>'success')::boolean != true THEN

      RETURN v_res;

    END IF;

    SELECT status INTO v_status FROM public.packing_orders WHERE id = p_packing_order_id;

  END IF;



  -- 2. Cascade Packaging Stage

  IF v_status = 'crops_confirmed' THEN

    v_res := public.rpc_confirm_packing_packaging(p_packing_order_id);

    IF (v_res->>'success')::boolean != true THEN

      RETURN v_res;

    END IF;

    SELECT status INTO v_status FROM public.packing_orders WHERE id = p_packing_order_id;

  END IF;



  -- 3. Cascade Costs Stage

  IF v_status = 'packaging_confirmed' THEN

    v_res := public.rpc_confirm_packing_costs(p_packing_order_id);

    IF (v_res->>'success')::boolean != true THEN

      RETURN v_res;

    END IF;

    SELECT status INTO v_status FROM public.packing_orders WHERE id = p_packing_order_id;

  END IF;



  -- 4. Cascade Final Approval Stage

  IF v_status = 'costs_confirmed' THEN

    v_res := public.rpc_confirm_packing_final(p_packing_order_id);

    IF (v_res->>'success')::boolean != true THEN

      RETURN v_res;

    END IF;

  END IF;



  RETURN json_build_object(

    'success', true,

    'status', 'final_approved',

    'message', 'تم تأكيد واعتماد أمر التعبئة بجميع مراحله بنجاح'

  );

END;

$function$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated, service_role;



-- ==============================================================================

-- APPENDED FROM MIGRATION 469 (Crop-Centric Seasonal Cost Centers & Branch Binding)

-- ==============================================================================

-- ==============================================================================

-- Migration: 20260911000001_469_crop_centric_seasonal_cost_centers_and_branch_binding.sql

-- Description:

-- 1. Decouple cost centers from purchasing methods (e.g. merge "Mango - Weight" & "Mango - Cartons" into canonical crop cost centers).

-- 2. Add seasonal agricultural naming, lifecycle, and rollover mechanism to public.cost_centers.

-- 3. Add branch_id and cost_center_id tracking to treasury_transactions, account_ledger_entries, spend_custody, transfer_custody, and draft RPCs.

-- ==============================================================================





-- ── 1. Enhance public.cost_centers with Seasonal and Agricultural Fields ───────

ALTER TABLE public.cost_centers

  ADD COLUMN IF NOT EXISTS crop_name TEXT,

  ADD COLUMN IF NOT EXISTS crop_code TEXT,

  ADD COLUMN IF NOT EXISTS season TEXT DEFAULT '2026-2027',

  ADD COLUMN IF NOT EXISTS season_status TEXT NOT NULL DEFAULT 'active', -- 'active', 'closed'

  ADD COLUMN IF NOT EXISTS start_date DATE,

  ADD COLUMN IF NOT EXISTS end_date DATE,

  ADD COLUMN IF NOT EXISTS opening_balance NUMERIC NOT NULL DEFAULT 0,

  ADD COLUMN IF NOT EXISTS current_balance NUMERIC NOT NULL DEFAULT 0,

  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,

  ADD COLUMN IF NOT EXISTS closed_by UUID REFERENCES auth.users(id),

  ADD COLUMN IF NOT EXISTS rollover_cost_center_id BIGINT REFERENCES public.cost_centers(id),

  ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES public.stations(id) ON DELETE SET NULL;



CREATE INDEX IF NOT EXISTS idx_cost_centers_season ON public.cost_centers(season);

CREATE INDEX IF NOT EXISTS idx_cost_centers_season_status ON public.cost_centers(season_status);

CREATE INDEX IF NOT EXISTS idx_cost_centers_crop_code ON public.cost_centers(crop_code);

CREATE INDEX IF NOT EXISTS idx_cost_centers_branch_id ON public.cost_centers(branch_id);



-- ── 2. Canonical Crop Name Cleaner Function (Decouples Purchasing Methods) ────

CREATE OR REPLACE FUNCTION public.fn_canonical_crop_name(p_name TEXT)

RETURNS TEXT AS $$

DECLARE

  v_clean TEXT := TRIM(COALESCE(p_name, ''));

BEGIN

  IF v_clean = '' THEN

    RETURN 'محصول عام';

  END IF;



  -- 1. Strip purchase mode suffixes with dashes/hyphens

  v_clean := REGEXP_REPLACE(v_clean, '\s*[-–/\\:]\s*(وزن|كرتون|كرتونة|كراتين|طرد|طرود|صندوق|صناديق|شوال|شوالات|بالوزن|بالكرتون|بالطرد|قطاعي|جملة|خام).*$', '', 'gi');



  -- 2. Strip purchase mode suffixes inside parentheses or brackets

  v_clean := REGEXP_REPLACE(v_clean, '\s*[\(\[\{](وزن|كرتون|كرتونة|كراتين|طرد|طرود|صندوق|صناديق|شوال|شوالات|بالوزن|بالكرتون|بالطرد|قطاعي|جملة|خام)[\)\]\}].*$', '', 'gi');



  -- 3. Strip English purchase mode tokens

  v_clean := REGEXP_REPLACE(v_clean, '\s*[-–/\\:]\s*(weight|carton|cartons|box|boxes|crate|crates|pkg|package|bulk).*$', '', 'gi');

  v_clean := REGEXP_REPLACE(v_clean, '\s*[\(\[\{](weight|carton|cartons|box|boxes|crate|crates|pkg|package|bulk)[\)\]\}].*$', '', 'gi');



  -- 4. Strip leading line keywords if redundant

  v_clean := REGEXP_REPLACE(v_clean, '^(خط\s+محصول|خط\s+إنتاج|خط)\s+', '', 'gi');



  v_clean := TRIM(v_clean);

  IF v_clean = '' THEN

    RETURN TRIM(COALESCE(p_name, 'محصول عام'));

  END IF;



  RETURN v_clean;

END;

$$ LANGUAGE plpgsql IMMUTABLE;



-- ── 3. Resolve Canonical Crop Slug & Cost Center Code ───────────────────────────

CREATE OR REPLACE FUNCTION public.fn_resolve_crop_slug(p_crop_name TEXT)

RETURNS TEXT AS $$

DECLARE

  v_lower TEXT := LOWER(COALESCE(p_crop_name, ''));

BEGIN

  IF v_lower LIKE '%مانج%' OR v_lower LIKE '%مانق%' OR v_lower LIKE '%mango%' THEN

    RETURN 'MANGO';

  ELSIF v_lower LIKE '%فراول%' OR v_lower LIKE '%strawberry%' THEN

    RETURN 'STRAWBERRY';

  ELSIF v_lower LIKE '%عنب%' OR v_lower LIKE '%grape%' THEN

    RETURN 'GRAPES';

  ELSIF v_lower LIKE '%برتقال%' OR v_lower LIKE '%orange%' THEN

    RETURN 'ORANGE';

  ELSIF v_lower LIKE '%ليمون%' OR v_lower LIKE '%lemon%' THEN

    RETURN 'LEMON';

  ELSIF v_lower LIKE '%يوسفي%' OR v_lower LIKE '%mandarin%' THEN

    RETURN 'MANDARIN';

  ELSIF v_lower LIKE '%رمان%' OR v_lower LIKE '%pomegranate%' THEN

    RETURN 'POMEGRANATE';

  ELSIF v_lower LIKE '%موز%' OR v_lower LIKE '%banana%' THEN

    RETURN 'BANANA';

  ELSIF v_lower LIKE '%خوخ%' OR v_lower LIKE '%peach%' THEN

    RETURN 'PEACH';

  ELSIF v_lower LIKE '%مشمش%' OR v_lower LIKE '%apricot%' THEN

    RETURN 'APRICOT';

  ELSIF v_lower LIKE '%بلح%' OR v_lower LIKE '%تمر%' OR v_lower LIKE '%dates%' THEN

    RETURN 'DATES';

  ELSIF v_lower LIKE '%تين%' OR v_lower LIKE '%fig%' THEN

    RETURN 'FIG';

  ELSE

    RETURN 'CROP';

  END IF;

END;

$$ LANGUAGE plpgsql IMMUTABLE;



-- ── 4. Resolve or Provision Unified Crop Cost Center ─────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_resolve_active_crop_cost_center(

  p_crop_name TEXT,

  p_fruit_type_id BIGINT DEFAULT NULL

)

RETURNS TABLE (

  cost_center_id TEXT,

  cost_center_name TEXT

) AS $$

DECLARE

  v_bound_cc_id TEXT;

  v_canon_crop TEXT;

  v_slug TEXT;

  v_res_code TEXT;

  v_res_name TEXT;

BEGIN

  -- Priority 1: Check fruit_types.cost_center_id explicitly bound during item setup/registration

  -- IMPORTANT: If the bound CC is closed/rolled-over, automatically follow its rollover_cost_center_id

  -- to the currently active period (prevents stale pointer after season closure).

  IF p_fruit_type_id IS NOT NULL THEN

    SELECT ft.cost_center_id INTO v_bound_cc_id

    FROM public.fruit_types ft

    WHERE ft.id = p_fruit_type_id;



    IF v_bound_cc_id IS NOT NULL AND TRIM(v_bound_cc_id) <> '' THEN

      -- First try: look up the bound CC and check if it is still active

      SELECT cc.code, COALESCE(cc.name_ar, cc.name)

      INTO v_res_code, v_res_name

      FROM public.cost_centers cc

      WHERE (cc.code = v_bound_cc_id OR cc.id::text = v_bound_cc_id)

        AND cc.is_active = TRUE

        AND (cc.season_status IS NULL OR cc.season_status NOT IN ('closed', 'permanently_closed'))

      LIMIT 1;



      -- Second try: if the directly-bound CC is now closed, follow its rollover pointer

      IF v_res_code IS NULL THEN

        SELECT COALESCE(next_cc.code, COALESCE(NULL::TEXT, NULL)), COALESCE(next_cc.name_ar, next_cc.name)

        INTO v_res_code, v_res_name

        FROM public.cost_centers closed_cc

        JOIN public.cost_centers next_cc

          ON next_cc.id = closed_cc.rollover_cost_center_id

        WHERE (closed_cc.code = v_bound_cc_id OR closed_cc.id::text = v_bound_cc_id)

          AND next_cc.is_active = TRUE

          AND (next_cc.season_status IS NULL OR next_cc.season_status NOT IN ('closed', 'permanently_closed'))

        LIMIT 1;

      END IF;



      IF v_res_code IS NOT NULL THEN

        cost_center_id := v_res_code;

        cost_center_name := v_res_name;

        RETURN NEXT;

        RETURN;

      END IF;

    END IF;

  END IF;



  -- Priority 1b: If fruit_type_id was null, try finding fruit_types by crop name

  -- Also follows rollover pointers if the bound CC is closed.

  IF p_crop_name IS NOT NULL AND TRIM(p_crop_name) <> '' THEN

    SELECT ft.cost_center_id INTO v_bound_cc_id

    FROM public.fruit_types ft

    WHERE ft.cost_center_id IS NOT NULL

      AND TRIM(ft.cost_center_id) <> ''

      AND (

        ft.name = TRIM(p_crop_name)

        OR ft.name ILIKE '%' || public.fn_canonical_crop_name(p_crop_name) || '%'

      )

    ORDER BY (CASE WHEN ft.name = TRIM(p_crop_name) THEN 1 ELSE 2 END)

    LIMIT 1;



    IF v_bound_cc_id IS NOT NULL AND TRIM(v_bound_cc_id) <> '' THEN

      -- First try: bound CC still active

      SELECT cc.code, COALESCE(cc.name_ar, cc.name)

      INTO v_res_code, v_res_name

      FROM public.cost_centers cc

      WHERE (cc.code = v_bound_cc_id OR cc.id::text = v_bound_cc_id)

        AND cc.is_active = TRUE

        AND (cc.season_status IS NULL OR cc.season_status NOT IN ('closed', 'permanently_closed'))

      LIMIT 1;



      -- Second try: follow rollover pointer if bound CC is closed

      IF v_res_code IS NULL THEN

        SELECT COALESCE(next_cc.code, COALESCE(NULL::TEXT, NULL)), COALESCE(next_cc.name_ar, next_cc.name)

        INTO v_res_code, v_res_name

        FROM public.cost_centers closed_cc

        JOIN public.cost_centers next_cc

          ON next_cc.id = closed_cc.rollover_cost_center_id

        WHERE (closed_cc.code = v_bound_cc_id OR closed_cc.id::text = v_bound_cc_id)

          AND next_cc.is_active = TRUE

          AND (next_cc.season_status IS NULL OR next_cc.season_status NOT IN ('closed', 'permanently_closed'))

        LIMIT 1;

      END IF;



      IF v_res_code IS NOT NULL THEN

        cost_center_id := v_res_code;

        cost_center_name := v_res_name;

        RETURN NEXT;

        RETURN;

      END IF;

    END IF;

  END IF;



  -- Priority 2: Resolve canonical seasonal cost center for the crop variety

  -- STRICT RULE: ONLY variety cost centers, NEVER generic line-based centers

  -- PERIOD PREFERENCE: Period-qualified active CCs (e.g. CC-MANGO-2026-2027-P2) have priority.

  v_canon_crop := public.fn_canonical_crop_name(COALESCE(p_crop_name, 'محصول'));

  v_slug := public.fn_resolve_crop_slug(v_canon_crop);



  -- 2a: Prefer period-qualified active CC (e.g. CC-MANGO-2026-2027-P2)

  SELECT code, name_ar INTO v_res_code, v_res_name

  FROM public.cost_centers

  WHERE is_active = TRUE

    AND (season_status = 'active' OR season_status IS NULL)

    AND cost_center_type = 'variety'

    AND name_ar NOT LIKE 'خط %'

    AND code ~ ('^CC-' || v_slug || '.*-P[0-9]+$')

  ORDER BY season_number DESC, id DESC

  LIMIT 1;



  -- 2b: Base season code fallback

  IF v_res_code IS NULL THEN

    SELECT code, name_ar INTO v_res_code, v_res_name

    FROM public.cost_centers

    WHERE is_active = TRUE

      AND (season_status = 'active' OR season_status IS NULL)

      AND cost_center_type = 'variety'

      AND name_ar NOT LIKE 'خط %'

      AND (

        crop_code = v_slug

        OR crop_name = v_canon_crop

        OR code = 'CC-' || v_slug || '-2026-2027'

        OR name_ar ILIKE v_canon_crop || ' (موسم %)'

      )

    ORDER BY CASE WHEN season_status = 'active' THEN 1 ELSE 2 END, season_number DESC, id DESC

    LIMIT 1;

  END IF;



  -- Priority 3: Any active variety CC for this crop (excluding lines & closed)

  IF v_res_code IS NULL THEN

    SELECT code, name_ar INTO v_res_code, v_res_name

    FROM public.cost_centers

    WHERE is_active = TRUE

      AND (season_status IS NULL OR season_status NOT IN ('closed', 'permanently_closed'))

      AND cost_center_type = 'variety'

      AND name_ar NOT LIKE 'خط %'

      AND (crop_code = v_slug OR crop_name = v_canon_crop OR code = 'CC-' || v_slug OR name_ar = v_canon_crop)

    ORDER BY id DESC

    LIMIT 1;

  END IF;



  -- Priority 4: Ultimate Fallback: generate canonical seasonal cost center code and display title

  -- NEVER generate line-based centers!

  IF v_res_code IS NULL THEN

    IF v_slug <> 'CROP' THEN

      v_res_code := 'CC-' || v_slug || '-2026-2027';

    ELSE

      v_res_code := 'CC-CROP-2026-2027';

    END IF;

    v_res_name := v_canon_crop || ' (موسم 2026-2027)';

  END IF;



  cost_center_id := v_res_code;

  cost_center_name := COALESCE(v_res_name, v_canon_crop || ' (موسم 2026-2027)');

  RETURN NEXT;

END;

$$ LANGUAGE plpgsql STABLE;



CREATE OR REPLACE FUNCTION public.fn_resolve_crop_cost_center_code(

  p_crop_name TEXT,

  p_fruit_type_id BIGINT DEFAULT NULL,

  p_season TEXT DEFAULT '2026-2027'

)

RETURNS TEXT AS $$

DECLARE

  v_res_id TEXT;

  v_res_name TEXT;

BEGIN

  SELECT r.cost_center_id, r.cost_center_name

  INTO v_res_id, v_res_name

  FROM public.fn_resolve_active_crop_cost_center(p_crop_name, p_fruit_type_id) r;



  RETURN v_res_id;

END;

$$ LANGUAGE plpgsql STABLE;



-- ── 4b. Trigger: Prevent Bleed into Closed Cost Centers ─────────────────────────

CREATE OR REPLACE FUNCTION public.fn_enforce_active_cost_center_routing_on_transactions()

RETURNS TRIGGER AS $$

DECLARE

  v_target_cc RECORD;

  v_next_cc RECORD;

  v_res_cc RECORD;

BEGIN

  -- Allow rollover system records to populate the target center

  IF NEW.source_type = 'season_rollover' THEN

    RETURN NEW;

  END IF;



  IF NEW.cost_center_id IS NOT NULL AND TRIM(NEW.cost_center_id) <> '' THEN

    SELECT id, code, name_ar, is_active, is_closed, season_status, status, rollover_cost_center_id

    INTO v_target_cc

    FROM public.cost_centers

    WHERE (code = NEW.cost_center_id OR id::text = NEW.cost_center_id)

    LIMIT 1;



    IF FOUND THEN

      -- Check if target cost center is closed or locked

      IF v_target_cc.is_active = FALSE

         OR COALESCE(v_target_cc.is_closed, FALSE) = TRUE

         OR v_target_cc.season_status IN ('closed', 'permanently_closed')

         OR v_target_cc.status IN ('closed', 'permanently_closed') THEN



        -- Follow rollover chain to active target period

        IF v_target_cc.rollover_cost_center_id IS NOT NULL THEN

          SELECT id, code, name_ar, is_active, is_closed, season_status, status

          INTO v_next_cc

          FROM public.cost_centers

          WHERE id = v_target_cc.rollover_cost_center_id;



          IF FOUND AND v_next_cc.is_active = TRUE

             AND COALESCE(v_next_cc.is_closed, FALSE) = FALSE

             AND (v_next_cc.season_status IS NULL OR v_next_cc.season_status NOT IN ('closed', 'permanently_closed'))

             AND (v_next_cc.status IS NULL OR v_next_cc.status NOT IN ('closed', 'permanently_closed')) THEN

            NEW.cost_center_id := v_next_cc.code;

            NEW.cost_center_name := COALESCE(v_next_cc.name_ar, NEW.cost_center_name);

            RETURN NEW;

          END IF;

        END IF;



        -- If rollover target was missing or also closed, resolve via active resolution function

        SELECT r.cost_center_id, r.cost_center_name INTO v_res_cc

        FROM public.fn_resolve_active_crop_cost_center(NEW.item_name, NEW.product_id) r;



        IF v_res_cc.cost_center_id IS NOT NULL THEN

          NEW.cost_center_id := v_res_cc.cost_center_id;

          NEW.cost_center_name := COALESCE(v_res_cc.cost_center_name, NEW.cost_center_name);

          RETURN NEW;

        END IF;



        -- If no active center could be resolved, prevent assignment to closed center

        RAISE EXCEPTION 'لا يمكن تسجيل معاملات جديدة على مركز تكلفة مقفل (%) - تم قفل الموسم الزراعي نهائياً',

          COALESCE(v_target_cc.name_ar, NEW.cost_center_id);

      END IF;

    END IF;

  END IF;



  RETURN NEW;

END;

$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS trg_prevent_closed_cost_center_bleed ON public.cost_center_transactions;

CREATE TRIGGER trg_prevent_closed_cost_center_bleed

  BEFORE INSERT OR UPDATE OF cost_center_id ON public.cost_center_transactions

  FOR EACH ROW

  EXECUTE FUNCTION public.fn_enforce_active_cost_center_routing_on_transactions();



-- ── 4c. Auto-heal any fruit_types pointing to closed/rolled-over cost centers ────

UPDATE public.fruit_types ft

SET cost_center_id = next_cc.code

FROM public.cost_centers closed_cc

JOIN public.cost_centers next_cc ON next_cc.id = closed_cc.rollover_cost_center_id

WHERE (ft.cost_center_id = closed_cc.code OR ft.cost_center_id = closed_cc.id::TEXT)

  AND (closed_cc.is_active = FALSE OR closed_cc.season_status IN ('closed', 'permanently_closed'))

  AND next_cc.is_active = TRUE

  AND (next_cc.season_status IS NULL OR next_cc.season_status NOT IN ('closed', 'permanently_closed'));



-- ── 5. Consolidate Legacy Cost Centers (DISABLED) ─────────────────────────────

-- ملاحظة: تم تعطيل دمج مراكز التكلفة لأن الجدول يتم تصفيره بالكامل

-- العميل ينشئ مراكز التكلفة حسب احتياجاته من واجهة التطبيق



-- ── 6. Seasonal Closing & Rollover RPC (Strict Two-Stage) ───────────────────

CREATE OR REPLACE FUNCTION public.rpc_close_and_rollover_cost_center(

    p_cost_center_id BIGINT,

    p_next_season TEXT DEFAULT NULL,

    p_notes TEXT DEFAULT NULL,

    p_target_stage TEXT DEFAULT NULL,

    p_override_balance NUMERIC DEFAULT NULL

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_old_cc RECORD;

    v_net_balance NUMERIC := 0;

    v_new_cc_id BIGINT;

    v_new_code TEXT;

    v_new_name_ar TEXT;

    v_new_name_en TEXT;

    v_clean_crop_name TEXT;

    v_slug TEXT;

    v_tx_source_id TEXT;

    v_old_start_year INT;

    v_calc_next_season TEXT;

    v_year_matches TEXT[];

    v_closure_stage TEXT;

    v_new_season_number INT;

    v_new_closure_count INT;

    v_is_final_closure BOOLEAN := FALSE;

    v_var RECORD;

    v_variety_count INT := 0;

    v_sum_variety_amounts NUMERIC := 0;

    v_remainder NUMERIC := 0;

BEGIN

    SELECT * INTO v_old_cc

    FROM public.cost_centers

    WHERE id = p_cost_center_id FOR UPDATE;



    IF NOT FOUND THEN

        RAISE EXCEPTION 'مركز التكلفة برقم % غير موجود', p_cost_center_id;

    END IF;



    IF COALESCE(v_old_cc.is_closed, FALSE) = TRUE AND COALESCE(v_old_cc.season_status, 'active') = 'permanently_closed' THEN

        RAISE EXCEPTION 'مركز التكلفة (%) مقفل نهائياً للسنة الزراعية (%): تم استنفاد الموسمين المسموح بهما ولا يمكن الترحيل مرة أخرى.',

            v_old_cc.name_ar, COALESCE(v_old_cc.season, 'السابق');

    END IF;



    IF COALESCE(v_old_cc.is_closed, FALSE) = TRUE OR v_old_cc.season_status = 'closed' OR v_old_cc.is_active = FALSE OR COALESCE(v_old_cc.status, 'active') = 'closed' THEN

        RAISE EXCEPTION 'مركز التكلفة (%) مقفل بالفعل لهذا الموسم (%) ولا يمكن تكرار إقفاله أو ترحيله',

            v_old_cc.name_ar, COALESCE(v_old_cc.season, 'السابق');

    END IF;



    IF COALESCE(v_old_cc.closure_count, 0) >= 2 THEN

        RAISE EXCEPTION 'مركز التكلفة (%) وصل للحد الأقصى من الإقفالات الموسمية (٢ موسم). السنة الزراعية مقفلة نهائياً.',

            v_old_cc.name_ar;

    END IF;



    IF COALESCE(v_old_cc.season_number, 1) = 1 AND COALESCE(v_old_cc.closure_count, 0) = 0 THEN

        v_closure_stage := 'season_1_to_2';

        v_new_season_number := 2;

        v_new_closure_count := 1;

        v_is_final_closure := FALSE;

    ELSE

        v_closure_stage := 'final_closure';

        v_new_season_number := 1;

        v_new_closure_count := 0;

        v_is_final_closure := TRUE;

    END IF;



    -- Strict stage validation against user request to prevent double-click stage escalation

    IF p_target_stage IS NOT NULL AND TRIM(p_target_stage) <> '' THEN

        IF p_target_stage = 'season_1_to_2' AND v_closure_stage <> 'season_1_to_2' THEN

            RAISE EXCEPTION 'تم ترحيل الفترة الأولى بالفعل لمركز التكلفة (%) ولا يمكن تكرار ترحيلها.', v_old_cc.name_ar;

        ELSIF p_target_stage = 'final_closure' AND v_closure_stage <> 'final_closure' THEN

            RAISE EXCEPTION 'يجب ترحيل الفترة الأولى أولاً قبل تنفيذ الإقفال النهائي للسنة لمركز التكلفة (%).', v_old_cc.name_ar;

        END IF;

    END IF;



    v_year_matches := regexp_matches(COALESCE(v_old_cc.season, v_old_cc.name_ar, '2026-2027'), '(\d{4})');

    IF v_year_matches IS NOT NULL AND array_length(v_year_matches, 1) >= 1 THEN

        v_old_start_year := v_year_matches[1]::INT;

    ELSE

        v_old_start_year := EXTRACT(YEAR FROM CURRENT_DATE)::INT;

    END IF;



    -- IF final closure: increment to next year. IF NOT final closure: preserve current season!

    IF v_is_final_closure THEN

        v_calc_next_season := (v_old_start_year + 1)::TEXT || '-' || (v_old_start_year + 2)::TEXT;

    ELSE

        v_calc_next_season := v_old_start_year::TEXT || '-' || (v_old_start_year + 1)::TEXT;

    END IF;



    IF p_next_season IS NOT NULL AND TRIM(p_next_season) <> '' THEN

        v_year_matches := regexp_matches(TRIM(p_next_season), '(\d{4})');

        IF v_year_matches IS NOT NULL AND array_length(v_year_matches, 1) >= 1 THEN

            DECLARE

                v_user_start_year INT := v_year_matches[1]::INT;

            BEGIN

                v_calc_next_season := v_user_start_year::TEXT || '-' || (v_user_start_year + 1)::TEXT;

            END;

        END IF;

    END IF;



    v_clean_crop_name := COALESCE(NULLIF(v_old_cc.crop_name, ''), v_old_cc.name_ar);

    v_clean_crop_name := REGEXP_REPLACE(v_clean_crop_name, '\s*[\(\[\{]?(موسم|season)\s*[^)\]\}]*[\)\]\}]?', '', 'gi');

    v_clean_crop_name := REGEXP_REPLACE(v_clean_crop_name, '\s*[\(\[\{]?\d{4}\s*[-/–]\s*\d{4}[\)\]\}]?', '', 'g');

    v_clean_crop_name := REGEXP_REPLACE(v_clean_crop_name, '\s*[\(\[\{]?\d{4}[\)\]\}]?', '', 'g');

    v_clean_crop_name := public.fn_canonical_crop_name(v_clean_crop_name);



    v_slug := COALESCE(NULLIF(v_old_cc.crop_code, ''), public.fn_resolve_crop_slug(v_clean_crop_name));



    -- Determine net balance:

    -- If p_override_balance is explicitly provided, use it directly (ensures 100% exact match with operational report)

    IF p_override_balance IS NOT NULL THEN

        v_net_balance := p_override_balance;

    ELSE

        SELECT COALESCE(SUM(

          CASE 

            -- If an intra-center rollover already exists in transactions alongside operational lines,

            -- exclude the rollover line to avoid duplicating the underlying operations

            WHEN source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$' THEN 0

            ELSE amount

          END

        ), 0) INTO v_net_balance

        FROM public.cost_center_transactions

        WHERE (cost_center_id = v_old_cc.code

           OR cost_center_id = v_old_cc.id::TEXT

           OR cost_center_name = v_old_cc.name_ar)

          AND is_confirmed = TRUE;



        -- Only add v_old_cc.opening_balance if cost_center_transactions does NOT already have an opening_balance / season_rollover transaction

        IF NOT EXISTS (

            SELECT 1 FROM public.cost_center_transactions

            WHERE (cost_center_id = v_old_cc.code OR cost_center_id = v_old_cc.id::TEXT OR cost_center_name = v_old_cc.name_ar)

              AND source_type IN ('opening_balance', 'season_rollover')

              AND is_confirmed = TRUE

        ) THEN

            v_net_balance := v_net_balance + COALESCE(v_old_cc.opening_balance, 0);

        END IF;

    END IF;



    IF NOT v_is_final_closure THEN

        -- ══════════════════════════════════════════════════════════════════════

        -- STAGE 1: INTRA-CARD ROLLOVER (P1 -> P2 inside SAME card, NO new card)

        -- ══════════════════════════════════════════════════════════════════════

        v_new_cc_id := p_cost_center_id;

        v_new_code := v_old_cc.code;

        v_new_name_ar := v_old_cc.name_ar;

        v_new_name_en := v_old_cc.name_en;



        UPDATE public.cost_centers

        SET season_number = 2,

            closure_count = 1,

            is_active = TRUE,

            status = 'active',

            season_status = 'active',

            opening_balance = v_net_balance,

            current_balance = v_net_balance,

            closed_at = NOW(),

            closed_by = auth.uid(),

            description = COALESCE(p_notes, description, 'تم ترحيل الفترة الأولى إلى الفترة الثانية داخل نفس الكارت'),

            updated_at = NOW()

        WHERE id = p_cost_center_id;



        -- Record rollover transaction inside the same cost center

        IF v_net_balance <> 0 THEN

            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || p_cost_center_id::TEXT;

            INSERT INTO public.cost_center_transactions (

                cost_center_id, cost_center_name, cost_center_type,

                source_type, source_id, transaction_date, supplier_name, product_id,

                item_name, category, quantity, unit_price, currency, exchange_rate,

                total_in_currency, amount, notes, is_confirmed

            ) VALUES (

                v_new_code, v_new_name_ar, v_old_cc.cost_center_type,

                'season_rollover', v_tx_source_id, CURRENT_DATE,

                'رصيد مرحل من الفترة الأولى', v_old_cc.product_id,

                'رصيد مرحل من الفترة الأولى (الموسم الأول)',

                'رصيد افتتاحي / مرحل',

                1, v_net_balance, 'EGP', 1.0, v_net_balance, v_net_balance,

                'ترحيل رصيد الفترة الأولى إلى الفترة الثانية داخل نفس الكارت',

                TRUE

            )

            ON CONFLICT (source_type, source_id) DO UPDATE SET

                cost_center_id = EXCLUDED.cost_center_id,

                cost_center_name = EXCLUDED.cost_center_name,

                category = EXCLUDED.category,

                amount = EXCLUDED.amount,

                total_in_currency = EXCLUDED.total_in_currency,

                quantity = EXCLUDED.quantity,

                unit_price = EXCLUDED.unit_price,

                item_name = EXCLUDED.item_name,

                notes = EXCLUDED.notes,

                updated_at = NOW();

        END IF;



    ELSE

        -- ══════════════════════════════════════════════════════════════════════

        -- STAGE 2: FINAL CLOSURE (Locks current card, creates NEW card for next year)

        -- ══════════════════════════════════════════════════════════════════════

        v_new_code := 'CC-' || v_slug || '-' || v_calc_next_season;

        v_new_name_ar := v_clean_crop_name || ' (موسم ' || v_calc_next_season || ')';

        v_new_name_en := COALESCE(v_old_cc.name_en, v_slug) || ' (Season ' || v_calc_next_season || ')';



        INSERT INTO public.cost_centers (

            code, name, name_ar, name_en, cost_center_type, product_id, entity_type,

            color, icon, is_active, status, crop_name, crop_code, season, season_status,

            opening_balance, current_balance, branch_id, description,

            closure_count, season_number

        ) VALUES (

            v_new_code, v_new_name_ar, v_new_name_ar, v_new_name_en,

            v_old_cc.cost_center_type, v_old_cc.product_id, v_old_cc.entity_type,

            v_old_cc.color, v_old_cc.icon, TRUE, 'active',

            v_clean_crop_name, v_slug, v_calc_next_season, 'active',

            v_net_balance, v_net_balance, v_old_cc.branch_id,

            COALESCE(p_notes, 'مرحل تلقائياً من موسم ' || COALESCE(v_old_cc.season, 'السابق')),

            0, 1

        )

        ON CONFLICT (code) DO UPDATE SET

            opening_balance = EXCLUDED.opening_balance,

            current_balance = EXCLUDED.current_balance,

            is_active = TRUE,

            status = 'active',

            season_status = 'active',

            crop_name = EXCLUDED.crop_name,

            closure_count = 0,

            season_number = 1,

            updated_at = NOW()

        RETURNING id INTO v_new_cc_id;



        UPDATE public.cost_centers

        SET status = 'permanently_closed',

            season_status = 'permanently_closed',

            is_active = FALSE,

            closed_at = NOW(),

            closed_by = auth.uid(),

            current_balance = v_net_balance,

            rollover_cost_center_id = v_new_cc_id,

            closure_count = 2,

            updated_at = NOW()

        WHERE id = p_cost_center_id;



    IF v_net_balance <> 0 THEN

        -- 1. Loop through all distinct product lines / varieties in the closed cost center

        FOR v_var IN

            SELECT 

                product_id,

                COALESCE(NULLIF(TRIM(item_name), ''), v_clean_crop_name) AS var_item_name,

                SUM(CASE 

                    WHEN source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$' THEN 0

                    ELSE amount

                END) AS var_net_amount,

                SUM(COALESCE(quantity, 0)) AS var_quantity

            FROM public.cost_center_transactions

            WHERE (cost_center_id = v_old_cc.code

               OR cost_center_id = v_old_cc.id::TEXT

               OR cost_center_name = v_old_cc.name_ar)

              AND is_confirmed = TRUE

            GROUP BY product_id, COALESCE(NULLIF(TRIM(item_name), ''), v_clean_crop_name)

            HAVING SUM(CASE 

                    WHEN source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$' THEN 0

                    ELSE amount

                END) <> 0

        LOOP

            v_variety_count := v_variety_count + 1;

            v_sum_variety_amounts := v_sum_variety_amounts + v_var.var_net_amount;

            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT || '_' || md5(v_var.var_item_name);



            INSERT INTO public.cost_center_transactions (

                cost_center_id, cost_center_name, cost_center_type,

                source_type, source_id, transaction_date, supplier_name, product_id,

                item_name, category, quantity, unit_price, currency, exchange_rate,

                total_in_currency, amount, notes, is_confirmed

            ) VALUES (

                v_new_code, v_new_name_ar, v_old_cc.cost_center_type,

                'season_rollover', v_tx_source_id, CURRENT_DATE,

                'رصيد افتتاحي للموسم الجديد', v_var.product_id,

                v_var.var_item_name,

                'رصيد افتتاحي منقول من الموسم السابق',

                CASE WHEN v_var.var_quantity > 0 THEN v_var.var_quantity ELSE 1 END,

                CASE WHEN v_var.var_quantity > 0 THEN ROUND(v_var.var_net_amount / v_var.var_quantity, 2) ELSE v_var.var_net_amount END,

                'EGP', 1.0, v_var.var_net_amount, v_var.var_net_amount,

                CASE WHEN v_is_final_closure

                    THEN 'رصيد مرحل نهائي للصنف (' || v_var.var_item_name || ') من السنة الزراعية ' || COALESCE(v_old_cc.season, '')

                    ELSE 'رصيد مرحل للصنف (' || v_var.var_item_name || ') من الفترة ' || COALESCE(v_old_cc.season_number, 1)::TEXT

                END,

                TRUE

            )

            ON CONFLICT (source_type, source_id) DO UPDATE SET

                cost_center_id = EXCLUDED.cost_center_id,

                cost_center_name = EXCLUDED.cost_center_name,

                category = 'رصيد افتتاحي منقول من الموسم السابق',

                amount = EXCLUDED.amount,

                total_in_currency = EXCLUDED.total_in_currency,

                quantity = EXCLUDED.quantity,

                unit_price = EXCLUDED.unit_price,

                item_name = EXCLUDED.item_name,

                notes = EXCLUDED.notes,

                updated_at = NOW();

        END LOOP;



        -- 2. If no distinct variety breakdown was found, insert standard lump-sum rollover

        IF v_variety_count = 0 THEN

            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT;



            INSERT INTO public.cost_center_transactions (

                cost_center_id, cost_center_name, cost_center_type,

                source_type, source_id, transaction_date, supplier_name, product_id,

                item_name, category, quantity, unit_price, currency, exchange_rate,

                total_in_currency, amount, notes, is_confirmed

            ) VALUES (

                v_new_code, v_new_name_ar, v_old_cc.cost_center_type,

                'season_rollover', v_tx_source_id, CURRENT_DATE,

                'رصيد افتتاحي للموسم الجديد', v_old_cc.product_id,

                CASE WHEN v_is_final_closure

                    THEN 'رصيد مرحل نهائي من السنة الزراعية ' || COALESCE(v_old_cc.season, '')

                    ELSE 'رصيد مرحل من الموسم ' || COALESCE(v_old_cc.season, '') || ' (الفترة ' || COALESCE(v_old_cc.season_number, 1)::TEXT || ')'

                END,

                'رصيد افتتاحي منقول من الموسم السابق',

                1, v_net_balance, 'EGP', 1.0, v_net_balance, v_net_balance,

                CASE WHEN v_is_final_closure

                    THEN 'ترحيل نهائي - إقفال السنة الزراعية من مركز #' || p_cost_center_id::TEXT || ' (' || v_old_cc.name_ar || ')'

                    ELSE 'ترحيل إقفال موسمي (الفترة ' || COALESCE(v_old_cc.season_number, 1)::TEXT || ') من مركز #' || p_cost_center_id::TEXT || ' (' || v_old_cc.name_ar || ')'

                END,

                TRUE

            )

            ON CONFLICT (source_type, source_id) DO UPDATE SET

                cost_center_id = EXCLUDED.cost_center_id,

                cost_center_name = EXCLUDED.cost_center_name,

                category = 'رصيد افتتاحي منقول من الموسم السابق',

                amount = EXCLUDED.amount,

                total_in_currency = EXCLUDED.total_in_currency,

                item_name = EXCLUDED.item_name,

                notes = EXCLUDED.notes,

                updated_at = NOW();

        ELSIF (v_net_balance - v_sum_variety_amounts) <> 0 THEN

            -- Insert unallocated remainder if any

            v_remainder := v_net_balance - v_sum_variety_amounts;

            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT || '_remainder';



            INSERT INTO public.cost_center_transactions (

                cost_center_id, cost_center_name, cost_center_type,

                source_type, source_id, transaction_date, supplier_name, product_id,

                item_name, category, quantity, unit_price, currency, exchange_rate,

                total_in_currency, amount, notes, is_confirmed

            ) VALUES (

                v_new_code, v_new_name_ar, v_old_cc.cost_center_type,

                'season_rollover', v_tx_source_id, CURRENT_DATE,

                'رصيد افتتاحي للموسم الجديد', v_old_cc.product_id,

                v_clean_crop_name || ' (رصيد عام غير مخصص)',

                'رصيد افتتاحي منقول من الموسم السابق',

                1, v_remainder, 'EGP', 1.0, v_remainder, v_remainder,

                'رصيد مرحل عام غير مخصص لأصناف محددة من الفترة السابقة',

                TRUE

            )

            ON CONFLICT (source_type, source_id) DO UPDATE SET

                cost_center_id = EXCLUDED.cost_center_id,

                cost_center_name = EXCLUDED.cost_center_name,

                amount = EXCLUDED.amount,

                total_in_currency = EXCLUDED.total_in_currency,

                notes = EXCLUDED.notes,

                updated_at = NOW();

        END IF;

    END IF;

    END IF;



    -- Auto-update fruit_types.cost_center_id to the new active period/season code.

    -- This ensures all subsequent purchases for this crop route to the correct open period

    -- without manual intervention (prevents stale pointer after season closure).

    UPDATE public.fruit_types

    SET cost_center_id = v_new_code

    WHERE cost_center_id = v_old_cc.code

       OR cost_center_id = p_cost_center_id::TEXT;



    RETURN jsonb_build_object(

        'success', true,

        'message', CASE WHEN v_is_final_closure

            THEN 'تم إقفال السنة الزراعية نهائياً وترحيل الرصيد للسنة الجديدة بنجاح'

            ELSE 'تم إقفال الموسم الأول وترحيل الرصيد إلى الموسم الثاني بنجاح'

        END,

        'closure_stage', v_closure_stage,

        'is_final_closure', v_is_final_closure,

        'closed_cost_center_id', p_cost_center_id,

        'closed_season', v_old_cc.season,

        'closed_season_number', COALESCE(v_old_cc.season_number, 1),

        'new_cost_center_id', v_new_cc_id,

        'new_cost_center_code', v_new_code,

        'new_cost_center_name', v_new_name_ar,

        'new_season', v_calc_next_season,

        'new_season_number', v_new_season_number,

        'rollover_balance', v_net_balance

    );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_close_and_rollover_cost_center(BIGINT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated, service_role, anon;



-- ── 7. Branch & Cost Center Binding in Financial Tables ────────────────────────

ALTER TABLE public.treasury_transactions

  ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES public.stations(id) ON DELETE SET NULL,

  ADD COLUMN IF NOT EXISTS to_branch_id BIGINT REFERENCES public.stations(id) ON DELETE SET NULL,

  ADD COLUMN IF NOT EXISTS to_cost_center_id TEXT;



CREATE INDEX IF NOT EXISTS idx_treasury_transactions_branch_id ON public.treasury_transactions(branch_id);

CREATE INDEX IF NOT EXISTS idx_treasury_transactions_to_branch_id ON public.treasury_transactions(to_branch_id);



ALTER TABLE public.account_ledger_entries

  ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES public.stations(id) ON DELETE SET NULL;



CREATE INDEX IF NOT EXISTS idx_account_ledger_entries_branch_id ON public.account_ledger_entries(branch_id);



-- ── 8. Update post_journal_entry to record branch_id & cost_center_id ──────────

CREATE OR REPLACE FUNCTION public.post_journal_entry(

    p_source_type   TEXT,

    p_description   TEXT,

    p_entry_date    DATE,

    p_company_id    UUID,

    p_created_by    UUID,

    p_lines         JSONB,

    p_source_id     TEXT DEFAULT NULL

) RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

    v_je_id         BIGINT;

    v_entry_number  TEXT;

    v_total_debit   NUMERIC := 0;

    v_total_credit  NUMERIC := 0;

    v_line          JSONB;

    v_account_id    BIGINT;

    v_debit         NUMERIC;

    v_credit        NUMERIC;

    v_base_debit    NUMERIC;

    v_base_credit   NUMERIC;

    v_currency      TEXT;

    v_desc          TEXT;

    v_cost_center_id TEXT;

    v_branch_id     BIGINT;

    v_actual_date   DATE;

    v_base_amount   NUMERIC;

BEGIN

    -- ── IDEMPOTENCY SAFEGUARD ────────────────────────────────────────────────

    IF p_source_type IS NOT NULL AND p_source_id IS NOT NULL 

       AND p_source_type NOT IN ('manual', 'adjustment', 'lot_price_adjustment') THEN

        SELECT id INTO v_je_id

        FROM public.journal_entries

        WHERE source_type = p_source_type

          AND source_id = p_source_id

          AND deleted_at IS NULL

        ORDER BY id ASC

        LIMIT 1;



        IF v_je_id IS NOT NULL THEN

            RETURN v_je_id;

        END IF;

    END IF;



    -- Auto-provision or resolve company_id

    IF p_company_id IS NULL THEN

        SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

    END IF;



    IF p_company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE id = p_company_id) THEN

        BEGIN

            INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)

            VALUES (p_company_id, 'شركة النظام', true, now(), now())

            ON CONFLICT (id) DO UPDATE SET 

                is_active = true,

                updated_at = now();

        EXCEPTION WHEN OTHERS THEN

            SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

        END;

    END IF;



    IF p_company_id IS NULL THEN

        INSERT INTO public.sys_companies (name, is_active, created_at, updated_at)

        VALUES ('الشركة الافتراضية', true, now(), now())

        RETURNING id INTO p_company_id;

    END IF;



    v_actual_date := COALESCE(p_entry_date, (NOW() AT TIME ZONE 'Africa/Cairo')::DATE);

    IF p_entry_date = CURRENT_DATE AND (NOW() AT TIME ZONE 'Africa/Cairo')::DATE != CURRENT_DATE THEN

        v_actual_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    END IF;



    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);



    INSERT INTO journal_entries (

        entry_number, entry_date, description, status,

        is_auto_generated, source_type, source_id, created_by, company_id

    ) VALUES (

        v_entry_number, v_actual_date, p_description, 'posted',

        true, p_source_type, p_source_id, p_created_by, p_company_id

    ) RETURNING id INTO v_je_id;



    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)

    LOOP

        v_account_id    := (v_line->>'account_id')::BIGINT;

        v_debit         := COALESCE((v_line->>'debit')::NUMERIC, 0);

        v_credit        := COALESCE((v_line->>'credit')::NUMERIC, 0);

        v_base_debit    := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);

        v_base_credit   := COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);

        v_currency      := COALESCE(v_line->>'currency', 'EGP');

        v_desc          := COALESCE(v_line->>'description', p_description);

        v_cost_center_id:= COALESCE(NULLIF(v_line->>'cost_center_id', ''), NULL);

        v_branch_id     := CASE WHEN (v_line->>'branch_id') ~ '^[0-9]+$' THEN (v_line->>'branch_id')::BIGINT ELSE NULL END;



        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN

            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;

        END IF;



        IF v_debit > 0 AND v_credit > 0 THEN

            RAISE EXCEPTION 'Single line cannot have both debit and credit';

        END IF;



        IF v_debit = 0 AND v_credit = 0 THEN

            CONTINUE;

        END IF;



        v_total_debit  := v_total_debit + v_base_debit;

        v_total_credit := v_total_credit + v_base_credit;

        v_base_amount  := CASE WHEN v_debit > 0 THEN v_base_debit ELSE v_base_credit END;



        INSERT INTO account_ledger_entries (

            journal_entry_id, account_id, debit, credit,

            currency, amount_in_base_currency, description, company_id, cost_center_id, branch_id

        ) VALUES (

            v_je_id, v_account_id, v_debit, v_credit,

            v_currency, v_base_amount, v_desc, p_company_id, v_cost_center_id, v_branch_id

        );

    END LOOP;



    IF ABS(v_total_debit - v_total_credit) > 0.05 THEN

        RAISE EXCEPTION 'Journal entry unbalanced in base currency: Total Base Debit = %, Total Base Credit = %', v_total_debit, v_total_credit;

    END IF;



    RETURN v_je_id;

END;

$$;



GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;



-- ── 9. Update spend_custody with Branch & Cost Center Binding ──────────────────

DO $$

DECLARE

    r RECORD;

BEGIN

    FOR r IN SELECT oid::regprocedure AS func_sig 

             FROM pg_proc 

             WHERE proname = 'spend_custody'

               AND pronamespace = 'public'::regnamespace

    LOOP

        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';

    END LOOP;

END $$;



CREATE OR REPLACE FUNCTION public.spend_custody(

    p_treasury_id bigint,

    p_currency text,

    p_amount numeric,

    p_description text DEFAULT ''::text,

    p_customer_id integer DEFAULT NULL::integer,

    p_supplier_id uuid DEFAULT NULL::uuid,

    p_clearing_agent_id bigint DEFAULT NULL::bigint,

    p_shipping_company_id bigint DEFAULT NULL::bigint,

    p_shareholder_id uuid DEFAULT NULL::uuid,

    p_expense_account_id integer DEFAULT NULL::integer,

    p_reference_type text DEFAULT NULL::text,

    p_reference_id text DEFAULT NULL::text,

    p_notes text DEFAULT NULL::text,

    p_cost_center_id text DEFAULT NULL::text,

    p_branch_id bigint DEFAULT NULL::bigint

)

RETURNS bigint

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_current_balance NUMERIC := 0;

    v_current_cost_base NUMERIC := 0;

    v_current_book_rate NUMERIC := 1.0;

    v_new_balance     NUMERIC := 0;

    v_new_cost_base   NUMERIC := 0;

    v_new_book_rate   NUMERIC := 1.0;

    v_tx_id           BIGINT;

    v_company_id      UUID;

    v_treasury_acct   BIGINT;

    v_expense_acct    BIGINT;

    v_desc            TEXT;

    v_je_id           BIGINT;

    v_source_type     TEXT;

    v_je_source_type  TEXT;

    v_book_rate       NUMERIC := 1.0;

    v_base_amount     NUMERIC;

    v_snapshot        JSONB;

    v_cc_name         TEXT;

    v_acct_name       TEXT;

    v_branch_name     TEXT;

BEGIN

    IF p_amount <= 0 THEN

        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';

    END IF;



    -- 1. Lock treasury balance row

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)

    INTO v_current_balance, v_current_cost_base, v_current_book_rate

    FROM public.treasury_balances

    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency

    FOR UPDATE;



    IF v_current_balance < p_amount THEN

        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %, المطلوب: %)', v_current_balance, p_amount;

    END IF;



    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;

    IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    END IF;



    -- 2. Use Treasury Book Rate for disbursement in Base Currency (IAS 21)

    IF p_currency = 'EGP' THEN

        v_book_rate := 1.0;

        v_base_amount := p_amount;

        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);

        v_new_book_rate := 1.0;

    ELSE

        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));

        v_base_amount := ROUND(p_amount * v_book_rate, 2);

        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);

    END IF;



    v_new_balance := v_current_balance - p_amount;



    IF v_new_balance > 0 AND p_currency != 'EGP' THEN

        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);

    ELSIF p_currency = 'EGP' THEN

        v_new_book_rate := 1.0;

    ELSE

        v_new_book_rate := v_book_rate;

        v_new_cost_base := 0;

    END IF;



    -- 3. Resolve entity and GL accounts

    IF p_customer_id IS NOT NULL THEN

        v_source_type := 'customer';

        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لعميل');

        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id = p_customer_id;

    ELSIF p_supplier_id IS NOT NULL THEN

        v_source_type := 'supplier';

        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمورد');

        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id = p_supplier_id;

    ELSIF p_clearing_agent_id IS NOT NULL THEN

        v_source_type := 'clearing_agent';

        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمخلص جمركي');

        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id = p_clearing_agent_id;

    ELSIF p_shipping_company_id IS NOT NULL THEN

        v_source_type := 'shipping_company';

        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لشركة شحن');

        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id = p_shipping_company_id;

    ELSIF p_shareholder_id IS NOT NULL THEN

        v_source_type := 'shareholder';

        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمساهم');

        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_shareholder_id;

    ELSE

        v_source_type := 'expense';

        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف مصروفات');

    END IF;



    IF p_expense_account_id IS NOT NULL THEN

        v_expense_acct := p_expense_account_id;

    END IF;



    IF v_expense_acct IS NULL THEN

        v_expense_acct := public.resolve_gl_account('51101', v_company_id);

    END IF;



    v_treasury_acct := public.resolve_treasury_account(p_treasury_id::integer, p_currency, v_company_id);



    -- 4. Update Invoice / Lot reference if provided

    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN

        UPDATE public.purchase_invoices

        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,

            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),

            payment_status = CASE

                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'

                ELSE 'partial'

            END,

            updated_at = NOW()

        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;

    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN

        UPDATE public.lot_receipts

        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,

            updated_at = NOW()

        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;

    END IF;



    -- 5. Distinct Journal Entry source_type

    v_je_source_type := CASE

        WHEN p_supplier_id IS NOT NULL THEN

            CASE

                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'

                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'

                ELSE 'supplier_payment'

            END

        WHEN p_customer_id IS NOT NULL THEN 'customer_refund'

        WHEN p_clearing_agent_id IS NOT NULL THEN 'clearing_agent_payment'

        WHEN p_shipping_company_id IS NOT NULL THEN 'shipping_company_payment'

        WHEN p_shareholder_id IS NOT NULL THEN 'shareholder_withdrawal'

        ELSE 'expense_payment'

    END;



    -- 6. Post balanced Journal Entry with cost_center_id and branch_id tagged to debit line

    v_je_id := public.post_journal_entry(

        p_source_type := v_je_source_type,

        p_description := v_desc,

        p_entry_date := CURRENT_DATE,

        p_company_id := v_company_id,

        p_created_by := auth.uid(),

        p_lines := jsonb_build_array(

            jsonb_build_object(

                'account_id', v_expense_acct,  

                'debit', p_amount, 

                'credit', 0, 

                'base_debit', v_base_amount, 

                'base_credit', 0, 

                'currency', p_currency, 

                'description', v_desc,

                'cost_center_id', p_cost_center_id,

                'branch_id', p_branch_id

            ),

            jsonb_build_object(

                'account_id', v_treasury_acct, 

                'debit', 0, 

                'credit', p_amount, 

                'base_debit', 0, 

                'base_credit', v_base_amount, 

                'currency', p_currency, 

                'description', v_desc,

                'branch_id', p_branch_id

            )

        ),

        p_source_id := p_reference_id

    );



    -- 7. Update treasury balances

    UPDATE public.treasury_balances

    SET balance = v_new_balance,

        cost_base = v_new_cost_base,

        book_rate = v_new_book_rate,

        updated_at = NOW()

    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency;



    -- 8. Insert transaction snapshot

    v_snapshot := jsonb_build_object(

        'currency', p_currency,

        'exchange_rate', v_book_rate,

        'book_rate', v_new_book_rate,

        'amount', p_amount,

        'amount_in_base_currency', v_base_amount,

        'cost_center_id', p_cost_center_id,

        'branch_id', p_branch_id,

        'rate_date', CURRENT_DATE,

        'rate_source', 'treasury_book_rate'

    );



    INSERT INTO public.treasury_transactions (

        treasury_id, type, currency, amount, balance_before, balance_after,

        description, created_by, customer_id, supplier_id, clearing_agent_id,

        shipping_company_id, shareholder_id, source_type, journal_entry_id,

        expense_account_id, exchange_rate, amount_in_base_currency, currency_snapshot,

        cost_center_id, branch_id

    ) VALUES (

        p_treasury_id, 'expense', p_currency, p_amount, v_current_balance, v_new_balance,

        v_desc, auth.uid(), p_customer_id, p_supplier_id, p_clearing_agent_id,

        p_shipping_company_id, p_shareholder_id, v_source_type, v_je_id,

        v_expense_acct, v_book_rate, v_base_amount, v_snapshot,

        p_cost_center_id, p_branch_id

    ) RETURNING id INTO v_tx_id;



    -- 9. Update Counterparty Balances

    IF p_customer_id IS NOT NULL THEN

        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;

    ELSIF p_supplier_id IS NOT NULL THEN

        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;

    ELSIF p_clearing_agent_id IS NOT NULL THEN

        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_clearing_agent_id;

    ELSIF p_shipping_company_id IS NOT NULL THEN

        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_shipping_company_id;

    ELSIF p_shareholder_id IS NOT NULL THEN

        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;

        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;

        END IF;

    END IF;



    -- 10. Sync into cost_center_transactions for Cost Reporting if cost center specified

    IF p_cost_center_id IS NOT NULL AND p_cost_center_id != '' THEN

        SELECT name_ar INTO v_cc_name FROM public.cost_centers WHERE code = p_cost_center_id OR id::text = p_cost_center_id LIMIT 1;

        SELECT COALESCE(account_name, name) INTO v_acct_name FROM public.accounts WHERE id = v_expense_acct LIMIT 1;

        IF p_branch_id IS NOT NULL THEN

            SELECT name INTO v_branch_name FROM public.stations WHERE id = p_branch_id LIMIT 1;

        END IF;



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

            is_confirmed

        ) VALUES (

            p_cost_center_id,

            COALESCE(v_cc_name, 'مركز تكلفة'),

            'operational',

            'expense',

            'exp_' || v_tx_id::text,

            CURRENT_DATE,

            p_supplier_id,

            v_desc,

            NULL::bigint,

            COALESCE(v_acct_name, v_desc),

            CASE WHEN v_branch_name IS NOT NULL THEN 'مصروفات - فرع ' || v_branch_name ELSE 'مصروفات عمومية وتشغيلية' END,

            1,

            p_amount,

            p_currency,

            v_book_rate,

            p_amount,

            v_base_amount,

            v_desc,

            TRUE

        )

        ON CONFLICT (source_type, source_id) DO UPDATE SET

            cost_center_id = EXCLUDED.cost_center_id,

            amount = EXCLUDED.amount,

            total_in_currency = EXCLUDED.total_in_currency,

            updated_at = NOW();

    END IF;



    RETURN v_tx_id;

END;

$$;



GRANT EXECUTE ON FUNCTION public.spend_custody(bigint, text, numeric, text, integer, uuid, bigint, bigint, uuid, integer, text, text, text, text, bigint) TO authenticated, service_role, anon;





-- ── 10. Update transfer_custody with Branch & Cost Center Binding ─────────────

DO $$

DECLARE

    r RECORD;

BEGIN

    FOR r IN SELECT oid::regprocedure AS func_sig 

             FROM pg_proc 

             WHERE proname = 'transfer_custody'

               AND pronamespace = 'public'::regnamespace

    LOOP

        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';

    END LOOP;

END $$;



CREATE OR REPLACE FUNCTION public.transfer_custody(

    p_from_treasury_id integer,

    p_to_treasury_id integer,

    p_currency text,

    p_amount numeric,

    p_description text DEFAULT ''::text,

    p_notes text DEFAULT NULL::text,

    p_cost_center_id text DEFAULT NULL::text,

    p_branch_id bigint DEFAULT NULL::bigint,

    p_to_branch_id bigint DEFAULT NULL::bigint,

    p_to_cost_center_id text DEFAULT NULL::text

)

RETURNS bigint

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_from_balance NUMERIC;

    v_to_balance   NUMERIC;

    v_from_cost_base NUMERIC;

    v_to_cost_base NUMERIC;

    v_from_book_rate NUMERIC;

    v_to_book_rate NUMERIC;

    v_base_amount  NUMERIC;

    v_tx_id        BIGINT;

    v_je_id        BIGINT;

    v_company_id   UUID;

    v_from_acct    BIGINT;

    v_to_acct      BIGINT;

    v_desc         TEXT;

    v_user_id      UUID;

    v_from_name    TEXT;

    v_to_name      TEXT;

    v_dest_branch_id BIGINT;

    v_dest_cc_id   TEXT;

BEGIN

    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN

        SELECT id INTO v_user_id FROM public.users LIMIT 1;

    END IF;



    v_dest_branch_id := COALESCE(p_to_branch_id, p_branch_id);

    v_dest_cc_id := COALESCE(p_to_cost_center_id, p_cost_center_id);



    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)

    INTO v_from_balance, v_from_cost_base, v_from_book_rate

    FROM public.treasury_balances 

    WHERE treasury_id = p_from_treasury_id AND currency = p_currency

    FOR UPDATE;



    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN

        RAISE EXCEPTION 'الرصيد غير كاف للتحويل (المتوفر: %, المطلوب: %)', v_from_balance, p_amount;

    END IF;



    IF p_currency = 'EGP' THEN

        v_base_amount := p_amount;

    ELSE

        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);

    END IF;



    UPDATE public.treasury_balances 

    SET balance = balance - p_amount,

        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),

        updated_at = NOW()

    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;



    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)

    INTO v_to_balance, v_to_cost_base, v_to_book_rate

    FROM public.treasury_balances 

    WHERE treasury_id = p_to_treasury_id AND currency = p_currency

    FOR UPDATE;



    IF NOT FOUND THEN

        v_to_balance := 0;

        v_to_cost_base := 0;

        v_to_book_rate := 1.0;

        INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)

        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM public.treasuries WHERE id = p_to_treasury_id)));

    END IF;



    IF p_currency = 'EGP' THEN

        v_to_book_rate := 1.0;

    ELSE

        IF (v_to_balance + p_amount) > 0 THEN

            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);

        END IF;

    END IF;



    UPDATE public.treasury_balances

    SET balance = balance + p_amount,

        cost_base = COALESCE(cost_base, 0) + v_base_amount,

        book_rate = v_to_book_rate,

        updated_at = NOW()

    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;



    SELECT name INTO v_from_name FROM public.treasuries WHERE id = p_from_treasury_id;

    SELECT name INTO v_to_name FROM public.treasuries WHERE id = p_to_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل عهدة من ' || COALESCE(v_from_name, '') || ' إلى ' || COALESCE(v_to_name, ''));



    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_from_treasury_id;

    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);

    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);



    IF v_to_acct IS NULL THEN

        v_to_acct := public.ensure_custody_account(p_to_treasury_id, v_company_id);

    END IF;

    IF v_from_acct IS NULL THEN

        v_from_acct := public.ensure_custody_account(p_from_treasury_id, v_company_id);

    END IF;



    -- Post balanced journal entry tagging respective branch_id and cost_center_id on each line

    v_je_id := public.post_journal_entry(

        'custody_transfer', v_desc, CURRENT_DATE, v_company_id, v_user_id,

        jsonb_build_array(

            jsonb_build_object(

                'account_id', v_to_acct, 

                'debit', p_amount, 

                'credit', 0, 

                'currency', p_currency, 

                'description', v_desc || ' (استلام تحويل)', 

                'base_debit', v_base_amount, 

                'base_credit', 0,

                'cost_center_id', v_dest_cc_id,

                'branch_id', v_dest_branch_id

            ),

            jsonb_build_object(

                'account_id', v_from_acct, 

                'debit', 0, 

                'credit', p_amount, 

                'currency', p_currency, 

                'description', v_desc || ' (إرسال تحويل)', 

                'base_debit', 0, 

                'base_credit', v_base_amount,

                'cost_center_id', p_cost_center_id,

                'branch_id', p_branch_id

            )

        )

    );



    INSERT INTO public.treasury_transactions (

        treasury_id, type, amount, currency, description,

        balance_before, balance_after,

        reference_type, reference_id, notes, created_by, journal_entry_id,

        cost_center_id, branch_id, to_branch_id, to_cost_center_id

    ) VALUES (

        p_from_treasury_id, 'transfer_out', p_amount, p_currency, v_desc,

        v_from_balance, v_from_balance - p_amount,

        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id,

        p_cost_center_id, p_branch_id, v_dest_branch_id, v_dest_cc_id

    ) RETURNING id INTO v_tx_id;



    INSERT INTO public.treasury_transactions (

        treasury_id, type, amount, currency, description,

        balance_before, balance_after,

        reference_type, reference_id, notes, created_by, journal_entry_id,

        cost_center_id, branch_id, to_branch_id, to_cost_center_id

    ) VALUES (

        p_to_treasury_id, 'transfer_in', p_amount, p_currency, v_desc,

        v_to_balance, v_to_balance + p_amount,

        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id,

        v_dest_cc_id, v_dest_branch_id, p_branch_id, p_cost_center_id

    );



    RETURN v_tx_id;

END;

$$;



GRANT EXECUTE ON FUNCTION public.transfer_custody(integer, integer, text, numeric, text, text, text, bigint, bigint, text) TO authenticated, service_role, anon;





-- ── 11. Update rpc_save_treasury_draft & rpc_update_treasury_draft ────────────

DO $$

DECLARE

    r RECORD;

BEGIN

    FOR r IN SELECT oid::regprocedure AS func_sig 

             FROM pg_proc 

             WHERE proname IN ('rpc_save_treasury_draft', 'rpc_update_treasury_draft')

               AND pronamespace = 'public'::regnamespace

    LOOP

        EXECUTE 'DROP FUNCTION ' || r.func_sig || ' CASCADE';

    END LOOP;

END $$;



CREATE OR REPLACE FUNCTION public.rpc_save_treasury_draft(

    p_treasury_id BIGINT,

    p_type TEXT,

    p_amount NUMERIC,

    p_currency TEXT,

    p_description TEXT DEFAULT NULL,

    p_notes TEXT DEFAULT NULL,

    p_category_id BIGINT DEFAULT NULL,

    p_expense_account_id BIGINT DEFAULT NULL,

    p_revenue_account_id BIGINT DEFAULT NULL,

    p_customer_id BIGINT DEFAULT NULL,

    p_supplier_id UUID DEFAULT NULL,

    p_clearing_agent_id BIGINT DEFAULT NULL,

    p_shipping_company_id BIGINT DEFAULT NULL,

    p_shareholder_id UUID DEFAULT NULL,

    p_payload JSONB DEFAULT '{}'::jsonb,

    p_cost_center_id TEXT DEFAULT NULL,

    p_branch_id BIGINT DEFAULT NULL,

    p_to_branch_id BIGINT DEFAULT NULL,

    p_to_cost_center_id TEXT DEFAULT NULL

)

RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_tx_id BIGINT;

    v_payload JSONB;

    v_cc_id TEXT;

    v_branch_id BIGINT;

    v_cat_id BIGINT := p_category_id;

BEGIN

    IF p_amount <= 0 THEN

        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';

    END IF;



    -- Safety check: ensure category_id actually exists in expense_categories to prevent FK 23503

    IF v_cat_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.expense_categories WHERE id = v_cat_id) THEN

        v_cat_id := NULL;

    END IF;



    v_cc_id := COALESCE(p_cost_center_id, p_payload->>'cost_center_id');

    v_branch_id := COALESCE(p_branch_id, CASE WHEN (p_payload->>'branch_id') ~ '^[0-9]+$' THEN (p_payload->>'branch_id')::BIGINT ELSE NULL END);



    v_payload := COALESCE(p_payload, '{}'::jsonb);

    IF v_cc_id IS NOT NULL THEN

        v_payload := jsonb_set(v_payload, '{cost_center_id}', to_jsonb(v_cc_id));

    END IF;

    IF v_branch_id IS NOT NULL THEN

        v_payload := jsonb_set(v_payload, '{branch_id}', to_jsonb(v_branch_id));

    END IF;

    IF p_to_branch_id IS NOT NULL THEN

        v_payload := jsonb_set(v_payload, '{to_branch_id}', to_jsonb(p_to_branch_id));

    END IF;

    IF p_to_cost_center_id IS NOT NULL THEN

        v_payload := jsonb_set(v_payload, '{to_cost_center_id}', to_jsonb(p_to_cost_center_id));

    END IF;



    INSERT INTO public.treasury_transactions (

        treasury_id,

        type,

        amount,

        currency,

        description,

        notes,

        category_id,

        expense_account_id,

        revenue_account_id,

        customer_id,

        supplier_id,

        clearing_agent_id,

        shipping_company_id,

        shareholder_id,

        status,

        payload,

        cost_center_id,

        branch_id,

        to_branch_id,

        to_cost_center_id,

        created_by,

        created_at

    ) VALUES (

        p_treasury_id,

        p_type,

        p_amount,

        p_currency,

        p_description,

        p_notes,

        v_cat_id,

        p_expense_account_id,

        p_revenue_account_id,

        p_customer_id,

        p_supplier_id,

        p_clearing_agent_id,

        p_shipping_company_id,

        p_shareholder_id,

        'draft',

        v_payload,

        v_cc_id,

        v_branch_id,

        p_to_branch_id,

        p_to_cost_center_id,

        auth.uid(),

        NOW()

    )

    RETURNING id INTO v_tx_id;



    RETURN v_tx_id;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_save_treasury_draft(BIGINT, TEXT, NUMERIC, TEXT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, UUID, BIGINT, BIGINT, UUID, JSONB, TEXT, BIGINT, BIGINT, TEXT) TO authenticated, service_role, anon;





-- Update rpc_update_treasury_draft

CREATE OR REPLACE FUNCTION public.rpc_update_treasury_draft(

    p_transaction_id BIGINT,

    p_treasury_id BIGINT DEFAULT NULL,

    p_amount NUMERIC DEFAULT NULL,

    p_currency TEXT DEFAULT NULL,

    p_description TEXT DEFAULT NULL,

    p_notes TEXT DEFAULT NULL,

    p_category_id BIGINT DEFAULT NULL,

    p_expense_account_id BIGINT DEFAULT NULL,

    p_revenue_account_id BIGINT DEFAULT NULL,

    p_customer_id BIGINT DEFAULT NULL,

    p_supplier_id UUID DEFAULT NULL,

    p_clearing_agent_id BIGINT DEFAULT NULL,

    p_shipping_company_id BIGINT DEFAULT NULL,

    p_shareholder_id UUID DEFAULT NULL,

    p_payload JSONB DEFAULT NULL,

    p_cost_center_id TEXT DEFAULT NULL,

    p_branch_id BIGINT DEFAULT NULL,

    p_to_branch_id BIGINT DEFAULT NULL,

    p_to_cost_center_id TEXT DEFAULT NULL

)

RETURNS BOOLEAN

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_cc_id TEXT;

    v_branch_id BIGINT;

    v_payload JSONB;

    v_cat_id BIGINT := p_category_id;

BEGIN

    -- Safety check: ensure category_id actually exists in expense_categories to prevent FK 23503

    IF v_cat_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.expense_categories WHERE id = v_cat_id) THEN

        v_cat_id := NULL;

    END IF;



    v_cc_id := COALESCE(p_cost_center_id, p_payload->>'cost_center_id');

    v_branch_id := COALESCE(p_branch_id, CASE WHEN (p_payload->>'branch_id') ~ '^[0-9]+$' THEN (p_payload->>'branch_id')::BIGINT ELSE NULL END);



    UPDATE public.treasury_transactions

    SET

        treasury_id = COALESCE(p_treasury_id, treasury_id),

        amount = COALESCE(p_amount, amount),

        currency = COALESCE(p_currency, currency),

        description = COALESCE(p_description, description),

        notes = p_notes,

        category_id = v_cat_id,

        expense_account_id = p_expense_account_id,

        revenue_account_id = p_revenue_account_id,

        customer_id = p_customer_id,

        supplier_id = p_supplier_id,

        clearing_agent_id = p_clearing_agent_id,

        shipping_company_id = p_shipping_company_id,

        shareholder_id = p_shareholder_id,

        cost_center_id = COALESCE(v_cc_id, cost_center_id),

        branch_id = COALESCE(v_branch_id, branch_id),

        to_branch_id = COALESCE(p_to_branch_id, to_branch_id),

        to_cost_center_id = COALESCE(p_to_cost_center_id, to_cost_center_id),

        payload = CASE 

            WHEN p_payload IS NOT NULL THEN p_payload

            ELSE payload 

        END

    WHERE id = p_transaction_id AND status = 'draft';



    IF NOT FOUND THEN

        RAISE EXCEPTION 'لم يتم العثور على المسودة أو أنها مؤكدة بالفعل';

    END IF;



    RETURN TRUE;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_update_treasury_draft(BIGINT, BIGINT, NUMERIC, TEXT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, UUID, BIGINT, BIGINT, UUID, JSONB, TEXT, BIGINT, BIGINT, TEXT) TO authenticated, service_role, anon;



ALTER TABLE IF EXISTS public.supplier_payment_allocations 

    ADD COLUMN IF NOT EXISTS currency TEXT,

    ADD COLUMN IF NOT EXISTS entity_type TEXT,

    ADD COLUMN IF NOT EXISTS entity_id TEXT;



-- ── 12. Update rpc_confirm_treasury_draft to propagate branch_id ──────────────

CREATE OR REPLACE FUNCTION public.rpc_confirm_treasury_draft(

    p_transaction_id BIGINT

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_tx RECORD;

    v_res JSONB;

    v_spend_id BIGINT;

    v_receipt_type TEXT;

    v_counterparty_type TEXT;

    v_mp_source_type TEXT;

    v_mp_source_id BIGINT;

    v_cost_center_id TEXT;

    v_branch_id BIGINT;

BEGIN

    SELECT * INTO v_tx

    FROM public.treasury_transactions

    WHERE id = p_transaction_id FOR UPDATE;



    IF NOT FOUND THEN

        RAISE EXCEPTION 'الحركة غير موجودة';

    END IF;



    IF v_tx.status != 'draft' THEN

        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';

    END IF;



    v_cost_center_id := COALESCE(v_tx.cost_center_id, NULLIF(v_tx.payload->>'cost_center_id', ''));

    v_branch_id := COALESCE(

        v_tx.branch_id, 

        CASE WHEN (v_tx.payload->>'branch_id') ~ '^[0-9]+$' THEN (v_tx.payload->>'branch_id')::BIGINT ELSE NULL END

    );



    IF v_tx.type = 'deposit' OR v_tx.type = 'receipt' THEN

        v_receipt_type := COALESCE(v_tx.payload->>'receipt_type', 'cash');

        v_counterparty_type := v_tx.payload->>'counterparty_type';



        v_res := public.receive_payment(

            p_receipt_type      := v_receipt_type,

            p_amount            := v_tx.amount,

            p_currency          := v_tx.currency,

            p_counterparty_type := v_counterparty_type,

            p_counterparty_id   := COALESCE(v_tx.customer_id, NULLIF(v_tx.payload->>'counterparty_id', '')::integer, NULLIF(v_tx.payload->>'customer_id', '')::integer),

            p_supplier_id       := COALESCE(v_tx.supplier_id, NULLIF(v_tx.payload->>'supplier_id', '')::uuid),

            p_shareholder_id    := COALESCE(v_tx.shareholder_id, NULLIF(v_tx.payload->>'shareholder_id', '')::uuid),

            p_description       := v_tx.description,

            p_notes             := v_tx.notes,

            p_treasury_id       := v_tx.treasury_id

        );



        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;



        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الاستلام وترحيل القيد بنجاح', 'result', v_res);



    ELSIF v_tx.type = 'multi_payment' OR COALESCE((v_tx.payload->>'is_multi_payment')::boolean, false) = true THEN

        v_mp_source_type := COALESCE(v_tx.payload->>'source_type', 'treasury');

        v_mp_source_id   := COALESCE(

            (v_tx.payload->>'source_id')::bigint,

            v_tx.treasury_id::bigint

        );



        v_res := public.rpc_entity_multi_payment(

            p_source_type        := v_mp_source_type,

            p_source_id          := v_mp_source_id,

            p_currency           := v_tx.currency,

            p_amount             := v_tx.amount,

            p_entity_type        := LOWER(COALESCE(v_tx.payload->>'entity_type', 'supplier')),

            p_entity_id          := COALESCE(v_tx.payload->>'entity_id', v_tx.supplier_id::text),

            p_description        := COALESCE(v_tx.description, 'سداد متعدد'),

            p_expense_account_id := v_tx.expense_account_id,

            p_notes              := v_tx.notes

        );



        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;



        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد السداد المتعدد بنجاح', 'result', v_res);



    ELSIF v_tx.type = 'exchange' OR v_tx.type = 'currency_exchange' THEN

        PERFORM public.exchange_currency(

            p_treasury_id   := v_tx.treasury_id::text,

            p_from_currency := COALESCE(v_tx.payload->>'from_currency', v_tx.currency),

            p_to_currency   := (v_tx.payload->>'to_currency')::text,

            p_amount_from   := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),

            p_amount_to     := (v_tx.payload->>'amount_to')::numeric,

            p_exchange_rate := (v_tx.payload->>'exchange_rate')::numeric,

            p_user_id       := v_tx.created_by,

            p_transfer_mode := COALESCE(v_tx.payload->>'transfer_mode', 'exchange'),

            p_description   := COALESCE(v_tx.description, 'تحويل عملة')

        );



        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;



        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة بنجاح');



    ELSIF v_tx.type = 'expense' OR v_tx.type = 'withdrawal' THEN

        v_spend_id := public.spend_custody(

            p_treasury_id        := v_tx.treasury_id::bigint,

            p_currency           := v_tx.currency,

            p_amount             := v_tx.amount,

            p_description        := v_tx.description,

            p_supplier_id        := COALESCE(v_tx.supplier_id, NULLIF(v_tx.payload->>'supplier_id', '')::uuid),

            p_expense_account_id := COALESCE(

                v_tx.expense_account_id::integer, 

                NULLIF(v_tx.payload->>'expense_account_id', '')::integer, 

                v_tx.category_id::integer

            ),

            p_notes              := v_tx.notes,

            p_customer_id        := COALESCE(v_tx.customer_id, NULLIF(v_tx.payload->>'customer_id', '')::integer),

            p_clearing_agent_id  := COALESCE(v_tx.clearing_agent_id, NULLIF(v_tx.payload->>'clearing_agent_id', '')::bigint),

            p_shipping_company_id := COALESCE(v_tx.shipping_company_id, NULLIF(v_tx.payload->>'shipping_company_id', '')::bigint),

            p_shareholder_id     := COALESCE(v_tx.shareholder_id, NULLIF(v_tx.payload->>'shareholder_id', '')::uuid),

            p_cost_center_id     := v_cost_center_id,

            p_branch_id          := v_branch_id

        );



        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;



        RETURN jsonb_build_object(

            'success', true, 

            'message', 'تم تأكيد المصروف وترحيل القيد بنجاح', 

            'result', jsonb_build_object('transaction_id', v_spend_id)

        );

    ELSE

        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;

    END IF;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_treasury_draft(bigint) TO authenticated, anon, service_role;



-- ── 13. Update Trigger for lot_receipts to use Canonical Crop Cost Center ─────

CREATE OR REPLACE FUNCTION public.fn_sync_lot_receipt_cost_center_transaction()

RETURNS TRIGGER AS $$

DECLARE

  v_ft_code TEXT;

  v_ft_name TEXT;

  v_supplier_name TEXT;

  v_unit_price NUMERIC;

  v_amount NUMERIC;

  v_cc_id TEXT;

  v_ex_rate NUMERIC;

  v_canon_crop_name TEXT;

BEGIN

  -- Lookup fruit type details

  SELECT code, name INTO v_ft_code, v_ft_name

  FROM public.fruit_types

  WHERE id = NEW.fruit_type_id;



  v_canon_crop_name := public.fn_canonical_crop_name(COALESCE(NEW.product_name, v_ft_name, 'محصول'));

  v_cc_id := public.fn_resolve_crop_cost_center_code(v_canon_crop_name, NEW.fruit_type_id);



  -- Lookup supplier name

  SELECT name INTO v_supplier_name

  FROM public.suppliers

  WHERE id::text = NEW.supplier_id::text;



  v_ex_rate := COALESCE(NEW.exchange_rate, 1.0);

  IF v_ex_rate <= 0 THEN

    v_ex_rate := 1.0;

  END IF;



  v_amount := ROUND((NEW.total_fruit_cost * v_ex_rate)::numeric, 2);

  v_unit_price := ROUND((v_amount / NULLIF(NEW.gross_weight_kg, 0))::numeric, 2);



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

    is_confirmed

  ) VALUES (

    v_cc_id,

    v_canon_crop_name,

    'variety',

    'lot_receipt',

    NEW.id::text,

    NEW.receipt_date::date,

    NEW.supplier_id::text,

    v_supplier_name,

    NEW.fruit_type_id,

    v_canon_crop_name,

    'تكلفة المحاصيل',

    NEW.gross_weight_kg,

    v_unit_price,

    COALESCE(NEW.currency, 'EGP'),

    v_ex_rate,

    ROUND(NEW.total_fruit_cost::numeric, 2),

    v_amount,

    NEW.notes,

    COALESCE(NEW.is_confirmed, TRUE)

  )

  ON CONFLICT (source_type, source_id) DO UPDATE SET

    cost_center_id = EXCLUDED.cost_center_id,

    cost_center_name = EXCLUDED.cost_center_name,

    transaction_date = EXCLUDED.transaction_date,

    supplier_id = EXCLUDED.supplier_id,

    supplier_name = EXCLUDED.supplier_name,

    product_id = EXCLUDED.product_id,

    item_name = EXCLUDED.item_name,

    quantity = EXCLUDED.quantity,

    unit_price = EXCLUDED.unit_price,

    currency = EXCLUDED.currency,

    exchange_rate = EXCLUDED.exchange_rate,

    total_in_currency = EXCLUDED.total_in_currency,

    amount = EXCLUDED.amount,

    notes = EXCLUDED.notes,

    is_confirmed = EXCLUDED.is_confirmed,

    updated_at = NOW();



  RETURN NEW;

END;

$$ LANGUAGE plpgsql;



-- ==============================================================================

-- APPENDED FROM MIGRATION 470 (Disable Auto Cost Center & Explicit Product Link)

-- ==============================================================================

-- ============================================================================

-- Migration 470: Disable Automatic Cost Center on Product & Bind Explicitly

-- ============================================================================

-- Description:

-- 1. Drops automatic cost center creation trigger from fruit_types table.

--    Accountants will manually define cost centers via the Cost Centers page.

-- 2. Adds explicit cost_center_id column to fruit_types to allow direct linking.

-- 3. Updates fn_sync_lot_receipt_cost_center_transaction to prioritize

--    the explicitly linked cost_center_id on fruit_types before falling back

--    to canonical crop-level cost center resolution.

-- ============================================================================





-- ── 1. Drop Automatic Cost Center Trigger & Sync Function ──────────────────

DROP TRIGGER IF EXISTS trg_fruit_types_cost_center ON public.fruit_types;

DROP FUNCTION IF EXISTS public.fn_sync_fruit_type_cost_center();



-- ── 2. Add Explicit cost_center_id Column to fruit_types ───────────────────

ALTER TABLE public.fruit_types 

  ADD COLUMN IF NOT EXISTS cost_center_id TEXT;

ALTER TABLE public.fruit_types 

  ALTER COLUMN cost_center_id TYPE TEXT USING cost_center_id::TEXT;



CREATE INDEX IF NOT EXISTS idx_fruit_types_cost_center_id 

  ON public.fruit_types (cost_center_id);



COMMENT ON COLUMN public.fruit_types.cost_center_id IS 

  'Explicitly selected cost center code or ID manually linked to this fruit item.';



-- ── 3. Update fn_sync_lot_receipt_cost_center_transaction ──────────────────

-- Prioritizes fruit_types.cost_center_id if set by the accountant.

CREATE OR REPLACE FUNCTION public.fn_sync_lot_receipt_cost_center_transaction()

RETURNS TRIGGER AS $$

DECLARE

  v_ft_name TEXT;

  v_supplier_name TEXT;

  v_unit_price NUMERIC;

  v_qty NUMERIC;

  v_amount NUMERIC;

  v_cc_id TEXT;

  v_cc_name TEXT;

  v_ex_rate NUMERIC;

BEGIN

  -- Lookup fruit type name if product_name not set

  IF NEW.product_name IS NULL OR TRIM(NEW.product_name) = '' THEN

    SELECT name INTO v_ft_name FROM public.fruit_types WHERE id = NEW.fruit_type_id;

  END IF;



  -- Resolve the exact active seasonal cost center

  SELECT r.cost_center_id, r.cost_center_name

  INTO v_cc_id, v_cc_name

  FROM public.fn_resolve_active_crop_cost_center(

    COALESCE(NEW.product_name, v_ft_name, 'محصول'),

    NEW.fruit_type_id

  ) r;



  -- Lookup supplier name

  SELECT name INTO v_supplier_name

  FROM public.suppliers

  WHERE id::text = NEW.supplier_id::text;



  v_ex_rate := COALESCE(NEW.exchange_rate, 1.0);

  IF v_ex_rate <= 0 THEN v_ex_rate := 1.0; END IF;



  v_amount := ROUND((NEW.total_fruit_cost * v_ex_rate)::numeric, 2);



  -- Unit Dimension Selection:

  IF COALESCE(NEW.purchase_mode, 'weight') = 'carton' AND COALESCE(NEW.carton_count, 0) > 0 THEN

    v_qty := NEW.carton_count;

    v_unit_price := COALESCE(NULLIF(NEW.price_per_carton, 0), ROUND((v_amount / NULLIF(NEW.carton_count, 0))::numeric, 2));

  ELSE

    v_qty := COALESCE(NULLIF(NEW.net_weight_kg, 0), NEW.gross_weight_kg, 0);

    v_unit_price := ROUND((v_amount / NULLIF(v_qty, 0))::numeric, 2);

  END IF;



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

    is_confirmed

  ) VALUES (

    v_cc_id,

    v_cc_name,

    'variety',

    'lot_receipt',

    NEW.id::text,

    NEW.receipt_date::date,

    NEW.supplier_id::text,

    v_supplier_name,

    NEW.fruit_type_id,

    COALESCE(NEW.product_name, v_ft_name, 'محصول'),

    'تكلفة المحاصيل',

    v_qty,

    v_unit_price,

    COALESCE(NEW.currency, 'EGP'),

    v_ex_rate,

    ROUND(NEW.total_fruit_cost::numeric, 2),

    v_amount,

    NEW.notes,

    COALESCE(NEW.is_confirmed, TRUE)

  )

  ON CONFLICT (source_type, source_id) DO UPDATE SET

    cost_center_id = EXCLUDED.cost_center_id,

    cost_center_name = EXCLUDED.cost_center_name,

    transaction_date = EXCLUDED.transaction_date,

    supplier_id = EXCLUDED.supplier_id,

    supplier_name = EXCLUDED.supplier_name,

    product_id = EXCLUDED.product_id,

    item_name = EXCLUDED.item_name,

    quantity = EXCLUDED.quantity,

    unit_price = EXCLUDED.unit_price,

    currency = EXCLUDED.currency,

    exchange_rate = EXCLUDED.exchange_rate,

    total_in_currency = EXCLUDED.total_in_currency,

    amount = EXCLUDED.amount,

    notes = EXCLUDED.notes,

    is_confirmed = EXCLUDED.is_confirmed,

    updated_at = NOW();



  RETURN NEW;

END;

$$ LANGUAGE plpgsql;



-- ── 4. Drop & Recreate rpc_get_lot_return_available_quantities ───────────────

DO $$

DECLARE r RECORD;

BEGIN

  FOR r IN

    SELECT oid::regprocedure AS sig

    FROM pg_proc

    WHERE proname = 'rpc_get_lot_return_available_quantities'

      AND pronamespace = 'public'::regnamespace

  LOOP

    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';

  END LOOP;

END $$;

DROP FUNCTION IF EXISTS public.rpc_get_lot_return_available_quantities(bigint) CASCADE;

DROP FUNCTION IF EXISTS public.rpc_get_lot_return_available_quantities CASCADE;



CREATE OR REPLACE FUNCTION public.rpc_get_lot_return_available_quantities(

  p_lot_id bigint DEFAULT NULL

)

RETURNS TABLE (

  lot_id bigint,

  lot_number text,

  product_name text,

  fruit_type_id text,

  supplier_id text,

  supplier_name text,

  station_id text,

  station_name text,

  receipt_date date,

  purchase_mode text,

  currency text,

  exchange_rate numeric,

  unit_price numeric,

  total_fruit_cost numeric,

  purchased_quantity numeric,

  net_quantity numeric,

  already_returned_quantity numeric,

  available_quantity numeric,

  unit_label text

)

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

BEGIN

  RETURN QUERY

  WITH returns_agg AS (

    SELECT

      lr_ret.lot_receipt_id,

      COALESCE(SUM(lr_ret.returned_quantity), 0)::numeric AS total_returned

    FROM public.lot_returns lr_ret

    GROUP BY lr_ret.lot_receipt_id

  ),

  batches_agg AS (

    SELECT

      spb.product_code,

      COALESCE(SUM(spb.quantity), 0)::numeric AS initial_batch_quantity,

      COALESCE(SUM(spb.remaining_quantity), 0)::numeric AS total_batch_remaining

    FROM public.station_product_batches spb

    WHERE spb.source_type = 'lot_receipt'

    GROUP BY spb.product_code

  )

  SELECT

    lr.id::bigint AS lot_id,

    COALESCE(lr.lot_number, lr.id::text)::text AS lot_number,

    COALESCE(lr.product_name, 'محصول')::text AS product_name,

    lr.fruit_type_id::text AS fruit_type_id,

    lr.supplier_id::text AS supplier_id,

    COALESCE(s.name, 'بدون مورد')::text AS supplier_name,

    lr.station_id::text AS station_id,

    COALESCE(st.name, 'المحطة الرئيسية')::text AS station_name,

    lr.receipt_date::date AS receipt_date,

    COALESCE(lr.purchase_mode, 'weight')::text AS purchase_mode,

    COALESCE(lr.currency, 'EGP')::text AS currency,

    COALESCE(lr.exchange_rate, 1.0)::numeric AS exchange_rate,

    -- Effective Unit Price per Net Unit:

    (CASE

      WHEN COALESCE(lr.purchase_mode, 'weight') = 'carton' THEN

        CASE

          WHEN COALESCE(lr.price_per_carton, 0) > 0 THEN lr.price_per_carton::numeric

          WHEN COALESCE(lr.total_fruit_cost, 0) > 0 AND COALESCE(ba.initial_batch_quantity, lr.carton_count, 0) > 0 THEN

            ROUND((lr.total_fruit_cost / COALESCE(ba.initial_batch_quantity, lr.carton_count))::numeric, 2)

          ELSE COALESCE(lr.fruit_cost_per_kg, 0)::numeric

        END

      WHEN COALESCE(lr.total_fruit_cost, 0) > 0 AND COALESCE(NULLIF(lr.net_weight_kg, 0), lr.gross_weight_kg, ba.initial_batch_quantity, 0) > 0 THEN

        ROUND((lr.total_fruit_cost / NULLIF(COALESCE(NULLIF(lr.net_weight_kg, 0), lr.gross_weight_kg, ba.initial_batch_quantity, 0), 0))::numeric, 2)

      WHEN COALESCE(lr.fruit_cost_per_kg, 0) > 0 THEN lr.fruit_cost_per_kg::numeric

      ELSE 0::numeric

    END)::numeric AS unit_price,

    COALESCE(lr.total_fruit_cost, 0)::numeric AS total_fruit_cost,

    -- Gross Original Purchase Quantity:

    (CASE

      WHEN COALESCE(lr.purchase_mode, 'weight') = 'carton' THEN

        COALESCE(lr.carton_count, ba.initial_batch_quantity, 0)::numeric

      ELSE

        COALESCE(NULLIF(lr.gross_weight_kg, 0), lr.net_weight_kg, ba.initial_batch_quantity, 0)::numeric

    END)::numeric AS purchased_quantity,

    -- Net Warehouse Quantity:

    (CASE

      WHEN COALESCE(ba.initial_batch_quantity, 0) > 0 THEN

        ba.initial_batch_quantity::numeric

      WHEN COALESCE(lr.purchase_mode, 'weight') = 'carton' THEN

        CASE

          WHEN COALESCE(lr.weight_per_carton_kg, 0) > 0 AND COALESCE(lr.net_weight_kg, 0) > 0

               AND ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0) > 0

               AND ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0) <= COALESCE(lr.carton_count, 999999999) THEN

            ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0)

          WHEN COALESCE(lr.carton_count, 0) > 0 THEN lr.carton_count::numeric

          ELSE COALESCE(ba.total_batch_remaining, 0)::numeric

        END

      ELSE

        COALESCE(NULLIF(lr.net_weight_kg, 0), lr.gross_weight_kg, 0)::numeric

    END)::numeric AS net_quantity,

    COALESCE(ra.total_returned, 0)::numeric AS already_returned_quantity,

    -- Available quantity: strictly based on Net Warehouse Quantity minus returns, capped by actual batch stock if batches exist

    LEAST(

      GREATEST(0, (

        CASE

          WHEN COALESCE(ba.initial_batch_quantity, 0) > 0 THEN

            ba.initial_batch_quantity::numeric

          WHEN COALESCE(lr.purchase_mode, 'weight') = 'carton' THEN

            CASE

              WHEN COALESCE(lr.weight_per_carton_kg, 0) > 0 AND COALESCE(lr.net_weight_kg, 0) > 0

                   AND ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0) > 0

                   AND ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0) <= COALESCE(lr.carton_count, 999999999) THEN

                ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0)

              WHEN COALESCE(lr.carton_count, 0) > 0 THEN lr.carton_count::numeric

              ELSE COALESCE(ba.total_batch_remaining, 0)::numeric

            END

          ELSE

            COALESCE(NULLIF(lr.net_weight_kg, 0), lr.gross_weight_kg, 0)::numeric

        END

        - COALESCE(ra.total_returned, 0)::numeric

      )),

      COALESCE(ba.total_batch_remaining, GREATEST(0, (

        CASE

          WHEN COALESCE(ba.initial_batch_quantity, 0) > 0 THEN

            ba.initial_batch_quantity::numeric

          WHEN COALESCE(lr.purchase_mode, 'weight') = 'carton' THEN

            CASE

              WHEN COALESCE(lr.weight_per_carton_kg, 0) > 0 AND COALESCE(lr.net_weight_kg, 0) > 0

                   AND ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0) > 0

                   AND ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0) <= COALESCE(lr.carton_count, 999999999) THEN

                ROUND((lr.net_weight_kg / lr.weight_per_carton_kg)::numeric, 0)

              WHEN COALESCE(lr.carton_count, 0) > 0 THEN lr.carton_count::numeric

              ELSE COALESCE(ba.total_batch_remaining, 0)::numeric

            END

          ELSE

            COALESCE(NULLIF(lr.net_weight_kg, 0), lr.gross_weight_kg, 0)::numeric

        END

        - COALESCE(ra.total_returned, 0)::numeric

      )))

    )::numeric AS available_quantity,

    (CASE

      WHEN COALESCE(lr.purchase_mode, 'weight') = 'carton' THEN 'كرتونة'

      ELSE 'كجم'

    END)::text AS unit_label

  FROM public.lot_receipts lr

  LEFT JOIN public.suppliers s ON s.id = lr.supplier_id

  LEFT JOIN public.stations st ON st.id = lr.station_id

  LEFT JOIN returns_agg ra ON ra.lot_receipt_id = lr.id

  LEFT JOIN batches_agg ba ON (ba.product_code = lr.lot_number OR ba.product_code = lr.id::text)

  WHERE (p_lot_id IS NULL OR lr.id = p_lot_id)

    AND COALESCE(lr.is_confirmed, false) = true

  ORDER BY lr.receipt_date DESC, lr.id DESC;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_get_lot_return_available_quantities(bigint) TO authenticated, anon, service_role;



-- ── 4.b Helper Function: upsert_station_product ─────────────────────────────

CREATE OR REPLACE FUNCTION public.upsert_station_product(

  p_station_id BIGINT,

  p_item_type TEXT,

  p_raw_material_id UUID,

  p_fruit_type_id BIGINT,

  p_product_name TEXT,

  p_product_code TEXT,

  p_delta NUMERIC,

  p_unit TEXT DEFAULT 'piece'

)

RETURNS VOID

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

BEGIN

  IF p_item_type = 'material' AND p_raw_material_id IS NOT NULL THEN

    INSERT INTO public.station_products (

      station_id, item_type, raw_material_id, product_name, product_code, quantity, unit, updated_at

    ) VALUES (

      p_station_id, 'material', p_raw_material_id, p_product_name, p_product_code, GREATEST(p_delta, 0), p_unit, NOW()

    )

    ON CONFLICT (station_id, raw_material_id) WHERE item_type = 'material' AND raw_material_id IS NOT NULL

    DO UPDATE SET

      quantity = public.station_products.quantity + p_delta,

      product_name = EXCLUDED.product_name,

      product_code = EXCLUDED.product_code,

      updated_at = NOW();



    DELETE FROM public.station_products

    WHERE station_id = p_station_id AND raw_material_id = p_raw_material_id AND item_type = 'material' AND quantity <= 0;



  ELSIF p_item_type = 'fruit' AND p_fruit_type_id IS NOT NULL THEN

    INSERT INTO public.station_products (

      station_id, item_type, fruit_type_id, product_name, product_code, quantity, unit, updated_at

    ) VALUES (

      p_station_id, 'fruit', p_fruit_type_id, p_product_name, p_product_code, GREATEST(p_delta, 0), p_unit, NOW()

    )

    ON CONFLICT (station_id, fruit_type_id) WHERE item_type = 'fruit' AND fruit_type_id IS NOT NULL

    DO UPDATE SET

      quantity = public.station_products.quantity + p_delta,

      product_name = EXCLUDED.product_name,

      product_code = EXCLUDED.product_code,

      updated_at = NOW();



    DELETE FROM public.station_products

    WHERE station_id = p_station_id AND fruit_type_id = p_fruit_type_id AND item_type = 'fruit' AND quantity <= 0;

  END IF;

END;

$$;



GRANT EXECUTE ON FUNCTION public.upsert_station_product(BIGINT, TEXT, UUID, BIGINT, TEXT, TEXT, NUMERIC, TEXT) TO authenticated, anon, service_role;



-- ── 5. Drop & Recreate rpc_process_lot_receipt ───────────────────────────────

DO $$

DECLARE r RECORD;

BEGIN

  FOR r IN

    SELECT oid::regprocedure AS sig

    FROM pg_proc

    WHERE proname = 'rpc_process_lot_receipt'

      AND pronamespace = 'public'::regnamespace

  LOOP

    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';

  END LOOP;

END $$;

DROP FUNCTION IF EXISTS public.rpc_process_lot_receipt(BIGINT) CASCADE;

DROP FUNCTION IF EXISTS public.rpc_process_lot_receipt(BIGINT, NUMERIC) CASCADE;

DROP FUNCTION IF EXISTS public.rpc_process_lot_receipt(BIGINT, NUMERIC, UUID) CASCADE;

DROP FUNCTION IF EXISTS public.rpc_process_lot_receipt CASCADE;



CREATE OR REPLACE FUNCTION public.rpc_process_lot_receipt(

  p_lot_id BIGINT,

  p_unit_cost_kg NUMERIC DEFAULT NULL

)

RETURNS JSON

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

DECLARE

  v_lot RECORD;

  v_batch_id BIGINT;

  v_batch_qty NUMERIC;

  v_unit_cost NUMERIC;

  v_supplier_name TEXT;

  v_unit TEXT := 'kg';

  v_already_returned NUMERIC := 0;

BEGIN

  SELECT * INTO v_lot

  FROM lot_receipts

  WHERE id = p_lot_id;



  IF NOT FOUND THEN

    RETURN json_build_object('success', false, 'error', 'اللوط غير موجود');

  END IF;



  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' AND COALESCE(v_lot.carton_count, 0) > 0 THEN

    IF COALESCE(v_lot.weight_per_carton_kg, 0) > 0 AND COALESCE(v_lot.net_weight_kg, 0) > 0

       AND ROUND((v_lot.net_weight_kg / v_lot.weight_per_carton_kg)::numeric, 0) > 0

       AND ROUND((v_lot.net_weight_kg / v_lot.weight_per_carton_kg)::numeric, 0) <= COALESCE(v_lot.carton_count, 999999999) THEN

      v_batch_qty := ROUND((v_lot.net_weight_kg / v_lot.weight_per_carton_kg)::numeric, 0);

    ELSE

      v_batch_qty := v_lot.carton_count;

    END IF;

    v_unit_cost := COALESCE(NULLIF(v_lot.price_per_carton, 0), NULLIF(p_unit_cost_kg, 0), v_lot.fruit_cost_per_kg, 0);

    v_unit := 'carton';

  ELSE

    v_batch_qty := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

    v_unit_cost := COALESCE(NULLIF(p_unit_cost_kg, 0), v_lot.fruit_cost_per_kg, 0);

    v_unit := 'kg';

  END IF;



  IF v_lot.supplier_id IS NOT NULL THEN

    SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;

  END IF;

  v_supplier_name := COALESCE(v_supplier_name, '');



  -- Calculate already returned to avoid wiping partial returns if reprocessed

  SELECT COALESCE(SUM(returned_quantity), 0) INTO v_already_returned

  FROM lot_returns

  WHERE lot_receipt_id = p_lot_id;



  -- Check if batch already exists for this lot receipt

  SELECT id INTO v_batch_id

  FROM station_product_batches

  WHERE station_id = v_lot.station_id

    AND source_type = 'lot_receipt'

    AND (product_code = v_lot.lot_number OR product_code = v_lot.id::text)

  LIMIT 1;



  IF v_batch_id IS NOT NULL THEN

    UPDATE station_product_batches

    SET quantity = v_batch_qty,

        remaining_quantity = GREATEST(0, v_batch_qty - v_already_returned),

        unit_cost = v_unit_cost,

        currency = COALESCE(v_lot.currency, 'EGP'),

        exchange_rate = COALESCE(v_lot.exchange_rate, 1.0),

        supplier_name = v_supplier_name,

        item_type = 'fruit',

        fruit_type_id = v_lot.fruit_type_id,

        updated_at = NOW()

    WHERE id = v_batch_id;

  ELSE

    INSERT INTO station_product_batches (

      station_id, product_name, product_code, quantity, remaining_quantity,

      unit_cost, currency, exchange_rate, source_type, source_date, supplier_name,

      item_type, fruit_type_id

    ) VALUES (

      v_lot.station_id, v_lot.product_name, v_lot.lot_number, v_batch_qty, GREATEST(0, v_batch_qty - v_already_returned),

      v_unit_cost, COALESCE(v_lot.currency, 'EGP'), COALESCE(v_lot.exchange_rate, 1.0),

      'lot_receipt', v_lot.created_at, v_supplier_name,

      'fruit', v_lot.fruit_type_id

    ) RETURNING id INTO v_batch_id;

  END IF;



  -- Synchronize station_products

  IF v_lot.fruit_type_id IS NOT NULL THEN

    INSERT INTO public.station_products (

      station_id, item_type, fruit_type_id, product_name, product_code, quantity, unit, updated_at

    ) VALUES (

      v_lot.station_id,

      'fruit',

      v_lot.fruit_type_id,

      v_lot.product_name,

      v_lot.lot_number,

      GREATEST(0, v_batch_qty - v_already_returned),

      v_unit,

      NOW()

    )

    ON CONFLICT (station_id, fruit_type_id) WHERE item_type = 'fruit' AND fruit_type_id IS NOT NULL

    DO UPDATE SET

      quantity = EXCLUDED.quantity,

      product_name = EXCLUDED.product_name,

      product_code = EXCLUDED.product_code,

      unit = EXCLUDED.unit,

      updated_at = NOW();

  ELSE

    UPDATE public.station_products

    SET quantity = GREATEST(0, v_batch_qty - v_already_returned),

        item_type = 'fruit',

        updated_at = NOW()

    WHERE station_id = v_lot.station_id AND product_name = v_lot.product_name;



    IF NOT FOUND THEN

      INSERT INTO public.station_products (

        station_id, item_type, product_name, product_code, quantity, unit, updated_at

      ) VALUES (

        v_lot.station_id,

        'fruit',

        v_lot.product_name,

        v_lot.lot_number,

        GREATEST(0, v_batch_qty - v_already_returned),

        v_unit,

        NOW()

      );

    END IF;

  END IF;



  UPDATE lot_receipts

  SET status = 'received'

  WHERE id = p_lot_id AND status IS DISTINCT FROM 'received';



  RETURN json_build_object(

    'success', true,

    'lot_id', p_lot_id,

    'lot_number', v_lot.lot_number,

    'station_id', v_lot.station_id,

    'product_name', v_lot.product_name,

    'batch_id', v_batch_id,

    'batch_qty', v_batch_qty,

    'remaining_qty', GREATEST(0, v_batch_qty - v_already_returned)

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_process_lot_receipt(BIGINT, NUMERIC) TO authenticated, anon, service_role;



-- ── 6. Drop & Recreate rpc_process_lot_return with Net Warehouse Baseline Guardrails ────

DO $$

DECLARE r RECORD;

BEGIN

  FOR r IN

    SELECT oid::regprocedure AS sig

    FROM pg_proc

    WHERE proname = 'rpc_process_lot_return'

      AND pronamespace = 'public'::regnamespace

  LOOP

    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';

  END LOOP;

END $$;

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



  -- Lookup supplier name early to include in journal entries and ledger memos

  v_supplier_name := NULL;

  IF v_lot.supplier_id IS NOT NULL THEN

    SELECT name INTO v_supplier_name

    FROM public.suppliers

    WHERE id = v_lot.supplier_id;

  END IF;

  v_supplier_name := COALESCE(NULLIF(TRIM(v_supplier_name), ''), 'مورد غير محدد');



  IF v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN

    v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    v_desc := 'مرتجع شراء محصول: ' || v_product_name || ' | المورد: ' || v_supplier_name || ' | لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT) || ' (' || p_return_quantity || ' ' || v_unit_label || ' صافي مخزني)';



    v_je_id := public.post_journal_entry(

      p_company_id := v_company_id,

      p_entry_date := CURRENT_DATE,

      p_source_type := 'lot_return',

      p_description := v_desc,

      p_created_by := p_user_id,

      p_lines := jsonb_build_array(

        jsonb_build_object(

          'account_id', v_supplier_leaf_account_id,

          'debit', v_return_value_egp,

          'credit', 0,

          'base_debit', v_return_value_egp,

          'base_credit', 0,

          'currency', 'EGP',

          'amount_in_base_currency', v_return_value_egp,

          'description', 'تخفيض مستحقات المورد: ' || v_supplier_name || ' - مرتجع لوط #' || COALESCE(v_lot.lot_number, v_lot.id::TEXT) || ' (' || v_product_name || ')'

        ),

        jsonb_build_object(

          'account_id', v_inventory_account_id,

          'debit', 0,

          'credit', v_return_value_egp,

          'base_debit', 0,

          'base_credit', v_return_value_egp,

          'currency', 'EGP',

          'amount_in_base_currency', v_return_value_egp,

          'description', 'تخفيض مخزون المحاصيل المرتجعة للمورد: ' || v_supplier_name || ' - لوط #' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)

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

      COALESCE(p_notes, 'مرتجع شراء محصول للمورد: ' || v_supplier_name || ' - لوط #' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)),

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

        COALESCE(p_notes, 'مرتجع شراء محصول للمورد: ' || v_supplier_name || ' - لوط #' || COALESCE(v_lot.lot_number, v_lot.id::text)),

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



-- ==============================================================================

-- Universal Enterprise RLS Policies: Full Access for Authenticated ERP Users

-- ==============================================================================

DO $$

DECLARE

    r RECORD;

BEGIN

    FOR r IN (

        SELECT tablename 

        FROM pg_tables 

        WHERE schemaname = 'public'

    ) LOOP

        -- 1. Enable RLS

        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' ENABLE ROW LEVEL SECURITY;';

        

        -- 2. Grant full CRUD access to authenticated users

        EXECUTE 'DROP POLICY IF EXISTS "allow_all_authenticated" ON public.' || quote_ident(r.tablename) || ';';

        EXECUTE 'CREATE POLICY "allow_all_authenticated" ON public.' || quote_ident(r.tablename) || ' FOR ALL TO authenticated USING (true) WITH CHECK (true);';

        

        -- 3. Grant read access to anon

        EXECUTE 'DROP POLICY IF EXISTS "allow_anon_read" ON public.' || quote_ident(r.tablename) || ';';

        EXECUTE 'CREATE POLICY "allow_anon_read" ON public.' || quote_ident(r.tablename) || ' FOR SELECT TO anon USING (true);';

    END LOOP;

END $$;



-- ── 15. RPC to fetch all journal entries for a purchase invoice ──────────────

DROP FUNCTION IF EXISTS public.rpc_get_purchase_journal_entries(TEXT);



CREATE OR REPLACE FUNCTION public.rpc_get_purchase_journal_entries(

  p_purchase_id TEXT

)

RETURNS TABLE (

  journal_entry_id BIGINT,

  entry_number     TEXT,

  entry_date       DATE,

  description      TEXT,

  source_type      TEXT,

  source_id        TEXT,

  total_debit      NUMERIC,

  total_credit     NUMERIC,

  currency         TEXT,

  created_at       TIMESTAMPTZ

)

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_invoice_number TEXT;

BEGIN

  SELECT invoice_number INTO v_invoice_number

  FROM purchase_invoices WHERE id::TEXT = p_purchase_id;



  RETURN QUERY

  SELECT DISTINCT ON (je.id)

    je.id AS journal_entry_id,

    je.entry_number,

    je.entry_date,

    je.description,

    je.source_type,

    je.source_id,

    COALESCE(SUM(ale.debit) OVER (PARTITION BY je.id), 0) AS total_debit,

    COALESCE(SUM(ale.credit) OVER (PARTITION BY je.id), 0) AS total_credit,

    (SELECT ale2.currency FROM public.account_ledger_entries ale2

     WHERE ale2.journal_entry_id = je.id AND ale2.currency IS NOT NULL

     ORDER BY ale2.id LIMIT 1) AS currency,

    je.created_at

  FROM public.journal_entries je

  INNER JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id

  WHERE je.deleted_at IS NULL

    AND ale.deleted_at IS NULL

    AND (

      (je.source_id = p_purchase_id AND je.source_type IN ('purchase_inventory', 'purchase_payment', 'purchase_price_adjustment'))

      OR

      (v_invoice_number IS NOT NULL AND v_invoice_number != ''

       AND je.description LIKE '%' || v_invoice_number || '%'

       AND je.source_type IN ('purchase_inventory', 'purchase_payment'))

    )

  ORDER BY je.id, je.created_at DESC;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_get_purchase_journal_entries(TEXT) TO authenticated, anon, service_role;



-- ── 16. RPC to close Opening Balance Suspense (23421) into Retained Earnings (23411) ──

DROP FUNCTION IF EXISTS public.rpc_close_opening_balance_suspense(BIGINT, DATE, UUID);

DROP FUNCTION IF EXISTS public.rpc_close_opening_balance_suspense(BIGINT, DATE);



CREATE OR REPLACE FUNCTION public.rpc_close_opening_balance_suspense(

    p_fiscal_year_id BIGINT,

    p_closing_date DATE,

    p_company_id UUID DEFAULT NULL

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

    v_suspense_id BIGINT;

    v_retained_id BIGINT;

    v_debit_total NUMERIC := 0;

    v_credit_total NUMERIC := 0;

    v_balance NUMERIC := 0;

    v_je_id BIGINT;

    v_entry_num TEXT;

BEGIN

    -- Resolve accounts

    v_suspense_id := public.resolve_gl_account('23421', p_company_id);

    v_retained_id := public.resolve_gl_account('23411', p_company_id);



    IF v_suspense_id IS NULL OR v_retained_id IS NULL THEN

        RETURN jsonb_build_object('success', false, 'message', 'Accounts 23421 or 23411 not found');

    END IF;



    -- Calculate balance of 23421

    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)

    INTO v_debit_total, v_credit_total

    FROM public.account_ledger_entries

    WHERE account_id = v_suspense_id

      AND deleted_at IS NULL

      AND (p_company_id IS NULL OR company_id = p_company_id);



    v_balance := v_credit_total - v_debit_total;



    IF ABS(v_balance) < 0.0001 THEN

        RETURN jsonb_build_object('success', true, 'message', 'Suspense account already balanced (zero)', 'balance', 0);

    END IF;



    -- Create Closing Journal Entry

    v_entry_num := 'CLOSE-OB-' || TO_CHAR(p_closing_date, 'YYYYMMDD') || '-' || LPAD(FLOOR(RANDOM()*1000)::TEXT, 3, '0');



    INSERT INTO public.journal_entries (

        entry_number, entry_date, description, source_type, source_id, status, company_id

    ) VALUES (

        v_entry_num, p_closing_date,

        'إقفال فروق الأرصدة الافتتاحية في الأرباح/الخسائر المرحلة نهاية السنة',

        'fiscal_year_closing', p_fiscal_year_id::TEXT, 'posted', p_company_id

    ) RETURNING id INTO v_je_id;



    -- Double-entry: zero out 23421, transfer to 23411

    IF v_balance > 0 THEN

        -- Net Credit in Suspense -> Debit Suspense, Credit Retained Earnings

        INSERT INTO public.account_ledger_entries (

            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES

        (v_je_id, v_suspense_id, v_balance, 0, 'EGP', v_balance, 'تصفير فروق أرصدة افتتاحية', p_company_id),

        (v_je_id, v_retained_id, 0, v_balance, 'EGP', v_balance, 'ترحيل فروق أرصدة افتتاحية إلى أرباح مرحلة', p_company_id);

    ELSE

        -- Net Debit in Suspense -> Credit Suspense, Debit Retained Earnings

        INSERT INTO public.account_ledger_entries (

            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES

        (v_je_id, v_suspense_id, 0, ABS(v_balance), 'EGP', ABS(v_balance), 'تصفير فروق أرصدة افتتاحية', p_company_id),

        (v_je_id, v_retained_id, ABS(v_balance), 0, 'EGP', ABS(v_balance), 'ترحيل فروق أرصدة افتتاحية إلى أرباح مرحلة', p_company_id);

    END IF;



    RETURN jsonb_build_object(

        'success', true,

        'journal_entry_id', v_je_id,

        'closed_balance', v_balance,

        'closing_date', p_closing_date

    );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_close_opening_balance_suspense(BIGINT, DATE, UUID) TO authenticated, anon, service_role;





-- ── 16. Trial Balance & Account Totals RPCs ─────────────────────────────────

-- Re-affirm compatibility view journal_entry_lines

CREATE OR REPLACE VIEW public.journal_entry_lines AS

SELECT * FROM public.v_journal_entry_lines;



GRANT SELECT ON public.journal_entry_lines TO authenticated, service_role, anon;



-- Drop old variants of get_account_totals_rpc

DROP FUNCTION IF EXISTS public.get_account_totals_rpc(date, date);

DROP FUNCTION IF EXISTS public.get_account_totals_rpc(date, date, text);

DROP FUNCTION IF EXISTS public.get_account_totals_rpc(date, date, text, boolean);



-- Recreate get_account_totals_rpc using account_ledger_entries / journal_entries

CREATE OR REPLACE FUNCTION public.get_account_totals_rpc(

    p_from date DEFAULT NULL::date,

    p_to date DEFAULT NULL::date,

    p_currency text DEFAULT NULL::text,

    p_exclude_closing boolean DEFAULT false

)

RETURNS TABLE(

    account_id text,

    debit numeric,

    credit numeric

)

LANGUAGE sql

STABLE

SECURITY DEFINER

SET search_path TO 'public', 'extensions'

AS $$

  SELECT

    ale.account_id::text,

    COALESCE(SUM(

      CASE 

        WHEN p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' THEN

          CASE WHEN ale.debit > 0 THEN COALESCE(NULLIF(ale.amount_in_base_currency, 0), ale.debit) ELSE 0 END

        ELSE ale.debit

      END

    ), 0)::numeric AS debit,

    COALESCE(SUM(

      CASE 

        WHEN p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' THEN

          CASE WHEN ale.credit > 0 THEN COALESCE(NULLIF(ale.amount_in_base_currency, 0), ale.credit) ELSE 0 END

        ELSE ale.credit

      END

    ), 0)::numeric AS credit

  FROM public.account_ledger_entries ale

  JOIN public.journal_entries je ON je.id = ale.journal_entry_id

  WHERE ale.deleted_at IS NULL

    AND je.deleted_at IS NULL

    AND (p_from IS NULL OR je.entry_date >= p_from)

    AND (p_to IS NULL OR je.entry_date <= p_to)

    AND (p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' OR ale.currency = p_currency)

    AND (NOT p_exclude_closing OR COALESCE(je.source_type, '') <> 'fiscal_year_closing')

  GROUP BY ale.account_id;

$$;



GRANT EXECUTE ON FUNCTION public.get_account_totals_rpc(date, date, text, boolean) TO authenticated, anon, service_role;





-- Hierarchical Trial Balance RPC rolling up posting accounts to parent accounts

DROP FUNCTION IF EXISTS public.get_trial_balance_rpc(date, date, text, boolean);



CREATE OR REPLACE FUNCTION public.get_trial_balance_rpc(

    p_from date DEFAULT NULL::date,

    p_to date DEFAULT NULL::date,

    p_currency text DEFAULT NULL::text,

    p_exclude_closing boolean DEFAULT false

)

RETURNS TABLE(

    account_id text,

    account_code text,

    account_name text,

    account_type text,

    parent_id text,

    opening_debit numeric,

    opening_credit numeric,

    period_debit numeric,

    period_credit numeric,

    total_debit numeric,

    total_credit numeric,

    ending_balance numeric,

    is_parent boolean

)

LANGUAGE sql

STABLE

SECURITY DEFINER

SET search_path TO 'public', 'extensions'

AS $$

  WITH RECURSIVE

  period_leaf AS (

    SELECT

      ale.account_id,

      COALESCE(SUM(

        CASE 

          WHEN p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' THEN

            CASE WHEN ale.debit > 0 THEN COALESCE(NULLIF(ale.amount_in_base_currency, 0), ale.debit) ELSE 0 END

          ELSE ale.debit

        END

      ), 0)::numeric AS p_debit,

      COALESCE(SUM(

        CASE 

          WHEN p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' THEN

            CASE WHEN ale.credit > 0 THEN COALESCE(NULLIF(ale.amount_in_base_currency, 0), ale.credit) ELSE 0 END

          ELSE ale.credit

        END

      ), 0)::numeric AS p_credit

    FROM public.account_ledger_entries ale

    JOIN public.journal_entries je ON je.id = ale.journal_entry_id

    WHERE ale.deleted_at IS NULL

      AND je.deleted_at IS NULL

      AND (p_from IS NULL OR je.entry_date >= p_from)

      AND (p_to IS NULL OR je.entry_date <= p_to)

      AND (p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' OR ale.currency = p_currency)

      AND (NOT p_exclude_closing OR COALESCE(je.source_type, '') <> 'fiscal_year_closing')

    GROUP BY ale.account_id

  ),

  opening_leaf AS (

    SELECT

      ale.account_id,

      COALESCE(SUM(

        CASE 

          WHEN p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' THEN

            CASE WHEN ale.debit > 0 THEN COALESCE(NULLIF(ale.amount_in_base_currency, 0), ale.debit) ELSE 0 END

          ELSE ale.debit

        END

      ), 0)::numeric AS op_debit,

      COALESCE(SUM(

        CASE 

          WHEN p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' THEN

            CASE WHEN ale.credit > 0 THEN COALESCE(NULLIF(ale.amount_in_base_currency, 0), ale.credit) ELSE 0 END

          ELSE ale.credit

        END

      ), 0)::numeric AS op_credit

    FROM public.account_ledger_entries ale

    JOIN public.journal_entries je ON je.id = ale.journal_entry_id

    WHERE ale.deleted_at IS NULL

      AND je.deleted_at IS NULL

      AND (p_from IS NOT NULL AND je.entry_date < p_from)

      AND (p_currency IS NULL OR p_currency = '' OR p_currency = 'ALL' OR ale.currency = p_currency)

    GROUP BY ale.account_id

  ),

  account_closure AS (

    SELECT id AS leaf_id, id AS ancestor_id

    FROM public.accounts

    WHERE is_active = true

    UNION ALL

    SELECT ac.leaf_id, a.parent_id AS ancestor_id

    FROM account_closure ac

    JOIN public.accounts a ON a.id = ac.ancestor_id

    WHERE a.parent_id IS NOT NULL

  ),

  parent_status AS (

    SELECT DISTINCT parent_id AS pid

    FROM public.accounts

    WHERE parent_id IS NOT NULL AND is_active = true

  )

  SELECT

    a.id::text AS account_id,

    a.account_code::text,

    COALESCE(a.account_name, a.name, '')::text AS account_name,

    a.account_type::text,

    a.parent_id::text,

    COALESCE(SUM(opl.op_debit), 0)::numeric AS opening_debit,

    COALESCE(SUM(opl.op_credit), 0)::numeric AS opening_credit,

    COALESCE(SUM(pl.p_debit), 0)::numeric AS period_debit,

    COALESCE(SUM(pl.p_credit), 0)::numeric AS period_credit,

    (COALESCE(SUM(opl.op_debit), 0) + COALESCE(SUM(pl.p_debit), 0))::numeric AS total_debit,

    (COALESCE(SUM(opl.op_credit), 0) + COALESCE(SUM(pl.p_credit), 0))::numeric AS total_credit,

    ((COALESCE(SUM(opl.op_debit), 0) + COALESCE(SUM(pl.p_debit), 0)) -

     (COALESCE(SUM(opl.op_credit), 0) + COALESCE(SUM(pl.p_credit), 0)))::numeric AS ending_balance,

    (ps.pid IS NOT NULL) AS is_parent

  FROM public.accounts a

  LEFT JOIN account_closure ac ON ac.ancestor_id = a.id

  LEFT JOIN period_leaf pl ON pl.account_id = ac.leaf_id

  LEFT JOIN opening_leaf opl ON opl.account_id = ac.leaf_id

  LEFT JOIN parent_status ps ON ps.pid = a.id

  WHERE a.is_active = true

  GROUP BY a.id, a.account_code, a.account_name, a.name, a.account_type, a.parent_id, ps.pid

  ORDER BY a.account_code;

$$;



GRANT EXECUTE ON FUNCTION public.get_trial_balance_rpc(date, date, text, boolean) TO authenticated, anon, service_role;



-- ════════════════════════════════════════════════════════════════════════════

-- Shareholder Profit Distribution Double-Entry GL Integration

-- ════════════════════════════════════════════════════════════════════════════



ALTER TABLE public.shareholder_profit_distributions

ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;



CREATE INDEX IF NOT EXISTS idx_spd_journal_entry_id ON public.shareholder_profit_distributions(journal_entry_id);



CREATE OR REPLACE FUNCTION public.distribute_shipment_profit(p_shipment_id_str text)

RETURNS void

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $function$

DECLARE

  v_shipment_id BIGINT;

  v_company_id UUID;

  v_shipment_no TEXT;

  v_shipment_profit NUMERIC;

  

  v_new_distributions JSONB := '[]'::jsonb;

  

  -- Settings

  v_settings JSONB;

  v_shipment_pcts JSONB;

  v_conv JSONB;

  v_p4_map JSONB;

  

  -- Iteration

  v_dist_idx INT;

  v_person_id UUID;

  v_pct NUMERIC;

  v_share NUMERIC;

  v_rate NUMERIC;

  v_final_currency TEXT;

  v_final_amount NUMERIC;

  v_sh_name TEXT;

  

  -- Journal Entry

  v_je_lines JSONB := '[]'::jsonb;

  v_desc TEXT;

  v_debit_acct BIGINT;

  v_shareholder_acct BIGINT;

  v_je_id BIGINT;

  v_total_base NUMERIC := 0;

  

  -- Old data

  v_old_dist RECORD;

  v_old_je_id BIGINT;

  v_set_rec RECORD;

BEGIN

  v_shipment_id := p_shipment_id_str::BIGINT;



  -- ── STEP 1: VALIDATION & DATA FETCH ──

  SELECT s.shipment_no, s.net_profit_egp, 

         COALESCE(s.company_id, (SELECT id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1))

  INTO v_shipment_no, v_shipment_profit, v_company_id

  FROM public.export_shipments s

  WHERE s.id = v_shipment_id;



  IF v_shipment_no IS NULL THEN

    RAISE EXCEPTION 'الشحنة رقم % غير موجودة.', p_shipment_id_str;

  END IF;



  IF v_shipment_profit IS NULL OR v_shipment_profit = 0 THEN

    RAISE EXCEPTION 'لا يوجد أرباح مسجلة لهذه الشحنة لتوزيعها.';

  END IF;



  -- Resolve Debit Account (Current Year Profit 23511 or Retained Earnings 23411)

  SELECT id INTO v_debit_acct 

  FROM public.accounts 

  WHERE account_code = '23511' AND is_leaf = true LIMIT 1;



  IF v_debit_acct IS NULL THEN

    SELECT id INTO v_debit_acct 

    FROM public.accounts 

    WHERE account_code = '23411' AND is_leaf = true LIMIT 1;

  END IF;



  IF v_debit_acct IS NULL THEN

    SELECT id INTO v_debit_acct 

    FROM public.accounts 

    WHERE account_code IN ('23421', '23111') AND is_leaf = true LIMIT 1;

  END IF;



  IF v_debit_acct IS NULL THEN

    RAISE EXCEPTION 'حساب توزيع الأرباح (23511 أو 23411) غير موجود في شجرة الحسابات.';

  END IF;



  SELECT * INTO v_set_rec FROM public.profit_distribution_settings LIMIT 1;

  IF v_set_rec IS NULL THEN

    RAISE EXCEPTION 'إعدادات التوزيع غير موجودة أو غير مفعلة.';

  END IF;



  v_settings := v_set_rec.percentages;

  v_p4_map := v_set_rec.person4_for_shipment;

  v_conv := v_set_rec.currency_conversions;



  v_desc := 'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no;



  -- Compute distributions

  IF v_settings IS NOT NULL AND jsonb_typeof(v_settings) = 'object' THEN

    v_shipment_pcts := v_settings -> p_shipment_id_str;

  END IF;



  -- Fallback: if no specific percentages set for this shipment, use default equal split

  IF v_shipment_pcts IS NULL OR jsonb_array_length(v_shipment_pcts) = 0 THEN

    v_shipment_pcts := '[33.33, 33.33, 33.34, 0.0]'::jsonb;

  END IF;



  IF v_conv IS NULL OR jsonb_typeof(v_conv) != 'object' THEN

    v_conv := '{}'::jsonb;

  END IF;

  IF v_conv -> p_shipment_id_str IS NOT NULL THEN

    v_conv := v_conv -> p_shipment_id_str;

  ELSE

    v_conv := '{}'::jsonb;

  END IF;



  IF v_p4_map IS NULL OR jsonb_typeof(v_p4_map) != 'object' THEN

    v_p4_map := '{}'::jsonb;

  END IF;



  -- Calculate distributions for Person 1..3

  FOR v_i IN 1..3 LOOP

    IF v_i = 1 THEN v_person_id := v_set_rec.person1_id;

    ELSIF v_i = 2 THEN v_person_id := v_set_rec.person2_id;

    ELSIF v_i = 3 THEN v_person_id := v_set_rec.person3_id;

    END IF;



    v_pct := 0;

    IF v_shipment_pcts IS NOT NULL THEN

      v_pct := COALESCE((v_shipment_pcts ->> (v_i - 1))::NUMERIC, 0);

    END IF;



    CONTINUE WHEN v_pct IS NULL OR v_pct = 0 OR v_person_id IS NULL;



    v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);

    v_final_currency := COALESCE(NULLIF(v_conv -> (v_i - 1)::text ->> 'currency', ''), 'EGP');

    v_rate := COALESCE((v_conv -> (v_i - 1)::text ->> 'rate')::NUMERIC, 0);

    

    IF v_final_currency != 'EGP' AND v_rate > 0 THEN

      v_final_amount := ROUND(v_share / v_rate, 2);

    ELSE

      v_final_currency := 'EGP';

      v_final_amount := v_share;

    END IF;



    v_new_distributions := v_new_distributions || jsonb_build_object(

        'shareholder_id', v_person_id,

        'person_index', v_i - 1,

        'percentage', v_pct,

        'amount_egp', v_share,

        'currency', v_final_currency,

        'converted_amount', v_final_amount,

        'rate_to_egp', NULLIF(v_rate, 0)

    );

  END LOOP;



  -- Person 4 calculation

  BEGIN

    IF (v_p4_map ->> p_shipment_id_str) IS NOT NULL AND (v_p4_map ->> p_shipment_id_str) != '' THEN

      v_person_id := (v_p4_map ->> p_shipment_id_str)::UUID;

    ELSE

      v_person_id := NULL;

    END IF;

  EXCEPTION WHEN OTHERS THEN

    v_person_id := NULL;

  END;



  IF v_person_id IS NOT NULL THEN

    v_pct := GREATEST(100

      - COALESCE((v_shipment_pcts ->> 0)::NUMERIC, 0)

      - COALESCE((v_shipment_pcts ->> 1)::NUMERIC, 0)

      - COALESCE((v_shipment_pcts ->> 2)::NUMERIC, 0), 0);



    IF v_pct > 0 THEN

      v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);

      v_final_currency := COALESCE(NULLIF(v_conv -> '3' ->> 'currency', ''), 'EGP');

      v_rate := COALESCE((v_conv -> '3' ->> 'rate')::NUMERIC, 0);

      

      IF v_final_currency != 'EGP' AND v_rate > 0 THEN

        v_final_amount := ROUND(v_share / v_rate, 2);

      ELSE

        v_final_currency := 'EGP';

        v_final_amount := v_share;

      END IF;



      v_new_distributions := v_new_distributions || jsonb_build_object(

          'shareholder_id', v_person_id,

          'person_index', 3,

          'percentage', v_pct,

          'amount_egp', v_share,

          'currency', v_final_currency,

          'converted_amount', v_final_amount,

          'rate_to_egp', NULLIF(v_rate, 0)

      );

    END IF;

  END IF;



  IF jsonb_array_length(v_new_distributions) = 0 THEN

    RAISE EXCEPTION 'لم يتم تعيين نسب للمساهمين لهذه الشحنة. تأكد من حفظ نسب التوزيع أولاً.';

  END IF;



  -- ── STEP 2: CLEAR OLD DISTRIBUTIONS & REVERT BALANCES / ENTRIES ──

  

  -- Revert / Delete previous journal entries for this shipment

  FOR v_old_je_id IN 

    SELECT id FROM public.journal_entries 

    WHERE source_type = 'profit_distribution' AND source_id = p_shipment_id_str

  LOOP

    DELETE FROM public.journal_entries WHERE id = v_old_je_id;

  END LOOP;



  -- Revert balances from old distribution records

  FOR v_old_dist IN 

      SELECT id, shareholder_id, converted_amount, currency 

      FROM public.shareholder_profit_distributions 

      WHERE shipment_id = v_shipment_id AND deleted_at IS NULL

  LOOP

      IF v_old_dist.currency = 'EGP' THEN 

        UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;

      ELSIF v_old_dist.currency = 'USD' THEN 

        UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;

      ELSIF v_old_dist.currency = 'EUR' THEN 

        UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;

      ELSIF v_old_dist.currency = 'GBP' THEN 

        UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id; 

      END IF;

  END LOOP;



  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;



  -- ── STEP 3: INSERT NEW DISTRIBUTIONS & CONSTRUCT GL LINES ──

  

  FOR v_dist_idx IN 0 .. jsonb_array_length(v_new_distributions) - 1 LOOP

    DECLARE

      v_d JSONB := v_new_distributions -> v_dist_idx;

      v_sh_id UUID := (v_d ->> 'shareholder_id')::UUID;

      v_curr TEXT := v_d ->> 'currency';

      v_c_amt NUMERIC := (v_d ->> 'converted_amount')::NUMERIC;

      v_amt_egp NUMERIC := (v_d ->> 'amount_egp')::NUMERIC;

      v_r NUMERIC := (v_d ->> 'rate_to_egp')::NUMERIC;

    BEGIN

      -- 1. Insert distribution row

      INSERT INTO public.shareholder_profit_distributions (

          shipment_id,

          shareholder_id,

          person_index,

          percentage,

          amount_egp,

          currency,

          converted_amount,

          rate_to_egp

      ) VALUES (

          v_shipment_id,

          v_sh_id,

          (v_d ->> 'person_index')::INT,

          (v_d ->> 'percentage')::NUMERIC,

          v_amt_egp,

          v_curr,

          v_c_amt,

          v_r

      );



      -- 2. Update shareholder balance

      IF v_curr = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_c_amt WHERE id = v_sh_id;

      ELSIF v_curr = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_c_amt WHERE id = v_sh_id;

      ELSIF v_curr = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_c_amt WHERE id = v_sh_id;

      ELSIF v_curr = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_c_amt WHERE id = v_sh_id; END IF;



      -- 3. Resolve Shareholder Level 5 Posting Account (Group 232: 23211, 23212, 23213)

      SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_sh_id;

      

      IF v_shareholder_acct IS NULL THEN

        SELECT a.id INTO v_shareholder_acct

        FROM public.accounts a

        JOIN public.shareholders s ON s.id = v_sh_id

        WHERE a.is_leaf = true

          AND (

            (s.name LIKE '%عماد%' AND a.account_code = '23211') OR

            (s.name LIKE '%عبدالباطن%' AND a.account_code = '23212') OR

            (s.name LIKE '%إسلام%' AND a.account_code = '23213') OR

            (s.name LIKE '%اسلام%' AND a.account_code = '23213') OR

            a.name = 'Shareholder - ' || s.name

          )

        LIMIT 1;

      END IF;



      IF v_shareholder_acct IS NULL THEN

        SELECT id INTO v_shareholder_acct FROM public.accounts WHERE account_code = '2321' LIMIT 1;

      END IF;



      v_sh_name := COALESCE((SELECT name FROM public.shareholders WHERE id = v_sh_id), 'مساهم');



      -- 4. Build Credit Line for Shareholder with entity_type & entity_id

      v_je_lines := v_je_lines || jsonb_build_object(

          'account_id', v_shareholder_acct,

          'debit', 0,

          'base_debit', 0,

          'credit', v_c_amt,

          'base_credit', v_amt_egp,

          'currency', v_curr,

          'entity_type', 'shareholder',

          'entity_id', v_sh_id::text,

          'description', 'توزيع أرباح شحنة ' || v_shipment_no || ' - نصيب ' || v_sh_name

      );



      v_total_base := v_total_base + v_amt_egp;

    END;

  END LOOP;



  -- ── STEP 4: ADD BALANCING DEBIT LINE & POST JOURNAL ENTRY ──

  

  -- Add DR Current Year Profit / Retained Earnings (23511 / 23411)

  v_je_lines := jsonb_build_array(

      jsonb_build_object(

          'account_id', v_debit_acct,

          'debit', v_total_base,

          'base_debit', v_total_base,

          'credit', 0,

          'base_credit', 0,

          'currency', 'EGP',

          'description', 'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no || ' على المساهمين'

      )

  ) || v_je_lines;



  -- Post double-entry journal entry via unified posting engine

  v_je_id := public.post_journal_entry(

      'profit_distribution',

      'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no,

      (NOW() AT TIME ZONE 'Africa/Cairo')::DATE,

      v_company_id,

      auth.uid(),

      v_je_lines,

      p_shipment_id_str

  );



  -- Link journal_entry_id to distributions

  UPDATE public.shareholder_profit_distributions

  SET journal_entry_id = v_je_id

  WHERE shipment_id = v_shipment_id;



  -- Mark shipment redistribution flag

  UPDATE public.export_shipments

  SET needs_profit_redistribution = false

  WHERE id = v_shipment_id;



END;

$function$;



GRANT EXECUTE ON FUNCTION public.distribute_shipment_profit(text) TO authenticated, service_role, anon;



CREATE OR REPLACE FUNCTION public.undo_profit_distribution(p_shipment_id_text text)

RETURNS void

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $function$

DECLARE

  v_shipment_id BIGINT;

  v_dist RECORD;

  v_old_je_id BIGINT;

BEGIN

  v_shipment_id := p_shipment_id_text::BIGINT;



  -- 1. Delete associated journal entries

  FOR v_old_je_id IN

    SELECT id FROM public.journal_entries

    WHERE source_type = 'profit_distribution'

      AND source_id = p_shipment_id_text

  LOOP

    DELETE FROM public.journal_entries WHERE id = v_old_je_id;

  END LOOP;



  -- 2. Revert shareholder balances

  FOR v_dist IN

    SELECT * FROM public.shareholder_profit_distributions 

    WHERE shipment_id = v_shipment_id AND deleted_at IS NULL

  LOOP

    IF v_dist.currency = 'EGP' THEN

      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;

    ELSIF v_dist.currency = 'USD' THEN

      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;

    ELSIF v_dist.currency = 'EUR' THEN

      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;

    ELSIF v_dist.currency = 'GBP' THEN

      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;

    END IF;

  END LOOP;



  -- 3. Delete distributions

  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;



  -- 4. Update shipment flag

  UPDATE public.export_shipments

  SET needs_profit_redistribution = false

  WHERE id = v_shipment_id;

END;

$function$;



GRANT EXECUTE ON FUNCTION public.undo_profit_distribution(text) TO authenticated, service_role, anon;



CREATE OR REPLACE FUNCTION public.rpc_get_profit_distribution_journal_entries(p_shipment_id bigint)

RETURNS jsonb

LANGUAGE plpgsql

SECURITY DEFINER

AS $function$

DECLARE

  v_result JSONB;

BEGIN

  SELECT COALESCE(jsonb_agg(je.* ORDER BY je.created_at DESC), '[]'::JSONB)

  INTO v_result

  FROM (

      SELECT 

          je.id,

          je.entry_number,

          je.entry_date AS transaction_date,

          je.description,

          je.source_type,

          je.source_id,

          je.status,

          je.created_at,

          (

              SELECT jsonb_agg(

                  jsonb_build_object(

                      'account_name', a.name,

                      'account_code', a.account_code,

                      'debit', ale.debit,

                      'credit', ale.credit,

                      'currency', ale.currency

                  )

              )

              FROM public.account_ledger_entries ale

              JOIN public.accounts a ON a.id = ale.account_id

              WHERE ale.journal_entry_id = je.id

                AND ale.deleted_at IS NULL

          ) as lines

      FROM public.journal_entries je

      WHERE (je.source_type = 'profit_distribution' OR je.source_type = 'profit_distribution_reversal')

        AND je.source_id = p_shipment_id::TEXT

        AND je.deleted_at IS NULL

  ) je;

  

  RETURN v_result;

END;

$function$;



GRANT EXECUTE ON FUNCTION public.rpc_get_profit_distribution_journal_entries(bigint) TO authenticated, service_role, anon;



-- Auto-generate GL journal entries for existing distributed shipments if missing

DO $do$

DECLARE

  r_shipment RECORD;

BEGIN

  FOR r_shipment IN

    SELECT DISTINCT shipment_id

    FROM public.shareholder_profit_distributions

    WHERE deleted_at IS NULL

      AND (journal_entry_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.journal_entries WHERE id = journal_entry_id))

  LOOP

    BEGIN

      PERFORM public.distribute_shipment_profit(r_shipment.shipment_id::text);

    EXCEPTION WHEN OTHERS THEN

      NULL;

    END;

  END LOOP;

END;

$do$;



-- ----------------------------------------------------------------------------

-- Dual-cost tracking columns on public.packing_order_cost_items

-- ----------------------------------------------------------------------------



ALTER TABLE public.packing_order_cost_items

  ADD COLUMN IF NOT EXISTS cost_status VARCHAR(20) NOT NULL DEFAULT 'expected',

  ADD COLUMN IF NOT EXISTS expected_amount NUMERIC(15, 2) DEFAULT 0.00,

  ADD COLUMN IF NOT EXISTS actual_amount NUMERIC(15, 2) NULL,

  ADD COLUMN IF NOT EXISTS variance_amount NUMERIC(15, 2) DEFAULT 0.00,

  ADD COLUMN IF NOT EXISTS invoice_ref TEXT NULL,

  ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ NULL,

  ADD COLUMN IF NOT EXISTS reconciled_by UUID NULL,

  ADD COLUMN IF NOT EXISTS variance_journal_entry_id BIGINT NULL,

  ADD COLUMN IF NOT EXISTS settlement_notes TEXT NULL;



DO $$

BEGIN

  IF NOT EXISTS (

    SELECT 1 FROM pg_constraint WHERE conname = 'packing_order_cost_items_status_chk'

  ) THEN

    ALTER TABLE public.packing_order_cost_items

      ADD CONSTRAINT packing_order_cost_items_status_chk

      CHECK (cost_status IN ('expected', 'actual'));

  END IF;

END $$;



UPDATE public.packing_order_cost_items

SET expected_amount = COALESCE(expected_amount, base_amount, 0),

    cost_status = COALESCE(cost_status, 'expected')

WHERE expected_amount = 0 OR cost_status IS NULL;



-- ----------------------------------------------------------------------------

-- Update trigger function: sync_packing_order_costs_to_export_shipments

-- ----------------------------------------------------------------------------



CREATE OR REPLACE FUNCTION public.sync_packing_order_costs_to_export_shipments()

RETURNS trigger

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

  v_shipment RECORD;

  v_new_cost NUMERIC;

  v_new_landed NUMERIC;

  v_new_carton_cost NUMERIC;

BEGIN

  v_new_cost := COALESCE(NEW.packing_cost_per_carton, 0);



  IF TG_OP = 'UPDATE' AND (OLD.packing_cost_per_carton IS NOT DISTINCT FROM NEW.packing_cost_per_carton) THEN

    RETURN NEW;

  END IF;



  IF v_new_cost <= 0 THEN

    RETURN NEW;

  END IF;



  UPDATE public.export_shipment_items

  SET price = v_new_cost,

      amount = ROUND(quantity * v_new_cost, 2)

  WHERE packing_order_id = NEW.id;



  UPDATE public.shipment_cost_items sci

  SET unit_price = v_new_cost

  FROM public.export_shipment_items esi

  WHERE esi.shipment_id::text = sci.shipment_id::text

    AND esi.packing_order_id = NEW.id

    AND sci.category = 'packing';



  FOR v_shipment IN

    SELECT DISTINCT shipment_id

    FROM public.export_shipment_items

    WHERE packing_order_id = NEW.id

  LOOP

    SELECT

      COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0) INTO v_new_carton_cost

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = v_shipment.shipment_id::text;



    SELECT

      COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +

      COALESCE((

        SELECT ROUND(SUM(sci.total_price), 2)

        FROM public.shipment_cost_items sci

        WHERE sci.shipment_id::text = v_shipment.shipment_id::text

          AND sci.category <> 'packing'

      ), 0) INTO v_new_landed

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = v_shipment.shipment_id::text;



    UPDATE public.export_shipments s

    SET cost_per_carton = v_new_carton_cost,

        total_landed_cost = v_new_landed,

        net_profit_egp = COALESCE(s.total_revenue_egp, 0) - v_new_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),

        net_profit = COALESCE(s.total_revenue_egp, 0) - v_new_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),

        updated_at = now()

    WHERE s.id::text = v_shipment.shipment_id::text;

  END LOOP;



  RETURN NEW;

END;

$$;



DROP TRIGGER IF EXISTS trg_sync_packing_order_costs ON public.packing_orders;

CREATE TRIGGER trg_sync_packing_order_costs

AFTER UPDATE OF packing_cost_per_carton ON public.packing_orders

FOR EACH ROW

EXECUTE FUNCTION public.sync_packing_order_costs_to_export_shipments();



-- ----------------------------------------------------------------------------

-- RPC: rpc_settle_packing_cost_item (Automated Reconciliation & Profitability)

-- ----------------------------------------------------------------------------



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

  r_order RECORD;

  v_order_num TEXT;

  v_company_id UUID;

  v_supplier_id UUID;

  v_supp_str TEXT;

  v_supplier RECORD;



  v_expected NUMERIC := 0;

  v_old_actual NUMERIC := NULL;

  v_baseline NUMERIC := 0;

  v_incremental_variance NUMERIC := 0;

  v_total_variance NUMERIC := 0;

  v_abs_variance NUMERIC := 0;



  v_finished_inv_acc INT;

  v_supp_acc INT;

  v_supp_leaf_acc INT;

  v_je_id BIGINT := NULL;

  v_entry_num TEXT;



  v_new_other_cost_base NUMERIC := 0;

  v_new_total_cost NUMERIC := 0;

  v_new_carton_cost NUMERIC := 0;

  v_cartons_count NUMERIC := 0;



  v_order_notes JSONB;

  v_cost_items_arr JSONB;

  v_idx INT;

  v_ci_elem JSONB;

  v_shipments_affected INT := 0;

  r_shipment RECORD;

  v_new_shipment_landed NUMERIC;

  v_new_shipment_carton_cost NUMERIC;

BEGIN

  IF p_actual_amount IS NULL OR p_actual_amount < 0 THEN

    RETURN jsonb_build_object('success', false, 'error', 'المبلغ الفعلي غير صالح');

  END IF;



  SELECT * INTO r_item 

  FROM public.packing_order_cost_items 

  WHERE id = p_cost_item_id 

  FOR UPDATE;



  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'بند التكلفة غير موجود');

  END IF;



  SELECT * INTO r_order 

  FROM public.packing_orders 

  WHERE id = r_item.packing_order_id 

  FOR UPDATE;



  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة المرتبط غير موجود');

  END IF;



  v_order_num := COALESCE(r_order.order_number, r_order.id::text);



  v_expected := COALESCE(

    NULLIF(r_item.expected_amount, 0),

    NULLIF((r_item.currency_snapshot->'settlement'->>'expected_amount')::numeric, 0),

    NULLIF(r_item.base_amount, 0),

    NULLIF((r_item.currency_snapshot->>'total_egp')::numeric, 0),

    NULLIF((r_item.currency_snapshot->>'total')::numeric, 0),

    NULLIF(r_item.original_amount, 0),

    0

  );

  v_old_actual := r_item.actual_amount;



  IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
    v_baseline := v_old_actual;
  ELSIF r_order.costs_journal_entry_id IS NOT NULL THEN
    v_baseline := v_expected;
  ELSE
    v_baseline := 0;
  END IF;



  v_incremental_variance := ROUND(p_actual_amount - v_baseline, 2);

  v_total_variance := ROUND(p_actual_amount - v_expected, 2);

  v_abs_variance := ABS(v_incremental_variance);



  v_supplier_id := NULL;

  v_supp_str := NULL;

  IF r_item.currency_snapshot IS NOT NULL THEN

    v_supp_str := r_item.currency_snapshot->>'supplier_id';

  END IF;

  IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN

    v_supp_str := r_item.supplier_id;

  END IF;



  IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN

    BEGIN

      v_supplier_id := v_supp_str::uuid;

    EXCEPTION WHEN OTHERS THEN

      v_supplier_id := NULL;

    END;

  END IF;



  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;

  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;



  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));



  -- Determine balancing account

  v_supp_acc := NULL;

  IF LOWER(COALESCE(r_item.category, '')) = 'logistics' OR r_item.name ILIKE '%نقل%' THEN

    v_supp_acc := public.resolve_gl_account('21111', v_company_id);

    IF v_supp_acc IS NULL THEN v_supp_acc := public.resolve_gl_account('2111', v_company_id); END IF;

  ELSIF LOWER(COALESCE(r_item.category, '')) = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%' THEN

    v_supp_acc := public.resolve_gl_account('31331', v_company_id);

  ELSIF v_supplier_id IS NOT NULL THEN

    SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;

    IF FOUND AND v_supplier.account_id IS NOT NULL THEN

      v_supp_acc := v_supplier.account_id;

    ELSE

      v_supp_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);

    END IF;

  END IF;



  IF v_supp_acc IS NULL THEN

    v_supp_acc := public.resolve_gl_account('2000', v_company_id);

  END IF;

  IF v_supp_acc IS NULL THEN

    v_supp_acc := public.resolve_gl_account('2111', v_company_id);

  END IF;



  IF v_incremental_variance <> 0 THEN

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



    INSERT INTO public.journal_entries (

      entry_number, entry_date, description, status,

      is_auto_generated, source_type, source_id, company_id,

      created_by, created_at, updated_at

    ) VALUES (

      'PENDING',

      (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date,

      'قيد تسوية تكلفة فعلية - أمر تعبئة ' || v_order_num || ' (' || r_item.name || ')',

      'posted', true, 'packing_cost_settlement', p_cost_item_id::text, v_company_id,

      COALESCE(p_settled_by, auth.uid()), now(), now()

    ) RETURNING id INTO v_je_id;



    v_entry_num := public.fn_get_next_sequence(v_company_id, 'settlement', NULL, NULL);

    IF v_entry_num IS NULL OR v_entry_num = '' THEN

      v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');

    END IF;

    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;



    IF v_incremental_variance > 0 THEN

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

        'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_supp_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

        'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

    ELSE

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_supp_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

        'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

      INSERT INTO public.account_ledger_entries (

        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

      ) VALUES (

        v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

        'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

      );

    END IF;

  END IF;



  UPDATE public.packing_order_cost_items

  SET cost_status = 'actual',

      actual_amount = p_actual_amount,

      base_amount = p_actual_amount,

      original_amount = p_actual_amount,

      expected_amount = v_expected,

      variance_amount = v_total_variance,

      invoice_ref = COALESCE(NULLIF(p_invoice_ref, ''), invoice_ref),

      settlement_notes = COALESCE(NULLIF(p_notes, ''), settlement_notes),

      reconciled_at = now(),

      reconciled_by = COALESCE(p_settled_by, auth.uid()),

      variance_journal_entry_id = COALESCE(v_je_id, variance_journal_entry_id),

      currency_snapshot = jsonb_set(

        COALESCE(currency_snapshot, '{}'::jsonb),

        '{settlement}',

        jsonb_build_object(

          'cost_status', 'actual',

          'expected_amount', v_expected,

          'actual_amount', p_actual_amount,

          'variance_amount', v_total_variance,

          'invoice_ref', p_invoice_ref,

          'settled_at', now(),

          'journal_entry_id', v_je_id

        ),

        true

      )

  WHERE id = p_cost_item_id;



  BEGIN

    v_order_notes := COALESCE(r_order.notes::jsonb, '{}'::jsonb);

    IF jsonb_typeof(v_order_notes) = 'string' THEN

      v_order_notes := (v_order_notes #>> '{}')::jsonb;

    END IF;

  EXCEPTION WHEN OTHERS THEN

    v_order_notes := '{}'::jsonb;

  END;



  IF v_order_notes ? 'cost_items' AND jsonb_typeof(v_order_notes->'cost_items') = 'array' THEN

    v_cost_items_arr := '[]'::jsonb;

    FOR v_ci_elem IN SELECT jsonb_array_elements(v_order_notes->'cost_items')

    LOOP

      IF (v_ci_elem->>'name' = r_item.name) AND 

         ((v_supplier_id IS NOT NULL AND v_ci_elem->>'supplier_id' = v_supplier_id::text) OR (v_supplier_id IS NULL)) THEN

        v_ci_elem := v_ci_elem || jsonb_build_object(

          'cost_status', 'actual',

          'expected_amount', v_expected,

          'actual_amount', p_actual_amount,

          'variance_amount', v_total_variance,

          'total_egp', p_actual_amount,

          'total', p_actual_amount,

          'invoice_ref', p_invoice_ref,

          'reconciled_at', now()

        );

      END IF;

      v_cost_items_arr := v_cost_items_arr || jsonb_build_array(v_ci_elem);

    END LOOP;

    v_order_notes := jsonb_set(v_order_notes, '{cost_items}', v_cost_items_arr, true);

  END IF;



  SELECT COALESCE(SUM(base_amount), 0) INTO v_new_other_cost_base

  FROM public.packing_order_cost_items

  WHERE packing_order_id = r_order.id;



  v_new_total_cost := COALESCE(r_order.fruit_cost_base, 0) + COALESCE(r_order.actual_material_cost, 0) + v_new_other_cost_base;



  SELECT COALESCE(SUM(carton_count), 0) INTO v_cartons_count

  FROM public.packing_order_lines

  WHERE packing_order_id = r_order.id;



  IF v_cartons_count <= 0 THEN

    v_cartons_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);

  END IF;



  IF v_cartons_count > 0 THEN

    v_new_carton_cost := ROUND(v_new_total_cost / v_cartons_count, 2);

  ELSE

    v_new_carton_cost := r_order.packing_cost_per_carton;

  END IF;



  UPDATE public.packing_orders

  SET other_cost_base = v_new_other_cost_base,

      total_cost = v_new_total_cost,

      packing_cost_per_carton = v_new_carton_cost,

      notes = v_order_notes::text,

      updated_at = now()

  WHERE id = r_order.id;



  FOR r_shipment IN

    SELECT DISTINCT shipment_id

    FROM public.export_shipment_items

    WHERE packing_order_id = r_order.id

  LOOP

    v_shipments_affected := v_shipments_affected + 1;



    UPDATE public.export_shipment_items

    SET price = v_new_carton_cost,

        amount = ROUND(quantity * v_new_carton_cost, 2)

    WHERE shipment_id = r_shipment.shipment_id AND packing_order_id = r_order.id;



    UPDATE public.shipment_cost_items sci

    SET unit_price = v_new_carton_cost

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = sci.shipment_id::text

      AND esi.packing_order_id = r_order.id

      AND sci.category = 'packing';



    SELECT

      COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0) INTO v_new_shipment_carton_cost

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;



    SELECT

      COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +

      COALESCE((

        SELECT ROUND(SUM(sci.total_price), 2)

        FROM public.shipment_cost_items sci

        WHERE sci.shipment_id::text = r_shipment.shipment_id::text

          AND sci.category <> 'packing'

      ), 0) INTO v_new_shipment_landed

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

    'cost_item_id', p_cost_item_id,

    'item_name', r_item.name,

    'packing_order_id', r_order.id,

    'order_number', v_order_num,

    'supplier_id', v_supplier_id,

    'expected_amount', v_expected,

    'actual_amount', p_actual_amount,

    'variance_amount', v_total_variance,

    'incremental_variance', v_incremental_variance,

    'journal_entry_id', v_je_id,

    'new_packing_cost_per_carton', v_new_carton_cost,

    'affected_shipments_count', v_shipments_affected,

    'message', 'تمت تسوية التكلفة وتحديث أرصدة المورد وتكاليف الشحنات والربحية بنجاح'

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_item(BIGINT, NUMERIC, TEXT, TEXT, UUID) TO authenticated, service_role, anon;



-- ----------------------------------------------------------------------------

-- RPC: rpc_get_supplier_expected_cost_items

-- ----------------------------------------------------------------------------



CREATE OR REPLACE FUNCTION public.rpc_get_supplier_expected_cost_items(

  p_supplier_type TEXT DEFAULT NULL,

  p_supplier_id UUID DEFAULT NULL,

  p_status TEXT DEFAULT NULL,

  p_search TEXT DEFAULT NULL,

  p_limit INT DEFAULT 200,

  p_offset INT DEFAULT 0

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

  v_result JSONB;

BEGIN

  SELECT COALESCE(jsonb_agg(item_row), '[]'::jsonb) INTO v_result

  FROM (

    SELECT

      ci.id AS cost_item_id,

      ci.packing_order_id,

      po.order_number,

      po.status AS order_status,

      po.packed_at AS order_date,

      po.packing_cost_per_carton,

      ci.name AS item_name,

      ci.category,

      ci.report_category_id,

      COALESCE(rc.name, ci.category) AS report_category_name,

      ci.cost_status,

      COALESCE(

        NULLIF(ci.expected_amount, 0),

        NULLIF((ci.currency_snapshot->'settlement'->>'expected_amount')::numeric, 0),

        CASE WHEN ci.cost_status = 'expected' THEN NULLIF(ci.base_amount, 0) ELSE NULL END,

        NULLIF((ci.currency_snapshot->>'total_egp')::numeric, 0),

        NULLIF((ci.currency_snapshot->>'total')::numeric, 0),

        NULLIF(ci.original_amount, 0),

        ci.base_amount,

        0

      ) AS expected_amount,

      ci.actual_amount,

      COALESCE(ci.variance_amount, 0) AS variance_amount,

      ci.original_currency,

      ci.original_amount,

      ci.exchange_rate,

      ci.base_amount,

      COALESCE(

        NULLIF((ci.currency_snapshot->>'quantity')::numeric, 0),

        1.0

      ) AS quantity,

      COALESCE(

        NULLIF((ci.currency_snapshot->>'unit_price')::numeric, 0),

        CASE 

          WHEN COALESCE((ci.currency_snapshot->>'quantity')::numeric, 1.0) > 0 

          THEN COALESCE(NULLIF(ci.expected_amount, 0), NULLIF(ci.base_amount, 0), ci.original_amount, 0) / COALESCE((ci.currency_snapshot->>'quantity')::numeric, 1.0)

          ELSE COALESCE(NULLIF(ci.expected_amount, 0), NULLIF(ci.base_amount, 0), ci.original_amount, 0)

        END

      ) AS unit_price,

      ci.invoice_ref,

      ci.settlement_notes,

      ci.reconciled_at,

      ci.variance_journal_entry_id,

      s.id AS supplier_id,

      s.name AS supplier_name,

      s.code AS supplier_code,

      s.supplier_type,

      s.phone AS supplier_phone,

      s.outstanding_balance AS supplier_outstanding_balance,

      COALESCE(

        (

          SELECT jsonb_agg(

            jsonb_build_object(

              'shipment_id', es.id,

              'shipment_no', es.shipment_no,

              'status', es.status,

              'total_landed_cost', es.total_landed_cost,

              'net_profit_egp', es.net_profit_egp

            )

          )

          FROM public.export_shipment_items esi

          JOIN public.export_shipments es ON es.id::text = esi.shipment_id::text

          WHERE esi.packing_order_id = po.id

        ),

        '[]'::jsonb

      ) AS linked_shipments

    FROM public.packing_order_cost_items ci

    JOIN public.packing_orders po ON po.id = ci.packing_order_id

    LEFT JOIN public.cost_report_categories rc ON rc.id = ci.report_category_id

    LEFT JOIN public.suppliers s ON (

      s.id::text = ci.supplier_id 

      OR s.id::text = (ci.currency_snapshot->>'supplier_id')

    )

    WHERE 

      (

        p_supplier_type IS NULL 

        OR p_supplier_type = 'all'

        OR (p_supplier_type = 'station' AND (s.supplier_type = 'station' OR s.code LIKE '85%' OR s.code LIKE '86%' OR s.code LIKE '87%' OR s.code LIKE '88%' OR s.code LIKE '89%' OR ci.name ILIKE '%تشغيل%' OR ci.name ILIKE '%تبريد%' OR ci.name ILIKE '%محطة%'))

        OR (p_supplier_type = 'deduction' AND (s.supplier_type IN ('deduction', 'deductions') OR s.code LIKE '4%' OR ci.name ILIKE '%تخصيم%' OR ci.name ILIKE '%فحص%'))

      )

      AND (

        p_supplier_id IS NULL 

        OR s.id = p_supplier_id

      )

      AND (

        p_status IS NULL 

        OR p_status = 'all'

        OR ci.cost_status = p_status

      )

      AND (

        p_search IS NULL 

        OR p_search = ''

        OR ci.name ILIKE '%' || p_search || '%'

        OR po.order_number ILIKE '%' || p_search || '%'

        OR s.name ILIKE '%' || p_search || '%'

        OR s.code ILIKE '%' || p_search || '%'

        OR ci.invoice_ref ILIKE '%' || p_search || '%'

      )

    ORDER BY 

      CASE WHEN ci.cost_status = 'expected' THEN 0 ELSE 1 END,

      ci.id DESC

    LIMIT p_limit

    OFFSET p_offset

  ) item_row;



  RETURN v_result;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_get_supplier_expected_cost_items(TEXT, UUID, TEXT, TEXT, INT, INT) TO authenticated, service_role, anon;



-- ----------------------------------------------------------------------------

-- RPC: rpc_settle_packing_cost_variances (Batch Variance Settlement & Profitability)

-- ----------------------------------------------------------------------------



CREATE OR REPLACE FUNCTION public.rpc_settle_packing_cost_variances(

  p_packing_order_id BIGINT,

  p_settlements JSONB,

  p_general_notes TEXT DEFAULT NULL,

  p_settled_by UUID DEFAULT NULL

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

  r_order RECORD;

  v_order_num TEXT;

  v_company_id UUID;

  v_finished_inv_acc INT;



  v_item_elem JSONB;

  v_cost_item_id BIGINT;

  v_actual_amt NUMERIC;

  v_inv_ref TEXT;

  v_item_notes TEXT;



  r_item RECORD;

  v_expected NUMERIC;

  v_old_actual NUMERIC;

  v_baseline NUMERIC;

  v_incremental_variance NUMERIC;

  v_total_variance NUMERIC;

  v_abs_variance NUMERIC;



  v_is_admin BOOLEAN;

  v_is_transport BOOLEAN;

  v_supplier_id UUID;

  v_supp_str TEXT;

  v_trans_supplier_id INT;

  v_supplier RECORD;

  v_target_acc INT;

  v_category_acc INT;



  v_je_id BIGINT := NULL;

  v_entry_num TEXT;

  v_total_inc_variance NUMERIC := 0;

  v_total_actual_costs NUMERIC := 0;

  v_total_expected_costs NUMERIC := 0;

  v_settled_count INT := 0;



  v_cartons_count NUMERIC := 0;

  v_new_other_cost_base NUMERIC := 0;

  v_new_total_cost NUMERIC := 0;

  v_new_carton_cost NUMERIC := 0;



  v_order_notes JSONB;

  v_cost_items_arr JSONB;

  v_ci_elem JSONB;



  v_shipments_affected INT := 0;

  r_shipment RECORD;

  v_new_shipment_landed NUMERIC;

  v_new_shipment_carton_cost NUMERIC;

  v_shipments_report JSONB := '[]'::jsonb;

  v_shipment_row RECORD;

BEGIN

  IF p_settlements IS NULL OR jsonb_typeof(p_settlements) <> 'array' OR jsonb_array_length(p_settlements) = 0 THEN

    RETURN jsonb_build_object('success', false, 'error', 'قائمة تسوية البنود فارغة');

  END IF;



  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;

  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  v_order_num := COALESCE(r_order.order_number, p_packing_order_id::text);



  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;

  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;



  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));



  -- Pre-calculate total variance to see if journal entry needed

  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)

  LOOP

    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;

    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;

    IF v_actual_amt IS NOT NULL AND v_actual_amt >= 0 THEN

      SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id;

      IF FOUND THEN

        v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);

        v_old_actual := r_item.actual_amount;

        IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
    v_baseline := v_old_actual;
  ELSIF r_order.costs_journal_entry_id IS NOT NULL THEN
    v_baseline := v_expected;
  ELSE
    v_baseline := 0;
  END IF;

        v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);

        v_total_inc_variance := v_total_inc_variance + v_incremental_variance;

      END IF;

    END IF;

  END LOOP;



  IF v_total_inc_variance <> 0 THEN

    INSERT INTO public.journal_entries (

      entry_number, entry_date, description, status,

      is_auto_generated, source_type, source_id, company_id,

      created_by, created_at, updated_at

    ) VALUES (

      'PENDING',

      (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date,

      'قيد تسوية فروق التكاليف الفعلية - أمر تعبئة ' || v_order_num,

      'posted', true, 'packing_cost_settlement', p_packing_order_id::text, v_company_id,

      COALESCE(p_settled_by, auth.uid()), now(), now()

    ) RETURNING id INTO v_je_id;



    v_entry_num := public.fn_get_next_sequence(v_company_id, 'settlement', NULL, NULL);

    IF v_entry_num IS NULL OR v_entry_num = '' THEN

      v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');

    END IF;

    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  END IF;



  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)

  LOOP

    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;

    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;

    v_inv_ref := v_item_elem->>'invoice_ref';

    v_item_notes := v_item_elem->>'notes';



    IF v_actual_amt IS NULL OR v_actual_amt < 0 THEN

      CONTINUE;

    END IF;



    SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id FOR UPDATE;

    IF NOT FOUND THEN

      CONTINUE;

    END IF;



    v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);

    v_old_actual := r_item.actual_amount;

    IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
    v_baseline := v_old_actual;
  ELSIF r_order.costs_journal_entry_id IS NOT NULL THEN
    v_baseline := v_expected;
  ELSE
    v_baseline := 0;
  END IF;



    v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);

    v_total_variance := ROUND(v_actual_amt - v_expected, 2);

    v_abs_variance := ABS(v_incremental_variance);



    v_is_admin := (LOWER(COALESCE(r_item.category, '')) = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%');

    v_is_transport := (LOWER(COALESCE(r_item.category, '')) = 'logistics' OR r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%سيار%' OR r_item.name ILIKE '%شحن داخلي%');



    v_supplier_id := NULL;

    v_supp_str := NULL;

    IF r_item.currency_snapshot IS NOT NULL THEN

      v_supp_str := r_item.currency_snapshot->>'supplier_id';

    END IF;

    IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN

      v_supp_str := r_item.supplier_id;

    END IF;



    IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN

      BEGIN

        v_supplier_id := v_supp_str::uuid;

      EXCEPTION WHEN OTHERS THEN

        v_supplier_id := NULL;

        BEGIN

          v_trans_supplier_id := v_supp_str::integer;

          v_is_transport := TRUE;

        EXCEPTION WHEN OTHERS THEN

          v_trans_supplier_id := NULL;

        END;

      END;

    END IF;



    IF v_supplier_id IS NOT NULL THEN

      SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;

      IF v_supplier.supplier_type = 'transport' THEN

        v_is_transport := TRUE;

      END IF;

    END IF;



    v_target_acc := NULL;

    IF v_is_transport THEN

      v_target_acc := public.resolve_gl_account('21111', v_company_id);

      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

    ELSIF v_is_admin THEN

      v_target_acc := public.resolve_gl_account('31331', v_company_id);

    ELSIF v_supplier_id IS NOT NULL THEN

      IF v_supplier.account_id IS NOT NULL THEN

        v_target_acc := v_supplier.account_id;

      ELSE

        v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);

      END IF;

    ELSE

      IF r_item.report_category_id IS NOT NULL THEN

        SELECT account_id INTO v_category_acc FROM public.cost_report_categories WHERE id = r_item.report_category_id;

        IF v_category_acc IS NOT NULL THEN v_target_acc := v_category_acc; END IF;

      END IF;

      IF v_target_acc IS NULL THEN

        SELECT account_id INTO v_category_acc FROM public.cost_report_categories WHERE name = r_item.name LIMIT 1;

        IF v_category_acc IS NOT NULL THEN v_target_acc := v_category_acc; END IF;

      END IF;

    END IF;



    IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2000', v_company_id); END IF;

    IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;



    IF v_incremental_variance <> 0 AND v_je_id IS NOT NULL THEN

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

          p_packing_order_id,

          'cost_settlement',

          COALESCE(v_inv_ref, r_item.name),

          CASE 

            WHEN v_incremental_variance > 0 THEN 

              'تسوية تكلفة فعلية (زيادة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')

            ELSE 

              'تسوية تكلفة فعلية (وفر) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')

          END,

          now()

        );

      END IF;



      IF v_incremental_variance > 0 THEN

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_finished_inv_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

          'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_target_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

          'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

      ELSE

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_target_acc, v_abs_variance, 0, 'EGP', v_abs_variance,

          'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

        INSERT INTO public.account_ledger_entries (

          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

          v_je_id, v_finished_inv_acc, 0, v_abs_variance, 'EGP', v_abs_variance,

          'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id

        );

      END IF;

    END IF;



    UPDATE public.packing_order_cost_items

    SET cost_status = 'actual',

        actual_amount = v_actual_amt,

        base_amount = v_actual_amt,

        original_amount = v_actual_amt,

        expected_amount = v_expected,

        variance_amount = v_total_variance,

        invoice_ref = COALESCE(NULLIF(v_inv_ref, ''), invoice_ref),

        settlement_notes = COALESCE(NULLIF(v_item_notes, ''), settlement_notes),

        reconciled_at = now(),

        reconciled_by = COALESCE(p_settled_by, auth.uid()),

        variance_journal_entry_id = COALESCE(v_je_id, variance_journal_entry_id),

        currency_snapshot = jsonb_set(

          COALESCE(currency_snapshot, '{}'::jsonb),

          '{settlement}',

          jsonb_build_object(

            'cost_status', 'actual',

            'expected_amount', v_expected,

            'actual_amount', v_actual_amt,

            'variance_amount', v_total_variance,

            'invoice_ref', v_inv_ref,

            'settled_at', now(),

            'journal_entry_id', v_je_id

          ),

          true

        )

    WHERE id = v_cost_item_id;



    v_settled_count := v_settled_count + 1;

  END LOOP;



  SELECT COALESCE(SUM(base_amount), 0) INTO v_new_other_cost_base

  FROM public.packing_order_cost_items

  WHERE packing_order_id = p_packing_order_id;



  v_new_total_cost := COALESCE(r_order.fruit_cost_base, 0) + COALESCE(r_order.actual_material_cost, 0) + v_new_other_cost_base;



  SELECT COALESCE(SUM(carton_count), 0) INTO v_cartons_count

  FROM public.packing_order_lines

  WHERE packing_order_id = p_packing_order_id;



  IF v_cartons_count <= 0 THEN

    v_cartons_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);

  END IF;



  IF v_cartons_count > 0 THEN

    v_new_carton_cost := ROUND(v_new_total_cost / v_cartons_count, 2);

  ELSE

    v_new_carton_cost := r_order.packing_cost_per_carton;

  END IF;



  BEGIN

    v_order_notes := COALESCE(r_order.notes::jsonb, '{}'::jsonb);

    IF jsonb_typeof(v_order_notes) = 'string' THEN

      v_order_notes := (v_order_notes #>> '{}')::jsonb;

    END IF;

  EXCEPTION WHEN OTHERS THEN

    v_order_notes := '{}'::jsonb;

  END;



  IF v_order_notes ? 'cost_items' AND jsonb_typeof(v_order_notes->'cost_items') = 'array' THEN

    v_cost_items_arr := '[]'::jsonb;

    FOR v_ci_elem IN SELECT jsonb_array_elements(v_order_notes->'cost_items')

    LOOP

      SELECT * INTO r_item 

      FROM public.packing_order_cost_items 

      WHERE packing_order_id = p_packing_order_id AND name = (v_ci_elem->>'name')

      LIMIT 1;

      IF FOUND THEN

        v_ci_elem := v_ci_elem || jsonb_build_object(

          'cost_status', r_item.cost_status,

          'expected_amount', r_item.expected_amount,

          'actual_amount', r_item.actual_amount,

          'variance_amount', r_item.variance_amount,

          'total_egp', r_item.base_amount,

          'total', r_item.original_amount,

          'invoice_ref', r_item.invoice_ref,

          'reconciled_at', r_item.reconciled_at

        );

      END IF;

      v_cost_items_arr := v_cost_items_arr || jsonb_build_array(v_ci_elem);

    END LOOP;

    v_order_notes := jsonb_set(v_order_notes, '{cost_items}', v_cost_items_arr, true);

  END IF;



  UPDATE public.packing_orders

  SET other_cost_base = v_new_other_cost_base,

      total_cost = v_new_total_cost,

      packing_cost_per_carton = v_new_carton_cost,

      notes = v_order_notes::text,

      updated_at = now()

  WHERE id = p_packing_order_id;



  -- Update Linked Export Shipments

  FOR r_shipment IN

    SELECT DISTINCT shipment_id

    FROM public.export_shipment_items

    WHERE packing_order_id = p_packing_order_id

  LOOP

    v_shipments_affected := v_shipments_affected + 1;



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



    SELECT

      COALESCE(ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2), 0) INTO v_new_shipment_carton_cost

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;



    SELECT

      COALESCE(ROUND(SUM(esi.quantity * esi.price), 2), 0) +

      COALESCE((

        SELECT ROUND(SUM(sci.total_price), 2)

        FROM public.shipment_cost_items sci

        WHERE sci.shipment_id::text = r_shipment.shipment_id::text

          AND sci.category <> 'packing'

      ), 0) INTO v_new_shipment_landed

    FROM public.export_shipment_items esi

    WHERE esi.shipment_id::text = r_shipment.shipment_id::text;



    UPDATE public.export_shipments s

    SET cost_per_carton = v_new_shipment_carton_cost,

        total_landed_cost = v_new_shipment_landed,

        net_profit_egp = COALESCE(s.total_revenue_egp, 0) - v_new_shipment_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),

        net_profit = COALESCE(s.total_revenue_egp, 0) - v_new_shipment_landed - COALESCE(s.allocated_admin_expenses, 0) - COALESCE(s.allocated_taxes, 0),

        updated_at = now()

    WHERE s.id::text = r_shipment.shipment_id::text;



    SELECT id, shipment_no, total_revenue_egp, total_landed_cost, net_profit_egp 

    INTO v_shipment_row

    FROM public.export_shipments

    WHERE id::text = r_shipment.shipment_id::text;



    v_shipments_report := v_shipments_report || jsonb_build_array(jsonb_build_object(

      'shipment_id', v_shipment_row.id,

      'shipment_no', v_shipment_row.shipment_no,

      'total_revenue_egp', v_shipment_row.total_revenue_egp,

      'total_landed_cost', v_shipment_row.total_landed_cost,

      'net_profit_egp', v_shipment_row.net_profit_egp

    ));

  END LOOP;



  SELECT 

    COALESCE(SUM(expected_amount), 0),

    COALESCE(SUM(actual_amount), 0)

  INTO v_total_expected_costs, v_total_actual_costs

  FROM public.packing_order_cost_items

  WHERE packing_order_id = p_packing_order_id;



  RETURN jsonb_build_object(

    'success', true,

    'packing_order_id', p_packing_order_id,

    'order_number', v_order_num,

    'settled_items_count', v_settled_count,

    'total_expected_costs', v_total_expected_costs,

    'total_actual_costs', v_total_actual_costs,

    'total_variance', (v_total_actual_costs - v_total_expected_costs),

    'journal_entry_id', v_je_id,

    'journal_entry_number', v_entry_num,

    'new_packing_cost_per_carton', v_new_carton_cost,

    'affected_shipments_count', v_shipments_affected,

    'affected_shipments', v_shipments_report,

    'message', 'تم تأكيد التسوية الفعلية وتوليد القيود المحاسبية وتحديث ربحية الشحنات بنجاح'

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_variances(BIGINT, JSONB, TEXT, UUID) TO authenticated, service_role, anon;



-- ----------------------------------------------------------------------------

-- Helper RPC: rpc_get_packing_order_variance_details

-- ----------------------------------------------------------------------------



CREATE OR REPLACE FUNCTION public.rpc_get_packing_order_variance_details(p_packing_order_id BIGINT)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

  r_order RECORD;

  v_items JSONB := '[]'::jsonb;

  v_shipments JSONB := '[]'::jsonb;

  v_carton_count NUMERIC := 0;

BEGIN

  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id;

  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  SELECT COALESCE(jsonb_agg(item_row), '[]'::jsonb) INTO v_items

  FROM (

    SELECT 

      ci.id,

      ci.name,

      ci.category,

      ci.cost_status,

      COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0) AS expected_amount,

      ci.actual_amount,

      COALESCE(ci.variance_amount, CASE WHEN ci.actual_amount IS NOT NULL THEN ci.actual_amount - COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0) ELSE 0 END) AS variance_amount,

      ci.invoice_ref,

      ci.settlement_notes,

      ci.reconciled_at,

      ci.reconciled_by,

      ci.variance_journal_entry_id,

      ci.supplier_id,

      COALESCE(s.name, ci.currency_snapshot->>'supplier_name', 'مورد عام / بدون مورد') AS supplier_name,

      COALESCE(s.supplier_type, ci.currency_snapshot->>'supplier_type', 'general') AS supplier_type

    FROM public.packing_order_cost_items ci

    LEFT JOIN public.suppliers s ON (s.id::text = ci.supplier_id)

    WHERE ci.packing_order_id = p_packing_order_id

    ORDER BY ci.id

  ) item_row;



  SELECT COALESCE(jsonb_agg(ship_row), '[]'::jsonb) INTO v_shipments

  FROM (

    SELECT DISTINCT

      s.id,

      s.shipment_no,

      s.status,

      s.destination_country,

      s.customer_name,

      COALESCE(s.total_revenue_egp, 0) AS total_revenue_egp,

      COALESCE(s.total_landed_cost, 0) AS total_landed_cost,

      COALESCE(s.cost_per_carton, 0) AS cost_per_carton,

      COALESCE(s.net_profit_egp, 0) AS net_profit_egp,

      COALESCE(s.allocated_admin_expenses, 0) AS allocated_admin_expenses,

      COALESCE(s.allocated_taxes, 0) AS allocated_taxes,

      esi.quantity AS order_cartons_in_shipment

    FROM public.export_shipments s

    JOIN public.export_shipment_items esi ON (esi.shipment_id::text = s.id::text)

    WHERE esi.packing_order_id = p_packing_order_id

  ) ship_row;



  SELECT COALESCE(SUM(carton_count), 0) INTO v_carton_count

  FROM public.packing_order_lines

  WHERE packing_order_id = p_packing_order_id;

  IF v_carton_count <= 0 THEN

    v_carton_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);

  END IF;



  RETURN jsonb_build_object(

    'success', true,

    'packing_order_id', p_packing_order_id,

    'order_number', COALESCE(r_order.order_number, p_packing_order_id::text),

    'order_status', r_order.status,

    'fruit_cost_base', COALESCE(r_order.fruit_cost_base, 0),

    'actual_material_cost', COALESCE(r_order.actual_material_cost, 0),

    'other_cost_base', COALESCE(r_order.other_cost_base, 0),

    'total_cost', COALESCE(r_order.total_cost, 0),

    'carton_count', v_carton_count,

    'packing_cost_per_carton', COALESCE(r_order.packing_cost_per_carton, 0),

    'items', v_items,

    'shipments', v_shipments

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_get_packing_order_variance_details(BIGINT) TO authenticated, service_role, anon;



-- ============================================================================

-- rpc_add_transport_invoice: تسجيل فاتورة نقل لمورد نقل

-- ============================================================================

DO $$

DECLARE

    r RECORD;

BEGIN

    FOR r IN (

        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args

        FROM pg_proc p

        JOIN pg_namespace n ON n.oid = p.pronamespace

        WHERE n.nspname = 'public' AND p.proname = 'rpc_add_transport_invoice'

    ) LOOP

        EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s) CASCADE;', r.proname, r.args);

    END LOOP;

END $$;



CREATE OR REPLACE FUNCTION public.rpc_add_transport_invoice(

    p_supplier_id        integer,

    p_amount             numeric,

    p_number_of_trucks   numeric DEFAULT 1,

    p_truck_count        numeric DEFAULT 1,

    p_route_from       text    DEFAULT NULL,

    p_route_to         text    DEFAULT NULL,

    p_date             date    DEFAULT NULL,

    p_description      text    DEFAULT NULL,

    p_expense_account_id integer DEFAULT NULL,

    p_reference_number text    DEFAULT NULL,

    p_notes            text    DEFAULT NULL

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

        ORDER BY CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END

        LIMIT 1;

    END IF;



    v_supplier_acct_id := v_supplier.account_id;

    IF v_supplier_acct_id IS NULL THEN

        SELECT id INTO v_supplier_acct_id

        FROM public.accounts

        WHERE (code = '21311' OR account_code = '21311'

               OR name ILIKE '%موردي نقل%' OR name ILIKE '%دائنو نقل%')

          AND is_active = true

        ORDER BY id ASC LIMIT 1;

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





-- ============================================================================

-- rpc_pay_transport_supplier: تسجيل سداد لمورد نقل

-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_pay_transport_supplier(

    integer, text, integer, numeric, date, text, text

);



CREATE OR REPLACE FUNCTION public.rpc_pay_transport_supplier(

    p_supplier_id   integer,

    p_source_type   text,

    p_source_id     integer,

    p_amount        numeric,

    p_date          date    DEFAULT NULL,

    p_description   text    DEFAULT NULL,

    p_notes         text    DEFAULT NULL

)

RETURNS jsonb

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

    v_date             date;

    v_desc             text;

    v_txn_type         text;

    v_supplier         RECORD;

    v_journal_id       bigint;

    v_entry_number     text;

    v_transaction_id   integer;

    v_supplier_acct_id bigint;

    v_source_acct_id   bigint;

BEGIN

    v_date := COALESCE(p_date, (NOW() AT TIME ZONE 'Africa/Cairo')::date);



    IF p_amount IS NULL OR p_amount <= 0 THEN

        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');

    END IF;



    SELECT id, name, account_id, balance

    INTO v_supplier

    FROM public.transport_suppliers

    WHERE id = p_supplier_id;



    IF NOT FOUND THEN

        RETURN jsonb_build_object('success', false, 'error', 'مورد النقل غير موجود');

    END IF;



    IF p_source_type = 'bank' THEN

        v_txn_type := 'bank_payment';

    ELSE

        v_txn_type := 'cash_payment';

    END IF;



    v_desc := COALESCE(p_description, 'سداد لمورد نقل - ' || v_supplier.name);



    v_supplier_acct_id := v_supplier.account_id;

    IF v_supplier_acct_id IS NULL THEN

        SELECT id INTO v_supplier_acct_id

        FROM public.accounts

        WHERE (code = '21311' OR account_code = '21311'

               OR name ILIKE '%موردي نقل%' OR name ILIKE '%دائنو نقل%')

          AND is_active = true

        ORDER BY id ASC LIMIT 1;

    END IF;



    IF p_source_type = 'bank' THEN

        SELECT account_id INTO v_source_acct_id

        FROM public.bank_accounts

        WHERE id = p_source_id;



        IF v_source_acct_id IS NULL THEN

            SELECT id INTO v_source_acct_id

            FROM public.accounts

            WHERE (code = '12211' OR account_code = '12211' OR name ILIKE '%بنك%')

              AND is_active = true

            ORDER BY id ASC LIMIT 1;

        END IF;

    ELSE

        IF p_source_id IS NOT NULL THEN

            SELECT account_id INTO v_source_acct_id

            FROM public.treasuries

            WHERE id = p_source_id;

        END IF;



        IF v_source_acct_id IS NULL THEN

            SELECT id INTO v_source_acct_id

            FROM public.accounts

            WHERE (code = '12111' OR account_code = '12111'

                   OR name ILIKE '%صندوق%' OR name ILIKE '%خزينة%')

              AND is_active = true

            ORDER BY id ASC LIMIT 1;

        END IF;

    END IF;



    IF v_supplier_acct_id IS NOT NULL AND v_source_acct_id IS NOT NULL THEN

        v_entry_number := 'TP-' || to_char(v_date, 'YYYYMMDD') || '-' ||

                          lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');



        INSERT INTO public.journal_entries (

            entry_number, entry_date, description, status, source_type, source_id

        ) VALUES (

            v_entry_number, v_date, v_desc, 'posted',

            'transport_payment', 'transport_suppliers_' || p_supplier_id::text

        ) RETURNING id INTO v_journal_id;



        INSERT INTO public.account_ledger_entries (

            journal_entry_id, account_id, debit, credit,

            currency, amount_in_base_currency, description,

            entity_type, entity_id

        ) VALUES (

            v_journal_id, v_supplier_acct_id, p_amount, 0,

            'EGP', p_amount, v_desc,

            'transport_supplier', p_supplier_id::text

        );



        INSERT INTO public.account_ledger_entries (

            journal_entry_id, account_id, debit, credit,

            currency, amount_in_base_currency, description,

            entity_type, entity_id

        ) VALUES (

            v_journal_id, v_source_acct_id, 0, p_amount,

            'EGP', p_amount, v_desc,

            'transport_supplier', p_supplier_id::text

        );

    END IF;



    INSERT INTO public.transport_transactions (

        supplier_id, type, amount, description,

        notes, journal_entry_id, date

    ) VALUES (

        p_supplier_id, v_txn_type, p_amount, v_desc,

        p_notes, v_journal_id, v_date

    ) RETURNING id INTO v_transaction_id;



    UPDATE public.transport_suppliers

    SET balance = COALESCE(balance, 0) - p_amount,

        current_balance = COALESCE(current_balance, 0) - p_amount,

        updated_at = NOW()

    WHERE id = p_supplier_id;



    RETURN jsonb_build_object(

        'success', true,

        'transaction_id', v_transaction_id,

        'journal_id', v_journal_id,

        'journal_number', v_entry_number,

        'amount', p_amount,

        'payment_type', v_txn_type

    );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_pay_transport_supplier(

    integer, text, integer, numeric, date, text, text

) TO authenticated, service_role, anon;





NOTIFY pgrst, 'reload_schema';



COMMIT;



-- ══════════════════════════════════════════════════════════════════════════════

-- تصفير نهائي لمراكز التكلفة ومعاملاتها (transaction مستقلة)

-- العميل ينشئ مراكز التكلفة حسب احتياجاته من واجهة التطبيق

-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;



-- 1. حذف كل معاملات مراكز التكلفة

DELETE FROM public.cost_center_transactions;



-- 2. إزالة ربط مراكز التكلفة من الجداول المرتبطة

UPDATE public.accounts SET cost_center_id = NULL WHERE cost_center_id IS NOT NULL;

UPDATE public.cost_report_categories SET cost_center_id = NULL WHERE cost_center_id IS NOT NULL;

UPDATE public.fruit_types SET cost_center_id = NULL WHERE cost_center_id IS NOT NULL;



-- 3. حذف كل مراكز التكلفة

DELETE FROM public.cost_centers;



COMMIT;

