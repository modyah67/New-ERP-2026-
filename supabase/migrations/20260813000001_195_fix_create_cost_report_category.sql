-- ============================================================================
-- Migration: Fix create_cost_report_category unique constraint violation
-- ============================================================================

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
  ON CONFLICT (name) DO UPDATE 
    SET scope = CASE 
      WHEN cost_report_categories.scope != EXCLUDED.scope THEN 'both' 
      ELSE cost_report_categories.scope 
    END
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_cost_report_category(text, text) TO authenticated;
