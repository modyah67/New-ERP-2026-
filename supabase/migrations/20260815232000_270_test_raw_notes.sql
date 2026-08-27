BEGIN;

CREATE OR REPLACE FUNCTION public.test_raw_notes()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notes text;
BEGIN
  SELECT notes::text INTO v_notes FROM public.packing_orders WHERE id = 1;
  RETURN v_notes;
END;
$$;

COMMIT;
