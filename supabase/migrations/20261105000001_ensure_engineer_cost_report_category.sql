-- ============================================================================
-- Migration: Ensure Engineer Cost Report Category & Sanitize Dangling Foreign Keys
-- Description: Pure SQL (no DO block required) to ensure compatibility across
--              Supabase SQL Editor, psql, and migration runners.
-- ============================================================================

-- 1. Insert 'مصاريف مهندسين' into cost_report_categories if it does not exist
INSERT INTO public.cost_report_categories (
    name,
    scope,
    is_system,
    type,
    account_id,
    supplier_type,
    cost_center_id
)
SELECT
    'مصاريف مهندسين',
    'packing',
    FALSE,
    'direct',
    (SELECT id FROM public.accounts WHERE account_code = '31251' AND deleted_at IS NULL LIMIT 1),
    'engineer',
    'CC-ENG-EXP'
WHERE NOT EXISTS (
    SELECT 1 FROM public.cost_report_categories WHERE name = 'مصاريف مهندسين'
);

-- 2. Update existing 'مصاريف مهندسين' category attributes
UPDATE public.cost_report_categories
SET scope = 'packing',
    supplier_type = 'engineer',
    cost_center_id = 'CC-ENG-EXP',
    account_id = COALESCE(
        (SELECT id FROM public.accounts WHERE account_code = '31251' AND deleted_at IS NULL LIMIT 1),
        cost_report_categories.account_id
    )
WHERE name = 'مصاريف مهندسين';

-- 3. Link all engineer_expenses cost items to the valid category id
UPDATE public.packing_order_cost_items
SET report_category_id = (SELECT id FROM public.cost_report_categories WHERE name = 'مصاريف مهندسين' LIMIT 1)
WHERE category = 'engineer_expenses'
  AND (
      report_category_id IS NULL
      OR NOT EXISTS (
          SELECT 1 FROM public.cost_report_categories c WHERE c.id = packing_order_cost_items.report_category_id
      )
  );

-- 4. Clean up any other dangling foreign keys in packing_order_cost_items
UPDATE public.packing_order_cost_items
SET report_category_id = NULL
WHERE report_category_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.cost_report_categories c WHERE c.id = packing_order_cost_items.report_category_id
  );

-- 5. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
