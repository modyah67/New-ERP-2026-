-- ============================================================================
-- Migration: Multi-Stage Workflow & Approvals for Packing Orders
-- Description:
--   Supports granular, stage-based confirmation workflow for packing orders:
--     1. Draft (pending/draft)
--     2. Crops Confirmed (fruit deducted from inventory, fruit GL entry posted)
--     3. Packaging Confirmed (materials deducted from stock, packaging GL entry posted)
--     4. Costs Confirmed (costs classified, supplier liabilities posted to sub-ledger & GL)
--     5. Final Approved (order fully closed and locked)
-- ============================================================================

-- 1. Update packing_orders status check constraint
ALTER TABLE public.packing_orders
DROP CONSTRAINT IF EXISTS packing_orders_status_check;

ALTER TABLE public.packing_orders
ADD CONSTRAINT packing_orders_status_check
CHECK (status = ANY (ARRAY[
    'draft'::text,
    'pending'::text,
    'in_progress'::text,
    'crops_confirmed'::text,
    'packaging_confirmed'::text,
    'costs_confirmed'::text,
    'final_approved'::text,
    'completed'::text,
    'cancelled'::text,
    'returned'::text
]));

-- 2. Add stage tracking columns to packing_orders
ALTER TABLE public.packing_orders
ADD COLUMN IF NOT EXISTS crops_confirmed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS crops_journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS packaging_confirmed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS packaging_journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS costs_confirmed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS costs_journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS final_approved_at TIMESTAMPTZ;

-- 3. Register document sequence types if needed
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES 
  ('packing_crops', 'Packing Order Crops Confirmation', 'POC', true),
  ('packing_pkg', 'Packing Order Packaging Confirmation', 'POP', true),
  ('packing_cost', 'Packing Order Cost Items Confirmation', 'POX', true)
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- STAGE 1: Confirm Crops & Deduct Inventory (تأكيد المحاصيل وخصم المخزون)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_crops(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_station_id INT;
  v_packed_at TIMESTAMPTZ;
  v_company_id UUID;

  v_tot_raw_cost NUMERIC := 0;
  v_tot_waste_cost NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_fruit_net_cost NUMERIC := 0;

  v_finished_inv_acc INT;
  v_raw_inv_acc INT;
  v_sorting_inv_acc INT;
  v_crop_waste_inter_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_alloc JSONB;
  v_el JSONB;
  v_batch_id BIGINT;
  v_used_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_curr_rem NUMERIC;
  v_sp_qty NUMERIC;
  v_crops_found BOOLEAN := false;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Idempotency check: only block if the order has already been final approved / completed
  IF v_order.status IN ('final_approved', 'completed') THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة معتمد نهائياً ومقفل بالكامل',
      'status', v_order.status,
      'journal_entry_id', COALESCE(v_order.crops_journal_entry_id, v_order.journal_entry_id)
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
  v_packed_at := COALESCE(v_order.packed_at, now());

  -- 1. Deduct Fruit Batches from inventory
  IF v_notes ? 'fruit_allocation' THEN
    v_alloc := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_alloc) = 'object' THEN v_alloc := jsonb_build_array(v_alloc); END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
        v_crops_found := true;
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id
        FOR UPDATE;

        IF FOUND THEN
          IF v_curr_rem < v_used_qty THEN
            RAISE EXCEPTION 'الكمية المتاحة في الدفعة رقم % غير كافية (المتاح: %، المطلوب: %)', v_batch_id, v_curr_rem, v_used_qty;
          END IF;

          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - v_used_qty
          WHERE id = v_batch_id;

          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
          FROM public.station_product_batches
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

          UPDATE public.station_products
          SET quantity = v_sp_qty, updated_at = NOW()
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
        ELSE
          RAISE EXCEPTION 'الدفعة رقم % غير موجودة في المخزن', v_batch_id;
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 2. Calculate Fruit Costs
  v_tot_raw_cost := ROUND(COALESCE(v_order.fruit_cost_base, 0), 4);
  IF v_tot_raw_cost = 0 AND v_notes ? 'fruit_allocation' THEN
    DECLARE
      v_f_elem JSONB;
      v_f_arr JSONB := v_notes->'fruit_allocation';
    BEGIN
      IF jsonb_typeof(v_f_arr) = 'object' THEN v_f_arr := jsonb_build_array(v_f_arr); END IF;
      FOR v_f_elem IN SELECT * FROM jsonb_array_elements(v_f_arr) LOOP
        v_tot_raw_cost := v_tot_raw_cost + (
          COALESCE((v_f_elem->>'quantity')::numeric, 0) *
          COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0)
        );
      END LOOP;
    END;
  END IF;
  IF v_tot_raw_cost = 0 THEN
    v_tot_raw_cost := ROUND(COALESCE(v_order.fruit_cost_allocated, 0), 4);
  END IF;

  v_tot_sorting_cost := ROUND(COALESCE((v_notes->>'sorting_cost')::numeric, 0), 4);
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_sortings WHERE packing_order_id = p_packing_order_id;
  END IF;

  v_tot_waste_cost := ROUND(COALESCE((v_notes->>'waste_cost')::numeric, 0), 4);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;

  v_fruit_net_cost := ROUND(GREATEST(0, v_tot_raw_cost - v_tot_sorting_cost - v_tot_waste_cost), 4);

  -- 3. Resolve GL Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc     := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));
  v_sorting_inv_acc      := COALESCE(public.resolve_gl_account('12414', v_company_id), public.resolve_gl_account('1032', v_company_id));
  v_raw_inv_acc          := COALESCE(public.resolve_gl_account('12412', v_company_id), public.resolve_gl_account('1030', v_company_id));
  v_crop_waste_inter_acc := COALESCE(public.resolve_gl_account('9112', v_company_id), public.resolve_gl_account('2107', v_company_id));

  -- 4. Create Crops Confirmation Journal Entry (if any raw fruit cost > 0)
  IF v_tot_raw_cost > 0 THEN
    IF v_order.crops_journal_entry_id IS NOT NULL THEN
      v_je_id := v_order.crops_journal_entry_id;
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      UPDATE public.journal_entries
      SET description = 'قيد تأكيد وصرف محاصيل أمر تعبئة رقم ' || v_order_num,
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
        'قيد تأكيد وصرف محاصيل أمر تعبئة رقم ' || v_order_num,
        'posted', true, 'packing_order_crops', p_packing_order_id::text, v_company_id,
        auth.uid(), now(), now()
      ) RETURNING id INTO v_je_id;

      v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_crops', NULL, NULL);
      IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'POC-' || LPAD(v_je_id::text, 5, '0');
      END IF;
      UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
    END IF;

    -- DR Finished Goods Inventory (Net Fruit Cost + Fruit Waste Cost)
    IF (v_fruit_net_cost + v_tot_waste_cost) > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_finished_inv_acc, (v_fruit_net_cost + v_tot_waste_cost), 0, 'EGP', (v_fruit_net_cost + v_tot_waste_cost),
        'تكلفة المحصول الداخل في التعبئة وهالك الفاقد - أمر ' || v_order_num, v_company_id
      );
      v_sum_debit := v_sum_debit + (v_fruit_net_cost + v_tot_waste_cost);
    END IF;

    -- DR Sorting Inventory (12414 / 1032)
    IF v_tot_sorting_cost > 0 AND v_sorting_inv_acc IS NOT NULL THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, 'EGP', v_tot_sorting_cost,
        'مخزون الفرز - أمر تعبئة ' || v_order_num, v_company_id
      );
      v_sum_debit := v_sum_debit + v_tot_sorting_cost;
    END IF;

    -- CR Raw Produce Inventory (12412 / 1030)
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,
      'صرف محصول خام بالكامل - أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;

    -- Balance check
    IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN
      RAISE EXCEPTION 'فشل تأكيد قيد المحاصيل: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
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
  v_notes := jsonb_set(v_notes, '{workflow_stages,crops}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'raw_cost', v_tot_raw_cost,
    'sorting_cost', v_tot_sorting_cost,
    'waste_cost', v_tot_waste_cost
  ), true);

  UPDATE public.packing_orders
  SET status = CASE
        WHEN status IN ('packaging_confirmed', 'costs_confirmed', 'final_approved', 'completed') THEN status
        ELSE 'crops_confirmed'
      END,
      crops_confirmed_at = COALESCE(crops_confirmed_at, now()),
      crops_journal_entry_id = v_je_id,
      journal_entry_id = COALESCE(journal_entry_id, v_je_id),
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'status', 'crops_confirmed',
    'journal_entry_id', v_je_id,
    'raw_cost', v_tot_raw_cost,
    'sorting_cost', v_tot_sorting_cost,
    'waste_cost', v_tot_waste_cost,
    'fruit_net_cost', v_fruit_net_cost
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_crops(bigint) TO authenticated, service_role, anon;


-- ============================================================================
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

  -- Validate prerequisite: crops must be confirmed first
  IF v_order.status IN ('draft', 'pending') THEN
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

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_el JSONB;
  r_cost RECORD;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_max_cost_item_id BIGINT;
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
          v_supplier_id := v_supp_str::uuid;
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
          currency_snapshot, supplier_id, payment_status, paid_amount
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
            'supplier_id', v_supplier_id,
            'supplier_name', v_el->>'supplier_name',
            'target_line_index', v_target_line_idx
          ),
          v_supplier_id::text,
          'unpaid',
          0
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

      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
        END IF;
      END IF;

      IF v_credit_acc IS NULL THEN
        v_credit_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
      END IF;

      IF v_credit_acc IS NULL THEN
        v_credit_acc := public.resolve_gl_account('2000', v_company_id);
      END IF;

      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
        'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
      );
      v_sum_credit := v_sum_credit + r_cost.base_amount;
      v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

      -- Post Sub-Ledger Entry for Supplier
      IF v_supplier_id IS NOT NULL THEN
        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
          'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
          'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
        );
        UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
      END IF;
    END LOOP;

    -- Fallback for unallocated general costs
    IF v_tot_cost_items > v_posted_cost_items THEN
      v_credit_acc := public.resolve_gl_account('2000', v_company_id);
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

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';
