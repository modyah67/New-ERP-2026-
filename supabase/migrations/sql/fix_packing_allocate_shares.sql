-- ============================================================================
-- Fix: Define _packing_allocate_shares helper function
-- Required by rpc_confirm_packing_order when allocating overhead across lines
-- ============================================================================

CREATE OR REPLACE FUNCTION public._packing_allocate_shares(p_method text, p_bases numeric[])
 RETURNS numeric[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_n INT;
  v_total NUMERIC := 0;
  v_shares NUMERIC[];
  i INT;
BEGIN
  v_n := COALESCE(array_length(p_bases, 1), 0);
  IF v_n = 0 THEN
    RETURN ARRAY[]::NUMERIC[];
  END IF;

  FOR i IN 1..v_n LOOP
    v_total := v_total + COALESCE(p_bases[i], 0);
  END LOOP;

  IF v_total <= 0 THEN
    v_shares := ARRAY[]::NUMERIC[];
    FOR i IN 1..v_n LOOP
      v_shares := v_shares || ARRAY[ROUND((1.0 / v_n)::numeric, 8)];
    END LOOP;
    RETURN v_shares;
  END IF;

  v_shares := ARRAY[]::NUMERIC[];
  FOR i IN 1..v_n LOOP
    v_shares := v_shares || ARRAY[ROUND((COALESCE(p_bases[i], 0) / v_total)::numeric, 8)];
  END LOOP;
  RETURN v_shares;
END;
$function$;

GRANT EXECUTE ON FUNCTION public._packing_allocate_shares(text, numeric[]) TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';