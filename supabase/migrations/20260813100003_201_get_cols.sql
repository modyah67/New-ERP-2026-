CREATE OR REPLACE FUNCTION rpc_get_cols() RETURNS jsonb AS $$
BEGIN
  RETURN (SELECT jsonb_agg(column_name) FROM information_schema.columns WHERE table_name = 'export_shipments');
END;
$$ LANGUAGE plpgsql;
