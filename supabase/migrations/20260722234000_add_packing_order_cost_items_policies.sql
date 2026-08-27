-- ============================================================================
-- Migration: Add missing RLS policy for packing_order_cost_items
-- ============================================================================

-- Create policy to allow all actions for authenticated users
CREATE POLICY "Allow all authenticated" ON "public"."packing_order_cost_items"
  AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
