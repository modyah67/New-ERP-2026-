-- Migration 20260728185200: Fix rpc_cancel_packing_order to delete sortings
--
-- The archived version (268) had:
--   1. Block cancel if any sorting was sold
--   2. Delete packing_order_sortings on cancel
-- Both were lost in v3. This migration restores them.

CREATE OR REPLACE FUNCTION rpc_cancel_packing_order(
  p_packing_order_id BIGINT
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_station_id INTEGER;
  v_allocations JSONB := '[]'::jsonb;
  v_el JSONB;
BEGIN
  SELECT * INTO v_order FROM packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  -- Block cancel if any sorting was sold
  IF EXISTS (
    SELECT 1 FROM packing_order_sortings
    WHERE packing_order_id = p_packing_order_id
      AND status = 'sold'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن الإلغاء لأنه تم بيع بعض من الفرز الخاص بهذا الأمر');
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- Build fruit allocation entries
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  END IF;

  -- Build material allocation entries
  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id', v_el->>'batch_id',
          'quantity', v_el->>'used_qty',
          'product_name', v_el->>'product_name',
          'product_code', COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  -- Restore stock to warehouse
  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM restore_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- Delete associated sorting outputs
  DELETE FROM packing_order_sortings WHERE packing_order_id = p_packing_order_id;

  -- Reverse treasury payments
  IF v_notes ? 'cost_items' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      IF v_el ? 'treasury_transaction_id' AND v_el->>'treasury_transaction_id' IS NOT NULL
         AND v_el->>'treasury_transaction_id' != '' THEN
        DECLARE
          v_treasury_id BIGINT := (v_el->>'treasury_transaction_id')::bigint;
          v_amount NUMERIC := COALESCE((v_el->>'amount')::numeric, 0);
          v_currency TEXT := COALESCE(v_el->>'currency', 'EGP');
        BEGIN
          UPDATE public.treasury_balances
          SET balance = balance + v_amount
          WHERE treasury_id = v_treasury_id AND currency = v_currency;

          INSERT INTO public.treasury_transactions (treasury_id, type, amount, currency, description, reference_type, reference_id)
          VALUES (v_treasury_id, 'return_in', v_amount, v_currency,
            'استرداد - إلغاء أمر التعبئة رقم ' || p_packing_order_id,
            'packing_order', p_packing_order_id);

          UPDATE public.packing_order_cost_items
          SET treasury_transaction_id = NULL
          WHERE packing_order_id = p_packing_order_id
            AND treasury_transaction_id = v_treasury_id;
        END;
      END IF;
    END LOOP;
  END IF;

  -- Reverse bank payments
  IF v_notes ? 'cost_items' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      IF v_el ? 'bank_transaction_id' AND v_el->>'bank_transaction_id' IS NOT NULL
         AND v_el->>'bank_transaction_id' != '' THEN
        DECLARE
          v_bank_txn_id BIGINT := (v_el->>'bank_transaction_id')::bigint;
          v_amount NUMERIC := COALESCE((v_el->>'amount')::numeric, 0);
          v_bank_account_id BIGINT;
        BEGIN
          SELECT bank_account_id INTO v_bank_account_id
          FROM bank_account_transactions WHERE id = v_bank_txn_id;

          IF v_bank_account_id IS NOT NULL THEN
            UPDATE public.bank_accounts
            SET balance = balance + v_amount
            WHERE id = v_bank_account_id;

            INSERT INTO public.bank_account_transactions (bank_account_id, type, amount, description, reference_type, reference_id)
            VALUES (v_bank_account_id, 'deposit', v_amount,
              'استرداد - إلغاء أمر التعبئة رقم ' || p_packing_order_id,
              'packing_order', p_packing_order_id);
          END IF;

          UPDATE public.packing_order_cost_items
          SET bank_transaction_id = NULL
          WHERE packing_order_id = p_packing_order_id
            AND bank_transaction_id = v_bank_txn_id;
        END;
      END IF;
    END LOOP;
  END IF;

  -- Reverse supplier credit
  IF v_notes ? 'cost_items' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      IF (NOT (v_el ? 'treasury_transaction_id') OR v_el->>'treasury_transaction_id' IS NULL OR v_el->>'treasury_transaction_id' = '')
         AND (NOT (v_el ? 'bank_transaction_id') OR v_el->>'bank_transaction_id' IS NULL OR v_el->>'bank_transaction_id' = '')
         AND v_el ? 'supplier_id' AND v_el->>'supplier_id' IS NOT NULL AND v_el->>'supplier_id' != '' THEN
        DECLARE
          v_supplier_id UUID := (v_el->>'supplier_id')::uuid;
          v_amount NUMERIC := COALESCE((v_el->>'amount')::numeric, 0);
        BEGIN
          UPDATE public.suppliers
          SET outstanding_balance = outstanding_balance - v_amount
          WHERE id = v_supplier_id;

          DELETE FROM public.ledger_entries
          WHERE entity_type = 'supplier'
            AND entity_id = v_supplier_id::text
            AND reference_type = 'packing_cost_item'
            AND reference_id = p_packing_order_id
            AND entry_type = 'credit';
        END;
      END IF;
    END LOOP;
  END IF;

  -- Mark order as cancelled
  UPDATE public.packing_orders
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_cancel_packing_order(BIGINT) TO authenticated;

-- Cleanup: remove orphaned sortings for already-cancelled orders
DELETE FROM packing_order_sortings pos
USING packing_orders po
WHERE pos.packing_order_id = po.id
  AND po.status = 'cancelled';

NOTIFY pgrst, 'reload schema';
