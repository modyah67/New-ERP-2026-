-- Add ORDER BY updated_at DESC, created_at DESC to ensure the latest exchange rate is fetched.

CREATE OR REPLACE FUNCTION public.fn_get_exchange_rate(p_currency TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    IF p_currency IS NULL OR p_currency = 'EGP' THEN
        RETURN 1.0;
    END IF;

    SELECT rate_to_egp INTO v_rate
    FROM public.exchange_rates
    WHERE currency_code = p_currency
    ORDER BY updated_at DESC, created_at DESC
    LIMIT 1;

    IF v_rate IS NULL OR v_rate <= 0 THEN
        RAISE EXCEPTION 'لم يتم العثور على سعر صرف معتمد للعملة (%) في جدول أسعار الصرف', p_currency;
    END IF;

    RETURN v_rate;
END;
$$;
