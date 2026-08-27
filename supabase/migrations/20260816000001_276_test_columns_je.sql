BEGIN;

CREATE OR REPLACE FUNCTION public.test_columns_je()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_res json;
BEGIN
  SELECT json_agg(column_name) INTO v_res 
  FROM information_schema.columns 
  WHERE table_name = 'journal_entries';
  RETURN v_res;
END;
$$;

COMMIT;
