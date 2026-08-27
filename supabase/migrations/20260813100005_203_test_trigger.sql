CREATE OR REPLACE FUNCTION test_update_po() RETURNS void AS $$
BEGIN
    UPDATE packing_orders SET sold_cartons = COALESCE(sold_cartons, 0) WHERE id = 2;
END;
$$ LANGUAGE plpgsql;
