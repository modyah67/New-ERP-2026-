-- ============================================================================
-- Function & Trigger: sync_packing_order_costs_to_export_shipments
-- Purpose: Automatically synchronize updated packing order carton costs
--          to linked export shipment items, shipment cost items, and shipments.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_packing_order_costs_to_export_shipments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment RECORD;
  v_new_cost NUMERIC;
BEGIN
  v_new_cost := COALESCE(NEW.packing_cost_per_carton, 0);

  IF TG_OP = 'UPDATE' AND (OLD.packing_cost_per_carton IS NOT DISTINCT FROM NEW.packing_cost_per_carton) THEN
    RETURN NEW;
  END IF;

  IF v_new_cost <= 0 THEN
    RETURN NEW;
  END IF;

  -- 1. Update export_shipment_items prices linked to this packing order
  UPDATE public.export_shipment_items
  SET price = v_new_cost,
      amount = ROUND(quantity * v_new_cost, 2)
  WHERE packing_order_id = NEW.id;

  -- 2. Update read-only packing cost items in shipment_cost_items
  UPDATE public.shipment_cost_items sci
  SET unit_price = v_new_cost
  FROM public.export_shipment_items esi
  WHERE esi.shipment_id::text = sci.shipment_id::text
    AND esi.packing_order_id = NEW.id
    AND sci.category = 'packing';

  -- 3. Recalculate cost_per_carton & total_landed_cost for affected export_shipments
  FOR v_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.export_shipment_items
    WHERE packing_order_id = NEW.id
  LOOP
    UPDATE public.export_shipments s
    SET cost_per_carton = COALESCE((
          SELECT ROUND(SUM(esi.quantity * esi.price) / GREATEST(1, SUM(esi.quantity)), 2)
          FROM public.export_shipment_items esi
          WHERE esi.shipment_id::text = s.id::text
        ), s.cost_per_carton),
        total_landed_cost = COALESCE((
          SELECT ROUND(SUM(esi.quantity * esi.price), 2)
          FROM public.export_shipment_items esi
          WHERE esi.shipment_id::text = s.id::text
        ), 0) + COALESCE((
          SELECT ROUND(SUM(sci.total_price), 2)
          FROM public.shipment_cost_items sci
          WHERE sci.shipment_id::text = s.id::text
            AND sci.category <> 'packing'
        ), 0),
        updated_at = now()
    WHERE s.id::text = v_shipment.shipment_id::text;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_packing_order_costs ON public.packing_orders;
CREATE TRIGGER trg_sync_packing_order_costs
AFTER UPDATE OF packing_cost_per_carton ON public.packing_orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_packing_order_costs_to_export_shipments();
