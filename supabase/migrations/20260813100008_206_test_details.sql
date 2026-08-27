CREATE OR REPLACE FUNCTION test_update_po_details() RETURNS jsonb AS $$
DECLARE
    v_old RECORD;
    v_new RECORD;
BEGIN
    SELECT * INTO v_old FROM packing_orders WHERE id = 2;
    UPDATE packing_orders SET sold_cartons = COALESCE(sold_cartons, 0) WHERE id = 2 RETURNING * INTO v_new;
    RETURN jsonb_build_object('old_net', v_old.total_net_weight, 'new_net', v_new.total_net_weight, 'old_gross', v_old.total_gross_weight, 'new_gross', v_new.total_gross_weight);
END;
$$ LANGUAGE plpgsql;
