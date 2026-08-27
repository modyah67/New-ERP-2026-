-- ============================================================================
-- Migration 323: Isolated Packing Waste and Sorting Accounts Integration
-- ============================================================================
-- 1. Chart of Accounts Additions:
--    - 51102: Produce Waste & Spoilage (هالك وفاقد المحاصيل) - Expense (5110)
--    - 51103: Produce Sorting & Grading (تسوية وفرز المحاصيل) - Expense / Contra (5110)
--    - 51104: Packaging Materials Waste (هالك وفاقد مواد التعبئة والتغليف) - Expense (5110)
--
-- 2. Packing Order Journal Entry Integration (rpc_confirm_packing_order):
--    - Produce Drawn: CR 1030 (Produce Inventory) only.
--    - Produce Waste: DR 51102 (Produce Waste & Spoilage).
--    - Produce Sorting: CR 51103 (Produce Sorting & Grading) as cost deduction/reclassification.
--    - Packaging Drawn: CR 1040 (Packaging Materials Inventory) only.
--    - Packaging Waste: DR 51104 (Packaging Materials Waste).
--    - Additional Costs: CR Supplier / Cash Accounts in EGP.
--    - Finished Goods: DR 1031 (Finished Goods Inventory).
--    - Waste Capitalization Absorption: CR 51102 / 51104 for absorbed waste inside 1031.
--    - 100% Balanced Journal Entry: Total Debits = Total Credits down to 0.00 delta.
--
-- 3. Packing Order Cancellation (rpc_cancel_packing_order):
--    - Symmetrical reversal of all accounts.
-- ============================================================================

BEGIN;

-- ── 1. Create and Ensure Dedicated Waste and Sorting Accounts ──
DO $$
DECLARE
  v_comp_id UUID;
BEGIN
  FOR v_comp_id IN (SELECT id FROM public.sys_companies WHERE deleted_at IS NULL)
  LOOP
    -- 51102: Produce Waste & Spoilage (هالك وفاقد المحاصيل)
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '51102' AND (company_id = v_comp_id OR company_id IS NULL)) THEN
      INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id
      ) VALUES (
        '51102', 'Produce Waste & Spoilage', 'هالك وفاقد المحاصيل', 'expense', true, true, true, 51102, v_comp_id
      ) ON CONFLICT (account_code) DO NOTHING;
    END IF;

    -- 51103: Produce Sorting & Grading (تسوية وفرز المحاصيل)
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '51103' AND (company_id = v_comp_id OR company_id IS NULL)) THEN
      INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id
      ) VALUES (
        '51103', 'Produce Sorting & Grading', 'تسوية وفرز المحاصيل', 'expense', true, true, true, 51103, v_comp_id
      ) ON CONFLICT (account_code) DO NOTHING;
    END IF;

    -- 51104: Packaging Materials Waste (هالك وفاقد مواد التعبئة والتغليف)
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '51104' AND (company_id = v_comp_id OR company_id IS NULL)) THEN
      INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id
      ) VALUES (
        '51104', 'Packaging Materials Waste', 'هالك وفاقد مواد التعبئة والتغليف', 'expense', true, true, true, 51104, v_comp_id
      ) ON CONFLICT (account_code) DO NOTHING;
    END IF;
  END LOOP;

  -- Global fallback if no companies exist
  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '51102') THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order)
    VALUES ('51102', 'Produce Waste & Spoilage', 'هالك وفاقد المحاصيل', 'expense', true, true, true, 51102)
    ON CONFLICT (account_code) DO NOTHING;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '51103') THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order)
    VALUES ('51103', 'Produce Sorting & Grading', 'تسوية وفرز المحاصيل', 'expense', true, true, true, 51103)
    ON CONFLICT (account_code) DO NOTHING;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '51104') THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order)
    VALUES ('51104', 'Packaging Materials Waste', 'هالك وفاقد مواد التعبئة والتغليف', 'expense', true, true, true, 51104)
    ON CONFLICT (account_code) DO NOTHING;
  END IF;
END $$;


-- ── 2. Update rpc_confirm_packing_order with Dedicated Accounts ──
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order           RECORD;
  v_notes           JSONB;
  v_station_id      INTEGER;
  v_alloc           JSONB;
  v_el              JSONB;
  v_batch_id        BIGINT;
  v_used_qty        NUMERIC;
  v_curr_rem        NUMERIC;
  v_pname           TEXT;
  v_pcode           TEXT;
  v_sp_qty          NUMERIC;
  v_company_id      UUID;
  
  -- GL Accounts
  v_finished_inv_acc BIGINT;
  v_raw_inv_acc     BIGINT;
  v_pkg_inv_acc     BIGINT;
  v_produce_waste_acc BIGINT;
  v_produce_sort_acc  BIGINT;
  v_pkg_waste_acc   BIGINT;
  v_credit_acc      BIGINT;
  
  v_je_id           BIGINT;
  v_entry_num       TEXT;
  v_sum_debit       NUMERIC := 0;
  v_sum_credit      NUMERIC := 0;

  v_line_ids        BIGINT[] := ARRAY[]::BIGINT[];
  v_line_raw        NUMERIC[] := ARRAY[]::NUMERIC[];
  v_line_net        NUMERIC[] := ARRAY[]::NUMERIC[];
  v_line_overhead   NUMERIC[] := ARRAY[]::NUMERIC[];
  v_bases           NUMERIC[] := ARRAY[]::NUMERIC[];
  v_shares          NUMERIC[] := ARRAY[]::NUMERIC[];
  v_n               INT := 0;
  v_lines           RECORD;
  r_cost            RECORD;
  v_amount          NUMERIC;
  v_method          TEXT;
  v_assigned        NUMERIC;
  v_part            NUMERIC;

  v_tot_raw_cost    NUMERIC := 0;
  v_tot_pkg_drawn   NUMERIC := 0;
  v_tot_pkg_waste   NUMERIC := 0;
  v_tot_waste_cost  NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_tot_cost_items  NUMERIC := 0;
  v_finished_goods_cost NUMERIC := 0;

  v_supplier_id     UUID;
  v_supp_str        TEXT;
  v_target_line_idx INTEGER;
  v_amt_egp         NUMERIC;
  v_max_cost_item_id BIGINT;
  v_current_balance NUMERIC;
  v_treasury_tx_id  BIGINT;
  v_bank_tx_id      BIGINT;
  v_tx_desc         TEXT;
  v_mat_waste_pct   NUMERIC := 0.0;
  v_pkg_line_count  INT := 0;
  v_order_num       TEXT;
  v_supp_leaf_acc   BIGINT;
BEGIN
  -- ── 0. Lock and validate order ──
  SELECT * INTO v_order
  FROM public.packing_orders
  WHERE id = p_packing_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status = 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة مؤكد بالفعل');
  END IF;

  IF v_order.status != 'draft' AND v_order.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'حالة أمر التعبئة لا تسمح بالتأكيد: ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id::integer;
  v_notes := CASE
    WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb
    ELSE '{}'::jsonb
  END;
  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);

  -- ── A. Fruit Inventory Deduction (Batches & Stock) ──
  IF v_notes ? 'fruit_allocation' THEN
    v_alloc := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_alloc) = 'object' THEN
      v_alloc := jsonb_build_array(v_alloc);
    END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'دفعة المحصول رقم % غير موجودة في المحطة', v_batch_id;
        END IF;

        IF v_curr_rem < v_used_qty THEN
          RAISE EXCEPTION 'الكمية المتبقية في دفعة المحصول (%) أقل من المطلوب سحبه (%)', v_curr_rem, v_used_qty;
        END IF;

        UPDATE public.station_product_batches
        SET remaining_quantity = remaining_quantity - v_used_qty
        WHERE id = v_batch_id;

        -- Update station_products total
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
  END IF;

  -- ── B. Material Inventory Deduction (Batches & Stock) ──
  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials')
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
            -- Deduct across batches FIFO
            DECLARE
              v_rem_needed NUMERIC := v_used_qty;
              r_b RECORD;
              v_take NUMERIC;
            BEGIN
              FOR r_b IN (
                SELECT id, remaining_quantity
                FROM public.station_product_batches
                WHERE station_id = v_station_id
                  AND (product_name = v_pname OR product_code = v_pcode)
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
            END;
          END IF;
        ELSE
          -- Deduct across batches FIFO
          DECLARE
            v_rem_needed NUMERIC := v_used_qty;
            r_b RECORD;
            v_take NUMERIC;
          BEGIN
            FOR r_b IN (
              SELECT id, remaining_quantity
              FROM public.station_product_batches
              WHERE station_id = v_station_id
                AND (product_name = v_pname OR product_code = v_pcode)
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
          END;
        END IF;

        -- Update station_products total
        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);

        UPDATE public.station_products
        SET quantity = v_sp_qty, updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);
      END IF;
    END LOOP;

    -- Sync raw_materials and stock_batches
    DECLARE
      r_mat RECORD;
      v_mat_id UUID;
      r_sb RECORD;
      v_rem_to_deduct NUMERIC;
      v_take_qty NUMERIC;
    BEGIN
      FOR r_mat IN (
        SELECT
          elem->>'product_code' AS pcode,
          elem->>'product_name' AS pname,
          SUM(COALESCE((elem->>'used_qty')::numeric, (elem->>'quantity')::numeric, 0)) AS total_used
        FROM jsonb_array_elements(v_notes->'materials') AS elem
        GROUP BY elem->>'product_code', elem->>'product_name'
      ) LOOP
        v_mat_id := NULL;
        IF r_mat.pcode IS NOT NULL AND r_mat.pcode != '' THEN
          SELECT id INTO v_mat_id FROM public.raw_materials
          WHERE code = r_mat.pcode
            AND (name = r_mat.pname OR name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR name || ' (مادة تعبئة)' = r_mat.pname)
          LIMIT 1;
        END IF;
        IF v_mat_id IS NULL AND r_mat.pcode IS NOT NULL AND r_mat.pcode != '' THEN
          SELECT id INTO v_mat_id FROM public.raw_materials WHERE code = r_mat.pcode LIMIT 1;
        END IF;
        IF v_mat_id IS NULL THEN
          SELECT id INTO v_mat_id FROM public.raw_materials
          WHERE name = r_mat.pname OR name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR name || ' (مادة تعبئة)' = r_mat.pname
          LIMIT 1;
        END IF;

        IF v_mat_id IS NOT NULL THEN
          UPDATE public.raw_materials
          SET quantity = (
            SELECT COALESCE(SUM(remaining_quantity), 0)
            FROM public.station_product_batches
            WHERE (product_code = r_mat.pcode OR product_name = r_mat.pname OR product_name = REPLACE(r_mat.pname, ' (مادة تعبئة)', '') OR product_name = r_mat.pname || ' (مادة تعبئة)')
              AND source_type != 'lot_receipt'
          ),
          updated_at = NOW()
          WHERE id = v_mat_id;

          v_rem_to_deduct := r_mat.total_used;
          FOR r_sb IN (
            SELECT * FROM public.stock_batches
            WHERE product_id = v_mat_id
              AND remaining_quantity > 0
              AND status = 'active'
            ORDER BY created_at ASC
            FOR UPDATE
          ) LOOP
            IF v_rem_to_deduct <= 0 THEN EXIT; END IF;
            v_take_qty := LEAST(r_sb.remaining_quantity, v_rem_to_deduct);
            UPDATE public.stock_batches
            SET remaining_quantity = remaining_quantity - v_take_qty,
                status = CASE WHEN remaining_quantity - v_take_qty <= 0 THEN 'depleted' ELSE 'active' END,
                updated_at = NOW()
            WHERE id = r_sb.id;
            v_rem_to_deduct := v_rem_to_deduct - v_take_qty;
          END LOOP;
        END IF;
      END LOOP;
    END;
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
          currency_snapshot
        ) VALUES (
          p_packing_order_id,
          v_el->>'name',
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

  -- ── D. Prepare for line allocation ──
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

  -- ── E. Allocate cost items across lines ──
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

  -- ── F. Calculate Cost Components ──
  -- 1. Produce Gross Drawn Cost (Actual produce withdrawn from 1030)
  v_tot_raw_cost := COALESCE(v_order.fruit_cost_base, 0);
  IF v_tot_raw_cost = 0 THEN
    IF v_notes ? 'fruit_allocation' THEN
      DECLARE
        v_f_elem JSONB;
        v_f_arr JSONB := v_notes->'fruit_allocation';
      BEGIN
        IF jsonb_typeof(v_f_arr) = 'object' THEN v_f_arr := jsonb_build_array(v_f_arr); END IF;
        FOR v_f_elem IN SELECT * FROM jsonb_array_elements(v_f_arr) LOOP
          v_tot_raw_cost := v_tot_raw_cost + (COALESCE((v_f_elem->>'quantity')::numeric, 0) * COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0));
        END LOOP;
      END;
    END IF;
  END IF;
  IF v_tot_raw_cost = 0 THEN
    v_tot_raw_cost := COALESCE(v_order.fruit_cost_allocated, 0);
  END IF;

  -- 2. Produce Waste Cost
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 3. Sorting Cost
  v_tot_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_sortings WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 4. Packaging Materials Cost (Pure drawn cost from warehouse)
  v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
  v_tot_pkg_drawn := 0;

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    DECLARE
      v_m_el JSONB;
    BEGIN
      FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials') LOOP
        v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE((v_m_el->>'total')::numeric, (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) * COALESCE((v_m_el->>'unit_cost')::numeric, 0)));
      END LOOP;
    END;
  END IF;

  IF v_tot_pkg_drawn = 0 THEN
    v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    IF v_mat_waste_pct > 0 THEN
      v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 2);
    END IF;
  END IF;

  -- 5. Packaging Waste Cost
  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 2);

  -- 6. Additional Cost Items
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 7. Finished Goods Cost
  -- Formula: Finished Goods = (Produce Cost + Produce Waste - Sorting) + (Packaging Cost + Packaging Waste) + Additional Costs
  v_finished_goods_cost := COALESCE(v_order.total_packing_cost, ((v_tot_raw_cost + v_tot_waste_cost - v_tot_sorting_cost) + (v_tot_pkg_drawn + v_tot_pkg_waste) + v_tot_cost_items));

  -- ── G. Process Payments for Treasury/Bank ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    IF r_cost.payment_source_id IS NOT NULL AND r_cost.payment_source_type IN ('treasury', 'bank') THEN
      v_tx_desc := 'مصروف أمر تعبئة: ' || COALESCE(r_cost.name, 'بند تكلفة');
      v_supplier_id := NULL;
      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
        END IF;
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

  -- ── H. Resolve GL Accounts ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  -- 1031 Finished Goods
  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1; END IF;

  -- 1030 Produce Inventory
  SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;

  -- 1040 Packaging Inventory
  SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

  -- 51102 Produce Waste
  SELECT id INTO v_produce_waste_acc FROM accounts WHERE account_code = '51102' LIMIT 1;
  IF v_produce_waste_acc IS NULL THEN SELECT id INTO v_produce_waste_acc FROM accounts WHERE account_code = '6120' LIMIT 1; END IF;
  IF v_produce_waste_acc IS NULL THEN SELECT id INTO v_produce_waste_acc FROM accounts WHERE account_code = '51101' LIMIT 1; END IF;

  -- 51103 Produce Sorting
  SELECT id INTO v_produce_sort_acc FROM accounts WHERE account_code = '51103' LIMIT 1;
  IF v_produce_sort_acc IS NULL THEN SELECT id INTO v_produce_sort_acc FROM accounts WHERE account_code = '6120' LIMIT 1; END IF;
  IF v_produce_sort_acc IS NULL THEN SELECT id INTO v_produce_sort_acc FROM accounts WHERE account_code = '51101' LIMIT 1; END IF;

  -- 51104 Packaging Waste
  SELECT id INTO v_pkg_waste_acc FROM accounts WHERE account_code = '51104' LIMIT 1;
  IF v_pkg_waste_acc IS NULL THEN SELECT id INTO v_pkg_waste_acc FROM accounts WHERE account_code = '6120' LIMIT 1; END IF;
  IF v_pkg_waste_acc IS NULL THEN SELECT id INTO v_pkg_waste_acc FROM accounts WHERE account_code = '51101' LIMIT 1; END IF;

  IF v_finished_inv_acc IS NULL OR v_raw_inv_acc IS NULL THEN
    RAISE EXCEPTION 'حسابات المخزون (1030/1031) غير موجودة في شجرة الحسابات';
  END IF;

  -- Delete any prior journal entry
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
    'قيد أمر تعبئة رقم ' || v_order_num,
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    auth.uid(), now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- ── 1. DR Finished Goods Inventory (1031) - 100% in EGP ──
  IF v_finished_goods_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, 'EGP', v_finished_goods_cost,
      'مخزون الإنتاج التام - أمر تعبئة ' || v_order_num || ' (صافي ' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_finished_goods_cost;
  END IF;

  -- ── 2. DR Produce Waste & Spoilage (51102) ──
  IF v_tot_waste_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_produce_waste_acc, v_tot_waste_cost, 0, 'EGP', v_tot_waste_cost,
      'هالك وفاقد المحاصيل - أمر تعبئة ' || v_order_num || ' [Produce Waste: ' || v_tot_waste_cost || ' EGP]',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_waste_cost;
  END IF;

  -- ── 3. DR Packaging Materials Waste (51104) ──
  IF v_tot_pkg_waste > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_waste_acc, v_tot_pkg_waste, 0, 'EGP', v_tot_pkg_waste,
      'هالك وفاقد مواد التعبئة والتغليف - أمر تعبئة ' || v_order_num || ' [Packaging Waste: ' || v_tot_pkg_waste || ' EGP]',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_pkg_waste;
  END IF;

  -- ── 4. CR Produce Inventory (1030) - Exact Produce Drawn Only in EGP ──
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,
      'تحويل محاصيل خام - أمر تعبئة ' || v_order_num || ' [Produce Cost Drawn: ' || v_tot_raw_cost || ' EGP]',
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- ── 5. CR Packaging Materials Inventory (1040) - Exact Packaging Drawn Only in EGP ──
  v_pkg_line_count := 0;
  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    DECLARE
      v_m_el JSONB;
      v_m_base NUMERIC;
    BEGIN
      FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials') LOOP
        v_m_base := COALESCE((v_m_el->>'total')::numeric, (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) * COALESCE((v_m_el->>'unit_cost')::numeric, 0)));
        IF v_m_base > 0 THEN
          v_pkg_line_count := v_pkg_line_count + 1;
          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
          ) VALUES (
            v_je_id, v_pkg_inv_acc, 0, v_m_base, 'EGP', v_m_base,
            'سحب مواد تعبئة - ' || COALESCE(v_m_el->>'product_name', 'مادة تعبئة') || ' (أمر ' || v_order_num || ') [Packaging Drawn: ' || v_m_base || ' EGP]',
            v_company_id
          );
          v_sum_credit := v_sum_credit + v_m_base;
        END IF;
      END LOOP;
    END;
  END IF;

  IF v_pkg_line_count = 0 AND v_tot_pkg_drawn > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_drawn, 'EGP', v_tot_pkg_drawn,
      'سحب مواد تعبئة وتغليف - أمر تعبئة ' || v_order_num || ' [Packaging Drawn: ' || v_tot_pkg_drawn || ' EGP]',
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_drawn;
  END IF;

  -- ── 6. CR Produce Sorting & Grading (51103) - Sorting Reduction ──
  IF v_tot_sorting_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_produce_sort_acc, 0, v_tot_sorting_cost, 'EGP', v_tot_sorting_cost,
      'تسوية وفرز المحاصيل (تخفيض التكلفة) - أمر تعبئة ' || v_order_num || ' [Produce Sorting: ' || v_tot_sorting_cost || ' EGP]',
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_sorting_cost;
  END IF;

  -- ── 7. CR Additional Costs (Suppliers / Cash Accounts) in EGP ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;
    v_supplier_id := NULL;

    IF r_cost.payment_source_type = 'treasury' AND r_cost.payment_source_id IS NOT NULL THEN
      SELECT tb.account_id INTO v_credit_acc FROM public.treasury_balances tb WHERE tb.treasury_id = r_cost.payment_source_id AND tb.currency = r_cost.original_currency LIMIT 1;
      IF v_credit_acc IS NULL THEN v_credit_acc := public.resolve_treasury_account(r_cost.payment_source_id, r_cost.original_currency, v_company_id); END IF;
    ELSIF r_cost.payment_source_type = 'bank' AND r_cost.payment_source_id IS NOT NULL THEN
      SELECT ba.account_id INTO v_credit_acc FROM public.bank_accounts ba WHERE ba.id = r_cost.payment_source_id LIMIT 1;
    END IF;

    IF v_credit_acc IS NULL THEN
      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
        END IF;
      END IF;
    END IF;

    IF v_credit_acc IS NULL THEN
      SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' AND company_id = v_company_id LIMIT 1;
      IF v_credit_acc IS NULL THEN SELECT id INTO v_credit_acc FROM accounts WHERE account_code = '2000' LIMIT 1; END IF;
    END IF;

    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
      'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية') || ' [Additional Supplier Cost: ' || r_cost.base_amount || ' EGP]',
      v_company_id
    );
    v_sum_credit := v_sum_credit + r_cost.base_amount;

    -- Subledger entry in supplier's original currency
    IF v_supplier_id IS NOT NULL THEN
      INSERT INTO public.ledger_entries (
        entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
      ) VALUES (
        v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
        'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
        'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')',
        now()
      );
      UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
    END IF;
  END LOOP;

  -- ── 8. CR Waste Capitalization Absorption to balance entry ──
  -- When Produce Waste and Packaging Waste are absorbed into Finished Goods (1031),
  -- the absorption credit ensures the entry is 100% balanced without double counting.
  DECLARE
    v_delta NUMERIC := v_sum_debit - v_sum_credit;
  BEGIN
    IF v_delta > 0 THEN
      -- Offsetting credit for absorbed waste (Produce Waste + Packaging Waste)
      IF v_tot_waste_cost > 0 AND v_tot_pkg_waste > 0 AND v_delta = (v_tot_waste_cost + v_tot_pkg_waste) THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_produce_waste_acc, 0, v_tot_waste_cost, 'EGP', v_tot_waste_cost,
          'استيعاب هالك المحاصيل داخل تكلفة الإنتاج التام - أمر ' || v_order_num || ' [Produce Waste Absorbed: ' || v_tot_waste_cost || ' EGP]',
          v_company_id
        );
        v_sum_credit := v_sum_credit + v_tot_waste_cost;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_pkg_waste_acc, 0, v_tot_pkg_waste, 'EGP', v_tot_pkg_waste,
          'استيعاب هالك مواد التعبئة داخل تكلفة الإنتاج التام - أمر ' || v_order_num || ' [Packaging Waste Absorbed: ' || v_tot_pkg_waste || ' EGP]',
          v_company_id
        );
        v_sum_credit := v_sum_credit + v_tot_pkg_waste;
      ELSE
        -- Single clean absorption line on produce waste or pkg waste account
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, CASE WHEN v_tot_pkg_waste > 0 THEN v_pkg_waste_acc ELSE v_produce_waste_acc END,
          0, v_delta, 'EGP', v_delta,
          'استيعاب فاقد التشغيل وتكلفة التعبئة داخل الإنتاج التام - أمر ' || v_order_num,
          v_company_id
        );
        v_sum_credit := v_sum_credit + v_delta;
      END IF;
    ELSIF v_delta < 0 THEN
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_produce_sort_acc, ABS(v_delta), 0, 'EGP', ABS(v_delta),
        'تسوية تكلفة أمر تعبئة - أمر ' || v_order_num,
        v_company_id
      );
      v_sum_debit := v_sum_debit + ABS(v_delta);
    END IF;
  END;

  -- ── I. Update packing order line costs ──
  FOR v_i IN 1..v_n LOOP
    UPDATE public.packing_order_lines
    SET overhead_cost = v_line_overhead[v_i],
        final_cost = v_line_raw[v_i] + v_line_overhead[v_i]
    WHERE id = v_line_ids[v_i];
  END LOOP;

  -- ── J. Mark order completed ──
  UPDATE public.packing_orders
  SET status = 'completed',
      journal_entry_id = v_je_id,
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'journal_entry_id', v_je_id,
    'finished_goods_cost', v_finished_goods_cost,
    'total_raw_cost', v_tot_raw_cost,
    'total_packaging_drawn', v_tot_pkg_drawn,
    'total_packaging_waste', v_tot_pkg_waste,
    'total_waste_cost', v_tot_waste_cost,
    'total_sorting_cost', v_tot_sorting_cost,
    'total_overhead', v_tot_cost_items,
    'lines_count', v_n,
    'debit', v_sum_debit,
    'credit', v_sum_credit
  );
END;
$$;


-- ── 3. Update rpc_cancel_packing_order with Symmetrical Reversal ──
CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_orig_je RECORD;
  v_rev_je_id BIGINT;
  v_entry_num TEXT;
  v_company_id UUID;
  v_line RECORD;
  v_notes JSONB;
  v_el JSONB;
  v_batch_id BIGINT;
  v_used_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_station_id INTEGER;
  v_sp_qty NUMERIC;
  v_sunk_exp_acc BIGINT;
  v_order_num TEXT;
BEGIN
  SELECT * INTO v_order
  FROM public.packing_orders
  WHERE id = p_packing_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status = 'cancelled' THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة ملغي بالفعل');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة غير مؤكد');
  END IF;

  v_station_id := v_order.station_id::integer;
  v_notes := CASE
    WHEN v_order.notes IS NOT NULL AND v_order.notes != '' THEN v_order.notes::jsonb
    ELSE '{}'::jsonb
  END;
  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);

  -- ── 1. Restore Fruit Batches ──
  IF v_notes ? 'fruit_allocation' THEN
    DECLARE
      v_alloc JSONB := v_notes->'fruit_allocation';
    BEGIN
      IF jsonb_typeof(v_alloc) = 'object' THEN v_alloc := jsonb_build_array(v_alloc); END IF;
      FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)
      LOOP
        v_batch_id := (v_el->>'batch_id')::bigint;
        v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);
        v_pname := v_el->>'product_name';
        v_pcode := v_el->>'product_code';

        IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity + v_used_qty
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
      END LOOP;
    END;
  END IF;

  -- ── 2. Restore Material Batches ──
  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials')
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'used_qty')::numeric, (v_el->>'quantity')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
        UPDATE public.station_product_batches
        SET remaining_quantity = remaining_quantity + v_used_qty
        WHERE id = v_batch_id;

        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);

        UPDATE public.station_products
        SET quantity = v_sp_qty, updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);
      END IF;
    END LOOP;
  END IF;

  -- ── 3. Post Symmetrical Reversal Journal Entry ──
  IF v_order.journal_entry_id IS NOT NULL THEN
    SELECT * INTO v_orig_je FROM public.journal_entries WHERE id = v_order.journal_entry_id;
    v_company_id := v_orig_je.company_id;

    SELECT id INTO v_sunk_exp_acc FROM public.accounts WHERE account_code = '51101' LIMIT 1;
    IF v_sunk_exp_acc IS NULL THEN SELECT id INTO v_sunk_exp_acc FROM public.accounts WHERE account_code = '6000' LIMIT 1; END IF;

    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      CURRENT_DATE,
      'قيد إلغاء أمر تعبئة رقم ' || v_order_num,
      'posted', true, 'packing_order_cancellation', p_packing_order_id::text, v_company_id,
      auth.uid(), now(), now()
    ) RETURNING id INTO v_rev_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_rev_je_id;

    -- Reverse every line exactly (swapping debit and credit)
    FOR v_line IN
      SELECT ale.*, a.account_code
      FROM public.account_ledger_entries ale
      JOIN public.accounts a ON a.id = ale.account_id
      WHERE ale.journal_entry_id = v_order.journal_entry_id
    LOOP
      IF v_line.account_code LIKE '2000%' THEN
        -- Supplier was credited. On cancellation, supplier keeps credit (services were rendered).
        -- We debit sunk cancellation expense instead of deducting supplier.
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_rev_je_id, v_sunk_exp_acc, v_line.credit, 0, v_line.currency, v_line.amount_in_base_currency,
          'مصروف خدمات أمر تعبئة ملغي - ' || COALESCE(v_line.description, ''),
          v_company_id
        );
      ELSE
        -- Standard symmetrical swap
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_rev_je_id, v_line.account_id, v_line.credit, v_line.debit, v_line.currency, v_line.amount_in_base_currency,
          'عكس: ' || COALESCE(v_line.description, ''),
          v_company_id
        );
      END IF;
    END LOOP;

    UPDATE public.packing_orders
    SET status = 'cancelled',
        reversal_journal_entry_id = v_rev_je_id,
        updated_at = NOW()
    WHERE id = p_packing_order_id;
  ELSE
    UPDATE public.packing_orders
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = p_packing_order_id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'original_journal_entry_id', v_order.journal_entry_id,
    'reversal_journal_entry_id', v_rev_je_id
  );
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
