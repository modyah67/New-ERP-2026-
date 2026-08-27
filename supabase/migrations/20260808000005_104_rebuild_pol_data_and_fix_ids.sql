-- Migration 104: Rebuild packing_order_lines with correct data and matching IDs
-- ═══════════════════════════════════════════════════════════════
-- Root cause: packing_order_lines had IDs 3,4 (from test RPC), but export_shipment_items reference line_id=1,2.
-- Export form can't find lines by ID → falls back to order-level packing_cost_per_carton (424.82).
-- Fix: delete stale lines, insert with correct data + explicit IDs 1,2 matching export items.

-- 1. Delete all existing lines for packing_order #1
DELETE FROM public.packing_order_lines WHERE packing_order_id = 1;

-- 2. Insert correct per-line data with explicit IDs matching export_shipment_items
-- Line 1 (matches export item id=1: مانجا, 80 cartons):
--   rawCost=10000, specific=160, costItems=1363.64 (BY_NET_WEIGHT)
INSERT INTO public.packing_order_lines (
  id, packing_order_id, product_name, grade, batch_id,
  quantity, carton_count, net_weight_per_carton, gross_weight_per_carton,
  unit_cost, raw_material_cost, expected_loss_percent,
  waste_weight_kg, waste_cost, sorted_weight_kg, sorting_cost,
  specific_packaging_cost, allocated_shared_packaging,
  allocated_cost_items, final_cost, final_unit_cost,
  sold_cartons, notes, updated_at
) VALUES (
  1, 1, 'مانجا', 'A', 5,
  900, 80, 11.25, 12.5,
  11.1111, 10000.00, 0,
  0, 0, 0, 0,
  160.00, 0.00,
  1363.64, 11523.64, 14.4046,
  0, NULL, NOW()
);

-- Line 2 (matches export item id=2: فراولة, 90 cartons):
--   rawCost=1000, specific=10560, costItems=136.36 (BY_NET_WEIGHT)
INSERT INTO public.packing_order_lines (
  id, packing_order_id, product_name, grade, batch_id,
  quantity, carton_count, net_weight_per_carton, gross_weight_per_carton,
  unit_cost, raw_material_cost, expected_loss_percent,
  waste_weight_kg, waste_cost, sorted_weight_kg, sorting_cost,
  specific_packaging_cost, allocated_shared_packaging,
  allocated_cost_items, final_cost, final_unit_cost,
  sold_cartons, notes, updated_at
) VALUES (
  2, 1, 'فراولة', 'A', 6,
  90, 90, 1.0, 1.11,
  11.1111, 1000.00, 0,
  0, 0, 0, 0,
  10560.00, 0.00,
  136.36, 11696.36, 129.9596,
  0, NULL, NOW()
);

-- 3. Reset BIGSERIAL sequence to avoid future ID conflicts
SELECT setval(
  pg_get_serial_sequence('public.packing_order_lines', 'id'),
  GREATEST(
    (SELECT COALESCE(MAX(id), 0) FROM public.packing_order_lines),
    2
  )
);

-- 4. Verify
DO $$
DECLARE
  v_count INT;
  v_sum NUMERIC;
  v_item RECORD;
  v_line RECORD;
BEGIN
  SELECT COUNT(*), COALESCE(SUM(final_cost), 0) INTO v_count, v_sum
  FROM public.packing_order_lines WHERE packing_order_id = 1;
  RAISE NOTICE 'packing_order_id=1: % lines, total final_cost=%', v_count, v_sum;

  IF v_count != 2 THEN
    RAISE EXCEPTION 'Expected 2 lines, got %', v_count;
  END IF;

  FOR v_item IN
    SELECT ei.id AS item_id, ei.product_name AS item_name, ei.quantity AS item_qty,
           ei.packing_order_line_id AS ref_line_id,
           pol.id AS line_id, pol.product_name AS line_name, pol.carton_count,
           pol.final_cost, pol.specific_packaging_cost, pol.allocated_cost_items
    FROM public.export_shipment_items ei
    JOIN public.packing_order_lines pol ON pol.id = ei.packing_order_line_id
    WHERE ei.packing_order_id = 1
  LOOP
    RAISE NOTICE 'export_item_id=% (%) → line_id=% (name=%, final_cost=%, cartons=%)',
      v_item.item_id, v_item.item_name, v_item.line_id,
      v_item.line_name, v_item.final_cost, v_item.carton_count;
  END LOOP;
END $$;
