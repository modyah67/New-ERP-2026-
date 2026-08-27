-- Backfill: refresh ALL packing orders that have stale prices
-- This is needed because the previous rpc_refresh_packing_order_prices
-- was not multiplying by exchange_rate, producing wrong costs.

DO $$
DECLARE
  v_order RECORD;
  v_result JSONB;
BEGIN
  FOR v_order IN
    SELECT id FROM packing_orders
    WHERE status IN ('confirmed', 'packed', 'completed')
    ORDER BY id
  LOOP
    BEGIN
      v_result := rpc_refresh_packing_order_prices(v_order.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Failed to refresh packing order %: %', v_order.id, SQLERRM;
    END;
  END LOOP;
END;
$$;
