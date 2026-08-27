-- Migration 100: Add packing_order_line_id to export_shipment_items
-- Links each shipment item to the specific packing_order_line (not just the packing order header)
-- This enables per-line packing cost per carton display in export shipments

ALTER TABLE public.export_shipment_items
  ADD COLUMN IF NOT EXISTS packing_order_line_id INTEGER;

-- Backfill: auto-update only where exactly 1 matching line exists per (packing_order_id, fruit_type_id)
DO $$
DECLARE
  v_auto_updated INTEGER;
  v_needs_review INTEGER;
BEGIN
  -- Step 1: Count matches per shipment item, then auto-update unique ones
  UPDATE public.export_shipment_items esi
  SET packing_order_line_id = sub.line_id
  FROM (
    SELECT
      esi2.id AS item_id,
      pol.id AS line_id
    FROM public.export_shipment_items esi2
    JOIN public.packing_order_lines pol
      ON pol.packing_order_id = esi2.packing_order_id
     AND pol.fruit_type_id = esi2.finished_product_id
    WHERE esi2.packing_order_line_id IS NULL
      AND esi2.packing_order_id IS NOT NULL
      AND esi2.finished_product_id IS NOT NULL
  ) sub
  JOIN (
    SELECT
      esi3.id AS item_id,
      COUNT(*) AS match_count
    FROM public.export_shipment_items esi3
    JOIN public.packing_order_lines pol2
      ON pol2.packing_order_id = esi3.packing_order_id
     AND pol2.fruit_type_id = esi3.finished_product_id
    WHERE esi3.packing_order_line_id IS NULL
      AND esi3.packing_order_id IS NOT NULL
      AND esi3.finished_product_id IS NOT NULL
    GROUP BY esi3.id
    HAVING COUNT(*) = 1
  ) uniq ON uniq.item_id = sub.item_id
  WHERE esi.id = sub.item_id;

  GET DIAGNOSTICS v_auto_updated = ROW_COUNT;

  RAISE NOTICE 'Migration 100: Auto-updated % shipment items with unique packing_order_line match', v_auto_updated;

  -- Step 2: Report items needing manual review (multiple matching lines)
  DROP TABLE IF EXISTS _migration_100_review;
  CREATE TABLE _migration_100_review AS
  SELECT
    esi.id AS shipment_item_id,
    esi.shipment_id,
    esi.product_name,
    esi.packing_order_id,
    esi.finished_product_id AS fruit_type_id,
    pol.id AS packing_order_line_id,
    pol.product_name AS line_product_name,
    pol.carton_count AS line_carton_count,
    pol.final_unit_cost AS line_final_unit_cost,
    pol.sold_cartons AS line_sold_cartons
  FROM public.export_shipment_items esi
  JOIN public.packing_order_lines pol
    ON pol.packing_order_id = esi.packing_order_id
   AND pol.fruit_type_id = esi.finished_product_id
  WHERE esi.packing_order_line_id IS NULL
    AND esi.packing_order_id IS NOT NULL
    AND esi.finished_product_id IS NOT NULL;

  SELECT COUNT(*) INTO v_needs_review FROM _migration_100_review;

  IF v_needs_review > 0 THEN
    RAISE WARNING 'Migration 100: % shipment items need MANUAL REVIEW. Run: SELECT * FROM _migration_100_review', v_needs_review;
  ELSE
    RAISE NOTICE 'Migration 100: No items need manual review. All matches are unique.';
    DROP TABLE IF EXISTS _migration_100_review;
  END IF;
END $$;
