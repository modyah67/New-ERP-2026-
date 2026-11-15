-- ============================================================================
-- RPC: rpc_apply_export_discount
-- Purpose: Apply or update discount on export shipment and recalculate ledger/GL
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_apply_export_discount(
  p_shipment_id bigint,
  p_discount_amount numeric,
  p_discount_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment RECORD;
  v_res jsonb;
BEGIN
  SELECT * INTO v_shipment
  FROM public.export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الشحنة التصديرية غير موجودة');
  END IF;

  IF p_discount_amount < 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'قيمة الخصم لا يمكن أن تكون سالبة');
  END IF;

  UPDATE public.export_shipments
  SET discount_amount = COALESCE(p_discount_amount, 0),
      discount_reason = p_discount_reason,
      applied_discount_amount = COALESCE(p_discount_amount, 0),
      updated_at = now()
  WHERE id = p_shipment_id;

  -- Re-process shipment ledger to update customer ledger and double-entry journals
  BEGIN
    v_res := public.rpc_process_export_shipment_ledger(p_shipment_id);
  EXCEPTION WHEN OTHERS THEN
    v_res := jsonb_build_object('success', false, 'warning', SQLERRM);
  END;

  RETURN jsonb_build_object(
    'success', true,
    'shipment_id', p_shipment_id,
    'discount_amount', p_discount_amount,
    'discount_reason', p_discount_reason,
    'ledger_result', v_res
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_apply_export_discount(bigint, numeric, text) TO authenticated, service_role, anon;
