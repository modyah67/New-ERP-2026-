-- ============================================================================
-- Migration: Add export_shipment_no and customer_name to rpc_get_packing_order_variance_details
-- Ensures that the export shipment number associated with the packing order
-- is automatically returned to pre-fill invoice/document reference fields in settlement.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_get_packing_order_variance_details(p_packing_order_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r_order RECORD;
  v_items JSONB := '[]'::jsonb;
  v_shipments JSONB := '[]'::jsonb;
  v_total_expected NUMERIC := 0;
  v_total_actual NUMERIC := 0;
  v_total_variance NUMERIC := 0;
  v_carton_count NUMERIC := 0;
  v_shipment_no TEXT;
  v_customer_name TEXT;
BEGIN
  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- 1. Get Cost Items
  SELECT COALESCE(jsonb_agg(item_row), '[]'::jsonb) INTO v_items
  FROM (
    SELECT 
      ci.id,
      ci.name,
      ci.category,
      ci.cost_status,
      COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0) AS expected_amount,
      ci.actual_amount,
      COALESCE(ci.variance_amount, CASE WHEN ci.actual_amount IS NOT NULL THEN ci.actual_amount - COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0) ELSE 0 END) AS variance_amount,
      ci.invoice_ref,
      ci.settlement_notes,
      ci.reconciled_at,
      ci.reconciled_by,
      ci.variance_journal_entry_id,
      ci.supplier_id,
      COALESCE(s.name, ci.currency_snapshot->>'supplier_name', 'مورد عام / بدون مورد') AS supplier_name,
      COALESCE(s.supplier_type, ci.currency_snapshot->>'supplier_type', 'general') AS supplier_type
    FROM public.packing_order_cost_items ci
    LEFT JOIN public.suppliers s ON (s.id::text = ci.supplier_id)
    WHERE ci.packing_order_id = p_packing_order_id
    ORDER BY ci.id
  ) item_row;

  -- 2. Get Linked Export Shipments with current profitability
  SELECT COALESCE(jsonb_agg(ship_row), '[]'::jsonb) INTO v_shipments
  FROM (
    SELECT DISTINCT
      s.id,
      s.shipment_no,
      s.status,
      s.destination_country,
      s.customer_name,
      COALESCE(s.total_revenue_egp, 0) AS total_revenue_egp,
      COALESCE(s.total_landed_cost, 0) AS total_landed_cost,
      COALESCE(s.cost_per_carton, 0) AS cost_per_carton,
      COALESCE(s.net_profit_egp, 0) AS net_profit_egp,
      COALESCE(s.allocated_admin_expenses, 0) AS allocated_admin_expenses,
      COALESCE(s.allocated_taxes, 0) AS allocated_taxes,
      esi.quantity AS order_cartons_in_shipment
    FROM public.export_shipments s
    JOIN public.export_shipment_items esi ON (esi.shipment_id::text = s.id::text)
    WHERE esi.packing_order_id = p_packing_order_id
  ) ship_row;

  -- 3. Calculate Carton Count
  SELECT COALESCE(SUM(carton_count), 0) INTO v_carton_count
  FROM public.packing_order_lines
  WHERE packing_order_id = p_packing_order_id;
  IF v_carton_count <= 0 THEN
    v_carton_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, 1);
  END IF;

  -- 4. Resolve Export Shipment No & Customer
  v_shipment_no := COALESCE(
    NULLIF(r_order.export_shipment_no, ''),
    CASE WHEN jsonb_array_length(v_shipments) > 0 THEN v_shipments->0->>'shipment_no' ELSE NULL END
  );
  v_customer_name := COALESCE(
    NULLIF(r_order.customer_name, ''),
    CASE WHEN jsonb_array_length(v_shipments) > 0 THEN v_shipments->0->>'customer_name' ELSE NULL END
  );

  RETURN jsonb_build_object(
    'success', true,
    'packing_order_id', p_packing_order_id,
    'order_number', COALESCE(r_order.order_number, p_packing_order_id::text),
    'order_status', r_order.status,
    'export_shipment_no', v_shipment_no,
    'customer_name', v_customer_name,
    'fruit_cost_base', COALESCE(r_order.fruit_cost_base, 0),
    'actual_material_cost', COALESCE(r_order.actual_material_cost, 0),
    'other_cost_base', COALESCE(r_order.other_cost_base, 0),
    'total_cost', COALESCE(r_order.total_cost, 0),
    'carton_count', v_carton_count,
    'packing_cost_per_carton', COALESCE(r_order.packing_cost_per_carton, 0),
    'items', v_items,
    'shipments', v_shipments
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_packing_order_variance_details(BIGINT) TO authenticated, service_role, anon;

COMMIT;
