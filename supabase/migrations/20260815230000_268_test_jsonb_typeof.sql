BEGIN;

CREATE OR REPLACE FUNCTION public.test_jsonb_typeof()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_notes JSONB;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = 1;
  v_notes := v_order.notes;
  
  RETURN json_build_object(
    'original_typeof', jsonb_typeof(v_notes),
    'is_string', jsonb_typeof(v_notes) = 'string',
    'parsed', (v_notes#>>'{}')::jsonb,
    'has_materials', ((v_notes#>>'{}')::jsonb) ? 'materials'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('error', SQLERRM);
END;
$$;

COMMIT;
