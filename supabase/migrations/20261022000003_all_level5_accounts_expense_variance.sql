-- ============================================================================
-- Migration: 20261022000003_all_level5_accounts_expense_variance.sql
-- Description: RPC function returning ALL Level 5 expense accounts under code 3
--              (LIKE '3%' AND LENGTH >= 5 AND NOT IN (3, 4))
--              comparing estimated, actual, and variance for each branch independently.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_cost_center_expense_branch_variance(
    p_cost_center_id TEXT DEFAULT NULL,
    p_from_date DATE DEFAULT NULL,
    p_to_date DATE DEFAULT NULL,
    p_customer TEXT DEFAULT NULL
)
RETURNS TABLE (
    branch_name TEXT,
    category_code TEXT,
    estimated_cost NUMERIC,
    actual_cost NUMERIC,
    variance_amount NUMERIC,
    variance_percentage NUMERIC,
    transaction_count BIGINT,
    settled_count BIGINT,
    pending_count BIGINT,
    details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_clean_cc TEXT := NULLIF(TRIM(COALESCE(p_cost_center_id, '')), '');
BEGIN
    RETURN QUERY
    WITH level5_accounts AS (
        SELECT 
            acc.id AS account_id,
            COALESCE(acc.account_code, acc.code) AS b_code,
            COALESCE(acc.account_code, acc.code) || ' - ' || COALESCE(acc.account_name, acc.name_ar, 'مصروف فرعي') AS b_name
        FROM public.accounts acc
        WHERE (acc.account_code LIKE '3%' OR acc.code LIKE '3%')
          AND (
            acc.is_leaf = TRUE 
            OR acc.level = 5 
            OR (LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 AND LENGTH(COALESCE(acc.account_code, acc.code)) NOT IN (3, 4))
          )
    ),
    raw_entries AS (
        -- 1. Packing Order Cost Items
        SELECT 
            CASE 
                WHEN ci.category IN ('engineer_expenses', 'engineer') 
                  OR ci.name ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR acc.account_code = '31251' 
                  OR acc.code = '31251' THEN '31251'
                WHEN COALESCE(acc.account_code, acc.code) LIKE '3%' 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) NOT IN (3, 4) THEN 
                    COALESCE(acc.account_code, acc.code)
                ELSE NULL
            END AS b_code,
            COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0)::NUMERIC AS est_amt,
            COALESCE(
                ci.actual_amount, 
                CASE 
                    WHEN ci.cost_status IN ('settled', 'actual') THEN ci.base_amount 
                    ELSE 0 
                END
            )::NUMERIC AS act_amt,
            CASE 
                WHEN ci.actual_amount IS NOT NULL OR ci.cost_status IN ('settled', 'actual') THEN 1 
                ELSE 0 
            END AS is_settled,
            CASE 
                WHEN (ci.cost_status = 'expected' OR ci.cost_status = 'estimated') AND ci.actual_amount IS NULL THEN 1 
                ELSE 0 
            END AS is_pending,
            jsonb_build_object(
                'id', ci.id,
                'name', ci.name,
                'source', 'packing_order_cost_items',
                'order_number', po.order_number,
                'expected', COALESCE(NULLIF(ci.expected_amount, 0), ci.base_amount, 0),
                'actual', ci.actual_amount,
                'status', ci.cost_status,
                'level', 5
            ) AS item_meta
        FROM public.packing_order_cost_items ci
        JOIN public.packing_orders po ON po.id = ci.packing_order_id
        LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
        LEFT JOIN public.cost_report_categories rc ON rc.id = ci.report_category_id
        LEFT JOIN public.accounts acc ON (acc.id = rc.account_id OR acc.account_code = rc.code)
        WHERE (p_from_date IS NULL OR po.created_at::DATE >= p_from_date)
          AND (p_to_date IS NULL OR po.created_at::DATE <= p_to_date)
          AND (p_customer IS NULL OR p_customer = 'all' OR s.customer_name = p_customer)
          AND (
            v_clean_cc IS NULL 
            OR v_clean_cc = 'all' 
            OR v_clean_cc = 'ALL'
            OR v_clean_cc = '31251'
            OR po.product_name = v_clean_cc
          )

        UNION ALL

        -- 2. Direct Cost Center Transactions
        SELECT 
            CASE 
                WHEN cct.category ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.item_name ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.cost_center_id = '31251' 
                  OR acc.account_code = '31251' 
                  OR acc.code = '31251' THEN '31251'
                WHEN COALESCE(acc.account_code, acc.code) LIKE '3%' 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) NOT IN (3, 4) THEN 
                    COALESCE(acc.account_code, acc.code)
                ELSE NULL
            END AS b_code,
            cct.amount::NUMERIC AS est_amt,
            cct.amount::NUMERIC AS act_amt,
            1 AS is_settled,
            0 AS is_pending,
            jsonb_build_object(
                'id', cct.id,
                'name', cct.item_name,
                'source', 'cost_center_transactions',
                'source_type', cct.source_type,
                'expected', cct.amount,
                'actual', cct.amount,
                'status', 'settled',
                'level', 5
            ) AS item_meta
        FROM public.cost_center_transactions cct
        LEFT JOIN public.accounts acc ON (acc.id::TEXT = cct.cost_center_id OR acc.account_code = cct.cost_center_id OR acc.code = cct.cost_center_id)
        WHERE cct.is_confirmed = TRUE
          AND cct.is_opening_balance = FALSE
          AND (cct.transaction_type IS NULL OR cct.transaction_type <> 'carried_forward')
          AND cct.source_type NOT IN ('opening_balance', 'season_rollover', 'packing_order_costs', 'packing_order_material')
          AND (cct.source_id IS NULL OR cct.source_id !~ '^rollover_')
          AND (p_from_date IS NULL OR cct.transaction_date >= p_from_date)
          AND (p_to_date IS NULL OR cct.transaction_date <= p_to_date)
          AND (
            v_clean_cc IS NULL 
            OR v_clean_cc = 'all' 
            OR v_clean_cc = 'ALL'
            OR v_clean_cc = '31251'
            OR cct.cost_center_id = v_clean_cc 
            OR cct.cost_center_name = v_clean_cc
          )
    ),
    aggregated_raw AS (
        SELECT 
            raw.b_code,
            COALESCE(SUM(raw.est_amt), 0)::NUMERIC AS estimated_cost,
            COALESCE(SUM(raw.act_amt), 0)::NUMERIC AS actual_cost,
            COUNT(*)::BIGINT AS transaction_count,
            COALESCE(SUM(raw.is_settled), 0)::BIGINT AS settled_count,
            COALESCE(SUM(raw.is_pending), 0)::BIGINT AS pending_count,
            jsonb_agg(raw.item_meta) AS details
        FROM raw_entries raw
        WHERE raw.b_code IS NOT NULL
        GROUP BY raw.b_code
    )
    SELECT 
        COALESCE(l5.b_name, agg.b_code || ' - مصروف تحليلي')::TEXT AS branch_name,
        COALESCE(l5.b_code, agg.b_code)::TEXT AS category_code,
        COALESCE(agg.estimated_cost, 0)::NUMERIC AS estimated_cost,
        COALESCE(agg.actual_cost, 0)::NUMERIC AS actual_cost,
        (COALESCE(agg.actual_cost, 0) - COALESCE(agg.estimated_cost, 0))::NUMERIC AS variance_amount,
        CASE 
            WHEN COALESCE(agg.estimated_cost, 0) > 0 THEN 
                ROUND(((COALESCE(agg.actual_cost, 0) - agg.estimated_cost) / agg.estimated_cost * 100)::NUMERIC, 2)
            ELSE 0::NUMERIC 
        END AS variance_percentage,
        COALESCE(agg.transaction_count, 0)::BIGINT AS transaction_count,
        COALESCE(agg.settled_count, 0)::BIGINT AS settled_count,
        COALESCE(agg.pending_count, 0)::BIGINT AS pending_count,
        COALESCE(agg.details, '[]'::JSONB) AS details
    FROM level5_accounts l5
    FULL OUTER JOIN aggregated_raw agg ON agg.b_code = l5.b_code
    WHERE (
        v_clean_cc IS NULL 
        OR v_clean_cc = 'all' 
        OR v_clean_cc = 'ALL' 
        OR COALESCE(l5.b_code, agg.b_code) = v_clean_cc
    )
    ORDER BY 
        CASE WHEN COALESCE(l5.b_code, agg.b_code) = '31251' THEN 0 ELSE 1 END,
        COALESCE(l5.b_code, agg.b_code) ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_cost_center_expense_branch_variance(TEXT, DATE, DATE, TEXT) 
  TO authenticated, service_role, anon;
