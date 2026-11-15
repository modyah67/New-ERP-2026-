-- ============================================================================
-- Migration: 20261004000005_fix_packing_orders_confirm_costs_and_cost_items_fk.sql
-- Description:
-- 1. Add costs_confirmed_by, crops_confirmed_by, packaging_confirmed_by, final_approved_by
--    columns to public.packing_orders.
-- 2. Add foreign key fk_packing_order_cost_items_packing_order on
--    public.packing_order_cost_items(packing_order_id) -> public.packing_orders(id).
-- 3. Notify PostgREST to reload schema cache.
-- ============================================================================

BEGIN;

-- 1. Ensure columns exist on packing_orders
ALTER TABLE public.packing_orders
  ADD COLUMN IF NOT EXISTS crops_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS packaging_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS costs_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS final_approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. Add Foreign Key between packing_order_cost_items and packing_orders
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_packing_order_cost_items_packing_order'
  ) THEN
    ALTER TABLE public.packing_order_cost_items
      ADD CONSTRAINT fk_packing_order_cost_items_packing_order
      FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- 3. Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
