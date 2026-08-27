-- Fix sequence out of sync for packing_order_lines
DO $$
DECLARE
    v_max_id BIGINT;
BEGIN
    SELECT COALESCE(MAX(id), 0) INTO v_max_id FROM public.packing_order_lines;
    IF v_max_id > 0 THEN
        PERFORM setval(pg_get_serial_sequence('public.packing_order_lines', 'id'), v_max_id);
    ELSE
        PERFORM setval(pg_get_serial_sequence('public.packing_order_lines', 'id'), 1, false);
    END IF;
END $$;
