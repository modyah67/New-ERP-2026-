-- ============================================================================
-- Migration: Fix packing_order_id column type in packing_order_cost_items
-- ============================================================================

-- 1. Alter the column type to bigint, handling any legacy UUID values safely
ALTER TABLE public.packing_order_cost_items
  ALTER COLUMN packing_order_id TYPE bigint USING (
    CASE 
      WHEN packing_order_id::text ~ '^[0-9]+$' THEN packing_order_id::text::bigint 
      ELSE NULL 
    END
  );

-- 2. Add foreign key constraint to packing_orders(id) (idempotent)
ALTER TABLE public.packing_order_cost_items
  DROP CONSTRAINT IF EXISTS fk_packing_order_cost_items_packing_order;

ALTER TABLE public.packing_order_cost_items
  ADD CONSTRAINT fk_packing_order_cost_items_packing_order
  FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id) ON DELETE CASCADE;

