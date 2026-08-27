BEGIN;

CREATE OR REPLACE FUNCTION public.test_loop()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notes JSONB := '{"cost_items": [{"id": 1}, {"id": 2}]}'::jsonb;
  v_el JSONB;
  v_res INTEGER := 0;
BEGIN
  FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items') LOOP
    v_res := v_res + (v_el->>'id')::integer;
  END LOOP;
  RETURN json_build_object('success', true, 'res', v_res);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

COMMIT;
