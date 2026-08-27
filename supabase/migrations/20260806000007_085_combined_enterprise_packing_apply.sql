-- ============================================================================
-- 085_combined_enterprise_packing_apply.sql
--
-- COMBINED migration: applies 083 + 084 in one transaction.
-- Run this in Supabase SQL Editor to activate the Enterprise Multi-Product
-- Packing Order system.
--
-- This file is idempotent — safe to re-run if any step already succeeded.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART A: From migration 083
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Ensure journal_entry_id on packing_orders & make lot_id nullable
ALTER TABLE public.packing_orders
ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT
REFERENCES public.journal_entries(id) ON DELETE SET NULL;

ALTER TABLE public.packing_orders
ALTER COLUMN lot_id DROP NOT NULL;

-- 2. Register document type for packing orders
INSERT INTO public.sys_document_types (code, name, prefix)
VALUES ('packing_order', 'أمر تعبئة', 'PK')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    prefix = EXCLUDED.prefix;

-- 3. Create packing_order_lines table (IF NOT EXISTS is safe)
CREATE TABLE IF NOT EXISTS public.packing_order_lines (
    id BIGSERIAL PRIMARY KEY,
    packing_order_id BIGINT NOT NULL REFERENCES public.packing_orders(id) ON DELETE CASCADE,
    product_id INTEGER,
    fruit_type_id INTEGER,
    product_name TEXT,
    grade TEXT DEFAULT 'A',
    source_lot_id BIGINT REFERENCES public.lot_receipts(id) ON DELETE SET NULL,
    batch_id INTEGER REFERENCES public.station_product_batches(id) ON DELETE SET NULL,
    quantity NUMERIC(15,3) DEFAULT 0,
    carton_count INTEGER DEFAULT 0 NOT NULL,
    net_weight_per_carton NUMERIC(10,3) DEFAULT 0 NOT NULL,
    gross_weight_per_carton NUMERIC(10,3) DEFAULT 0 NOT NULL,
    total_net_weight NUMERIC(15,3) GENERATED ALWAYS AS ((carton_count::numeric * net_weight_per_carton)) STORED,
    total_gross_weight NUMERIC(15,3) GENERATED ALWAYS AS ((carton_count::numeric * gross_weight_per_carton)) STORED,
    unit_cost NUMERIC(15,4) DEFAULT 0,
    raw_material_cost NUMERIC(15,2) DEFAULT 0,
    expected_loss_percent NUMERIC(5,2) DEFAULT 0,
    waste_weight_kg NUMERIC(15,3) DEFAULT 0,
    waste_cost NUMERIC(15,2) DEFAULT 0,
    sorted_weight_kg NUMERIC(15,3) DEFAULT 0,
    sorting_cost NUMERIC(15,2) DEFAULT 0,
    specific_packaging_cost NUMERIC(15,2) DEFAULT 0,
    allocated_shared_packaging NUMERIC(15,2) DEFAULT 0,
    allocated_cost_items NUMERIC(15,2) DEFAULT 0,
    final_cost NUMERIC(15,2) DEFAULT 0,
    final_unit_cost NUMERIC(15,4) DEFAULT 0,
    sold_cartons INTEGER DEFAULT 0 NOT NULL,
    notes JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_packing_order_lines_order_id ON public.packing_order_lines(packing_order_id);
CREATE INDEX IF NOT EXISTS idx_packing_order_lines_lot_id ON public.packing_order_lines(source_lot_id);
CREATE INDEX IF NOT EXISTS idx_packing_order_lines_batch_id ON public.packing_order_lines(batch_id);

-- Enable RLS
ALTER TABLE public.packing_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all for authenticated on packing_order_lines" ON public.packing_order_lines;
CREATE POLICY "Allow all for authenticated on packing_order_lines"
ON public.packing_order_lines
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- 4. Extend sorting and cost items columns
ALTER TABLE public.packing_order_sortings
ADD COLUMN IF NOT EXISTS packing_order_line_id BIGINT
REFERENCES public.packing_order_lines(id) ON DELETE SET NULL;

ALTER TABLE public.packing_order_cost_items
ADD COLUMN IF NOT EXISTS allocation_method TEXT DEFAULT 'BY_NET_WEIGHT';

ALTER TABLE public.packing_order_cost_items
ADD COLUMN IF NOT EXISTS target_line_id BIGINT
REFERENCES public.packing_order_lines(id) ON DELETE SET NULL;

-- 5. Backfill historical packing_orders into packing_order_lines
--    (only for orders that don't already have lines)
INSERT INTO public.packing_order_lines (
    packing_order_id,
    product_id,
    fruit_type_id,
    product_name,
    grade,
    source_lot_id,
    batch_id,
    quantity,
    carton_count,
    net_weight_per_carton,
    gross_weight_per_carton,
    unit_cost,
    raw_material_cost,
    waste_weight_kg,
    waste_cost,
    sorted_weight_kg,
    sorting_cost,
    specific_packaging_cost,
    allocated_shared_packaging,
    allocated_cost_items,
    final_cost,
    final_unit_cost,
    sold_cartons,
    notes,
    created_at,
    updated_at
)
SELECT
    po.id AS packing_order_id,
    NULL AS product_id,
    po.fruit_type_id,
    COALESCE(po.product_name, lr.product_name, 'محصول'),
    COALESCE(po.grade, 'A'),
    po.lot_id AS source_lot_id,
    po.batch_id,
    COALESCE(
        (po.notes::jsonb->>'partial_weight_kg')::numeric,
        lr.gross_weight_kg,
        (po.carton_count::numeric * po.net_weight_per_carton)
    ) AS quantity,
    po.carton_count,
    po.net_weight_per_carton,
    po.gross_weight_per_carton,
    CASE
        WHEN COALESCE(lr.gross_weight_kg, 0) > 0 THEN (COALESCE(po.fruit_cost_allocated, po.fruit_cost_base, 0) / lr.gross_weight_kg)
        ELSE 0
    END AS unit_cost,
    COALESCE(po.fruit_cost_allocated, po.fruit_cost_base, 0) AS raw_material_cost,
    COALESCE((po.notes::jsonb->>'waste_weight_kg')::numeric, 0) AS waste_weight_kg,
    COALESCE((po.notes::jsonb->>'waste_cost')::numeric, 0) AS waste_cost,
    COALESCE((po.notes::jsonb->>'sorted_weight_kg')::numeric, 0) AS sorted_weight_kg,
    COALESCE((po.notes::jsonb->>'sorting_cost')::numeric, 0) AS sorting_cost,
    COALESCE(po.actual_material_cost, po.material_cost_base, 0) AS specific_packaging_cost,
    0 AS allocated_shared_packaging,
    COALESCE(po.other_cost_base, 0) AS allocated_cost_items,
    COALESCE(po.total_packing_cost, 0) AS final_cost,
    COALESCE(po.packing_cost_per_carton, 0) AS final_unit_cost,
    COALESCE(po.sold_cartons, 0) AS sold_cartons,
    po.notes::jsonb AS notes,
    po.created_at,
    po.updated_at
FROM public.packing_orders po
LEFT JOIN public.lot_receipts lr ON lr.id = po.lot_id
WHERE NOT EXISTS (
    SELECT 1 FROM public.packing_order_lines pol WHERE pol.packing_order_id = po.id
);

-- Backfill sortings line links where possible
UPDATE public.packing_order_sortings pos
SET packing_order_line_id = (
    SELECT pol.id FROM public.packing_order_lines pol
    WHERE pol.packing_order_id = pos.packing_order_id
    LIMIT 1
)
WHERE pos.packing_order_line_id IS NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART B: From migration 084
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Finished Goods account (1031)
DO $$
DECLARE
  v_company_id UUID;
  v_parent_id BIGINT;
BEGIN
  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '1030'
  ORDER BY id
  LIMIT 1;

  IF NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '1031') THEN
    INSERT INTO accounts (
      account_code, name, account_name, account_type,
      parent_id, company_id, level, is_leaf, allow_posting, is_active
    ) VALUES (
      '1031',
      'Finished Goods Inventory',
      'مخزون الإنتاج التام',
      'asset',
      v_parent_id,
      v_company_id,
      2,
      true,
      true,
      true
    );
  END IF;
END $$;

-- 2. Reversal JE link on packing_orders
ALTER TABLE public.packing_orders
ADD COLUMN IF NOT EXISTS reversal_journal_entry_id BIGINT
REFERENCES public.journal_entries(id) ON DELETE SET NULL;

-- ============================================================================
-- Helper: allocate amount across lines by method
-- ============================================================================
CREATE OR REPLACE FUNCTION public._packing_allocate_shares(
  p_method TEXT,
  p_bases NUMERIC[]
)
RETURNS NUMERIC[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_n INT;
  v_total NUMERIC := 0;
  v_shares NUMERIC[];
  i INT;
BEGIN
  v_n := COALESCE(array_length(p_bases, 1), 0);
  IF v_n = 0 THEN
    RETURN ARRAY[]::NUMERIC[];
  END IF;

  FOR i IN 1..v_n LOOP
    v_total := v_total + COALESCE(p_bases[i], 0);
  END LOOP;

  IF v_total <= 0 THEN
    v_shares := ARRAY[]::NUMERIC[];
    FOR i IN 1..v_n LOOP
      v_shares := v_shares || ARRAY[ROUND((1.0 / v_n)::numeric, 8)];
    END LOOP;
    RETURN v_shares;
  END IF;

  v_shares := ARRAY[]::NUMERIC[];
  FOR i IN 1..v_n LOOP
    v_shares := v_shares || ARRAY[ROUND((COALESCE(p_bases[i], 0) / v_total)::numeric, 8)];
  END LOOP;
  RETURN v_shares;
END;
$$;

-- ============================================================================
-- 3. Enterprise rpc_confirm_packing_order (final version from 084)
-- ============================================================================
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
  v_allocations         JSONB := '[]'::jsonb;
  v_el                  JSONB;
  v_rate                NUMERIC;
  v_amt_egp             NUMERIC;
  v_amt_foreign         NUMERIC;
  v_curr                TEXT;
  r_cost                RECORD;
  r_line                RECORD;
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
  v_credit_acc          BIGINT;
  v_tot_raw_cost        NUMERIC := 0;
  v_tot_pkg_cost        NUMERIC := 0;
  v_tot_cost_items      NUMERIC := 0;
  v_tot_final_cost      NUMERIC := 0;
  v_lines_count         INTEGER := 0;
  v_line_ids            BIGINT[];
  v_line_raw            NUMERIC[];
  v_line_qty            NUMERIC[];
  v_line_net            NUMERIC[];
  v_line_gross          NUMERIC[];
  v_line_cartons        NUMERIC[];
  v_line_specific       NUMERIC[];
  v_line_shared         NUMERIC[];
  v_line_overhead       NUMERIC[];
  v_bases               NUMERIC[];
  v_shares              NUMERIC[];
  v_n                   INT;
  v_i                   INT;
  v_apply_to            TEXT;
  v_mat_cost            NUMERIC;
  v_shared_pkg_total    NUMERIC := 0;
  v_method              TEXT;
  v_amount              NUMERIC;
  v_part                NUMERIC;
  v_assigned            NUMERIC;
  v_target_idx          INT;
  v_sum_debit           NUMERIC := 0;
  v_sum_credit          NUMERIC := 0;
  v_lot_number          TEXT;
  i                     INT;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status NOT IN ('draft', 'pending') THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تأكيد أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- A. Sync cost items from notes
  IF v_notes ? 'cost_items' THEN
    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_rate := COALESCE(NULLIF((v_el->>'exchange_rate')::numeric, 0), 1.0);
      v_curr := COALESCE(NULLIF(v_el->>'supplier_currency', ''), 'EGP');

      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);
      IF v_amt_egp = 0 THEN
        v_amt_egp := COALESCE((v_el->>'total')::numeric, 0);
      END IF;

      IF v_curr = 'EGP' THEN
        v_amt_foreign := v_amt_egp;
      ELSIF v_rate > 0 THEN
        v_amt_foreign := ROUND(v_amt_egp / v_rate, 2);
      ELSE
        v_amt_foreign := v_amt_egp;
      END IF;

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
        v_curr,
        v_amt_foreign,
        v_rate,
        v_amt_egp,
        v_el,
        v_el->>'payment_source_type',
        NULLIF(v_el->>'payment_source_id', '')::bigint,
        COALESCE(v_el->>'allocation_method', 'BY_NET_WEIGHT'),
        NULLIF(v_el->>'target_line_id', '')::bigint
      );
    END LOOP;
  END IF;

  -- B. Load lines into arrays for allocation
  SELECT
    COALESCE(array_agg(pol.id ORDER BY pol.id), ARRAY[]::BIGINT[]),
    COALESCE(array_agg(COALESCE(pol.raw_material_cost, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
    COALESCE(array_agg(COALESCE(pol.quantity, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
    COALESCE(array_agg(COALESCE(pol.total_net_weight, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
    COALESCE(array_agg(COALESCE(pol.total_gross_weight, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
    COALESCE(array_agg(COALESCE(pol.carton_count, 0)::numeric ORDER BY pol.id), ARRAY[]::NUMERIC[])
  INTO v_line_ids, v_line_raw, v_line_qty, v_line_net, v_line_gross, v_line_cartons
  FROM public.packing_order_lines pol
  WHERE pol.packing_order_id = p_packing_order_id;

  v_n := COALESCE(array_length(v_line_ids, 1), 0);

  IF v_n = 0 THEN
    -- Legacy single-product fallback: ensure one line exists
    INSERT INTO public.packing_order_lines (
      packing_order_id, product_name, grade, source_lot_id, batch_id,
      quantity, carton_count, net_weight_per_carton, gross_weight_per_carton,
      unit_cost, raw_material_cost, final_cost, final_unit_cost
    ) VALUES (
      p_packing_order_id,
      COALESCE(v_order.product_name, ''),
      COALESCE(v_order.grade, 'A'),
      v_order.lot_id,
      v_order.batch_id,
      COALESCE(v_order.total_net_weight, 0),
      COALESCE(v_order.carton_count, 0),
      COALESCE(v_order.net_weight_per_carton, 0),
      COALESCE(v_order.gross_weight_per_carton, 0),
      CASE WHEN COALESCE(v_order.total_net_weight, 0) > 0
        THEN COALESCE(v_order.fruit_cost_allocated, 0) / v_order.total_net_weight ELSE 0 END,
      COALESCE(v_order.fruit_cost_allocated, v_order.fruit_cost_base, 0),
      COALESCE(v_order.total_packing_cost, 0),
      COALESCE(v_order.packing_cost_per_carton, 0)
    );

    SELECT
      COALESCE(array_agg(pol.id ORDER BY pol.id), ARRAY[]::BIGINT[]),
      COALESCE(array_agg(COALESCE(pol.raw_material_cost, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
      COALESCE(array_agg(COALESCE(pol.quantity, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
      COALESCE(array_agg(COALESCE(pol.total_net_weight, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
      COALESCE(array_agg(COALESCE(pol.total_gross_weight, 0) ORDER BY pol.id), ARRAY[]::NUMERIC[]),
      COALESCE(array_agg(COALESCE(pol.carton_count, 0)::numeric ORDER BY pol.id), ARRAY[]::NUMERIC[])
    INTO v_line_ids, v_line_raw, v_line_qty, v_line_net, v_line_gross, v_line_cartons
    FROM public.packing_order_lines pol
    WHERE pol.packing_order_id = p_packing_order_id;

    v_n := COALESCE(array_length(v_line_ids, 1), 0);
  END IF;

  v_line_specific := ARRAY[]::NUMERIC[];
  v_line_shared := ARRAY[]::NUMERIC[];
  v_line_overhead := ARRAY[]::NUMERIC[];
  FOR v_i IN 1..v_n LOOP
    v_line_specific := v_line_specific || ARRAY[0::numeric];
    v_line_shared := v_line_shared || ARRAY[0::numeric];
    v_line_overhead := v_line_overhead || ARRAY[0::numeric];
  END LOOP;

  -- C. Allocate packaging materials (apply_to)
  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_mat_cost := COALESCE((v_el->>'total')::numeric, 0);
      IF v_mat_cost = 0 THEN
        v_mat_cost := COALESCE((v_el->>'used_qty')::numeric, 0)
                    * COALESCE((v_el->>'unit_cost')::numeric, 0);
      END IF;
      IF v_mat_cost <= 0 THEN CONTINUE; END IF;

      v_apply_to := COALESCE(NULLIF(trim(v_el->>'apply_to'), ''), 'all');

      IF v_apply_to LIKE 'line:%' THEN
        v_target_idx := NULLIF(substring(v_apply_to from 6), '')::int;
        IF v_target_idx IS NOT NULL THEN
          v_target_idx := v_target_idx + 1;
        END IF;
        IF v_target_idx IS NOT NULL AND v_target_idx BETWEEN 1 AND v_n THEN
          v_line_specific[v_target_idx] := v_line_specific[v_target_idx] + v_mat_cost;
        ELSE
          v_shared_pkg_total := v_shared_pkg_total + v_mat_cost;
        END IF;
      ELSE
        v_shared_pkg_total := v_shared_pkg_total + v_mat_cost;
      END IF;
    END LOOP;
  END IF;

  IF v_shared_pkg_total > 0 THEN
    v_bases := v_line_net;
    v_shares := public._packing_allocate_shares('BY_NET_WEIGHT', v_bases);
    v_assigned := 0;
    FOR v_i IN 1..v_n LOOP
      IF v_i = v_n THEN
        v_part := ROUND(v_shared_pkg_total - v_assigned, 2);
      ELSE
        v_part := ROUND(v_shared_pkg_total * v_shares[v_i], 2);
      END IF;
      v_line_shared[v_i] := v_line_shared[v_i] + v_part;
      v_assigned := v_assigned + v_part;
    END LOOP;
  END IF;

  -- D. Allocate cost items by allocation_method
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
    v_amount := COALESCE(r_cost.base_amount, 0);
    IF v_amount <= 0 THEN CONTINUE; END IF;

    v_method := UPPER(COALESCE(r_cost.allocation_method, 'BY_NET_WEIGHT'));

    IF v_method = 'MANUAL' THEN
      IF r_cost.target_line_id IS NOT NULL THEN
        v_target_idx := NULL;
        FOR v_i IN 1..v_n LOOP
          IF v_line_ids[v_i] = r_cost.target_line_id THEN
            v_target_idx := v_i;
            EXIT;
          END IF;
        END LOOP;
        IF v_target_idx IS NOT NULL THEN
          v_line_overhead[v_target_idx] := v_line_overhead[v_target_idx] + v_amount;
          CONTINUE;
        END IF;
      END IF;

      IF r_cost.currency_snapshot IS NOT NULL
         AND r_cost.currency_snapshot ? 'target_line_index' THEN
        v_target_idx := (r_cost.currency_snapshot->>'target_line_index')::int;
        IF v_target_idx IS NOT NULL THEN
          v_target_idx := v_target_idx + 1;
          IF v_target_idx BETWEEN 1 AND v_n THEN
            v_line_overhead[v_target_idx] := v_line_overhead[v_target_idx] + v_amount;
            CONTINUE;
          END IF;
        END IF;
      END IF;

      v_method := 'EQUAL';
    END IF;

    CASE v_method
      WHEN 'BY_WEIGHT' THEN v_bases := v_line_gross;
      WHEN 'BY_NET_WEIGHT' THEN v_bases := v_line_net;
      WHEN 'BY_INPUT_WEIGHT' THEN v_bases := v_line_qty;
      WHEN 'BY_PRODUCT_VALUE' THEN v_bases := v_line_raw;
      WHEN 'BY_QUANTITY' THEN v_bases := v_line_cartons;
      WHEN 'BY_PACKAGES' THEN v_bases := v_line_cartons;
      WHEN 'EQUAL' THEN
        v_bases := ARRAY[]::NUMERIC[];
        FOR v_i IN 1..v_n LOOP v_bases := v_bases || ARRAY[1::numeric]; END LOOP;
      ELSE v_bases := v_line_net;
    END CASE;

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
  END LOOP;

  -- E. Persist allocated costs on lines + header totals
  v_tot_raw_cost := 0;
  v_tot_pkg_cost := 0;
  v_tot_cost_items := 0;
  v_tot_final_cost := 0;

  FOR v_i IN 1..v_n LOOP
    v_part := ROUND(
      COALESCE(v_line_raw[v_i], 0)
      + v_line_specific[v_i]
      + v_line_shared[v_i]
      + v_line_overhead[v_i],
      2
    );

    UPDATE public.packing_order_lines
    SET specific_packaging_cost = ROUND(v_line_specific[v_i], 2),
        allocated_shared_packaging = ROUND(v_line_shared[v_i], 2),
        allocated_cost_items = ROUND(v_line_overhead[v_i], 2),
        final_cost = v_part,
        final_unit_cost = CASE
          WHEN v_line_cartons[v_i] > 0 THEN ROUND(v_part / v_line_cartons[v_i], 4)
          ELSE 0 END,
        updated_at = NOW()
    WHERE id = v_line_ids[v_i];

    v_tot_raw_cost := v_tot_raw_cost + COALESCE(v_line_raw[v_i], 0);
    v_tot_pkg_cost := v_tot_pkg_cost + v_line_specific[v_i] + v_line_shared[v_i];
    v_tot_cost_items := v_tot_cost_items + v_line_overhead[v_i];
    v_tot_final_cost := v_tot_final_cost + v_part;
  END LOOP;

  v_tot_raw_cost := ROUND(v_tot_raw_cost, 2);
  v_tot_pkg_cost := ROUND(v_tot_pkg_cost, 2);
  v_tot_cost_items := ROUND(v_tot_cost_items, 2);
  v_tot_final_cost := ROUND(v_tot_final_cost, 2);
  v_lines_count := v_n;

  IF v_tot_final_cost = 0 THEN
    v_tot_raw_cost   := COALESCE(v_order.fruit_cost_allocated, v_order.fruit_cost_base, 0);
    v_tot_pkg_cost   := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
    v_tot_final_cost := COALESCE(v_order.total_packing_cost, (v_tot_raw_cost + v_tot_pkg_cost + v_tot_cost_items));
  END IF;

  UPDATE public.packing_orders
  SET fruit_cost_allocated = v_tot_raw_cost,
      fruit_cost_base = v_tot_raw_cost,
      actual_material_cost = v_tot_pkg_cost,
      material_cost_base = v_tot_pkg_cost,
      other_cost_base = v_tot_cost_items,
      total_packing_cost = v_tot_final_cost,
      packing_cost_per_carton = CASE
        WHEN COALESCE(carton_count, 0) > 0 THEN ROUND(v_tot_final_cost / carton_count, 4)
        ELSE packing_cost_per_carton END,
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  -- F. Stock deductions
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  ELSE
    FOR r_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id LOOP
      IF r_line.batch_id IS NOT NULL AND r_line.quantity > 0 THEN
        v_allocations := v_allocations || jsonb_build_array(
          jsonb_build_object(
            'batch_id', r_line.batch_id,
            'quantity', r_line.quantity,
            'product_name', r_line.product_name,
            'product_code', ''
          )
        );
      END IF;
    END LOOP;
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

  -- G. Cost item payments + supplier subledger
  FOR r_cost IN
    SELECT poci.*
    FROM public.packing_order_cost_items poci
    WHERE poci.packing_order_id = p_packing_order_id
  LOOP
    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    v_tx_desc := 'سداد بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد')
              || ' (أمر ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ')';

    -- Unpaid supplier credit
    IF v_supplier_id IS NOT NULL
       AND r_cost.original_amount > 0
       AND (r_cost.payment_source_type IS NULL OR r_cost.payment_source_type = 'none') THEN
      UPDATE public.suppliers
      SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.original_amount,
          updated_at = now()
      WHERE id = v_supplier_id;

      INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_text, description, created_by
      ) VALUES (
        'supplier', v_supplier_id::text, 'credit', r_cost.original_amount, r_cost.original_currency,
        'packing_cost', p_packing_order_id::text,
        'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد')
          || ' (أمر ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ')',
        auth.uid()
      );
    END IF;

    -- Treasury / Bank disbursement
    IF r_cost.payment_source_type IS NOT NULL AND r_cost.payment_source_id IS NOT NULL
       AND r_cost.treasury_transaction_id IS NULL AND r_cost.bank_transaction_id IS NULL THEN

      IF r_cost.payment_source_type = 'treasury' THEN
        SELECT balance INTO v_current_balance
        FROM public.treasury_balances
        WHERE treasury_id = r_cost.payment_source_id AND currency = r_cost.original_currency
        FOR UPDATE;

        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة للبند % (المتوفر: % %, المطلوب: % %)',
            r_cost.name, COALESCE(v_current_balance, 0), r_cost.original_currency,
            r_cost.original_amount, r_cost.original_currency;
        END IF;

        PERFORM public.spend_custody(
          r_cost.payment_source_id,
          r_cost.original_currency,
          r_cost.original_amount,
          v_tx_desc,
          NULL,
          v_supplier_id,
          NULL, NULL, NULL
        );

        SELECT id INTO v_treasury_tx_id
        FROM public.treasury_transactions
        WHERE treasury_id = r_cost.payment_source_id
          AND type = 'expense'
          AND amount = r_cost.original_amount
          AND currency = r_cost.original_currency
        ORDER BY created_at DESC
        LIMIT 1;

        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = v_treasury_tx_id
        WHERE id = r_cost.id;

      ELSIF r_cost.payment_source_type = 'bank' THEN
        SELECT balance INTO v_current_balance
        FROM public.bank_accounts
        WHERE id = r_cost.payment_source_id
        FOR UPDATE;

        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في البنك للبند % (المتوفر: %, المطلوب: %)',
            r_cost.name, COALESCE(v_current_balance, 0), r_cost.original_amount;
        END IF;

        SELECT (public.withdraw_bank_account(
          r_cost.payment_source_id::integer,
          r_cost.original_amount,
          v_tx_desc,
          CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
          v_supplier_id::text,
          NULL
        )->>'bank_tx_id')::integer INTO v_bank_tx_id;

        IF v_bank_tx_id IS NULL THEN
          SELECT id INTO v_bank_tx_id
          FROM public.bank_account_transactions
          WHERE bank_account_id = r_cost.payment_source_id
            AND amount = r_cost.original_amount
          ORDER BY created_at DESC
          LIMIT 1;
        END IF;

        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = v_bank_tx_id
        WHERE id = r_cost.id;
      END IF;
    END IF;
  END LOOP;

  -- H. Resolve GL accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;

  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1031' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN
    SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
  END IF;
  SELECT id INTO v_raw_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
  SELECT id INTO v_pkg_inv_acc FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

  SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '5040' LIMIT 1;
  IF v_expense_acc IS NULL THEN
    SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '51101' LIMIT 1;
  END IF;
  IF v_expense_acc IS NULL THEN
    SELECT id INTO v_expense_acc FROM accounts WHERE account_code = '6000' LIMIT 1;
  END IF;

  IF v_finished_inv_acc IS NULL OR v_raw_inv_acc IS NULL THEN
    RAISE EXCEPTION 'حسابات المخزون (1030/1031) غير موجودة في شجرة الحسابات';
  END IF;

  -- Clean stale JE if any
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
    'قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text)
      || ' (تحويل مخزون خام+تعبئة+مصاريف → إنتاج تام)',
    'posted', true, 'packing_order', p_packing_order_id::text,
    v_company_id, auth.uid(), NOW(), NOW()
  ) RETURNING id INTO v_je_id;

  v_entry_num := fn_generate_journal_entry_number(v_je_id);
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- DR Finished Goods
  IF v_tot_final_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_final_cost, 0,
      COALESCE(v_order.display_currency, 'EGP'), v_tot_final_cost,
      'إضافة مخزون إنتاج تام — أمر تعبئة: ' || COALESCE(v_order.order_number, p_packing_order_id::text)
    );
    v_sum_debit := v_sum_debit + v_tot_final_cost;
  END IF;

  -- CR Raw inventory
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost,
      COALESCE(v_order.display_currency, 'EGP'), v_tot_raw_cost,
      'صرف محاصيل/مواد خام — أمر تعبئة: ' || COALESCE(v_order.order_number, p_packing_order_id::text)
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- CR Packaging materials
  IF v_tot_pkg_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_cost,
      COALESCE(v_order.display_currency, 'EGP'), v_tot_pkg_cost,
      'صرف مواد تعبئة — أمر تعبئة: ' || COALESCE(v_order.order_number, p_packing_order_id::text)
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_cost;
  END IF;

  -- CR Overhead: paid → capitalize expense; unpaid → AP/supplier
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;

    IF r_cost.payment_source_type IN ('treasury', 'bank') THEN
      IF r_cost.treasury_transaction_id IS NOT NULL THEN
        SELECT ale.account_id INTO v_credit_acc
        FROM public.treasury_transactions tt
        JOIN public.journal_entries je ON je.id = tt.journal_entry_id
        JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id AND ale.debit > 0
        WHERE tt.id = r_cost.treasury_transaction_id
        LIMIT 1;
      ELSIF r_cost.bank_transaction_id IS NOT NULL THEN
        SELECT ale.account_id INTO v_credit_acc
        FROM public.bank_account_transactions bt
        JOIN public.journal_entries je ON je.id = bt.journal_entry_id
        JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id AND ale.debit > 0
        WHERE bt.id = r_cost.bank_transaction_id
        LIMIT 1;
      END IF;
      IF v_credit_acc IS NULL THEN
        v_credit_acc := v_expense_acc;
      END IF;
    ELSE
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
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
      ) VALUES (
        v_je_id, v_credit_acc, 0, r_cost.base_amount,
        COALESCE(r_cost.original_currency, 'EGP'), r_cost.base_amount,
        'تحميل مصروف/مستحق على الإنتاج التام: ' || COALESCE(r_cost.name, 'بند تكلفة')
      );
      v_sum_credit := v_sum_credit + r_cost.base_amount;
    END IF;
  END LOOP;

  -- Balance guard (allow 1 qirsh tolerance for rounding)
  IF ABS(ROUND(v_sum_debit, 2) - ROUND(v_sum_credit, 2)) > 0.01 THEN
    RAISE EXCEPTION
      'قيد أمر التعبئة غير متوازن: مدين=% دائن=% فرق=%',
      ROUND(v_sum_debit, 2), ROUND(v_sum_credit, 2),
      ROUND(v_sum_debit - v_sum_credit, 2);
  END IF;

  -- I. Link sortings to lines
  FOR r_line IN
    SELECT * FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id
      AND COALESCE(sorted_weight_kg, 0) > 0
  LOOP
    SELECT lr.lot_number INTO v_lot_number
    FROM public.lot_receipts lr
    WHERE lr.id = r_line.source_lot_id;

    UPDATE public.packing_order_sortings
    SET packing_order_line_id = r_line.id
    WHERE packing_order_id = p_packing_order_id
      AND packing_order_line_id IS NULL
      AND product_name = r_line.product_name
      AND ABS(weight_kg - r_line.sorted_weight_kg) < 0.001;
  END LOOP;

  -- J. Complete order
  UPDATE public.packing_orders
  SET status = 'completed',
      journal_entry_id = v_je_id,
      packed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'journal_entry_id', v_je_id,
    'total_final_cost', v_tot_final_cost,
    'total_raw_cost', v_tot_raw_cost,
    'total_packaging_cost', v_tot_pkg_cost,
    'total_overhead', v_tot_cost_items,
    'lines_count', v_lines_count,
    'debit', ROUND(v_sum_debit, 2),
    'credit', ROUND(v_sum_credit, 2)
  );
END;
$$;

-- ============================================================================
-- 4. Enterprise rpc_cancel_packing_order (reversing JE, not delete)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(
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
  v_allocations     JSONB := '[]'::jsonb;
  v_el              JSONB;
  r_cost            RECORD;
  r_line            RECORD;
  r_ale             RECORD;
  v_treasury_tx     RECORD;
  v_treasury_bal    RECORD;
  v_reversal_tx_id  BIGINT;
  v_bank_tx         RECORD;
  v_bank_bal_diff   NUMERIC;
  v_supplier_id     UUID;
  v_rate            NUMERIC;
  v_amt_foreign     NUMERIC;
  v_curr            TEXT;
  v_had_treasury_tx BOOLEAN;
  v_had_bank_tx     BOOLEAN;
  v_je_id           BIGINT;
  v_rev_je_id       BIGINT;
  v_entry_num       TEXT;
  v_company_id      UUID;
  v_sold_sortings   INT;
  i                 INT;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  SELECT COUNT(*) INTO v_sold_sortings
  FROM public.packing_order_sortings
  WHERE packing_order_id = p_packing_order_id
    AND (status = 'sold' OR COALESCE(total_sale_amount, 0) > 0);

  IF v_sold_sortings > 0 THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن الإلغاء: يوجد فرز مباع مرتبط بالأمر');
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  -- 1. Create reversing journal entry (keep original for audit)
  v_je_id := v_order.journal_entry_id;
  IF v_je_id IS NULL THEN
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'packing_order' AND source_id = p_packing_order_id::text
    ORDER BY id DESC LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    SELECT company_id INTO v_company_id FROM public.journal_entries WHERE id = v_je_id;

    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      CURRENT_DATE,
      'عكس قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text)
        || ' (مرجع القيد الأصلي #' || v_je_id::text || ')',
      'posted', true, 'packing_order_reversal', p_packing_order_id::text,
      v_company_id, auth.uid(), NOW(), NOW()
    ) RETURNING id INTO v_rev_je_id;

    v_entry_num := fn_generate_journal_entry_number(v_rev_je_id);
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_rev_je_id;

    FOR r_ale IN
      SELECT * FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id
    LOOP
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency,
        amount_in_base_currency, description
      ) VALUES (
        v_rev_je_id,
        r_ale.account_id,
        COALESCE(r_ale.credit, 0),
        COALESCE(r_ale.debit, 0),
        COALESCE(r_ale.currency, 'EGP'),
        COALESCE(r_ale.amount_in_base_currency, COALESCE(r_ale.debit, 0) + COALESCE(r_ale.credit, 0)),
        'عكس: ' || COALESCE(r_ale.description, '')
      );
    END LOOP;

    UPDATE public.journal_entries
    SET description = COALESCE(description, '') || ' [تم عكسه بالقيد #' || v_rev_je_id::text || ']'
    WHERE id = v_je_id;
  END IF;

  -- 2. Reverse payments
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
    v_had_treasury_tx := (r_cost.treasury_transaction_id IS NOT NULL);
    v_had_bank_tx     := (r_cost.bank_transaction_id IS NOT NULL);

    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    IF v_had_treasury_tx THEN
      SELECT * INTO v_treasury_tx
      FROM public.treasury_transactions
      WHERE id = r_cost.treasury_transaction_id;

      IF FOUND THEN
        SELECT * INTO v_treasury_bal
        FROM public.treasury_balances
        WHERE treasury_id = v_treasury_tx.treasury_id
          AND currency   = v_treasury_tx.currency
        FOR UPDATE;

        IF FOUND THEN
          UPDATE public.treasury_balances
          SET balance = v_treasury_bal.balance + v_treasury_tx.amount,
              updated_at = NOW()
          WHERE treasury_id = v_treasury_tx.treasury_id
            AND currency = v_treasury_tx.currency;

          INSERT INTO public.treasury_transactions (
            treasury_id, type, currency, amount,
            balance_before, balance_after,
            description, supplier_id, created_by
          ) VALUES (
            v_treasury_tx.treasury_id, 'return_in', v_treasury_tx.currency, v_treasury_tx.amount,
            v_treasury_bal.balance, v_treasury_bal.balance + v_treasury_tx.amount,
            'عكس سداد بند تكلفة أمر تعبئة ملغي: أمر '
              || COALESCE(v_order.order_number, p_packing_order_id::text)
              || ' (مرجع: ' || v_treasury_tx.id::text || ')',
            v_treasury_tx.supplier_id, auth.uid()
          ) RETURNING id INTO v_reversal_tx_id;
        END IF;

        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = NULL WHERE id = r_cost.id;
      END IF;
    END IF;

    IF v_had_bank_tx THEN
      SELECT * INTO v_bank_tx
      FROM public.bank_account_transactions
      WHERE id = r_cost.bank_transaction_id;

      IF FOUND THEN
        IF v_bank_tx.type = 'deposit' THEN
          v_bank_bal_diff := -v_bank_tx.amount;
        ELSE
          v_bank_bal_diff := v_bank_tx.amount;
        END IF;

        UPDATE public.bank_accounts
        SET balance = balance + v_bank_bal_diff
        WHERE id = v_bank_tx.bank_account_id;

        INSERT INTO public.bank_account_transactions (
          bank_account_id, type, amount,
          balance_before, balance_after,
          description, entity_type, entity_id, created_by
        )
        SELECT
          v_bank_tx.bank_account_id,
          CASE WHEN v_bank_tx.type = 'deposit' THEN 'withdrawal' ELSE 'deposit' END,
          v_bank_tx.amount,
          ba.balance - v_bank_bal_diff,
          ba.balance,
          'عكس سداد بند تكلفة أمر تعبئة ملغي: أمر '
            || COALESCE(v_order.order_number, p_packing_order_id::text)
            || ' (مرجع: ' || v_bank_tx.id::text || ')',
          v_bank_tx.entity_type, v_bank_tx.entity_id, auth.uid()
        FROM public.bank_accounts ba
        WHERE ba.id = v_bank_tx.bank_account_id;

        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = NULL WHERE id = r_cost.id;
      END IF;
    END IF;

    -- Reverse unpaid supplier credit
    IF NOT v_had_treasury_tx AND NOT v_had_bank_tx AND v_supplier_id IS NOT NULL THEN
      v_rate := COALESCE(NULLIF(r_cost.exchange_rate, 0), 1.0);
      v_curr := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');
      v_amt_foreign := COALESCE(r_cost.original_amount, ROUND(r_cost.base_amount / v_rate, 2));

      IF v_amt_foreign > 0 THEN
        UPDATE public.suppliers
        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - v_amt_foreign)
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_type, entity_id, entry_type, amount, currency,
          reference_type, reference_text, description, created_by
        ) VALUES (
          'supplier', v_supplier_id::text, 'debit', v_amt_foreign, v_curr,
          'packing_cost_reversal', p_packing_order_id::text,
          'عكس بند تكلفة أمر تعبئة ملغي: أمر '
            || COALESCE(v_order.order_number, p_packing_order_id::text),
          auth.uid()
        );
      END IF;
    END IF;
  END LOOP;

  -- 3. Restore stock
  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  ELSE
    FOR r_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id LOOP
      IF r_line.batch_id IS NOT NULL AND r_line.quantity > 0 THEN
        v_allocations := v_allocations || jsonb_build_array(
          jsonb_build_object(
            'batch_id', r_line.batch_id,
            'quantity', r_line.quantity,
            'product_name', r_line.product_name,
            'product_code', ''
          )
        );
      END IF;
    END LOOP;
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
    PERFORM restore_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- 4. Delete pending (unsold) sortings
  DELETE FROM public.packing_order_sortings
  WHERE packing_order_id = p_packing_order_id
    AND status = 'pending'
    AND COALESCE(total_sale_amount, 0) = 0;

  -- 5. Mark cancelled
  UPDATE public.packing_orders
  SET status = 'cancelled',
      reversal_journal_entry_id = v_rev_je_id,
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'original_journal_entry_id', v_je_id,
    'reversal_journal_entry_id', v_rev_je_id
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_packing_order(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public._packing_allocate_shares(text, numeric[]) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
