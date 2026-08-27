CREATE OR REPLACE FUNCTION protect_completed_packing_order()
RETURNS trigger AS $$
BEGIN
  -- If both old and new status are 'completed', prevent modification of inventory-affecting fields
  IF OLD.status = 'completed' AND NEW.status = 'completed' THEN
    -- Note: We exclude generated columns (total_net_weight, total_gross_weight) 
    -- because in a BEFORE trigger their NEW value might be NULL or uncomputed, 
    -- causing false positives with IS DISTINCT FROM.
    IF OLD.carton_count IS DISTINCT FROM NEW.carton_count OR
       OLD.net_weight_per_carton IS DISTINCT FROM NEW.net_weight_per_carton OR
       OLD.gross_weight_per_carton IS DISTINCT FROM NEW.gross_weight_per_carton OR
       OLD.fruit_type_id IS DISTINCT FROM NEW.fruit_type_id OR
       OLD.batch_id IS DISTINCT FROM NEW.batch_id OR
       OLD.packing_cost_per_carton IS DISTINCT FROM NEW.packing_cost_per_carton OR
       OLD.total_packing_cost IS DISTINCT FROM NEW.total_packing_cost THEN
      
      RAISE EXCEPTION 'Cannot modify inventory-affecting fields of a completed packing order (ID: %). Must change status to draft first.', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
