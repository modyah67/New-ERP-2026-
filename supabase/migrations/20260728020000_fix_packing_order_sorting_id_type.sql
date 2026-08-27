-- ============================================================================
-- Migration: Fix packing_order_id column type in packing_order_sortings
-- ============================================================================

-- 1. Alter column type to bigint safely
ALTER TABLE public.packing_order_sortings
  ALTER COLUMN packing_order_id TYPE bigint USING (
    CASE 
      WHEN packing_order_id::text ~ '^[0-9]+$' THEN packing_order_id::text::bigint 
      ELSE NULL 
    END
  );

-- 2. Add foreign key constraint to packing_orders(id)
ALTER TABLE public.packing_order_sortings
  DROP CONSTRAINT IF EXISTS fk_packing_order_sortings_packing_order;

ALTER TABLE public.packing_order_sortings
  DROP CONSTRAINT IF EXISTS packing_order_sortings_packing_order_id_fkey;

ALTER TABLE public.packing_order_sortings
  ADD CONSTRAINT fk_packing_order_sortings_packing_order
  FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id) ON DELETE CASCADE;

-- 3. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
