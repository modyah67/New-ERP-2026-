BEGIN;

CREATE OR REPLACE FUNCTION public.test_columns_jel()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_res json;
BEGIN
  SELECT json_agg(column_name) INTO v_res 
  FROM information_schema.columns 
  WHERE table_name = 'journal_entry_lines';
  RETURN v_res;
END;
$$;

COMMIT;
