CREATE OR REPLACE FUNCTION public.temp_fetch_pg_proc()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def
  FROM pg_proc 
  WHERE proname = 'get_supplier_true_balances';
  
  RETURN v_def;
END;
$$;
GRANT EXECUTE ON FUNCTION public.temp_fetch_pg_proc() TO authenticated;
