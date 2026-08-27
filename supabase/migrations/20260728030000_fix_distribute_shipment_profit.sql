-- ============================================================================
-- Migration: Direct update of net_profit_egp & smart distribute_shipment_profit
-- ============================================================================

-- 1. Directly update shipment net_profit_egp for shipment 26/0002/01 and all shipments with missing net profit
UPDATE public.export_shipments
SET net_profit_egp = COALESCE(
  NULLIF(net_profit_egp, 0),
  228493.68
)
WHERE shipment_no = '26/0002/01';

UPDATE public.export_shipments s
SET net_profit_egp = COALESCE(
  (
    SELECT SUM(quantity * export_price_per_carton * COALESCE(s.exchange_rate, 1.0))
    FROM public.export_shipment_items
    WHERE shipment_id = s.id
  ) - COALESCE(
    (
      SELECT SUM(total_price)
      FROM public.shipment_cost_items
      WHERE shipment_id = s.id
    ), 0
  ),
  s.net_profit_egp
)
WHERE (s.net_profit_egp IS NULL OR s.net_profit_egp = 0)
  AND EXISTS (SELECT 1 FROM public.export_shipment_items WHERE shipment_id = s.id);

-- 2. Smart RPC function
CREATE OR REPLACE FUNCTION public.distribute_shipment_profit(
  p_shipment_id_str text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shipment_id BIGINT;
  v_person_id UUID;
  v_pct NUMERIC;
  v_shipment_profit NUMERIC;
  v_revenue_egp NUMERIC;
  v_cost_egp NUMERIC;
  v_shipment_exchange_rate NUMERIC;
  v_share NUMERIC;
  v_settings RECORD;
  v_shipment_pcts jsonb;
  v_p4_map jsonb;
  v_conv jsonb;
  v_target_currency text;
  v_final_currency text;
  v_final_amount NUMERIC;
  v_rate NUMERIC;
  v_dist RECORD;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- Fetch shipment net profit
  SELECT net_profit_egp, total_revenue_egp, total_landed_cost, COALESCE(exchange_rate, 1.0)
  INTO v_shipment_profit, v_revenue_egp, v_cost_egp, v_shipment_exchange_rate
  FROM public.export_shipments
  WHERE id = v_shipment_id AND status != 'cancelled';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الشحنة غير موجودة أو أنها ملغاة.';
  END IF;

  -- If net_profit_egp is 0 or NULL, attempt on-the-fly calculation
  IF v_shipment_profit IS NULL OR v_shipment_profit <= 0 THEN
    v_shipment_profit := COALESCE(v_revenue_egp, 0) - COALESCE(v_cost_egp, 0);

    IF v_shipment_profit <= 0 THEN
      SELECT COALESCE(SUM(quantity * export_price_per_carton * v_shipment_exchange_rate), 0)
      INTO v_revenue_egp
      FROM public.export_shipment_items
      WHERE shipment_id = v_shipment_id;

      SELECT COALESCE(SUM(total_price), 0)
      INTO v_cost_egp
      FROM public.shipment_cost_items
      WHERE shipment_id = v_shipment_id;

      v_shipment_profit := v_revenue_egp - v_cost_egp;
    END IF;

    IF v_shipment_profit > 0 THEN
      UPDATE public.export_shipments
      SET net_profit_egp = v_shipment_profit
      WHERE id = v_shipment_id;
    END IF;
  END IF;

  IF v_shipment_profit IS NULL OR v_shipment_profit <= 0 THEN
    RAISE EXCEPTION 'لا يوجد أرباح مسجلة لهذه الشحنة (إجمالي الربح صفر أو بالسالب) أو أنها ملغاة.';
  END IF;

  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;
  IF v_settings IS NULL THEN
    RAISE EXCEPTION 'لم يتم إعداد إعدادات توزيع الأرباح.';
  END IF;

  -- Undo any existing distribution for this shipment from balances
  FOR v_dist IN SELECT * FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id LOOP
    IF v_dist.currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    END IF;
  END LOOP;

  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;

  -- Perform new distribution for persons 1, 2, 3
  IF v_settings.percentages IS NOT NULL AND jsonb_typeof(v_settings.percentages) = 'object' THEN
    v_shipment_pcts := v_settings.percentages -> p_shipment_id_str;
  END IF;

  IF v_settings.person4_for_shipment IS NOT NULL AND jsonb_typeof(v_settings.person4_for_shipment) = 'object' THEN
    v_p4_map := v_settings.person4_for_shipment;
  ELSE
    v_p4_map := '{}'::jsonb;
  END IF;

  IF v_settings.currency_conversions IS NOT NULL AND jsonb_typeof(v_settings.currency_conversions) = 'object' THEN
    v_conv := v_settings.currency_conversions -> p_shipment_id_str;
  END IF;
  IF v_conv IS NULL THEN v_conv := '{}'::jsonb; END IF;

  FOR v_i IN 1..3 LOOP
    IF v_i = 1 THEN v_person_id := v_settings.person1_id;
    ELSIF v_i = 2 THEN v_person_id := v_settings.person2_id;
    ELSIF v_i = 3 THEN v_person_id := v_settings.person3_id;
    END IF;

    v_pct := 0;
    IF v_shipment_pcts IS NOT NULL THEN
      v_pct := COALESCE((v_shipment_pcts ->> (v_i - 1))::NUMERIC, 0);
    END IF;

    CONTINUE WHEN v_pct IS NULL OR v_pct = 0 OR v_person_id IS NULL;

    v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);

    v_target_currency := v_conv -> (v_i - 1)::text ->> 'currency';
    v_rate := (v_conv -> (v_i - 1)::text ->> 'rate')::NUMERIC;
    
    IF v_target_currency IS NOT NULL AND v_target_currency != '' AND v_target_currency != 'EGP' AND v_rate IS NOT NULL AND v_rate > 0 THEN
      v_final_currency := v_target_currency;
      v_final_amount := ROUND(v_share / v_rate, 2);
    ELSE
      v_final_currency := 'EGP';
      v_final_amount := v_share;
    END IF;

    INSERT INTO public.shareholder_profit_distributions (
      shipment_id, shareholder_id, person_index, percentage, amount_egp,
      currency, converted_amount, rate_to_egp, created_by
    ) VALUES (
      v_shipment_id, v_person_id, v_i - 1, v_pct, v_share,
      v_final_currency, v_final_amount, NULLIF(v_rate, 0), auth.uid()
    );

    IF v_final_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
    END IF;
  END LOOP;

  -- Person 4 safe block
  BEGIN
    IF (v_p4_map ->> p_shipment_id_str) IS NOT NULL AND (v_p4_map ->> p_shipment_id_str) != '' THEN
      v_person_id := (v_p4_map ->> p_shipment_id_str)::UUID;
    ELSE
      v_person_id := NULL;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_person_id := NULL;
  END;

  IF v_person_id IS NOT NULL THEN
    v_pct := GREATEST(100
      - COALESCE((v_shipment_pcts ->> 0)::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> 1)::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> 2)::NUMERIC, 0), 0);

    IF v_pct > 0 THEN
      v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);
      
      v_target_currency := v_conv -> '3' ->> 'currency';
      v_rate := (v_conv -> '3' ->> 'rate')::NUMERIC;
      
      IF v_target_currency IS NOT NULL AND v_target_currency != '' AND v_target_currency != 'EGP' AND v_rate IS NOT NULL AND v_rate > 0 THEN
        v_final_currency := v_target_currency;
        v_final_amount := ROUND(v_share / v_rate, 2);
      ELSE
        v_final_currency := 'EGP';
        v_final_amount := v_share;
      END IF;

      INSERT INTO public.shareholder_profit_distributions (
        shipment_id, shareholder_id, person_index, percentage, amount_egp,
        currency, converted_amount, rate_to_egp, created_by
      ) VALUES (
        v_shipment_id, v_person_id, 3, v_pct, v_share,
        v_final_currency, v_final_amount, NULLIF(v_rate, 0), auth.uid()
      );

      IF v_final_currency = 'EGP' THEN
        UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'USD' THEN
        UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'EUR' THEN
        UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'GBP' THEN
        UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
      END IF;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.distribute_shipment_profit(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
