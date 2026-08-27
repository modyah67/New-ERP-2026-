-- Migration 20260728230000: Fix duplicate payment entries for export shipments
--
-- Problem: rpc_process_export_shipment_ledger created shipment_payment credit entries,
-- AND depositWithCounterparty (bank path) also created bank_transfer credit entries.
-- Both updated customers.balance. Result: double entries + double balance for bank payments.
-- Treasury path had no ledger entry at all (only the RPC entry).
--
-- Fix: RPC only handles revenue (debit) + discount (credit).
-- Payment is handled entirely by ShipmentPaymentService on the Dart side.

-- Cleanup old duplicate shipment_payment entries
DELETE FROM ledger_entries
WHERE reference_type = 'shipment_payment'
  AND entity_type = 'customer'
  AND reference_text IN (
    SELECT id::text FROM export_shipments
  );

CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_ledger(
  p_shipment_id BIGINT,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue NUMERIC := 0;
  v_discount NUMERIC := 0;
  v_net_amount NUMERIC := 0;
  v_old_amount NUMERIC := 0;
  v_desc TEXT;
BEGIN
  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No customer assigned');
  END IF;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  v_discount := COALESCE(v_shipment.discount_amount, 0);
  v_net_amount := GREATEST(v_total_revenue - v_discount, 0);

  SELECT
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  UPDATE customers
  SET balance = COALESCE(balance, 0) - v_old_amount + v_net_amount,
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  IF v_total_revenue > 0 THEN
    v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_number;
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      COALESCE(v_shipment.currency, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  IF v_discount > 0 THEN
    v_desc := 'خصم شحنة تصدير رقم ' || v_shipment.shipment_number;
    IF COALESCE(v_shipment.discount_reason, '') != '' THEN
      v_desc := v_desc || ' (' || v_shipment.discount_reason || ')';
    END IF;

    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
      COALESCE(v_shipment.currency, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  UPDATE export_shipments
  SET applied_discount_amount = v_discount
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'total_revenue', v_total_revenue,
    'discount', v_discount,
    'net_amount', v_net_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(BIGINT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
