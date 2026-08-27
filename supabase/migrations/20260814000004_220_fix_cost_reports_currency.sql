-- Migration 220: Fix currency display in vw_cost_details_live
-- 1. Shipment cost items were displaying the shipment's currency (USD) instead of the actual supplier currency
-- 2. Prep center costs were also displaying the shipment's currency instead of EGP

DROP VIEW IF EXISTS public.vw_cost_details_live CASCADE;
CREATE OR REPLACE VIEW public.vw_cost_details_live AS

-- 1. Crops from Lots (Cost is in Foreign Currency)
SELECT
  l.receipt_date::date::text AS shipment_date,
  (SELECT STRING_AGG(DISTINCT s.shipment_no, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS shipment_no,
  (SELECT STRING_AGG(DISTINCT s.customer_name, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS customer_name,
  'crop' AS category,
  COALESCE(l.product_name, 'محصول') AS item_name,
  l.gross_weight_kg AS quantity,
  ROUND(((l.total_fruit_cost * COALESCE(l.exchange_rate, 1.0)) / NULLIF(l.gross_weight_kg, 0))::numeric, 2) AS unit_price,
  ROUND((l.total_fruit_cost * COALESCE(l.exchange_rate, 1.0))::numeric, 2) AS amount,
  COALESCE(l.currency, (SELECT s.currency FROM public.export_shipments s JOIN public.packing_orders po ON s.id = po.export_shipment_id WHERE po.lot_id = l.id LIMIT 1), 'EGP') AS currency,
  COALESCE(l.exchange_rate, 1.0) AS exchange_rate,
  ROUND(l.total_fruit_cost::numeric, 2) AS total_in_currency,
  l.notes AS notes,
  (SELECT MIN(po.export_shipment_id) FROM public.packing_orders po WHERE po.lot_id = l.id) AS shipment_id
FROM public.lot_receipts l
WHERE l.is_confirmed = TRUE

UNION ALL

-- 1.5 Crop Returns (Cost is in Foreign Currency)
SELECT
  r.created_at::date::text AS shipment_date,
  (SELECT STRING_AGG(DISTINCT s.shipment_no, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS shipment_no,
  (SELECT STRING_AGG(DISTINCT s.customer_name, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS customer_name,
  'crop' AS category,
  'مرتجع ' || COALESCE(l.product_name, 'محصول') AS item_name,
  -r.returned_quantity AS quantity,
  ROUND(((r.return_value * COALESCE(l.exchange_rate, 1.0)) / NULLIF(r.returned_quantity, 0))::numeric, 2) AS unit_price,
  ROUND(-(r.return_value * COALESCE(l.exchange_rate, 1.0))::numeric, 2) AS amount,
  COALESCE(l.currency, (SELECT s.currency FROM public.export_shipments s JOIN public.packing_orders po ON s.id = po.export_shipment_id WHERE po.lot_id = l.id LIMIT 1), 'EGP') AS currency,
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
  'packing_material' AS category,
  COALESCE(m->>'product_name', 'مادة تعبئة') AS item_name,
  (m->>'used_qty')::numeric AS quantity,
  ROUND(((m->>'total')::numeric / NULLIF((m->>'used_qty')::numeric, 0))::numeric, 2) AS unit_price,
  ROUND((m->>'total')::numeric, 2) AS amount,
  COALESCE(m->>'currency', s.currency, s.currency_code, 'EGP') AS currency,
  COALESCE((m->>'exchange_rate')::numeric, 1.0) AS exchange_rate,
  ROUND(COALESCE((m->>'total_foreign')::numeric, ((m->>'total')::numeric / NULLIF(COALESCE((m->>'exchange_rate')::numeric, 1.0), 0)))::numeric, 2) AS total_in_currency,
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
WHERE (m->>'total')::numeric > 0 AND po.status = 'completed'

UNION ALL

-- 3. Packing Cost Items from Packing Orders
SELECT
  COALESCE(po.packed_at, po.created_at)::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  COALESCE(c->>'category_name', c->>'category', 'other') AS category,
  COALESCE(c->>'name', 'بند تكلفة') AS item_name,
  (c->>'quantity')::numeric AS quantity,
  ROUND(((COALESCE(c->>'total_egp', c->>'total'))::numeric / NULLIF((c->>'quantity')::numeric, 0))::numeric, 2) AS unit_price,
  ROUND((COALESCE(c->>'total_egp', c->>'total'))::numeric, 2) AS amount,
  COALESCE(c->>'supplier_currency', s.currency, s.currency_code, 'EGP') AS currency,
  COALESCE((c->>'exchange_rate')::numeric, 1.0) AS exchange_rate,
  ROUND((c->>'total')::numeric, 2) AS total_in_currency,
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
WHERE (COALESCE(c->>'total_egp', c->>'total'))::numeric > 0 AND po.status IN ('completed', 'cancelled')

UNION ALL

-- 4. All other items from shipment_cost_items
SELECT
  s.shipment_date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  COALESCE(crc.name, sci.category) AS category,
  sci.description AS item_name,
  sci.quantity AS quantity,
  ROUND((sci.total_price / NULLIF(sci.quantity, 0))::numeric, 2) AS unit_price,
  ROUND(sci.total_price::numeric, 2) AS amount,
  COALESCE(sci.supplier_currency, sci.original_currency, s.currency, s.currency_code, 'EGP') AS currency,
  COALESCE(sci.exchange_rate, 1.0) AS exchange_rate,
  ROUND((sci.total_price / NULLIF(COALESCE(sci.exchange_rate, 1.0), 0))::numeric, 2) AS total_in_currency,
  sci.description AS notes,
  s.id AS shipment_id
FROM shipment_cost_items sci
JOIN export_shipments s ON s.id = sci.shipment_id
LEFT JOIN cost_report_categories crc ON crc.id = sci.report_category_id
WHERE sci.category NOT IN ('crop', 'packing')
  AND NOT (sci.category = 'other' AND sci.description LIKE 'محصول%')

UNION ALL

-- 5. Prep Center Costs
SELECT
  s.shipment_date::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  pci.cost_type AS category,
  pci.description AS item_name,
  pci.qty AS quantity,
  ROUND((pci.total_cost / NULLIF(pci.qty, 0))::numeric, 2) AS unit_price,
  ROUND(pci.total_cost::numeric, 2) AS amount,
  'EGP' AS currency,
  1.0 AS exchange_rate,
  ROUND(pci.total_cost::numeric, 2) AS total_in_currency,
  pci.notes AS notes,
  pci.shipment_id AS shipment_id
FROM public.prep_center_cost_items pci
JOIN public.export_shipments s ON s.id = pci.shipment_id

UNION ALL

-- 6. General Cost Items
SELECT
  gci.cost_date::date::text AS shipment_date,
  NULL AS shipment_no,
  NULL AS customer_name,
  'general' AS category,
  gci.name AS item_name,
  1 AS quantity,
  ROUND((gci.amount * 1.0)::numeric, 2) AS unit_price,
  ROUND((gci.amount * 1.0)::numeric, 2) AS amount,
  'EGP' AS currency,
  1.0 AS exchange_rate,
  ROUND((gci.amount * 1.0)::numeric, 2) AS total_in_currency,
  NULL AS notes,
  NULL AS shipment_id
FROM public.general_cost_items gci;

ALTER VIEW public.vw_cost_details_live OWNER TO postgres;
GRANT SELECT ON public.vw_cost_details_live TO authenticated;
GRANT SELECT ON public.vw_cost_details_live TO anon;

NOTIFY pgrst, 'reload_schema';
