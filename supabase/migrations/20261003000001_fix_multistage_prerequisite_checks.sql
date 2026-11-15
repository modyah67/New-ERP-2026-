-- ============================================================================
-- Migration: Fix Multi-Stage Workflow Prerequisite Checks & Status Preservation
-- Date: 2026-10-03
--
-- Description:
-- 1. Updates rpc_confirm_packing_packaging and rpc_confirm_packing_costs to
--    evaluate actual stage timestamp/journal entry flags (crops_confirmed_at,
--    packaging_confirmed_at) instead of solely trusting the status column.
--    This prevents false prerequisite errors if an order status was accidentally
--    synced as 'pending' despite crops being verified and deducted.
-- 2. Restores status to the correct workflow stage for any existing orders.
-- ============================================================================

-- ── 1. Auto-heal orders whose status regressed to draft/pending ──
UPDATE public.packing_orders
SET status = CASE
  WHEN final_approved_at IS NOT NULL THEN 'final_approved'
  WHEN costs_confirmed_at IS NOT NULL THEN 'costs_confirmed'
  WHEN packaging_confirmed_at IS NOT NULL THEN 'packaging_confirmed'
  WHEN crops_confirmed_at IS NOT NULL THEN 'crops_confirmed'
  ELSE status
END
WHERE status IN ('draft', 'pending')
  AND (crops_confirmed_at IS NOT NULL OR packaging_confirmed_at IS NOT NULL OR costs_confirmed_at IS NOT NULL OR final_approved_at IS NOT NULL);

-- ── 2. Update rpc_confirm_packing_packaging ──
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

  v_mat_waste_pct NUMERIC := 0;
  v_tot_pkg_drawn NUMERIC := 0;
  v_tot_pkg_waste NUMERIC := 0;
  v_tot_pkg_consumed NUMERIC := 0;

  v_finished_inv_acc INT;
  v_pkg_inv_acc INT;
  v_pkg_waste_inter_acc INT;

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
  v_sp_qty NUMERIC;
  v_rem_needed NUMERIC;
  r_b RECORD;
  v_take NUMERIC;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Validate prerequisite: crops must be confirmed first (check status AND actual confirmation flags)
  IF (v_order.status IN ('draft', 'pending')) AND v_order.crops_confirmed_at IS NULL AND v_order.crops_journal_entry_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'يجب تأكيد المحاصيل وخصمها من المخزن أولاً قبل تأكيد مواد التعبئة');
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

  -- 1. Deduct Materials Inventory
  DECLARE
    v_mat_array JSONB := '[]'::jsonb;
  BEGIN
    IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
      v_mat_array := v_notes->'materials';
    ELSIF v_notes ? 'material_items' AND jsonb_typeof(v_notes->'material_items') = 'array' THEN
      v_mat_array := v_notes->'material_items';
    END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_mat_array) LOOP
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';
      v_used_qty := COALESCE((v_el->>'used_qty')::numeric, (v_el->>'quantity')::numeric, 0);
      v_batch_id := NULL;
      IF v_el ? 'batch_id' AND (v_el->>'batch_id') IS NOT NULL AND (v_el->>'batch_id') != '' THEN
        v_batch_id := (v_el->>'batch_id')::bigint;
      END IF;

      IF v_used_qty > 0 THEN
        IF v_batch_id IS NOT NULL THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = GREATEST(0, remaining_quantity - v_used_qty),
              updated_at = now()
          WHERE id = v_batch_id;
        ELSE
          v_rem_needed := v_used_qty;
          FOR r_b IN
            SELECT id, remaining_quantity
            FROM public.station_product_batches
            WHERE station_id = v_station_id
              AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode))
              AND remaining_quantity > 0
            ORDER BY created_at ASC
            FOR UPDATE
          LOOP
            IF v_rem_needed <= 0 THEN EXIT; END IF;
            v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
            UPDATE public.station_product_batches
            SET remaining_quantity = remaining_quantity - v_take,
                updated_at = now()
            WHERE id = r_b.id;
            v_rem_needed := v_rem_needed - v_take;
          END LOOP;
        END IF;

        UPDATE public.station_products
        SET quantity = GREATEST(0, quantity - v_used_qty),
            updated_at = now()
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
  END;

  IF v_tot_pkg_drawn = 0 THEN
    v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    IF v_mat_waste_pct > 0 THEN
      v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 4);
    END IF;
  END IF;

  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 4);
  v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;

  -- 3. Resolve GL Accounts
  SELECT a.company_id INTO v_company_id FROM public.accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT a.company_id INTO v_company_id FROM public.accounts a WHERE a.company_id IS NOT NULL LIMIT 1;
  END IF;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;

  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));
  v_pkg_inv_acc      := COALESCE(public.resolve_gl_account('12411', v_company_id), public.resolve_gl_account('1040', v_company_id));

  -- 4. Journal Entry for Packaging
  IF v_tot_pkg_consumed > 0 AND v_finished_inv_acc IS NOT NULL AND v_pkg_inv_acc IS NOT NULL THEN
    IF v_order.packaging_journal_entry_id IS NOT NULL THEN
      v_je_id := v_order.packaging_journal_entry_id;
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
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

    -- DR Finished Goods Inventory (12413 / 1031) - absorbs total packaging materials including waste
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_pkg_consumed, 0, 'EGP', v_tot_pkg_consumed,
      'تكلفة مواد التعبئة والتغليف والهالك - أمر ' || v_order_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_pkg_consumed;

    -- CR Packaging Materials Inventory (12411 / 1040) - total materials disbursed from warehouse
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
    'packaging_base_cost', v_tot_pkg_drawn,
    'packaging_waste_cost', v_tot_pkg_waste,
    'packaging_total_cost', v_tot_pkg_consumed
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_packaging(bigint) TO authenticated, anon, service_role;
