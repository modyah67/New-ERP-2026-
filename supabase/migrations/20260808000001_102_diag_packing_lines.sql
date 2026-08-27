-- Create a simple readable view instead of RPC
DROP VIEW IF EXISTS _diag_packing_view;
CREATE VIEW _diag_packing_view AS
SELECT
  pol.id AS line_id,
  pol.packing_order_id,
  pol.product_name,
  pol.fruit_type_id,
  pol.carton_count,
  pol.sold_cartons,
  pol.raw_material_cost,
  pol.specific_packaging_cost,
  pol.allocated_shared_packaging,
  pol.allocated_cost_items,
  pol.final_cost,
  pol.final_unit_cost,
  pol.total_net_weight,
  pol.net_weight_per_carton,
  esi.id AS esi_item_id,
  esi.packing_order_line_id AS esi_line_id,
  esi.product_name AS esi_product_name,
  esi.quantity AS esi_quantity,
  esi.price AS esi_price
FROM packing_order_lines pol
LEFT JOIN export_shipment_items esi ON esi.packing_order_line_id = pol.id;

GRANT SELECT ON _diag_packing_view TO anon, authenticated;
