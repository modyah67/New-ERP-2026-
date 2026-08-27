-- Migration 377: Fix Lot Receipt inserting ghost station products
-- Resolves the issue where processing a lot creates a "material" station_product row instead of a "fruit" row

BEGIN;

-- 1. Fix the RPC to properly pass item_type and fruit_type_id
CREATE OR REPLACE FUNCTION public.rpc_process_lot_receipt(
  p_lot_id BIGINT,
  p_unit_cost_kg NUMERIC DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lot RECORD;
  v_total_graded NUMERIC := 0;
  v_batch_id INTEGER;
  v_batch_qty NUMERIC;
  v_unit_cost NUMERIC;
  v_supplier_name TEXT;
  v_unit TEXT := 'kg';
BEGIN
  SELECT * INTO v_lot
  FROM lot_receipts
  WHERE id = p_lot_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'اللوط غير موجود');
  END IF;

  SELECT COALESCE(SUM(weight_kg), 0)
  INTO v_total_graded
  FROM lot_grading_results
  WHERE lot_id = p_lot_id
    AND grade IN ('A', 'B', 'C')
    AND weight_kg > 0;

  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' AND COALESCE(v_lot.carton_count, 0) > 0 THEN
    v_batch_qty := v_lot.carton_count;
    v_unit_cost := COALESCE(NULLIF(v_lot.price_per_carton, 0), NULLIF(p_unit_cost_kg, 0), v_lot.fruit_cost_per_kg, 0);
    v_unit := 'carton';
  ELSE
    v_batch_qty := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, v_total_graded, 0);
    v_unit_cost := COALESCE(NULLIF(p_unit_cost_kg, 0), v_lot.fruit_cost_per_kg, 0);
    v_unit := 'kg';
  END IF;

  IF v_lot.supplier_id IS NOT NULL THEN
    SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;
  END IF;
  v_supplier_name := COALESCE(v_supplier_name, '');

  INSERT INTO station_product_batches (
    station_id, product_name, product_code, quantity, remaining_quantity,
    unit_cost, currency, exchange_rate, source_type, source_date, supplier_name,
    item_type, fruit_type_id
  ) VALUES (
    v_lot.station_id, v_lot.product_name, v_lot.lot_number, v_batch_qty, v_batch_qty,
    v_unit_cost, COALESCE(v_lot.currency, 'EGP'), COALESCE(v_lot.exchange_rate, 1.0),
    'lot_receipt', v_lot.created_at, v_supplier_name,
    'fruit', v_lot.fruit_type_id
  ) RETURNING id INTO v_batch_id;

  PERFORM public.upsert_station_product(
    v_lot.station_id,
    'fruit',
    NULL,
    v_lot.fruit_type_id,
    v_lot.product_name,
    v_lot.lot_number,
    v_batch_qty,
    v_unit
  );

  UPDATE lot_receipts
  SET status = 'sorting'
  WHERE id = p_lot_id AND status = 'received';

  RETURN json_build_object(
    'success', true,
    'lot_id', p_lot_id,
    'lot_number', v_lot.lot_number,
    'station_id', v_lot.station_id,
    'product_name', v_lot.product_name,
    'total_graded', v_total_graded,
    'batch_id', v_batch_id,
    'batch_qty', v_batch_qty
  );
END;
$$;

-- 2. Repair existing data: link any ghost batches properly
UPDATE public.station_product_batches spb
SET item_type = 'fruit',
    fruit_type_id = lr.fruit_type_id
FROM public.lot_receipts lr
WHERE spb.source_type = 'lot_receipt'
  AND spb.product_code = lr.lot_number
  AND (spb.item_type IS NULL OR spb.fruit_type_id IS NULL);

-- 3. Rebuild station_products to eliminate any ghosts that were created
DELETE FROM public.station_products;

INSERT INTO public.station_products (station_id, item_type, raw_material_id, product_name, product_code, quantity, unit)
SELECT
  spb.station_id,
  'material',
  spb.raw_material_id,
  rm.name,
  COALESCE(rm.code, ''),
  COALESCE(SUM(spb.remaining_quantity), 0),
  COALESCE(MAX(rm.unit), 'piece')
FROM public.station_product_batches spb
JOIN public.raw_materials rm ON rm.id = spb.raw_material_id
WHERE spb.item_type = 'material' AND spb.raw_material_id IS NOT NULL
GROUP BY spb.station_id, spb.raw_material_id, rm.name, rm.code
HAVING COALESCE(SUM(spb.remaining_quantity), 0) > 0;

INSERT INTO public.station_products (station_id, item_type, fruit_type_id, product_name, product_code, quantity, unit)
SELECT
  spb.station_id,
  'fruit',
  spb.fruit_type_id,
  ft.name,
  COALESCE(ft.code, ''),
  COALESCE(SUM(spb.remaining_quantity), 0),
  'kg'
FROM public.station_product_batches spb
JOIN public.fruit_types ft ON ft.id = spb.fruit_type_id
WHERE spb.item_type = 'fruit' AND spb.fruit_type_id IS NOT NULL
GROUP BY spb.station_id, spb.fruit_type_id, ft.name, ft.code
HAVING COALESCE(SUM(spb.remaining_quantity), 0) > 0;

COMMIT;

NOTIFY pgrst, 'reload schema';
