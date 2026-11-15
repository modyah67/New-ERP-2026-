-- ============================================================================
-- Migration: 20261111000003_order_range_filter_in_cost_settlement_rpc.sql
-- Purpose: Add optional shipment / packing order numeric range parameters
--          (p_from_order_id, p_to_order_id) to rpc_get_supplier_expected_cost_items
--          while preserving the JSONB return shape and excluding deleted/cancelled rows.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.rpc_get_supplier_expected_cost_items(TEXT, UUID, TEXT, TEXT, INT, INT);
DROP FUNCTION IF EXISTS public.rpc_get_supplier_expected_cost_items(TEXT, UUID, TEXT, TEXT, INT, INT, INT, INT);

CREATE OR REPLACE FUNCTION public.rpc_get_supplier_expected_cost_items(
  p_supplier_type TEXT DEFAULT NULL,
  p_supplier_id UUID DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INT DEFAULT 200,
  p_offset INT DEFAULT 0,
  p_from_order_id INT DEFAULT NULL,
  p_to_order_id INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(item_row), '[]'::jsonb) INTO v_result
  FROM (
    SELECT
      ci.id AS cost_item_id,
      ci.packing_order_id,
      po.order_number,
      po.status AS order_status,
      po.packed_at AS order_date,
      po.packing_cost_per_carton,
      ci.name AS item_name,
      ci.category,
      ci.report_category_id,
      COALESCE(rc.name, ci.category) AS report_category_name,
      ci.cost_status,
      COALESCE(
        NULLIF(ci.expected_amount, 0),
        NULLIF((ci.currency_snapshot->'settlement'->>'expected_amount')::numeric, 0),
        CASE WHEN ci.cost_status = 'expected' THEN NULLIF(ci.base_amount, 0) ELSE NULL END,
        NULLIF((ci.currency_snapshot->>'total_egp')::numeric, 0),
        NULLIF((ci.currency_snapshot->>'total')::numeric, 0),
        NULLIF(ci.original_amount, 0),
        ci.base_amount,
        0
      ) AS expected_amount,
      ci.actual_amount,
      COALESCE(ci.variance_amount, 0) AS variance_amount,
      ci.original_currency,
      ci.original_amount,
      ci.exchange_rate,
      ci.base_amount,
      COALESCE(
        NULLIF((ci.currency_snapshot->>'quantity')::numeric, 0),
        1.0
      ) AS quantity,
      COALESCE(
        NULLIF((ci.currency_snapshot->>'unit_price')::numeric, 0),
        CASE
          WHEN COALESCE((ci.currency_snapshot->>'quantity')::numeric, 1.0) > 0
          THEN COALESCE(NULLIF(ci.expected_amount, 0), NULLIF(ci.base_amount, 0), ci.original_amount, 0)
               / COALESCE((ci.currency_snapshot->>'quantity')::numeric, 1.0)
          ELSE COALESCE(NULLIF(ci.expected_amount, 0), NULLIF(ci.base_amount, 0), ci.original_amount, 0)
        END
      ) AS unit_price,
      ci.actual_quantity,
      ci.actual_unit_price,
      ci.actual_date_time,
      ci.detailed_notes,
      ci.currency_snapshot,
      ci.invoice_ref,
      ci.settlement_notes,
      ci.reconciled_at,
      ci.variance_journal_entry_id,
      s.id AS supplier_id,
      s.name AS supplier_name,
      s.code AS supplier_code,
      s.supplier_type,
      s.phone AS supplier_phone,
      s.outstanding_balance AS supplier_outstanding_balance,
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'shipment_id', es.id,
              'shipment_no', es.shipment_no,
              'status', es.status,
              'total_landed_cost', es.total_landed_cost,
              'net_profit_egp', es.net_profit_egp
            )
          )
          FROM public.export_shipment_items esi
          JOIN public.export_shipments es ON es.id::text = esi.shipment_id::text
          WHERE esi.packing_order_id = po.id
        ),
        '[]'::jsonb
      ) AS linked_shipments
    FROM public.packing_order_cost_items ci
    JOIN public.packing_orders po ON po.id = ci.packing_order_id
    LEFT JOIN public.cost_report_categories rc ON rc.id = ci.report_category_id
    LEFT JOIN public.suppliers s ON (
      s.id::text = ci.supplier_id
      OR s.id::text = (ci.currency_snapshot->>'supplier_id')
    )
    WHERE
      ci.deleted_at IS NULL
      AND COALESCE(po.status, '') <> 'cancelled'
      -- Supplier Type Filter
      AND (
        p_supplier_type IS NULL
        OR p_supplier_type = 'all'
        OR (p_supplier_type = 'station' AND (s.supplier_type = 'station' OR s.code LIKE '8%' OR ci.name ILIKE '%تشغيل%' OR ci.name ILIKE '%تبريد%' OR ci.name ILIKE '%محطة%'))
        OR (p_supplier_type = 'deduction' AND (s.supplier_type IN ('deduction', 'deductions') OR s.code LIKE '4%' OR ci.name ILIKE '%تخصيم%' OR ci.name ILIKE '%فحص%'))
      )
      -- Specific Supplier Filter
      AND (
        p_supplier_id IS NULL
        OR s.id = p_supplier_id
      )
      -- Cost Status Filter
      AND (
        p_status IS NULL
        OR p_status = 'all'
        OR ci.cost_status = p_status
      )
      -- Search Filter
      AND (
        p_search IS NULL
        OR p_search = ''
        OR ci.name ILIKE '%' || p_search || '%'
        OR po.order_number ILIKE '%' || p_search || '%'
        OR s.name ILIKE '%' || p_search || '%'
        OR s.code ILIKE '%' || p_search || '%'
        OR ci.invoice_ref ILIKE '%' || p_search || '%'
      )
      -- Shipment / Packing Order Numeric Range Filter (Inclusive)
      AND (
        p_from_order_id IS NULL
        OR COALESCE(
          NULLIF(
            substring(
              translate(COALESCE(po.order_number, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')
              FROM '(\d{1,15})$'
            ),
            ''
          )::BIGINT,
          ci.packing_order_id::BIGINT
        ) >= p_from_order_id
      )
      AND (
        p_to_order_id IS NULL
        OR COALESCE(
          NULLIF(
            substring(
              translate(COALESCE(po.order_number, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')
              FROM '(\d{1,15})$'
            ),
            ''
          )::BIGINT,
          ci.packing_order_id::BIGINT
        ) <= p_to_order_id
      )
    ORDER BY
      CASE WHEN ci.cost_status = 'expected' THEN 0 ELSE 1 END,
      ci.id DESC
    LIMIT p_limit
    OFFSET p_offset
  ) item_row;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_supplier_expected_cost_items(TEXT, UUID, TEXT, TEXT, INT, INT, INT, INT) TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;
