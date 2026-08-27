-- Migration 309: Fix crop carton batch quantity and price calculations
-- Ensures that when crops are purchased/managed in carton mode:
-- 1. Batch quantity in station_product_batches and station_products represents carton count.
-- 2. Batch unit_cost represents price per carton directly (no division by 2 or net weight).
-- 3. All transferred batches across all warehouses are updated with the exact unit price on price edit.

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
    unit_cost, currency, exchange_rate, source_type, source_date, supplier_name
  ) VALUES (
    v_lot.station_id, v_lot.product_name, v_lot.lot_number, v_batch_qty, v_batch_qty,
    v_unit_cost, COALESCE(v_lot.currency, 'EGP'), COALESCE(v_lot.exchange_rate, 1.0),
    'lot_receipt', v_lot.created_at, v_supplier_name
  ) RETURNING id INTO v_batch_id;

  INSERT INTO station_products (station_id, product_name, product_code, quantity, unit)
  VALUES (
    v_lot.station_id,
    v_lot.product_name,
    v_lot.lot_number,
    v_batch_qty,
    v_unit
  )
  ON CONFLICT (station_id, product_name) DO UPDATE SET
    quantity = (
      SELECT COALESCE(SUM(remaining_quantity), 0)
      FROM station_product_batches
      WHERE station_id = v_lot.station_id
        AND product_name = v_lot.product_name
    ),
    unit = v_unit,
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

CREATE OR REPLACE FUNCTION public.rpc_edit_lot_price(
    p_lot_id BIGINT,
    p_new_price NUMERIC,
    p_exchange_rate NUMERIC,
    p_currency TEXT,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_lot RECORD;
    v_new_total_cost NUMERIC;
    v_old_total_cost NUMERIC;
    v_effective_cost NUMERIC;
    v_total_graded NUMERIC := 0;
    v_grading RECORD;
    v_net_wt NUMERIC;
    v_new_fruit_cost_per_kg NUMERIC;
    v_new_batch_unit_cost NUMERIC;
    v_batch_record RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'غير مصرح لك بتعديل سعر المحصول';
    END IF;

    SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'رقم المحصول غير موجود (id=%)', p_lot_id;
    END IF;

    v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
    v_net_wt := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

    IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
      v_new_total_cost := COALESCE(v_lot.carton_count, 0) * p_new_price;
      v_new_fruit_cost_per_kg := CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END;
      v_new_batch_unit_cost := p_new_price; -- Unit cost for carton batches is price per carton (e.g. 5 USD)
    ELSE
      IF COALESCE(v_lot.gross_weight_kg, 0) > 0 THEN
        v_new_total_cost := v_lot.gross_weight_kg * p_new_price;
        v_new_fruit_cost_per_kg := CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END;
      ELSE
        v_new_total_cost := v_net_wt * p_new_price;
        v_new_fruit_cost_per_kg := p_new_price;
      END IF;
      v_new_batch_unit_cost := v_new_fruit_cost_per_kg; -- Unit cost for weight batches is price per kg
    END IF;

    -- Update lot receipt
    UPDATE lot_receipts
    SET price_per_carton = CASE WHEN COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN p_new_price ELSE price_per_carton END,
        fruit_cost_per_kg = v_new_fruit_cost_per_kg,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;

    -- Sync GL entries
    IF v_lot.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(p_lot_id, 'UPDATE');
    END IF;

    -- Update graded stock batches (inventory)
    SELECT COALESCE(SUM(weight_kg), 0) INTO v_total_graded
    FROM lot_grading_results
    WHERE lot_id = p_lot_id;

    IF v_total_graded > 0 THEN
      v_effective_cost := v_new_total_cost / v_total_graded;
      FOR v_grading IN (SELECT stock_batch_id FROM lot_grading_results WHERE lot_id = p_lot_id AND stock_batch_id IS NOT NULL) LOOP
        UPDATE stock_batches
        SET purchase_cost = v_effective_cost, average_cost = v_effective_cost
        WHERE id = v_grading.stock_batch_id;
      END LOOP;
    END IF;

    -- Update ALL station_product_batches across all warehouses (including transferred batches)
    FOR v_batch_record IN 
        SELECT id FROM station_product_batches 
        WHERE product_code = v_lot.lot_number
    LOOP
        UPDATE station_product_batches
        SET unit_cost = v_new_batch_unit_cost,
            exchange_rate = p_exchange_rate,
            currency = p_currency
        WHERE id = v_batch_record.id;
        
        PERFORM public.rpc_flag_packing_orders_for_refresh('fruit', v_batch_record.id);
    END LOOP;

    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_lot_receipt(BIGINT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;
