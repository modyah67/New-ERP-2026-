-- Fix upsert_station_product_quantity: match on both product_code AND product_name
-- Without this, if a raw material and fruit type share the same code,
-- buying the raw material just increments the fruit type's quantity instead
-- of creating a separate entry.

CREATE OR REPLACE FUNCTION public.upsert_station_product_quantity(
  p_station_id BIGINT,
  p_product_name TEXT,
  p_product_code TEXT,
  p_delta INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_id BIGINT;
  v_cur_qty INT;
BEGIN
  SELECT id, quantity INTO v_existing_id, v_cur_qty
  FROM station_products
  WHERE station_id = p_station_id
    AND product_code = p_product_code
    AND product_name = p_product_name
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    v_cur_qty := COALESCE(v_cur_qty, 0) + p_delta;
    IF v_cur_qty <= 0 THEN
      DELETE FROM station_products WHERE id = v_existing_id;
    ELSE
      UPDATE station_products SET quantity = v_cur_qty WHERE id = v_existing_id;
    END IF;
  ELSE
    IF p_delta > 0 THEN
      INSERT INTO station_products (station_id, product_name, product_code, quantity)
      VALUES (p_station_id, p_product_name, p_product_code, p_delta);
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_station_product_quantity(BIGINT, TEXT, TEXT, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';
