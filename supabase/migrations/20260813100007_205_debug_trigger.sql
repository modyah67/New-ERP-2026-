CREATE OR REPLACE FUNCTION protect_completed_packing_order()
RETURNS trigger AS $$
DECLARE
    changed_fields text := '';
BEGIN
  IF OLD.status = 'completed' AND NEW.status = 'completed' THEN
    IF OLD.carton_count IS DISTINCT FROM NEW.carton_count THEN changed_fields := changed_fields || 'carton_count, '; END IF;
    IF OLD.net_weight_per_carton IS DISTINCT FROM NEW.net_weight_per_carton THEN changed_fields := changed_fields || 'net_weight_per_carton, '; END IF;
    IF OLD.gross_weight_per_carton IS DISTINCT FROM NEW.gross_weight_per_carton THEN changed_fields := changed_fields || 'gross_weight_per_carton, '; END IF;
    IF OLD.total_net_weight IS DISTINCT FROM NEW.total_net_weight THEN changed_fields := changed_fields || 'total_net_weight, '; END IF;
    IF OLD.total_gross_weight IS DISTINCT FROM NEW.total_gross_weight THEN changed_fields := changed_fields || 'total_gross_weight, '; END IF;
    IF OLD.fruit_type_id IS DISTINCT FROM NEW.fruit_type_id THEN changed_fields := changed_fields || 'fruit_type_id, '; END IF;
    IF OLD.batch_id IS DISTINCT FROM NEW.batch_id THEN changed_fields := changed_fields || 'batch_id, '; END IF;
    IF OLD.packing_cost_per_carton IS DISTINCT FROM NEW.packing_cost_per_carton THEN changed_fields := changed_fields || 'packing_cost_per_carton, '; END IF;
    IF OLD.total_packing_cost IS DISTINCT FROM NEW.total_packing_cost THEN changed_fields := changed_fields || 'total_packing_cost, '; END IF;

    IF changed_fields <> '' THEN
      RAISE EXCEPTION 'Cannot modify inventory-affecting fields of a completed packing order (ID: %). Changed fields: %. Must change status to draft first.', OLD.id, changed_fields;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
