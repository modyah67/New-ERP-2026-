-- Compute actual stock per fruit type from station_product_batches via lot_receipts
-- This is the authoritative source, not the view which matches by product_name

CREATE OR REPLACE FUNCTION public.rpc_get_stock_by_fruit_type()
RETURNS TABLE(fruit_type_id bigint, total_qty double precision)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lr.fruit_type_id, SUM(spb.remaining_quantity)::double precision AS total_qty
  FROM station_product_batches spb
  JOIN lot_receipts lr ON lr.lot_number = spb.product_code
  WHERE spb.remaining_quantity > 0
  GROUP BY lr.fruit_type_id
  HAVING SUM(spb.remaining_quantity) > 0;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_stock_by_fruit_type() TO authenticated;

NOTIFY pgrst, 'reload schema';
