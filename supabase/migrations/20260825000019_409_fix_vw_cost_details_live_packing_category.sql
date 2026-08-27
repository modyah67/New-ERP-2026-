-- Migration 409: Fix vw_cost_details_live to properly categorize packing order cost items

CREATE OR REPLACE VIEW public.vw_cost_details_live AS

-- 1. Crops from Lots
SELECT
  l.receipt_date::date::text AS shipment_date,
  (SELECT STRING_AGG(DISTINCT s.shipment_no, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS shipment_no,
  (SELECT STRING_AGG(DISTINCT s.customer_name, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS customer_name,
  'تكلفة المحاصيل'::text AS category,
  COALESCE(l.product_name, 'محصول'::text) AS item_name,
  l.gross_weight_kg AS quantity,
  ROUND(((l.total_fruit_cost * COALESCE(l.exchange_rate, 1.0)) / NULLIF(l.gross_weight_kg, 0))::numeric, 2) AS unit_price,
  ROUND((l.total_fruit_cost * COALESCE(l.exchange_rate, 1.0))::numeric, 2) AS amount,
  COALESCE(l.currency, 'EGP'::text) AS currency,
  COALESCE(l.exchange_rate, 1.0) AS exchange_rate,
  ROUND(l.total_fruit_cost::numeric, 2) AS total_in_currency,
  l.notes AS notes,
  (SELECT MIN(po.export_shipment_id) FROM public.packing_orders po WHERE po.lot_id = l.id) AS shipment_id
FROM public.lot_receipts l
WHERE l.is_confirmed = TRUE

UNION ALL

-- 1.5 Crop Returns
SELECT
  r.created_at::date::text AS shipment_date,
  (SELECT STRING_AGG(DISTINCT s.shipment_no, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS shipment_no,
  (SELECT STRING_AGG(DISTINCT s.customer_name, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS customer_name,
  'تكلفة المحاصيل'::text AS category,
  'مرتجع '::text || COALESCE(l.product_name, 'محصول'::text) AS item_name,
  -r.returned_quantity AS quantity,
  ROUND(((r.return_value * COALESCE(l.exchange_rate, 1.0)) / NULLIF(r.returned_quantity, 0))::numeric, 2) AS unit_price,
  ROUND(-(r.return_value * COALESCE(l.exchange_rate, 1.0)), 2) AS amount,
  COALESCE(l.currency, 'EGP'::text) AS currency,
  COALESCE(l.exchange_rate, 1.0) AS exchange_rate,
  ROUND(-(r.return_value)::numeric, 2) AS total_in_currency,
  r.notes AS notes,
  (SELECT MIN(po.export_shipment_id) FROM public.packing_orders po WHERE po.lot_id = l.id) AS shipment_id
FROM public.lot_returns r
JOIN public.lot_receipts l ON l.id = r.lot_receipt_id

UNION ALL

-- 2. Packing Materials from Packing Orders
SELECT
  COALESCE(po.packed_at, po.created_at)::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  'مواد التعبئة'::text AS category,
  COALESCE(mat.m->>'product_name', 'مادة تعبئة'::text) AS item_name,
  (mat.m->>'used_qty')::numeric AS quantity,
  ROUND(((mat.m->>'total')::numeric / NULLIF((mat.m->>'used_qty')::numeric, 0))::numeric, 2) AS unit_price,
  ROUND((mat.m->>'total')::numeric, 2) AS amount,
  COALESCE(mat.m->>'currency', 'EGP'::text) AS currency,
  COALESCE((mat.m->>'exchange_rate')::numeric, 1.0) AS exchange_rate,
  ROUND(COALESCE((mat.m->>'total_foreign')::numeric, ((mat.m->>'total')::numeric / NULLIF(COALESCE((mat.m->>'exchange_rate')::numeric, 1.0), 0)))::numeric, 2) AS total_in_currency,
  po.notes AS notes,
  s.id AS shipment_id
FROM public.packing_orders po
LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
CROSS JOIN LATERAL (
  SELECT jsonb_array_elements(
    COALESCE(
      (po.notes::jsonb -> 'materials'),
      '[]'::jsonb
    )
  ) AS m
) mat
WHERE (mat.m->>'total')::numeric > 0 AND po.status = 'completed'

UNION ALL

-- 3. Packing Cost Items from Packing Orders (Dynamic category from cost_report_categories / category_name)
SELECT
  COALESCE(po.packed_at, po.created_at)::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  COALESCE(
    crc.name,
    NULLIF(cit.c->>'category_name', ''),
    CASE
      WHEN cit.c->>'category' = 'logistics' THEN 'لوجستيك ونقل'
      WHEN cit.c->>'category' = 'material' THEN 'مواد التعبئة'
      WHEN cit.c->>'category' = 'fruit' THEN 'تكلفة المحاصيل'
      WHEN cit.c->>'category' = 'other' THEN 'أخرى'
      WHEN NULLIF(cit.c->>'category', '') IS NOT NULL THEN cit.c->>'category'
      ELSE 'تعبئة وتغليف'
    END
  )::text AS category,
  COALESCE(cit.c->>'name', 'بند تكلفة تعبئة'::text) AS item_name,
  (cit.c->>'quantity')::numeric AS quantity,
  ROUND(((COALESCE(cit.c->>'total_egp', cit.c->>'total'))::numeric / NULLIF((cit.c->>'quantity')::numeric, 0))::numeric, 2) AS unit_price,
  ROUND((COALESCE(cit.c->>'total_egp', cit.c->>'total'))::numeric, 2) AS amount,
  COALESCE(cit.c->>'supplier_currency', 'EGP'::text) AS currency,
  COALESCE((cit.c->>'exchange_rate')::numeric, 1.0) AS exchange_rate,
  ROUND((cit.c->>'total')::numeric, 2) AS total_in_currency,
  po.notes AS notes,
  s.id AS shipment_id
FROM public.packing_orders po
LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
CROSS JOIN LATERAL (
  SELECT jsonb_array_elements(
    COALESCE(
      (po.notes::jsonb -> 'cost_items'),
      '[]'::jsonb
    )
  ) AS c
) cit
LEFT JOIN public.cost_report_categories crc 
  ON crc.id = (CASE WHEN (cit.c->>'report_category_id') ~ '^[0-9]+$' THEN (cit.c->>'report_category_id')::integer ELSE NULL END)
WHERE (COALESCE(cit.c->>'total_egp', cit.c->>'total'))::numeric > 0 AND po.status IN ('completed', 'cancelled')

UNION ALL

-- 4. Shipment Cost Items with explicit categorization
SELECT
  s.shipment_date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  CASE
    WHEN sci.vendor_type = 'shipping_company' OR sci.shipping_company_id IS NOT NULL OR sci.category IN ('freight', 'TRANSPORT', 'shipping') THEN 'تكلفة شركات الشحن'
    WHEN sci.vendor_type = 'clearing_agent' OR sci.clearing_agent_id IS NOT NULL OR sci.category IN ('clearance', 'CLEARING', 'clearing') THEN 'تكلفة المخلصين'
    WHEN crc.name IS NOT NULL AND crc.name NOT IN ('أخرى', 'OTHER') THEN crc.name
    WHEN sci.category IN ('packing', 'packaging', 'manual_packing') THEN 'تعبئة وتغليف'
    WHEN sci.category IN ('crop', 'manual_crop') THEN 'تكلفة المحاصيل'
    WHEN sci.category = 'packing_material' THEN 'مواد التعبئة'
    ELSE COALESCE(crc.name, 'أخرى')
  END::text AS category,
  sci.description AS item_name,
  sci.quantity,
  ROUND((sci.total_price / NULLIF(sci.quantity, 0))::numeric, 2) AS unit_price,
  ROUND(sci.total_price::numeric, 2) AS amount,
  COALESCE(sci.supplier_currency, sci.original_currency, 'EGP'::text) AS currency,
  COALESCE(sci.exchange_rate, 1.0) AS exchange_rate,
  ROUND((sci.total_price / NULLIF(COALESCE(sci.exchange_rate, 1.0), 0))::numeric, 2) AS total_in_currency,
  sci.description AS notes,
  s.id AS shipment_id
FROM public.shipment_cost_items sci
JOIN public.export_shipments s ON s.id = sci.shipment_id
LEFT JOIN public.cost_report_categories crc ON crc.id = sci.report_category_id
WHERE NOT (sci.category = 'crop' OR (sci.category = 'other' AND sci.description LIKE 'محصول%'))
  AND NOT (sci.description LIKE 'تكلفة الكراتين%' OR sci.description LIKE 'تكلفة كراتين%')

UNION ALL

-- 5. Prep Center Costs
SELECT
  s.shipment_date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  'تعبئة وتغليف'::text AS category,
  pci.description AS item_name,
  pci.qty AS quantity,
  ROUND((pci.total_cost / NULLIF(pci.qty, 0))::numeric, 2) AS unit_price,
  ROUND(pci.total_cost::numeric, 2) AS amount,
  'EGP'::text AS currency,
  1.0 AS exchange_rate,
  ROUND(pci.total_cost::numeric, 2) AS total_in_currency,
  pci.notes AS notes,
  pci.shipment_id AS shipment_id
FROM public.prep_center_cost_items pci
JOIN public.export_shipments s ON s.id = pci.shipment_id

UNION ALL

-- 6. General Cost Items
SELECT
  gci.cost_date::text AS shipment_date,
  NULL::text AS shipment_no,
  NULL::text AS customer_name,
  COALESCE(crc.name, 'مصاريف إدارية'::text) AS category,
  gci.name AS item_name,
  1::numeric AS quantity,
  ROUND((gci.amount * 1.0)::numeric, 2) AS unit_price,
  ROUND((gci.amount * 1.0)::numeric, 2) AS amount,
  'EGP'::text AS currency,
  1.0 AS exchange_rate,
  ROUND((gci.amount * 1.0)::numeric, 2) AS total_in_currency,
  NULL AS notes,
  NULL AS shipment_id
FROM public.general_cost_items gci
LEFT JOIN public.cost_report_categories crc ON crc.id = gci.report_category_id;

GRANT SELECT ON public.vw_cost_details_live TO authenticated;
GRANT SELECT ON public.vw_cost_details_live TO anon;
