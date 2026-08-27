BEGIN;

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
    v_delta NUMERIC;
    v_effective_cost NUMERIC;
    v_total_graded NUMERIC := 0;
    v_grading RECORD;
    v_net_wt NUMERIC;
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
      UPDATE lot_receipts
      SET price_per_carton = p_new_price,
          fruit_cost_per_kg = CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END,
          exchange_rate = p_exchange_rate,
          currency = p_currency,
          total_fruit_cost = v_new_total_cost,
          updated_at = now()
      WHERE id = p_lot_id;
    ELSE
      v_new_total_cost := COALESCE(v_lot.gross_weight_kg, 0) * p_new_price;
      UPDATE lot_receipts
      SET fruit_cost_per_kg = CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END,
          exchange_rate = p_exchange_rate,
          currency = p_currency,
          total_fruit_cost = v_new_total_cost,
          updated_at = now()
      WHERE id = p_lot_id;
    END IF;

    -- Sync GL entries (The sync function will handle the delta and journal entries)
    IF v_lot.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(p_lot_id, 'UPDATE');
    END IF;

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

    RETURN jsonb_build_object('success', true);
END;
$$;

COMMIT;
