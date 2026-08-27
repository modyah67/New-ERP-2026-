-- Migration 20260728220000: Fix export shipment paid amount not affecting customer balance/statement
--
-- Problem: rpc_process_export_shipment_ledger only handles revenue (debit) + discount (credit).
-- It never creates a credit entry for paid_amount, so:
--   1. customers.balance doesn't decrease when customer pays
--   2. The paid amount doesn't show in the customer statement
--
-- Treasury deposits via deposit_treasury don't set customer_id → statement can't find them.
-- Bank deposits via depositWithCounterparty aren't read by the statement at all.
--
-- Fix: Add CREDIT entry for paid_amount + update customers.balance accordingly.

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
  v_old_paid NUMERIC := 0;
  v_paid_amount NUMERIC := 0;
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
  v_paid_amount := COALESCE(v_shipment.paid_amount, 0);

  -- Calculate old net amount (debit - credit) from existing export_shipment entries
  SELECT
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Calculate old paid amount from existing shipment_payment entries
  SELECT COALESCE(SUM(amount), 0)
  INTO v_old_paid
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'shipment_payment'
    AND reference_text = p_shipment_id::TEXT;

  -- Update customer balance: revert old entries, apply new entries
  -- old_amount = old revenue net (debit), old_paid = old payment (credit)
  -- balance = balance - old_amount + v_net_amount + old_paid - v_paid_amount
  UPDATE customers
  SET balance = COALESCE(balance, 0) - v_old_amount + v_net_amount + v_old_paid - v_paid_amount,
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  -- Delete all old ledger entries for this shipment (revenue + discount)
  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Delete old payment entries
  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'shipment_payment'
    AND reference_text = p_shipment_id::TEXT;

  -- Insert DEBIT entry for the full revenue (before discount)
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

  -- Insert CREDIT entry for the discount amount
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

  -- Insert CREDIT entry for the paid amount (payment from customer)
  IF v_paid_amount > 0 THEN
    v_desc := 'دفعة على شحنة تصدير رقم ' || v_shipment.shipment_number;
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'credit', v_paid_amount,
      COALESCE(v_shipment.currency, 'USD'),
      'shipment_payment', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  UPDATE export_shipments
  SET applied_discount_amount = v_discount
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'total_revenue', v_total_revenue,
    'discount', v_discount,
    'net_amount', v_net_amount,
    'paid_amount', v_paid_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(BIGINT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
