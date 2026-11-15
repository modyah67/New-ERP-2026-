-- ============================================================================
-- Add Foreign Key from packing_order_cost_items to cost_report_categories
-- and reload PostgREST schema cache.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_packing_order_cost_items_report_category'
    ) THEN
        ALTER TABLE public.packing_order_cost_items
        ADD CONSTRAINT fk_packing_order_cost_items_report_category
        FOREIGN KEY (report_category_id)
        REFERENCES public.cost_report_categories(id)
        ON DELETE SET NULL;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
