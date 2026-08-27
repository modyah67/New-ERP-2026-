-- ============================================================================
-- Migration: Fix Export Discount Balance
-- ============================================================================
-- Issue: `rpc_apply_export_discount` created Journal Entries for the discount
-- but bypassed updating `customers.balance` and `ledger_entries`.
-- Fix: We simplify `rpc_apply_export_discount` to just save the discount and 
-- rely on `rpc_process_export_shipment_ledger` to handle the actual ledger 
-- posting, guaranteeing that `customers.balance` is perfectly synced.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_apply_export_discount(
  p_shipment_id BIGINT,
  p_discount_amount NUMERIC,
  p_discount_reason TEXT DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shipment RECORD;
BEGIN
  -- Verify shipment exists
  SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  -- Update discount amounts
  UPDATE export_shipments
  SET 
    discount_amount = p_discount_amount,
    applied_discount_amount = p_discount_amount
  WHERE id = p_shipment_id;

  -- Reprocess the ledger entries entirely (this handles JEs, ledger_entries, and customers.balance!)
  RETURN public.rpc_process_export_shipment_ledger(p_shipment_id, p_user_id);
END;
$$;

COMMIT;
