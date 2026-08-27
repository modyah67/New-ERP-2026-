-- Fix rpc_process_lot_receipt: always create a NEW batch per lot
-- Previously it used UPSERT which merged batches with same (source_date, station, product, supplier)
-- Now each lot receipt always gets its own batch row

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'rpc_process_lot_receipt'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    RAISE NOTICE 'Dropped: %', r.sig;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION rpc_process_lot_receipt(
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

  v_batch_qty := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, v_total_graded, 0);

  v_unit_cost := COALESCE(NULLIF(p_unit_cost_kg, 0), v_lot.fruit_cost_per_kg, 0);

  IF v_lot.supplier_id IS NOT NULL THEN
    SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;
  END IF;
  v_supplier_name := COALESCE(v_supplier_name, '');

  INSERT INTO station_product_batches (
    station_id, product_name, product_code, quantity, remaining_quantity,
    unit_cost, currency, exchange_rate, source_type, source_date, supplier_name
  ) VALUES (
    v_lot.station_id, v_lot.product_name, v_lot.lot_number, v_batch_qty, v_batch_qty,
    v_unit_cost, COALESCE(v_lot.currency, 'EGP'), COALESCE(v_lot.exchange_rate, 1.0),
    'lot_receipt', v_lot.created_at, v_supplier_name
  ) RETURNING id INTO v_batch_id;

  INSERT INTO station_products (station_id, product_name, product_code, quantity)
  VALUES (
    v_lot.station_id,
    v_lot.product_name,
    v_lot.lot_number,
    v_batch_qty
  )
  ON CONFLICT (station_id, product_name) DO UPDATE SET
    quantity = (
      SELECT COALESCE(SUM(remaining_quantity), 0)
      FROM station_product_batches
      WHERE station_id = v_lot.station_id
        AND product_name = v_lot.product_name
    ),
    product_code = EXCLUDED.product_code,
    updated_at = now();

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

GRANT EXECUTE ON FUNCTION rpc_process_lot_receipt(BIGINT, NUMERIC) TO authenticated;

NOTIFY pgrst, 'reload schema';
