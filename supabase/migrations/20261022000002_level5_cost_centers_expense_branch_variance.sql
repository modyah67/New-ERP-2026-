-- ============================================================================
-- Migration: 20261022000002_level5_cost_centers_expense_branch_variance.sql
-- Description: RPC function strictly restricted to Level 5 accounts under code 3
--              (المستوى الخامس فقط - 5 digits / Level 5 analytical accounts),
--              centering on 31251 - مصاريف مهندسين and Level 5 operational items,
--              while completely excluding Level 3 (3 digits) and Level 4 (4 digits).
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
    WITH raw_entries AS (
        -- ─────────────────────────────────────────────────────────────────
        -- 1. Packing Order Cost Items (بنود تكاليف أوامر التعبئة)
        -- Strictly Level 5 under Root 3 (LENGTH >= 5 AND NOT IN (3, 4))
        -- ─────────────────────────────────────────────────────────────────
        SELECT 
            CASE 
                -- Specific Engineer Expenses mapping to 31251 (Level 5)
                WHEN ci.category IN ('engineer_expenses', 'engineer') 
                  OR ci.name ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR acc.account_code = '31251' 
                  OR acc.code = '31251' THEN '31251 - مصاريف مهندسين'
                -- Other Level 5 accounts directly mapped from COA
                WHEN COALESCE(acc.account_code, acc.code) LIKE '3%' 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 THEN 
                    COALESCE(acc.account_code, acc.code) || ' - ' || COALESCE(acc.account_name, acc.name_ar, ci.name)
                ELSE NULL
            END AS b_name,
            CASE 
                WHEN ci.category IN ('engineer_expenses', 'engineer') 
                  OR ci.name ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR acc.account_code = '31251' 
                  OR acc.code = '31251' THEN '31251'
                WHEN COALESCE(acc.account_code, acc.code) LIKE '3%' 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 THEN 
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

        -- ─────────────────────────────────────────────────────────────────
        -- 2. Direct Cost Center Transactions (حركات مراكز التكلفة المباشرة)
        -- Strictly Level 5 under Root 3 (LENGTH >= 5 AND NOT IN (3, 4))
        -- ─────────────────────────────────────────────────────────────────
        SELECT 
            CASE 
                WHEN cct.category ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.item_name ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.cost_center_id = '31251' 
                  OR acc.account_code = '31251' 
                  OR acc.code = '31251' THEN '31251 - مصاريف مهندسين'
                WHEN COALESCE(acc.account_code, acc.code) LIKE '3%' 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 THEN 
                    COALESCE(acc.account_code, acc.code) || ' - ' || COALESCE(acc.account_name, acc.name_ar, cct.item_name)
                ELSE NULL
            END AS b_name,
            CASE 
                WHEN cct.category ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.item_name ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.cost_center_id = '31251' 
                  OR acc.account_code = '31251' 
                  OR acc.code = '31251' THEN '31251'
                WHEN COALESCE(acc.account_code, acc.code) LIKE '3%' 
                 AND LENGTH(COALESCE(acc.account_code, acc.code)) >= 5 THEN 
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
    )
    SELECT 
        raw.b_name::TEXT AS branch_name,
        raw.b_code::TEXT AS category_code,
        COALESCE(SUM(raw.est_amt), 0)::NUMERIC AS estimated_cost,
        COALESCE(SUM(raw.act_amt), 0)::NUMERIC AS actual_cost,
        COALESCE(SUM(raw.act_amt) - SUM(raw.est_amt), 0)::NUMERIC AS variance_amount,
        CASE 
            WHEN SUM(raw.est_amt) > 0 THEN 
                ROUND(((SUM(raw.act_amt) - SUM(raw.est_amt)) / SUM(raw.est_amt) * 100)::NUMERIC, 2)
            ELSE 0::NUMERIC 
        END AS variance_percentage,
        COUNT(*)::BIGINT AS transaction_count,
        COALESCE(SUM(raw.is_settled), 0)::BIGINT AS settled_count,
        COALESCE(SUM(raw.is_pending), 0)::BIGINT AS pending_count,
        jsonb_agg(raw.item_meta) AS details
    FROM raw_entries raw
    -- Strictly require Level 5 under Code 3: b_code starts with '3' and length >= 5
    -- Strictly exclude Level 3 (3 digits) and Level 4 (4 digits)
    WHERE raw.b_code IS NOT NULL 
      AND raw.b_name IS NOT NULL
      AND raw.b_code LIKE '3%'
      AND LENGTH(raw.b_code) >= 5
      AND LENGTH(raw.b_code) NOT IN (3, 4)
    GROUP BY raw.b_name, raw.b_code
    ORDER BY 
        CASE WHEN raw.b_code = '31251' THEN 0 ELSE 1 END,
        actual_cost DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_cost_center_expense_branch_variance(TEXT, DATE, DATE, TEXT) 
  TO authenticated, service_role, anon;
