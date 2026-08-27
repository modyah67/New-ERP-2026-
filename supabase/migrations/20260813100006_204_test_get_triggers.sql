CREATE OR REPLACE FUNCTION test_get_triggers() RETURNS jsonb AS $$
BEGIN
    RETURN (SELECT jsonb_agg(trigger_name) FROM information_schema.triggers WHERE event_object_table = 'packing_orders');
END;
$$ LANGUAGE plpgsql;
