-- ============================================================================
-- Migration 360: Packing Waste System & Sorting Decoupling
-- ============================================================================
-- 1. Modifies packing_order_sortings: drops NOT NULL on packing_order_id and adds packing_waste_id.
-- 2. Creates packing_wastes table (Draft/Completed lifecycle).
-- 3. Implements rpc_confirm_packing_waste:
--    - Deducts raw crop waste and sorting quantities from station_product_batches.
--    - Deducts packaging material waste from station_product_batches.
--    - Inserts sorting records into packing_order_sortings (Asset 1032).
--    - Generates balanced GL journal entry:
--        DR 51102 (هالك المحاصيل)
--        DR 51104 (هالك مواد التعبئة)
--        DR 1032  (مخزون الفرز)
--        DR 51101 (بنود التكلفة الإضافية)
--        CR 1030  (مخزون المحاصيل)
--        CR 1040  (مخزون مواد التعبئة)
--        CR Supplier accounts (استحقاق الموردين)
-- ============================================================================

-- 1. تعديل جدول الفرز لدعم أذون الهالك
ALTER TABLE public.packing_order_sortings 
  ALTER COLUMN packing_order_id DROP NOT NULL;

-- 2. إنشاء جدول أذون هالك التعبئة
CREATE TABLE IF NOT EXISTS public.packing_wastes (
    id BIGSERIAL PRIMARY KEY,
    waste_number TEXT UNIQUE NOT NULL,
    station_id INTEGER REFERENCES public.stations(id) ON DELETE RESTRICT,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'completed')),
    total_crop_waste_cost NUMERIC(14,2) DEFAULT 0,
    total_sorting_cost NUMERIC(14,2) DEFAULT 0,
    total_material_waste_cost NUMERIC(14,2) DEFAULT 0,
    total_cost_items NUMERIC(14,2) DEFAULT 0,
    total_waste_amount NUMERIC(14,2) DEFAULT 0,
    journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,
    notes JSONB DEFAULT '{}'::jsonb,
    company_id UUID REFERENCES public.sys_companies(id) ON DELETE SET NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ربط جدول الفرز بجدول الهالك كـ Foreign Key اختياري
ALTER TABLE public.packing_order_sortings 
  ADD COLUMN IF NOT EXISTS packing_waste_id BIGINT 
  REFERENCES public.packing_wastes(id) ON DELETE CASCADE;

-- 3. دالة تأكيد إذن هالك التعبئة (RPC)
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_waste(p_waste_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_waste RECORD;
  v_notes JSONB;
  v_waste_num TEXT;
  v_station_id INT;
  v_company_id UUID;
  v_user_id UUID;

  -- مجاميع التكاليف
  v_tot_crop_waste NUMERIC := 0;
  v_tot_sorting NUMERIC := 0;
  v_tot_crop_raw NUMERIC := 0;
  v_tot_mat_waste NUMERIC := 0;
  v_tot_cost_items NUMERIC := 0;
  v_grand_total NUMERIC := 0;

  -- حسابات شجرة الحسابات الرسمية
  v_waste_crop_acc INT;  -- 51102
  v_waste_mat_acc INT;   -- 51104
  v_sorting_acc INT;     -- 1032
  v_cost_item_acc INT;   -- 51101
  v_raw_inv_acc INT;     -- 1030
  v_pkg_inv_acc INT;     -- 1040
  v_credit_acc INT;
  v_supp_leaf_acc INT;

  -- قيد اليومية
  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  -- متغيرات الحلقات
  v_el JSONB;
  v_batch_id BIGINT;
  v_curr_rem NUMERIC;
  v_sp_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_waste_weight NUMERIC;
  v_sorted_weight NUMERIC;
  v_unit_cost NUMERIC;
  v_waste_cost NUMERIC;
  v_sorting_cost NUMERIC;
  v_waste_qty NUMERIC;
  v_amt_egp NUMERIC;
  v_supplier_id UUID;
  v_supp_str TEXT;
BEGIN
  -- أ. التحقق من وجود الإذن وحالته
  SELECT * INTO v_waste FROM public.packing_wastes WHERE id = p_waste_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'إذن الهالك غير موجود');
  END IF;

  IF v_waste.status = 'completed' THEN
    RETURN json_build_object('success', true, 'message', 'إذن الهالك مؤكد بالفعل', 'journal_entry_id', v_waste.journal_entry_id);
  END IF;

  v_notes := COALESCE(v_waste.notes, '{}'::jsonb);
  v_waste_num := COALESCE(v_waste.waste_number, 'PW-' || p_waste_id::text);
  v_station_id := v_waste.station_id;
  v_company_id := v_waste.company_id;
  v_user_id := COALESCE(v_waste.created_by, auth.uid());

  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  END IF;

  -- التحقق الإجباري: وجود بند تكلفة واحد على الأقل
  IF NOT (v_notes ? 'cost_items') OR jsonb_array_length(v_notes->'cost_items') = 0 THEN
    RETURN json_build_object('success', false, 'error', 'يجب إضافة بند تكلفة إضافي واحد على الأقل لتأكيد إذن الهالك');
  END IF;

  -- ب. خصم هالك وفرز المحاصيل من الدفعات والمخزون
  IF v_notes ? 'fruit_waste_items' AND jsonb_typeof(v_notes->'fruit_waste_items') = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'fruit_waste_items')
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_waste_weight := COALESCE((v_el->>'waste_weight')::numeric, 0);
      v_sorted_weight := COALESCE((v_el->>'sorting_weight')::numeric, 0);
      v_unit_cost := COALESCE((v_el->>'unit_cost')::numeric, 0);
      v_waste_cost := COALESCE((v_el->>'waste_cost')::numeric, v_waste_weight * v_unit_cost);
      v_sorting_cost := COALESCE((v_el->>'sorting_cost')::numeric, v_sorted_weight * v_unit_cost);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      v_tot_crop_waste := v_tot_crop_waste + v_waste_cost;
      v_tot_sorting := v_tot_sorting + v_sorting_cost;

      IF v_batch_id IS NOT NULL AND (v_waste_weight + v_sorted_weight) > 0 THEN
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id FOR UPDATE;

        IF FOUND AND v_curr_rem >= (v_waste_weight + v_sorted_weight) THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - (v_waste_weight + v_sorted_weight)
          WHERE id = v_batch_id;

          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
          FROM public.station_product_batches
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

          UPDATE public.station_products
          SET quantity = v_sp_qty, updated_at = NOW()
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
        END IF;

        -- إدراج الفرز في جدول الفرز
        IF v_sorted_weight > 0 THEN
          INSERT INTO public.packing_order_sortings (
            packing_order_id, packing_waste_id, station_id,
            product_name, lot_number,
            weight_kg, remaining_weight_kg,
            cost_per_kg, total_cost, status, created_at
          ) VALUES (
            NULL, p_waste_id, v_station_id,
            v_pname, v_pcode,
            v_sorted_weight, v_sorted_weight,
            v_unit_cost, v_sorting_cost, 'pending', NOW()
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  v_tot_crop_raw := v_tot_crop_waste + v_tot_sorting;

  -- ج. خصم هالك مواد التعبئة من الدفعات والمخزون
  IF v_notes ? 'material_waste_items' AND jsonb_typeof(v_notes->'material_waste_items') = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'material_waste_items')
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_waste_qty := COALESCE((v_el->>'waste_qty')::numeric, (v_el->>'quantity')::numeric, 0);
      v_unit_cost := COALESCE((v_el->>'unit_cost')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';
      v_tot_mat_waste := v_tot_mat_waste + COALESCE((v_el->>'total_cost')::numeric, v_waste_qty * v_unit_cost);

      IF v_batch_id IS NOT NULL AND v_waste_qty > 0 THEN
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id FOR UPDATE;

        IF FOUND AND v_curr_rem >= v_waste_qty THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - v_waste_qty
          WHERE id = v_batch_id;

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
  END IF;

  -- د. حساب بنود التكلفة الإضافية
  FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'cost_items')
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE((v_el->>'total_egp')::numeric, (v_el->>'amount')::numeric, 0);
  END LOOP;

  v_grand_total := v_tot_crop_raw + v_tot_mat_waste + v_tot_cost_items;

  -- هـ. استخراج حسابات شجرة الحسابات الرسمية (COA)
  v_waste_crop_acc := public.resolve_gl_account('51102', v_company_id);
  v_waste_mat_acc  := public.resolve_gl_account('51104', v_company_id);
  v_sorting_acc    := public.resolve_gl_account('1032', v_company_id);
  v_cost_item_acc  := public.resolve_gl_account('51101', v_company_id);
  v_raw_inv_acc    := public.resolve_gl_account('1030', v_company_id);
  v_pkg_inv_acc    := public.resolve_gl_account('1040', v_company_id);

  -- و. إنشاء رأس القيد في journal_entries
  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status,
    is_auto_generated, source_type, source_id, company_id,
    created_by, created_at, updated_at
  ) VALUES (
    'PENDING',
    COALESCE(v_waste.date, CURRENT_DATE),
    'قيد إذن هالك تعبئة رقم ' || v_waste_num,
    'posted', true, 'packing_waste', p_waste_id::text, v_company_id,
    v_user_id, now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_waste', NULL, NULL);
  IF v_entry_num IS NULL OR v_entry_num = '' THEN
    v_entry_num := 'PW-JE-' || LPAD(v_je_id::text, 5, '0');
  END IF;
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- ══════════════════════════════════════════════════════════════════════════
  -- ز. إدراج أطراف القيد المحاسبي في account_ledger_entries
  -- ══════════════════════════════════════════════════════════════════════════

  -- 1. DR 51102: هالك المحاصيل
  IF v_tot_crop_waste > 0 AND v_waste_crop_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_waste_crop_acc, v_tot_crop_waste, 0, 'EGP', v_tot_crop_waste,
      'إثبات هالك محاصيل - إذن ' || v_waste_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_crop_waste;
  END IF;

  -- 2. DR 51104: هالك مواد التعبئة
  IF v_tot_mat_waste > 0 AND v_waste_mat_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_waste_mat_acc, v_tot_mat_waste, 0, 'EGP', v_tot_mat_waste,
      'إثبات هالك مواد تعبئة وتغليف - إذن ' || v_waste_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_mat_waste;
  END IF;

  -- 3. DR 1032: مخزون الفرز المستخرج
  IF v_tot_sorting > 0 AND v_sorting_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_sorting_acc, v_tot_sorting, 0, 'EGP', v_tot_sorting,
      'إثبات مخزون الفرز - إذن ' || v_waste_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_sorting;
  END IF;

  -- 4. DR 51101: بنود التكلفة الإضافية
  FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'cost_items')
  LOOP
    v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'amount')::numeric, 0);
    IF v_amt_egp > 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_cost_item_acc, v_amt_egp, 0, 'EGP', v_amt_egp,
        'مصروف إضافي: ' || COALESCE(v_el->>'name', 'بند تكلفة') || ' - إذن ' || v_waste_num, v_company_id
      );
      v_sum_debit := v_sum_debit + v_amt_egp;
    END IF;
  END LOOP;

  -- 5. CR 1030: مخزون المحاصيل (إجمالي المسحوب هالك + فرز)
  IF v_tot_crop_raw > 0 AND v_raw_inv_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_crop_raw, 'EGP', v_tot_crop_raw,
      'صرف محصول خام بالكامل (هالك + فرز) - إذن ' || v_waste_num, v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_crop_raw;
  END IF;

  -- 6. CR 1040: مخزون مواد التعبئة والتغليف (المسحوب كهالك)
  IF v_tot_mat_waste > 0 AND v_pkg_inv_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_mat_waste, 'EGP', v_tot_mat_waste,
      'صرف خامات ومواد تعبئة هالكة - إذن ' || v_waste_num, v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_mat_waste;
  END IF;

  -- 7. CR حسابات الموردين لبنود التكلفة
  FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'cost_items')
  LOOP
    v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'amount')::numeric, 0);
    IF v_amt_egp > 0 THEN
      v_credit_acc := NULL;
      v_supplier_id := NULL;
      v_supp_str := v_el->>'supplier_id';

      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        v_supplier_id := v_supp_str::uuid;
        SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
        IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
      END IF;

      IF v_credit_acc IS NULL THEN
        v_credit_acc := public.resolve_gl_account('2000', v_company_id);
      END IF;

      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, v_amt_egp, 'EGP', v_amt_egp,
        'استحقاق مورد عن بند: ' || COALESCE(v_el->>'name', '') || ' - إذن ' || v_waste_num, v_company_id
      );
      v_sum_credit := v_sum_credit + v_amt_egp;

      IF v_supplier_id IS NOT NULL THEN
        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', v_amt_egp, 'EGP',
          'credit', p_waste_id, 'packing_waste', p_waste_id::text,
          'استحقاق بند تكلفة إذن هالك: ' || COALESCE(v_el->>'name', '') || ' (إذن ' || v_waste_num || ')', now()
        );
        UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amt_egp WHERE id = v_supplier_id;
      END IF;
    END IF;
  END LOOP;

  -- ح. التحقق من اتزان القيد
  IF ROUND(v_sum_debit, 2) != ROUND(v_sum_credit, 2) THEN
    RAISE EXCEPTION 'فشل تأكيد إذن الهالك: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
  END IF;

  -- ط. تحديث سجل إذن الهالك
  UPDATE public.packing_wastes
  SET status = 'completed',
      journal_entry_id = v_je_id,
      total_crop_waste_cost = v_tot_crop_waste,
      total_sorting_cost = v_tot_sorting,
      total_material_waste_cost = v_tot_mat_waste,
      total_cost_items = v_tot_cost_items,
      total_waste_amount = v_grand_total,
      updated_at = now()
  WHERE id = p_waste_id;

  RETURN json_build_object(
    'success', true,
    'waste_id', p_waste_id,
    'journal_entry_id', v_je_id,
    'total_crop_waste', v_tot_crop_waste,
    'total_sorting', v_tot_sorting,
    'total_material_waste', v_tot_mat_waste,
    'total_cost_items', v_tot_cost_items,
    'grand_total', v_grand_total,
    'debit', v_sum_debit,
    'credit', v_sum_credit
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_waste(bigint) TO authenticated;
