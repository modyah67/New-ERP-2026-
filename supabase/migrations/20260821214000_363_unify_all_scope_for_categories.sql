-- ============================================================================
-- Migration: 363_unify_all_scope_for_categories
-- Description: Update cost report categories to use 'all' instead of 'both'
--              and update list_cost_report_categories RPC.
-- ============================================================================

BEGIN;

-- 1. Update existing rows from 'both' to 'all'
UPDATE public.cost_report_categories
SET scope = 'all'
WHERE scope = 'both';

-- 2. Update default value on scope column
ALTER TABLE public.cost_report_categories
  ALTER COLUMN scope SET DEFAULT 'all';

-- 3. Update list_cost_report_categories function
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
    OR scope = 'all' 
    OR scope = 'both'
    OR (p_scope = 'packing_waste' AND scope IN ('packing', 'packing_waste', 'both', 'all'))
    OR (p_scope = 'packing' AND scope IN ('packing', 'both', 'all'))
    OR (p_scope = 'shipment' AND scope IN ('shipment', 'both', 'all'))
  )
  ORDER BY name;
$$;

GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(text) TO authenticated, anon, service_role;

COMMIT;
