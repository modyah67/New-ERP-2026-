-- Migration: Engineer Custody Pool Allocation Support
-- When packing costs are confirmed, engineer expenses loaded from custody pool
-- are already settled from employee custodies and do NOT deduct treasury balances again.

CREATE OR REPLACE FUNCTION rpc_confirm_packing_costs(p_order_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item RECORD;
  v_order RECORD;
  v_items_count INT := 0;
  v_total_cost NUMERIC := 0;
BEGIN
  -- 1. Fetch packing order
  SELECT * INTO v_order FROM packing_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Packing order not found');
  END IF;

  -- 2. Process cost items
  FOR v_item IN 
    SELECT * FROM packing_order_cost_items 
    WHERE packing_order_id = p_order_id
  LOOP
    v_items_count := v_items_count + 1;
    v_total_cost := v_total_cost + COALESCE(v_item.actual_amount, v_item.expected_amount, 0);

    -- If this is an engineer custody pool allocation or already settled, mark settled
    IF v_item.category IN ('engineer', 'engineer_expenses') THEN
      UPDATE packing_order_cost_items
      SET cost_status = 'actual',
          is_engineer_cost_settled = true,
          actual_amount = COALESCE(actual_amount, expected_amount)
      WHERE id = v_item.id;
    END IF;
  END LOOP;

  -- 3. Return confirmation summary
  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'items_count', v_items_count,
    'total_confirmed_cost', v_total_cost
  );
END;
$$;

