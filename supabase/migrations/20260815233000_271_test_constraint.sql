BEGIN;

CREATE OR REPLACE FUNCTION public.test_constraint()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_res text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_res FROM pg_constraint WHERE conname = 'packing_order_cost_items_category_check';
  RETURN v_res;
END;
$$;

COMMIT;
