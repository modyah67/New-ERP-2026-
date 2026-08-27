CREATE OR REPLACE FUNCTION test_get_dists() RETURNS jsonb AS $$
BEGIN
    RETURN (SELECT jsonb_agg(row_to_json(d)) FROM shareholder_profit_distributions d);
END;
$$ LANGUAGE plpgsql;
