-- ============================================================================
-- Migration: Unify cost report categories
-- Step 1: Add scope column, seed data, create CRUD RPCs
-- ============================================================================

-- 1. Add scope column (nullable first, then set default, then NOT NULL)
ALTER TABLE public.cost_report_categories
  ADD COLUMN IF NOT EXISTS scope text NOT NULL DEFAULT 'both';

COMMENT ON COLUMN public.cost_report_categories.scope IS
  'Controls which screens show this category: packing=order costs, shipment=shipment costing, both=both';

-- 2. Seed data: merge all hardcoded categories from packing_order_form_page
--    and shipment_costing_page into cost_report_categories.
--    Use ON CONFLICT (name) DO NOTHING to avoid duplicating if re-run.

-- Packing-only categories (from packing_order_form_page.dart _costCategoryLabel)
INSERT INTO cost_report_categories (name, scope, is_system, type) VALUES
  ('مواد تعبئة',     'packing',  true, 'direct'),
  ('تكاليف تصدير',  'packing',  true, 'direct'),
  ('تكلفة الفاكهة', 'packing',  true, 'direct'),
  ('عمالة',         'packing',  true, 'direct'),
  ('ديزل',          'packing',  true, 'direct'),
  ('أجرة زراعية',   'packing',  true, 'direct'),
  ('تبريد',         'packing',  true, 'direct'),
  ('ليبل',          'packing',  true, 'direct'),
  ('استيكر',        'packing',  true, 'direct')
ON CONFLICT (name) DO NOTHING;

-- Shipment-only categories (from shipment_costing_page.dart _systemCategories)
INSERT INTO cost_report_categories (name, scope, is_system, type) VALUES
  ('المحاصيل',            'shipment', true, 'direct'),
  ('تخليص جمركي',        'shipment', true, 'direct'),
  ('الشحن',               'shipment', true, 'direct'),
  ('تعبئة وتغليف إضافية','shipment', true, 'direct')
ON CONFLICT (name) DO NOTHING;

-- Both-screen categories (shared between packing + shipment)
INSERT INTO cost_report_categories (name, scope, is_system, type) VALUES
  ('تعبئة وتغليف',  'both', true, 'direct'),
  ('لوجستيك ونقل',  'both', true, 'direct'),
  ('مصاريف إدارية',  'both', true, 'direct'),
  ('أخرى',          'both', true, 'direct')
ON CONFLICT (name) DO NOTHING;

-- 3. RPC: List cost report categories (with optional scope filter)
CREATE OR REPLACE FUNCTION public.list_cost_report_categories(
  p_scope text DEFAULT NULL
)
RETURNS SETOF cost_report_categories
LANGUAGE sql STABLE
AS $$
  SELECT *
  FROM cost_report_categories
  WHERE (p_scope IS NULL OR scope = p_scope OR scope = 'both')
  ORDER BY name;
$$;

GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(text) TO authenticated;

-- 4. RPC: Create cost report category
CREATE OR REPLACE FUNCTION public.create_cost_report_category(
  p_name  text,
  p_scope text DEFAULT 'both'
)
RETURNS cost_report_categories
LANGUAGE plpgsql
AS $$
DECLARE
  v_row cost_report_categories;
BEGIN
  INSERT INTO cost_report_categories (name, scope, is_system, type)
  VALUES (p_name, p_scope, false, 'direct')
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_cost_report_category(text, text) TO authenticated;

-- 5. RPC: Update cost report category
CREATE OR REPLACE FUNCTION public.update_cost_report_category(
  p_id    integer,
  p_name  text DEFAULT NULL,
  p_scope text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE cost_report_categories
  SET name  = COALESCE(p_name, name),
      scope = COALESCE(p_scope, scope)
  WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_cost_report_category(integer, text, text) TO authenticated;

-- 6. RPC: Delete cost report category (only non-system ones)
CREATE OR REPLACE FUNCTION public.delete_cost_report_category(
  p_id integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM cost_report_categories WHERE id = p_id AND is_system = true) THEN
    RAISE EXCEPTION 'لا يمكن حذف تصنيف نظام مدمج';
  END IF;

  DELETE FROM cost_report_categories WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_cost_report_category(integer) TO authenticated;
