-- Migration: Add report_category_id to packing_order_cost_items
-- and update delete_cost_report_category RPC

-- 1. Add report_category_id to packing_order_cost_items if it doesn't exist
ALTER TABLE public.packing_order_cost_items
  ADD COLUMN IF NOT EXISTS report_category_id INTEGER REFERENCES public.cost_report_categories(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.packing_order_cost_items.report_category_id IS
  'FK references cost_report_categories(id) for unified report categorization';

-- 2. Redefine delete_cost_report_category to remove is_system constraint
-- and instead block deletion if the category is actively referenced in:
-- - shipment_cost_items
-- - packing_order_cost_items
-- - general_cost_items
CREATE OR REPLACE FUNCTION public.delete_cost_report_category(
  p_id integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.shipment_cost_items WHERE report_category_id = p_id) OR
     EXISTS (SELECT 1 FROM public.packing_order_cost_items WHERE report_category_id = p_id) OR
     EXISTS (SELECT 1 FROM public.general_cost_items WHERE report_category_id = p_id) THEN
    RAISE EXCEPTION 'لا يمكن حذف هذا التصنيف لأنه مستخدم في سجلات بنود التكلفة';
  END IF;

  DELETE FROM public.cost_report_categories WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_cost_report_category(integer) TO authenticated;
