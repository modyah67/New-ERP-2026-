-- Migration 20260728185100: Fix rpc_process_lot_receipt to include currency
--
-- The previous migration 20260728140000 was already applied before the
-- currency fix was added. Supabase only runs each migration once.
-- This new migration re-creates the function with currency support.
--
-- Also fixes existing batches that were created with currency='EGP'.

-- ============================================================
-- A. Re-create rpc_process_lot_receipt WITH currency + exchange_rate
-- ============================================================
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

  SELECT id INTO v_batch_id
  FROM station_product_batches
  WHERE source_type = 'lot_receipt'
    AND source_date = v_lot.created_at
    AND station_id = v_lot.station_id
    AND product_name = v_lot.product_name
    AND supplier_name = v_supplier_name
  LIMIT 1;

  IF v_batch_id IS NULL THEN
    INSERT INTO station_product_batches (
      station_id, product_name, product_code, quantity, remaining_quantity,
      unit_cost, currency, exchange_rate, source_type, source_date, supplier_name
    ) VALUES (
      v_lot.station_id, v_lot.product_name, v_lot.lot_number, v_batch_qty, v_batch_qty,
      v_unit_cost, COALESCE(v_lot.currency, 'EGP'), COALESCE(v_lot.exchange_rate, 1.0),
      'lot_receipt', v_lot.created_at, v_supplier_name
    ) RETURNING id INTO v_batch_id;
  ELSE
    UPDATE station_product_batches
    SET quantity = v_batch_qty,
        remaining_quantity = v_batch_qty,
        unit_cost = v_unit_cost,
        currency = COALESCE(v_lot.currency, 'EGP'),
        exchange_rate = COALESCE(v_lot.exchange_rate, 1.0),
        product_code = v_lot.lot_number
    WHERE id = v_batch_id;
  END IF;

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

-- ============================================================
-- B. Fix ALL existing lot_receipt batches: sync currency from supplier
--    This fixes batches that were created by the old RPC without currency.
-- ============================================================
UPDATE station_product_batches spb
SET currency = COALESCE(lr.currency, s.currency, 'EGP'),
    exchange_rate = COALESCE(lr.exchange_rate, 1.0)
FROM lot_receipts lr
LEFT JOIN suppliers s ON s.id = lr.supplier_id
WHERE spb.source_type = 'lot_receipt'
  AND spb.product_name = lr.product_name
  AND spb.station_id = lr.station_id
  AND spb.supplier_name = s.name
  AND (
    spb.currency IS NULL
    OR spb.currency = ''
    OR spb.currency = 'EGP'
  )
  AND COALESCE(lr.currency, s.currency, 'EGP') != 'EGP';

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
