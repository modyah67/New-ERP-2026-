-- ============================================================================
-- Migration 374: Route FX Gain/Loss in exchange_currency to 4310 and 6151
-- ============================================================================
-- Description:
-- 4310: أرباح فروق أسعار صرف العملات (Realized FX Gains)
-- 6151: خسائر فروق أسعار صرف العملات (Realized FX Losses)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id text,
    p_from_currency character varying,
    p_to_currency character varying,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid,
    p_transfer_mode text DEFAULT 'exchange'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_treasury_id         BIGINT := p_treasury_id::bigint;
    v_balance_before_from DECIMAL(15,2);
    v_balance_after_from  DECIMAL(15,2);
    v_cost_before_from    DECIMAL(15,2);
    v_rate_before_from    DECIMAL(15,4);
    v_new_cost_from       DECIMAL(15,2);
    v_new_rate_from       DECIMAL(15,4);

    v_balance_before_to   DECIMAL(15,2);
    v_balance_after_to    DECIMAL(15,2);
    v_cost_before_to      DECIMAL(15,2);
    v_rate_before_to      DECIMAL(15,4);
    v_new_cost_to         DECIMAL(15,2);
    v_new_rate_to         DECIMAL(15,4);

    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_fx_gain_loss_acct   BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
    v_base_amount         NUMERIC;
    v_cost_base_released  NUMERIC;
    v_realized_fx_diff    NUMERIC;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    IF p_from_currency != 'EGP' AND p_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
    END IF;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_from, v_cost_before_from, v_rate_before_from
    FROM treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_from_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate)
    VALUES (v_treasury_id, p_to_currency, 0.00, 0.00, 1.0000)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_to, v_cost_before_to, v_rate_before_to
    FROM treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_to_currency
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = v_treasury_id;

    v_desc := 'تحويل عملة من ' || p_from_currency || ' إلى ' || p_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE p_from_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE p_to_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    IF p_from_currency != 'EGP' THEN
        -- Selling foreign currency
        v_cost_base_released := ROUND(p_amount_from * v_rate_before_from, 2);
        v_new_cost_from := GREATEST(0, v_cost_before_from - v_cost_base_released);
        v_new_rate_from := CASE WHEN v_balance_after_from > 0 THEN ROUND(v_new_cost_from / v_balance_after_from, 4) ELSE v_rate_before_from END;

        v_new_cost_to := v_balance_after_to;
        v_new_rate_to := 1.0;
        v_realized_fx_diff := p_amount_to - v_cost_base_released;
    ELSE
        -- Buying foreign currency
        v_new_cost_from := v_balance_after_from;
        v_new_rate_from := 1.0;

        v_new_cost_to := v_cost_before_to + p_amount_from;
        v_new_rate_to := CASE WHEN v_balance_after_to > 0 THEN ROUND(v_new_cost_to / v_balance_after_to, 4) ELSE p_exchange_rate END;
        v_realized_fx_diff := 0;
    END IF;

    UPDATE treasury_balances
    SET balance = v_balance_after_from,
        cost_base = v_new_cost_from,
        book_rate = v_new_rate_from,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to,
        cost_base = v_new_cost_to,
        book_rate = v_new_rate_to,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND currency = p_to_currency;

    -- Base Amount is the EGP amount
    IF p_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    IF v_realized_fx_diff != 0 THEN
        IF v_realized_fx_diff > 0 THEN
            v_fx_gain_loss_acct := public.resolve_gl_account('4310', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', p_from_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', 0, 'credit', v_realized_fx_diff, 'base_debit', 0, 'base_credit', v_realized_fx_diff, 'currency', 'EGP', 'description', 'أرباح فروق عملة محققة')
                )
            );
        ELSE
            v_fx_gain_loss_acct := public.resolve_gl_account('6151', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', ABS(v_realized_fx_diff), 'credit', 0, 'base_debit', ABS(v_realized_fx_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق عملة محققة'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', p_from_currency, 'description', v_desc)
                )
            );
        END IF;
    ELSE
        v_je_id := public.post_journal_entry(
            'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
            jsonb_build_array(
                jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_from_currency, 'description', v_desc)
            )
        );
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency,
        v_desc || ' (صادر)', v_balance_before_from, v_balance_after_from,
        p_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency,
        v_desc || ' (وارد)', v_balance_before_to, v_balance_after_to,
        p_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'from_balance_after', v_balance_after_from,
        'to_balance_after', v_balance_after_to,
        'realized_fx_diff', v_realized_fx_diff
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_currency(text, character varying, character varying, numeric, numeric, numeric, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exchange_currency(text, character varying, character varying, numeric, numeric, numeric, uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.exchange_currency(text, character varying, character varying, numeric, numeric, numeric, uuid, text) TO service_role;

NOTIFY pgrst, 'reload_schema';
