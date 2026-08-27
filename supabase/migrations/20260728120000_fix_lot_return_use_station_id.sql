-- Fix lot return: comprehensive cleanup + correct RPC
-- Drops ALL possible overloaded versions of rpc_process_lot_return

-- Step 1: Drop ALL possible signatures (parameter order matters in PostgreSQL)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN 
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'rpc_process_lot_return'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    RAISE NOTICE 'Dropped: %', r.sig;
  END LOOP;
END $$;

-- Step 2: Create the correct single version
CREATE OR REPLACE FUNCTION public.rpc_process_lot_return(
  p_lot_id BIGINT,
  p_return_quantity NUMERIC,
  p_notes TEXT DEFAULT NULL,
  p_station_id BIGINT DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_product_name TEXT;
  v_unit_cost NUMERIC := 0;
  v_return_value NUMERIC := 0;
  v_remaining_in_batches NUMERIC := 0;
  v_batch RECORD;
  v_qty_to_deduct NUMERIC;
  v_desc TEXT;
  v_target_station BIGINT;
BEGIN
  IF p_return_quantity <= 0 THEN
    RAISE EXCEPTION 'الكمية المرتجعة يجب أن تكون أكبر من الصفر';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول لإتمام المرتجع';
  END IF;

  -- 1. Get lot details + fruit type name
  SELECT lr.*, ft.name AS fruit_type_name
  INTO v_lot
  FROM lot_receipts lr
  LEFT JOIN fruit_types ft ON ft.id = lr.fruit_type_id
  WHERE lr.id = p_lot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الاستلام غير موجود';
  END IF;

  -- Use lot_receipts.product_name (matches what rpc_process_lot_receipt stored in station_products)
  -- Fall back to fruit_types.name, then to a default
  v_product_name := COALESCE(
    NULLIF(v_lot.product_name, ''),
    NULLIF(v_lot.fruit_type_name, ''),
    'منتج'
  );

  -- Use the passed station_id if provided, otherwise fall back to lot_receipts.station_id
  v_target_station := COALESCE(p_station_id, v_lot.station_id);

  -- Cost: use original gross price
  v_unit_cost := COALESCE(v_lot.total_fruit_cost / NULLIF(v_lot.gross_weight_kg, 0), 0);
  v_return_value := p_return_quantity * v_unit_cost;

  -- 2. Check remaining quantity at the target station
  SELECT COALESCE(SUM(remaining_quantity), 0)
  INTO v_remaining_in_batches
  FROM station_product_batches
  WHERE product_code = v_lot.lot_number
    AND station_id = v_target_station;

  IF v_remaining_in_batches < p_return_quantity THEN
    RAISE EXCEPTION 'الكمية المرتجعة (% أكبر من الكمية المتبقية (%) في المحطة', p_return_quantity, v_remaining_in_batches;
  END IF;

  -- 3. Deduct from station_product_batches (FIFO)
  v_qty_to_deduct := p_return_quantity;

  FOR v_batch IN
    SELECT id, remaining_quantity
    FROM station_product_batches
    WHERE product_code = v_lot.lot_number
      AND station_id = v_target_station
      AND remaining_quantity > 0
    ORDER BY id ASC
    FOR UPDATE
  LOOP
    IF v_qty_to_deduct <= 0 THEN EXIT; END IF;

    IF v_batch.remaining_quantity >= v_qty_to_deduct THEN
      UPDATE station_product_batches
      SET remaining_quantity = remaining_quantity - v_qty_to_deduct
      WHERE id = v_batch.id;
      v_qty_to_deduct := 0;
    ELSE
      v_qty_to_deduct := v_qty_to_deduct - v_batch.remaining_quantity;
      UPDATE station_product_batches
      SET remaining_quantity = 0
      WHERE id = v_batch.id;
    END IF;
  END LOOP;

  -- 4. Update station_products quantity
  UPDATE station_products
  SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
      updated_at = now()
  WHERE station_id = v_target_station
    AND product_name = v_product_name;

  -- If no station_products row was found by exact name, try fruit_type_name
  IF NOT FOUND THEN
    UPDATE station_products
    SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
        updated_at = now()
    WHERE station_id = v_target_station
      AND product_name = v_lot.fruit_type_name;
  END IF;

  -- Delete zero-quantity station products
  DELETE FROM station_products
  WHERE station_id = v_target_station
    AND (product_name = v_product_name OR product_name = v_lot.fruit_type_name)
    AND COALESCE(quantity, 0) <= 0;

  -- 5. Insert lot return record
  INSERT INTO lot_returns (
    lot_receipt_id, supplier_id, station_id, returned_quantity, return_value, notes, created_by
  ) VALUES (
    v_lot.id, v_lot.supplier_id, v_target_station, p_return_quantity, v_return_value, p_notes, p_user_id
  );

  -- 6. Supplier Financials
  IF v_lot.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_return_value,
        updated_at = now()
    WHERE id = v_lot.supplier_id;

    v_desc := 'مرتجع محصول ' || v_lot.lot_number || ' - ' || v_product_name;
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, reference_type, reference_text, description, created_by
    ) VALUES (
      'supplier', v_lot.supplier_id::TEXT, 'debit', v_return_value, 'lot_return', v_lot.id::TEXT, v_desc, p_user_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'returned_quantity', p_return_quantity,
    'return_value', v_return_value,
    'unit_cost_used', v_unit_cost,
    'station_id', v_target_station
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_lot_return(BIGINT, NUMERIC, TEXT, BIGINT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
