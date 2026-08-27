-- ============================================================================
-- Migration: 361_packing_waste_categories_and_rpc
-- Description: Update list_cost_report_categories to support 'packing_waste'
--              and seed default packing waste cost categories.
-- ============================================================================

-- 1. Update list_cost_report_categories RPC to include 'packing_waste' scope
CREATE OR REPLACE FUNCTION public.list_cost_report_categories(
  p_scope text DEFAULT NULL
)
RETURNS SETOF cost_report_categories
LANGUAGE sql STABLE
AS $$
  SELECT *
  FROM cost_report_categories
  WHERE (
    p_scope IS NULL 
    OR scope = p_scope 
    OR scope = 'both' 
    OR scope = 'all'
    OR (p_scope = 'packing_waste' AND scope IN ('packing', 'both', 'all', 'packing_waste'))
  )
  ORDER BY name;
$$;

GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(text) TO authenticated, anon, service_role;

-- 2. Seed default packing waste categories
INSERT INTO public.cost_report_categories (name, scope, is_system, type) VALUES
  ('فرز وتدريج خارجي',     'packing_waste', true, 'direct'),
  ('نقل وتخلص من عوادم',  'packing_waste', true, 'direct'),
  ('عمالة فرز وهالك',      'packing_waste', true, 'direct')
ON CONFLICT (name) DO NOTHING;
