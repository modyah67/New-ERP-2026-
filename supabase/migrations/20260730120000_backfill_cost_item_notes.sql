-- Migration: Backfill cost_item notes from packing_orders.notes JSON
-- The 'notes' key was not being stored in currency_snapshot, causing
-- notes to be lost when reloading cost items from DB.

UPDATE packing_order_cost_items poci
SET currency_snapshot = COALESCE(poci.currency_snapshot, '{}'::jsonb) || jsonb_build_object(
  'notes',
  COALESCE(
    (SELECT item->>'notes'
     FROM jsonb_array_elements(
       COALESCE(
         (SELECT notes::jsonb->'cost_items' FROM packing_orders WHERE id = poci.packing_order_id),
         '[]'::jsonb
       )
     ) AS item
     WHERE item->>'name' = poci.name
       AND (item->>'supplier_name' IS NOT DISTINCT FROM (poci.currency_snapshot->>'supplier_name'))
     LIMIT 1),
    ''
  )
)
WHERE poci.currency_snapshot->>'notes' IS NULL
   OR poci.currency_snapshot->>'notes' = '';
