-- ============================================================================
-- Seasonal / Yearly Cumulative Packaging Waste Balance (رصيد الهالك التراكمي للموسم)
-- ----------------------------------------------------------------------------
-- Opening balance shown on the packing-order waste screen BEFORE the accountant
-- enters the current order's waste percentage.
--
--   opening_balance = Σ packaging waste from shipment returns in the season
--                   − Σ waste settlements in the season by OTHER packing orders
--
-- The current order's own settlements are excluded (returned separately as
-- current_order_settled) so the client can apply:
--   remaining = opening_balance − max(current_order_settled, current_order_waste)
-- without double counting.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_seasonal_packing_waste_balance(
    p_season_start DATE,
    p_season_end DATE,
    p_current_packing_order_id BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_return_waste NUMERIC := 0;
    v_return_cartons NUMERIC := 0;
    v_returns_count INTEGER := 0;
    v_settled_others NUMERIC := 0;
    v_settled_current NUMERIC := 0;
    v_settlements_count INTEGER := 0;
    v_opening NUMERIC := 0;
BEGIN
    -- 1. Season-wide packaging waste from shipment returns
    SELECT
        COALESCE(SUM(
            COALESCE((item->>'damaged_cartons')::numeric, 0) *
            COALESCE((item->>'carton_unit_cost')::numeric, 0)
        ), 0),
        COALESCE(SUM(COALESCE((item->>'damaged_cartons')::numeric, 0)), 0),
        COUNT(DISTINCT esr.id) FILTER (WHERE COALESCE((item->>'damaged_cartons')::numeric, 0) > 0)
    INTO v_return_waste, v_return_cartons, v_returns_count
    FROM public.export_shipment_returns esr
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(esr.raw_data->'items', '[]'::jsonb)) AS item
    WHERE esr.return_date::date BETWEEN p_season_start AND p_season_end;

    -- 2. Settlements in the season (split: other orders vs current order)
    SELECT
        COALESCE(SUM(amount) FILTER (
            WHERE p_current_packing_order_id IS NULL
               OR packing_order_id <> p_current_packing_order_id
        ), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE p_current_packing_order_id IS NOT NULL
              AND packing_order_id = p_current_packing_order_id
        ), 0),
        COUNT(*)
    INTO v_settled_others, v_settled_current, v_settlements_count
    FROM public.packing_order_waste_settlements
    WHERE settlement_date::date BETWEEN p_season_start AND p_season_end;

    v_opening := GREATEST(0, ROUND(v_return_waste - v_settled_others, 4));

    RETURN jsonb_build_object(
        'success', true,
        'season_start', p_season_start,
        'season_end', p_season_end,
        'season_return_waste', v_return_waste,
        'season_damaged_cartons', v_return_cartons,
        'season_returns_count', v_returns_count,
        'settled_by_other_orders', v_settled_others,
        'current_order_settled', v_settled_current,
        'settlements_count', v_settlements_count,
        'opening_balance', v_opening
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_seasonal_packing_waste_balance(DATE, DATE, BIGINT)
    TO authenticated, anon, service_role;
