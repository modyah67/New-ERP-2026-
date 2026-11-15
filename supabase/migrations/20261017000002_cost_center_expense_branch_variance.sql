-- ============================================================================
-- Migration: 20261017000002_cost_center_expense_branch_variance.sql
-- Description: RPC function to aggregate cost center expenses by their main branches
--              (مصاريف المهندسين، النقل، مواد التعبئة، المحاصيل، التعبئة، الشحن، التخليص، الإدارية)
--              calculating Estimated Cost vs Actual Settled Cost, Variance,
--              and Variance Percentage accurately without violating accounting constraints.
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
    v_target_crop TEXT := NULL;
    v_target_code TEXT := NULL;
    v_target_prod_id BIGINT := NULL;
BEGIN
    -- 1. Identify Target Cost Center Attributes if filtering
    IF v_clean_cc IS NOT NULL AND v_clean_cc <> 'all' AND v_clean_cc <> 'ALL' THEN
        SELECT 
            COALESCE(crop_code, code),
            code,
            product_id
        INTO 
            v_target_crop,
            v_target_code,
            v_target_prod_id
        FROM public.cost_centers
        WHERE id::TEXT = v_clean_cc 
           OR code = v_clean_cc 
           OR name_ar = v_clean_cc
        LIMIT 1;
    END IF;

    RETURN QUERY
    WITH raw_entries AS (
        -- ─────────────────────────────────────────────────────────────────
        -- A. Packing Order Additional Cost Items (بنود التكاليف الإضافية)
        -- ─────────────────────────────────────────────────────────────────
        SELECT 
            CASE 
                WHEN ci.category IN ('engineer_expenses', 'engineer') 
                  OR ci.name ~* '(مهندس|مهندسين|إشراف|اشراف)' THEN 'مصاريف مهندسين'
                WHEN ci.category IN ('logistics', 'transport') 
                  OR ci.name ~* '(نقل|مشال|نولون|سائق|سيارة)' THEN 'لوجستيك ونقل'
                WHEN ci.category = 'material' 
                  OR ci.name ~* '(كرتون|ورق|زوايا|طبالي|بلاستيك)' THEN 'مواد التعبئة'
                WHEN ci.category = 'packing' 
                  OR ci.name ~* '(محطة|تعبئة|تخصيم|عمالة)' THEN 'تعبئة وتغليف'
                WHEN ci.category = 'fruit' 
                  OR ci.name ~* '(محصول|شراء)' THEN 'تكلفة المحاصيل'
                WHEN ci.category = 'admin' 
                  OR ci.name ~* '(إدار|ادار)' THEN 'مصاريف إدارية'
                ELSE COALESCE(rc.name, ci.name, 'مصاريف أخرى')
            END AS b_name,
            CASE 
                WHEN ci.category IN ('engineer_expenses', 'engineer') 
                  OR ci.name ~* '(مهندس|مهندسين|إشراف|اشراف)' THEN 'engineer_expenses'
                WHEN ci.category IN ('logistics', 'transport') 
                  OR ci.name ~* '(نقل|مشال|نولون|سائق|سيارة)' THEN 'logistics'
                WHEN ci.category = 'material' 
                  OR ci.name ~* '(كرتون|ورق|زوايا|طبالي|بلاستيك)' THEN 'material'
                WHEN ci.category = 'packing' 
                  OR ci.name ~* '(محطة|تعبئة|تخصيم|عمالة)' THEN 'packing'
                WHEN ci.category = 'fruit' 
                  OR ci.name ~* '(محصول|شراء)' THEN 'fruit'
                WHEN ci.category = 'admin' 
                  OR ci.name ~* '(إدار|ادار)' THEN 'admin'
                ELSE 'other'
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
                'status', ci.cost_status
            ) AS item_meta
        FROM public.packing_order_cost_items ci
        JOIN public.packing_orders po ON po.id = ci.packing_order_id
        LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
        LEFT JOIN public.cost_report_categories rc ON rc.id = ci.report_category_id
        WHERE (p_from_date IS NULL OR po.created_at::DATE >= p_from_date)
          AND (p_to_date IS NULL OR po.created_at::DATE <= p_to_date)
          AND (p_customer IS NULL OR p_customer = 'all' OR s.customer_name = p_customer)
          AND (
            v_clean_cc IS NULL 
            OR v_clean_cc = 'all' 
            OR v_clean_cc = 'ALL'
            OR po.product_name = v_clean_cc
            OR (v_target_crop IS NOT NULL AND po.product_name ILIKE '%' || v_target_crop || '%')
            OR (v_target_prod_id IS NOT NULL AND po.fruit_type_id = v_target_prod_id)
            OR (v_target_code IS NOT NULL AND (v_target_code = 'CC-PACKING' OR v_target_code = 'packing_station'))
          )

        UNION ALL

        -- ─────────────────────────────────────────────────────────────────
        -- B. Packing Orders Fruit / Crop Cost (تكلفة المحاصيل)
        -- ─────────────────────────────────────────────────────────────────
        SELECT 
            'تكلفة المحاصيل' AS b_name,
            'fruit' AS b_code,
            COALESCE(NULLIF(po.fruit_cost_base, 0), po.fruit_cost_allocated, 0)::NUMERIC AS est_amt,
            COALESCE(po.fruit_cost_allocated, 0)::NUMERIC AS act_amt,
            CASE WHEN po.crops_confirmed_at IS NOT NULL OR po.status = 'completed' THEN 1 ELSE 0 END AS is_settled,
            CASE WHEN po.crops_confirmed_at IS NULL AND po.status <> 'completed' THEN 1 ELSE 0 END AS is_pending,
            jsonb_build_object(
                'id', po.id,
                'name', 'تكلفة المحصول الخام - ' || COALESCE(po.product_name, 'محصول'),
                'source', 'packing_orders_fruit',
                'order_number', po.order_number,
                'expected', po.fruit_cost_base,
                'actual', po.fruit_cost_allocated,
                'status', CASE WHEN po.crops_confirmed_at IS NOT NULL THEN 'settled' ELSE 'expected' END
            ) AS item_meta
        FROM public.packing_orders po
        LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
        WHERE (po.fruit_cost_base > 0 OR po.fruit_cost_allocated > 0)
          AND (p_from_date IS NULL OR po.created_at::DATE >= p_from_date)
          AND (p_to_date IS NULL OR po.created_at::DATE <= p_to_date)
          AND (p_customer IS NULL OR p_customer = 'all' OR s.customer_name = p_customer)
          AND (
            v_clean_cc IS NULL 
            OR v_clean_cc = 'all' 
            OR v_clean_cc = 'ALL'
            OR po.product_name = v_clean_cc
            OR (v_target_crop IS NOT NULL AND po.product_name ILIKE '%' || v_target_crop || '%')
            OR (v_target_prod_id IS NOT NULL AND po.fruit_type_id = v_target_prod_id)
          )

        UNION ALL

        -- ─────────────────────────────────────────────────────────────────
        -- C. Packing Orders Packaging Materials (مواد التعبئة)
        -- ─────────────────────────────────────────────────────────────────
        SELECT 
            'مواد التعبئة' AS b_name,
            'material' AS b_code,
            COALESCE(
                NULLIF(po.material_cost_base, 0), 
                NULLIF(po.estimated_material_cost, 0), 
                po.actual_material_cost, 
                0
            )::NUMERIC AS est_amt,
            COALESCE(po.actual_material_cost, 0)::NUMERIC AS act_amt,
            CASE WHEN po.packaging_confirmed_at IS NOT NULL OR po.status = 'completed' THEN 1 ELSE 0 END AS is_settled,
            CASE WHEN po.packaging_confirmed_at IS NULL AND po.status <> 'completed' THEN 1 ELSE 0 END AS is_pending,
            jsonb_build_object(
                'id', po.id,
                'name', 'مواد التعبئة والتغليف - أمر #' || po.order_number,
                'source', 'packing_orders_packaging',
                'order_number', po.order_number,
                'expected', COALESCE(NULLIF(po.material_cost_base, 0), po.estimated_material_cost, 0),
                'actual', po.actual_material_cost,
                'status', CASE WHEN po.packaging_confirmed_at IS NOT NULL THEN 'settled' ELSE 'expected' END
            ) AS item_meta
        FROM public.packing_orders po
        LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
        WHERE (po.material_cost_base > 0 OR po.actual_material_cost > 0)
          AND (p_from_date IS NULL OR po.created_at::DATE >= p_from_date)
          AND (p_to_date IS NULL OR po.created_at::DATE <= p_to_date)
          AND (p_customer IS NULL OR p_customer = 'all' OR s.customer_name = p_customer)
          AND (
            v_clean_cc IS NULL 
            OR v_clean_cc = 'all' 
            OR v_clean_cc = 'ALL'
            OR po.product_name = v_clean_cc
            OR (v_target_crop IS NOT NULL AND po.product_name ILIKE '%' || v_target_crop || '%')
            OR (v_target_prod_id IS NOT NULL AND po.fruit_type_id = v_target_prod_id)
            OR (v_target_code IS NOT NULL AND (v_target_code = 'CC-PACKING' OR v_target_code = 'packing_station'))
          )

        UNION ALL

        -- ─────────────────────────────────────────────────────────────────
        -- D. Direct Cost Center Transactions (strictly excluding rollovers)
        -- ─────────────────────────────────────────────────────────────────
        SELECT 
            CASE 
                WHEN cct.category ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.item_name ~* '(مهندس|مهندسين|إشراف|اشراف)' THEN 'مصاريف مهندسين'
                WHEN cct.category ~* '(نقل|لوجست|مشال|نولون)' 
                  OR cct.item_name ~* '(نقل|لوجست|مشال|نولون)' THEN 'لوجستيك ونقل'
                WHEN cct.category ~* '(تعبئة|كرتون|ورق)' 
                  OR cct.item_name ~* '(تعبئة|كرتون|ورق)' THEN 'مواد التعبئة'
                WHEN cct.category ~* '(شحن|بحري|جوي|خط ملاحي)' 
                  OR cct.item_name ~* '(شحن|بحري|جوي|خط ملاحي)' THEN 'تكلفة شركات الشحن'
                WHEN cct.category ~* '(تخليص|مخلص|جمارك)' 
                  OR cct.item_name ~* '(تخليص|مخلص|جمارك)' THEN 'تكلفة المخلصين'
                WHEN cct.category ~* '(محصول|خام|شراء)' 
                  OR cct.item_name ~* '(محصول|خام|شراء)' THEN 'تكلفة المحاصيل'
                WHEN cct.category ~* '(إدار|ادار)' 
                  OR cct.item_name ~* '(إدار|ادار)' THEN 'مصاريف إدارية'
                ELSE COALESCE(cct.category, 'مصاريف تشغيلية')
            END AS b_name,
            CASE 
                WHEN cct.category ~* '(مهندس|مهندسين|إشراف|اشراف)' 
                  OR cct.item_name ~* '(مهندس|مهندسين|إشراف|اشراف)' THEN 'engineer_expenses'
                WHEN cct.category ~* '(نقل|لوجست|مشال|نولون)' 
                  OR cct.item_name ~* '(نقل|لوجست|مشال|نولون)' THEN 'logistics'
                WHEN cct.category ~* '(تعبئة|كرتون|ورق)' 
                  OR cct.item_name ~* '(تعبئة|كرتون|ورق)' THEN 'material'
                WHEN cct.category ~* '(شحن|بحري|جوي|خط ملاحي)' 
                  OR cct.item_name ~* '(شحن|بحري|جوي|خط ملاحي)' THEN 'shipping'
                WHEN cct.category ~* '(تخليص|مخلص|جمارك)' 
                  OR cct.item_name ~* '(تخليص|مخلص|جمارك)' THEN 'clearance'
                WHEN cct.category ~* '(محصول|خام|شراء)' 
                  OR cct.item_name ~* '(محصول|خام|شراء)' THEN 'fruit'
                WHEN cct.category ~* '(إدار|ادار)' 
                  OR cct.item_name ~* '(إدار|ادار)' THEN 'admin'
                ELSE 'operational'
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
                'status', 'settled'
            ) AS item_meta
        FROM public.cost_center_transactions cct
        WHERE cct.is_confirmed = TRUE
          -- Strictly exclude carried forward opening balance snapshots
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
            OR cct.cost_center_id = v_clean_cc 
            OR cct.cost_center_name = v_clean_cc
            OR (v_target_code IS NOT NULL AND cct.cost_center_id = v_target_code)
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
    GROUP BY raw.b_name, raw.b_code
    ORDER BY 
        CASE raw.b_name
            WHEN 'مصاريف مهندسين' THEN 1
            WHEN 'لوجستيك ونقل' THEN 2
            WHEN 'مواد التعبئة' THEN 3
            WHEN 'تعبئة وتغليف' THEN 4
            WHEN 'تكلفة المحاصيل' THEN 5
            WHEN 'تكلفة شركات الشحن' THEN 6
            WHEN 'تكلفة المخلصين' THEN 7
            WHEN 'مصاريف إدارية' THEN 8
            ELSE 9
        END,
        actual_cost DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_cost_center_expense_branch_variance(TEXT, DATE, DATE, TEXT) 
  TO authenticated, service_role, anon;
