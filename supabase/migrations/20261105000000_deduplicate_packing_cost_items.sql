-- =========================================================================
-- Migration: Deduplicate Packing Order Cost Items
-- Description: Cleans up any duplicate cost items that may have occurred
--              due to repeated submissions or non-idempotent inserts.
-- =========================================================================

-- 1. Remove duplicate rows from public.packing_order_cost_items
--    Prioritize keeping rows that are settled (cost_status = 'actual' or actual_amount IS NOT NULL)
DELETE FROM public.packing_order_cost_items a
USING public.packing_order_cost_items b
WHERE a.packing_order_id = b.packing_order_id
  AND a.id <> b.id
  AND LOWER(TRIM(a.name)) = LOWER(TRIM(b.name))
  AND LOWER(TRIM(a.category)) = LOWER(TRIM(b.category))
  AND ROUND(COALESCE(a.expected_amount, a.base_amount, 0), 2) = ROUND(COALESCE(b.expected_amount, b.base_amount, 0), 2)
  AND (
    -- If b is settled and a is not, delete a
    ((b.cost_status = 'actual' OR b.actual_amount IS NOT NULL) AND (a.cost_status <> 'actual' OR a.actual_amount IS NULL))
    OR
    -- If both are settled or both unsettled, delete the higher ID
    (((b.cost_status = 'actual' OR b.actual_amount IS NOT NULL) = (a.cost_status = 'actual' OR a.actual_amount IS NOT NULL)) AND a.id > b.id)
  );

-- 2. Deduplicate notes->'cost_items' array inside packing_orders table
DO $$
DECLARE
  r RECORD;
  v_cleaned JSONB;
BEGIN
  FOR r IN 
    SELECT id, notes 
    FROM public.packing_orders 
    WHERE notes IS NOT NULL 
      AND notes::text LIKE '%cost_items%'
  LOOP
    BEGIN
      WITH items AS (
        SELECT DISTINCT ON (
          LOWER(TRIM(elem->>'name')),
          LOWER(TRIM(COALESCE(elem->>'report_category_id', elem->>'category', ''))),
          ROUND(COALESCE((elem->>'expected_amount')::numeric, (elem->>'total_egp')::numeric, (elem->>'total')::numeric, 0), 2)
        ) elem
        FROM jsonb_array_elements((r.notes::jsonb)->'cost_items') AS elem
        ORDER BY 
          LOWER(TRIM(elem->>'name')),
          LOWER(TRIM(COALESCE(elem->>'report_category_id', elem->>'category', ''))),
          ROUND(COALESCE((elem->>'expected_amount')::numeric, (elem->>'total_egp')::numeric, (elem->>'total')::numeric, 0), 2),
          -- Put settled items first
          CASE WHEN elem->>'cost_status' = 'actual' OR elem->>'actual_amount' IS NOT NULL THEN 0 ELSE 1 END
      )
      SELECT jsonb_agg(elem) INTO v_cleaned FROM items;

      IF v_cleaned IS NOT NULL THEN
        UPDATE public.packing_orders
        SET notes = jsonb_set(r.notes::jsonb, '{cost_items}', v_cleaned)::text
        WHERE id = r.id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Skip rows with invalid json notes
      NULL;
    END;
  END LOOP;
END $$;
