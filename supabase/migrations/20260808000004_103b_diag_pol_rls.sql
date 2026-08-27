CREATE OR REPLACE FUNCTION _diag_pol_count()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'packing_order_lines_count', (SELECT COUNT(*) FROM packing_order_lines WHERE packing_order_id = 1),
    'packing_order_lines', (SELECT jsonb_agg(jsonb_build_object('id', id, 'product_name', product_name, 'carton_count', carton_count, 'final_cost', final_cost, 'raw_material_cost', raw_material_cost, 'specific_packaging_cost', specific_packaging_cost, 'allocated_shared_packaging', allocated_shared_packaging, 'allocated_cost_items', allocated_cost_items)) FROM packing_order_lines WHERE packing_order_id = 1),
    'export_items', (SELECT jsonb_agg(jsonb_build_object('id', id, 'packing_order_line_id', packing_order_line_id, 'product_name', product_name, 'price', price, 'quantity', quantity)) FROM export_shipment_items WHERE packing_order_id = 1)
  );
$$;
