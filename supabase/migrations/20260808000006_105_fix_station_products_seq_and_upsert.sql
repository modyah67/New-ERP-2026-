-- Migration 105: Fix station_products duplicate key after master reset
-- The error "duplicate key value violates unique constraint station_products_pkey"
-- means the BIGINT IDENTITY sequence is out of sync with actual data.
-- This happens after master_client_handover_reset.sql re-inserts data.

-- 1. Reset station_products id sequence to max(id)
SELECT setval(
  pg_get_serial_sequence('public.station_products', 'id'),
  (SELECT COALESCE(MAX(id), 0) FROM public.station_products)
);

-- 2. Ensure upsert_station_product_quantity is the latest ON CONFLICT version
-- (Migration 078 already has ON CONFLICT, but re-create to be safe)
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
BEGIN
  IF p_delta = 0 THEN
    RETURN;
  END IF;

  INSERT INTO station_products (station_id, product_name, product_code, quantity)
  VALUES (p_station_id, p_product_name, p_product_code, p_delta)
  ON CONFLICT (station_id, product_name)
  DO UPDATE SET
    quantity = station_products.quantity + p_delta,
    product_code = COALESCE(NULLIF(p_product_code, ''), station_products.product_code);

  DELETE FROM station_products
  WHERE station_id = p_station_id AND product_name = p_product_name AND quantity <= 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_station_product_quantity(BIGINT, TEXT, TEXT, INT) TO authenticated;

-- 3. Fix all other BIGINT IDENTITY sequences that might be out of sync
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT
      t.relname AS table_name,
      a.attname AS column_name,
      pg_get_serial_sequence('public.' || t.relname, a.attname) AS seq_name
    FROM pg_class t
    JOIN pg_attribute a ON a.attrelid = t.oid
    WHERE t.relkind = 'r'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND pg_get_serial_sequence('public.' || t.relname, a.attname) IS NOT NULL
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  LOOP
    BEGIN
      EXECUTE format(
        'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM public.%I), 1))',
        r.seq_name, r.column_name, r.table_name
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not reset sequence for %.%: %', r.table_name, r.column_name, SQLERRM;
    END;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
