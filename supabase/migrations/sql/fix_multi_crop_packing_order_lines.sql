-- ==============================================================================
-- Migration: Fix Multi-Crop Packing Order Lines & Export Shipment Separation
-- ==============================================================================

-- 1. Ensure columns exist on public.packing_order_lines
ALTER TABLE IF EXISTS public.packing_order_lines 
    ADD COLUMN IF NOT EXISTS fruit_type_id INTEGER,
    ADD COLUMN IF NOT EXISTS product_name TEXT,
    ADD COLUMN IF NOT EXISTS source_lot_id TEXT,
    ADD COLUMN IF NOT EXISTS batch_id TEXT,
    ADD COLUMN IF NOT EXISTS quantity NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS carton_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS net_weight_per_carton NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS gross_weight_per_carton NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_net_weight NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_gross_weight NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS unit_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS raw_material_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS expected_loss_percent NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS waste_weight_kg NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS waste_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sorted_weight_kg NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sorting_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS specific_packaging_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS allocated_shared_packaging NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS allocated_cost_items NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS final_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS final_unit_cost NUMERIC DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sold_cartons INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS notes JSONB DEFAULT '{}'::jsonb;

-- 2. RPC: rpc_save_packing_order_lines
-- Saves or updates line items for a packing order atomically
DROP FUNCTION IF EXISTS public.rpc_save_packing_order_lines(bigint, jsonb);

CREATE OR REPLACE FUNCTION public.rpc_save_packing_order_lines(
  p_packing_order_id bigint,
  p_lines jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_line jsonb;
  v_count int := 0;
  v_line_id bigint;
  v_existing_ids bigint[];
BEGIN
  IF p_packing_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'packing_order_id is required');
  END IF;

  -- Collect incoming line IDs that are already persisted
  SELECT COALESCE(array_agg((elem->>'id')::bigint), ARRAY[]::bigint[])
  INTO v_existing_ids
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) elem
  WHERE elem ? 'id' AND elem->>'id' IS NOT NULL AND elem->>'id' != '';

  -- Delete lines for this order that are not in the incoming payload,
  -- provided they are not referenced in export shipments
  DELETE FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id
    AND id NOT IN (SELECT unnest(v_existing_ids))
    AND id NOT IN (SELECT packing_order_line_id FROM public.export_shipment_items WHERE packing_order_line_id IS NOT NULL);

  IF p_lines IS NOT NULL AND jsonb_array_length(p_lines) > 0 THEN
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
      v_line_id := NULLIF(v_line->>'id', '')::bigint;

      IF v_line_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.packing_order_lines WHERE id = v_line_id AND packing_order_id = p_packing_order_id) THEN
        -- UPDATE existing line
        UPDATE public.packing_order_lines
        SET
          product_id = (NULLIF(v_line->>'product_id', ''))::bigint,
          fruit_type_id = (NULLIF(v_line->>'fruit_type_id', ''))::int,
          product_name = COALESCE(v_line->>'product_name', product_name),
          grade = COALESCE(v_line->>'grade', grade, 'A'),
          source_lot_id = v_line->>'source_lot_id',
          batch_id = v_line->>'batch_id',
          quantity = COALESCE((NULLIF(v_line->>'quantity', ''))::numeric, 0),
          carton_count = COALESCE((NULLIF(v_line->>'carton_count', ''))::int, 0),
          net_weight_per_carton = COALESCE((NULLIF(v_line->>'net_weight_per_carton', ''))::numeric, 0),
          gross_weight_per_carton = COALESCE((NULLIF(v_line->>'gross_weight_per_carton', ''))::numeric, 0),
          total_net_weight = COALESCE((NULLIF(v_line->>'total_net_weight', ''))::numeric, 0),
          total_gross_weight = COALESCE((NULLIF(v_line->>'total_gross_weight', ''))::numeric, 0),
          unit_cost = COALESCE((NULLIF(v_line->>'unit_cost', ''))::numeric, 0),
          raw_material_cost = COALESCE((NULLIF(v_line->>'raw_material_cost', ''))::numeric, 0),
          expected_loss_percent = COALESCE((NULLIF(v_line->>'expected_loss_percent', ''))::numeric, 0),
          waste_weight_kg = COALESCE((NULLIF(v_line->>'waste_weight_kg', ''))::numeric, 0),
          waste_cost = COALESCE((NULLIF(v_line->>'waste_cost', ''))::numeric, 0),
          sorted_weight_kg = COALESCE((NULLIF(v_line->>'sorted_weight_kg', ''))::numeric, 0),
          sorting_cost = COALESCE((NULLIF(v_line->>'sorting_cost', ''))::numeric, 0),
          specific_packaging_cost = COALESCE((NULLIF(v_line->>'specific_packaging_cost', ''))::numeric, 0),
          allocated_shared_packaging = COALESCE((NULLIF(v_line->>'allocated_shared_packaging', ''))::numeric, 0),
          allocated_cost_items = COALESCE((NULLIF(v_line->>'allocated_cost_items', ''))::numeric, 0),
          final_cost = COALESCE((NULLIF(v_line->>'final_cost', ''))::numeric, 0),
          final_unit_cost = COALESCE((NULLIF(v_line->>'final_unit_cost', ''))::numeric, 0),
          notes = COALESCE(v_line->'notes', notes, '{}'::jsonb),
          updated_at = now()
        WHERE id = v_line_id;
      ELSE
        -- INSERT new line
        INSERT INTO public.packing_order_lines (
          packing_order_id,
          product_id,
          fruit_type_id,
          product_name,
          grade,
          source_lot_id,
          batch_id,
          quantity,
          carton_count,
          net_weight_per_carton,
          gross_weight_per_carton,
          total_net_weight,
          total_gross_weight,
          unit_cost,
          raw_material_cost,
          expected_loss_percent,
          waste_weight_kg,
          waste_cost,
          sorted_weight_kg,
          sorting_cost,
          specific_packaging_cost,
          allocated_shared_packaging,
          allocated_cost_items,
          final_cost,
          final_unit_cost,
          sold_cartons,
          notes,
          created_at,
          updated_at
        ) VALUES (
          p_packing_order_id,
          (NULLIF(v_line->>'product_id', ''))::bigint,
          (NULLIF(v_line->>'fruit_type_id', ''))::int,
          COALESCE(v_line->>'product_name', ''),
          COALESCE(v_line->>'grade', 'A'),
          v_line->>'source_lot_id',
          v_line->>'batch_id',
          COALESCE((NULLIF(v_line->>'quantity', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'carton_count', ''))::int, 0),
          COALESCE((NULLIF(v_line->>'net_weight_per_carton', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'gross_weight_per_carton', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'total_net_weight', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'total_gross_weight', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'unit_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'raw_material_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'expected_loss_percent', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'waste_weight_kg', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'waste_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'sorted_weight_kg', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'sorting_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'specific_packaging_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'allocated_shared_packaging', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'allocated_cost_items', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'final_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'final_unit_cost', ''))::numeric, 0),
          COALESCE((NULLIF(v_line->>'sold_cartons', ''))::int, 0),
          COALESCE(v_line->'notes', '{}'::jsonb),
          now(),
          now()
        );
      END IF;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_packing_order_lines(bigint, jsonb) TO authenticated, service_role, anon;

-- 3. Update increment_sold_cartons & decrement_sold_cartons to support optional line_id
CREATE OR REPLACE FUNCTION public.increment_sold_cartons(
  p_packing_order_id integer,
  p_additional integer,
  p_line_id bigint DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.packing_orders
  SET sold_cartons = LEAST(sold_cartons + p_additional, carton_count)
  WHERE id = p_packing_order_id;

  IF p_line_id IS NOT NULL THEN
    UPDATE public.packing_order_lines
    SET sold_cartons = LEAST(sold_cartons + p_additional, carton_count)
    WHERE id = p_line_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_sold_cartons(integer, integer, bigint) TO authenticated, service_role, anon;

CREATE OR REPLACE FUNCTION public.decrement_sold_cartons(
  p_packing_order_id integer,
  p_amount integer,
  p_line_id bigint DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.packing_orders
  SET sold_cartons = GREATEST(sold_cartons - p_amount, 0)
  WHERE id = p_packing_order_id;

  IF p_line_id IS NOT NULL THEN
    UPDATE public.packing_order_lines
    SET sold_cartons = GREATEST(sold_cartons - p_amount, 0)
    WHERE id = p_line_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.decrement_sold_cartons(integer, integer, bigint) TO authenticated, service_role, anon;

-- 4. Trigger to automatically keep sold_cartons synchronized whenever export_shipment_items change
CREATE OR REPLACE FUNCTION public.trg_sync_shipment_items_sold_cartons()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_po_id bigint;
  v_line_id bigint;
BEGIN
  v_po_id := COALESCE(NEW.packing_order_id, OLD.packing_order_id);
  v_line_id := COALESCE(NEW.packing_order_line_id, OLD.packing_order_line_id);

  IF v_po_id IS NOT NULL THEN
    UPDATE public.packing_orders
    SET sold_cartons = COALESCE((
      SELECT SUM(quantity) FROM public.export_shipment_items WHERE packing_order_id = v_po_id
    ), 0)
    WHERE id = v_po_id;
  END IF;

  IF v_line_id IS NOT NULL THEN
    UPDATE public.packing_order_lines
    SET sold_cartons = COALESCE((
      SELECT SUM(quantity) FROM public.export_shipment_items WHERE packing_order_line_id = v_line_id
    ), 0)
    WHERE id = v_line_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_export_shipment_items_sold_cartons ON public.export_shipment_items;
CREATE TRIGGER trg_export_shipment_items_sold_cartons
AFTER INSERT OR UPDATE OR DELETE ON public.export_shipment_items
FOR EACH ROW EXECUTE FUNCTION public.trg_sync_shipment_items_sold_cartons();
