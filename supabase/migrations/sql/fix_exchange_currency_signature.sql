-- ==============================================================================
-- Migration: Fix exchange_currency Signature to Support p_description & p_transfer_mode
-- Fixes: PostgrestException: function public.exchange_currency(p_treasury_id => text, p_from_currency => text, ...) does not exist
-- ==============================================================================

-- 1. Drop all existing overloads of exchange_currency to avoid parameter mismatch conflicts
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT oid::regprocedure AS func_sig 
             FROM pg_proc 
             WHERE proname = 'exchange_currency' 
               AND pronamespace = 'public'::regnamespace) 
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

-- 2. Create the unified exchange_currency function (TEXT treasury_id)
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id text,
    p_from_currency text,
    p_to_currency text,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid DEFAULT auth.uid(),
    p_transfer_mode text DEFAULT 'exchange',
    p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_treasury_id         BIGINT;
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
    v_user_id             UUID := COALESCE(p_user_id, auth.uid());
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF UPPER(p_from_currency) = UPPER(p_to_currency) THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    -- Clean treasury ID
    v_treasury_id := p_treasury_id::BIGINT;

    -- Description handling
    v_desc := COALESCE(
        NULLIF(TRIM(p_description), ''),
        'تحويل عملة من (' || p_amount_from || ' ' || UPPER(p_from_currency) || ') إلى (' || p_amount_to || ' ' || UPPER(p_to_currency) || ') بسعر ' || p_exchange_rate
    );

    -- 1. Lock from_currency row in treasury_balances
    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_from, v_cost_before_from, v_rate_before_from
    FROM public.treasury_balances
    WHERE treasury_id = v_treasury_id AND UPPER(currency) = UPPER(p_from_currency)
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    -- Ensure to_currency balance row exists
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate)
    VALUES (v_treasury_id, UPPER(p_to_currency), 0.00, 0.00, 1.0000)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_to, v_cost_before_to, v_rate_before_to
    FROM public.treasury_balances
    WHERE treasury_id = v_treasury_id AND UPPER(currency) = UPPER(p_to_currency)
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = v_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- Resolve GL Accounts for from_currency and to_currency
    v_from_acct := public.resolve_treasury_account(v_treasury_id, p_from_currency, v_company_id);
    IF v_from_acct IS NULL THEN
        v_from_acct := public.resolve_gl_account(
            CASE UPPER(p_from_currency) 
                WHEN 'EGP' THEN '12111' 
                WHEN 'USD' THEN '12122' 
                WHEN 'EUR' THEN '12123' 
                WHEN 'GBP' THEN '12124' 
                ELSE '12111' 
            END,
            v_company_id
        );
    END IF;
    IF v_from_acct IS NULL THEN
        v_from_acct := public.resolve_gl_account(
            CASE UPPER(p_from_currency) 
                WHEN 'EGP' THEN '11101' 
                WHEN 'USD' THEN '11102' 
                WHEN 'EUR' THEN '11103' 
                WHEN 'GBP' THEN '11104' 
                ELSE '11101' 
            END,
            v_company_id
        );
    END IF;

    v_to_acct := public.resolve_treasury_account(v_treasury_id, p_to_currency, v_company_id);
    IF v_to_acct IS NULL THEN
        v_to_acct := public.resolve_gl_account(
            CASE UPPER(p_to_currency) 
                WHEN 'EGP' THEN '12111' 
                WHEN 'USD' THEN '12122' 
                WHEN 'EUR' THEN '12123' 
                WHEN 'GBP' THEN '12124' 
                ELSE '12111' 
            END,
            v_company_id
        );
    END IF;
    IF v_to_acct IS NULL THEN
        v_to_acct := public.resolve_gl_account(
            CASE UPPER(p_to_currency) 
                WHEN 'EGP' THEN '11101' 
                WHEN 'USD' THEN '11102' 
                WHEN 'EUR' THEN '11103' 
                WHEN 'GBP' THEN '11104' 
                ELSE '11101' 
            END,
            v_company_id
        );
    END IF;

    -- Calculate balances and cost base
    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to   := v_balance_before_to + p_amount_to;

    IF UPPER(p_from_currency) != 'EGP' THEN
        -- Selling foreign currency -> release cost base
        v_cost_base_released := ROUND(p_amount_from * v_rate_before_from, 2);
        v_new_cost_from      := GREATEST(0, v_cost_before_from - v_cost_base_released);
        v_new_rate_from      := CASE WHEN v_balance_after_from > 0 THEN ROUND(v_new_cost_from / v_balance_after_from, 4) ELSE v_rate_before_from END;

        v_new_cost_to        := v_balance_after_to;
        v_new_rate_to        := 1.0;
        v_realized_fx_diff   := p_amount_to - v_cost_base_released;
    ELSE
        -- Buying foreign currency with EGP
        v_new_cost_from      := v_balance_after_from;
        v_new_rate_from      := 1.0;

        v_new_cost_to        := v_cost_before_to + p_amount_from;
        v_new_rate_to        := CASE WHEN v_balance_after_to > 0 THEN ROUND(v_new_cost_to / v_balance_after_to, 4) ELSE p_exchange_rate END;
        v_realized_fx_diff   := 0;
        v_cost_base_released := p_amount_from;
    END IF;

    -- Update treasury balances
    UPDATE public.treasury_balances
    SET balance    = v_balance_after_from,
        cost_base  = v_new_cost_from,
        book_rate  = v_new_rate_from,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND UPPER(currency) = UPPER(p_from_currency);

    UPDATE public.treasury_balances
    SET balance    = v_balance_after_to,
        cost_base  = v_new_cost_to,
        book_rate  = v_new_rate_to,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND UPPER(currency) = UPPER(p_to_currency);

    -- Base amount calculation
    IF UPPER(p_from_currency) = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    -- Post balanced Journal Entry
    IF v_realized_fx_diff != 0 THEN
        IF v_realized_fx_diff > 0 THEN
            v_fx_gain_loss_acct := public.resolve_realized_fx_gain_account(v_company_id);
            IF v_fx_gain_loss_acct IS NULL THEN
                v_fx_gain_loss_acct := public.resolve_gl_account('4310', v_company_id);
            END IF;
            IF v_fx_gain_loss_acct IS NULL THEN
                v_fx_gain_loss_acct := public.resolve_gl_account('4220', v_company_id);
            END IF;

            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', UPPER(p_to_currency), 'description', v_desc),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', UPPER(p_from_currency), 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', 0, 'credit', v_realized_fx_diff, 'base_debit', 0, 'base_credit', v_realized_fx_diff, 'currency', 'EGP', 'description', 'أرباح فروق عملة محققة')
                )
            );
        ELSE
            v_fx_gain_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
            IF v_fx_gain_loss_acct IS NULL THEN
                v_fx_gain_loss_acct := public.resolve_gl_account('6151', v_company_id);
            END IF;
            IF v_fx_gain_loss_acct IS NULL THEN
                v_fx_gain_loss_acct := public.resolve_gl_account('5220', v_company_id);
            END IF;

            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', UPPER(p_to_currency), 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', ABS(v_realized_fx_diff), 'credit', 0, 'base_debit', ABS(v_realized_fx_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق عملة محققة'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', UPPER(p_from_currency), 'description', v_desc)
                )
            );
        END IF;
    ELSE
        v_je_id := public.post_journal_entry(
            'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
            jsonb_build_array(
                jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', UPPER(p_to_currency), 'description', v_desc),
                jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', UPPER(p_from_currency), 'description', v_desc)
            )
        );
    END IF;

    -- Record outgoing transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_out', p_amount_from, UPPER(p_from_currency),
        v_desc || ' (صادر)', v_balance_before_from, v_balance_after_from,
        v_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    -- Record incoming transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_in', p_amount_to, UPPER(p_to_currency),
        v_desc || ' (وارد)', v_balance_before_to, v_balance_after_to,
        v_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'amount_from', p_amount_from,
        'from_currency', UPPER(p_from_currency),
        'amount_to', p_amount_to,
        'to_currency', UPPER(p_to_currency),
        'exchange_rate', p_exchange_rate
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_currency(text, text, text, numeric, numeric, numeric, uuid, text, text) TO authenticated, service_role, anon;

-- 3. Overload for BIGINT treasury_id
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id bigint,
    p_from_currency text,
    p_to_currency text,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid DEFAULT auth.uid(),
    p_transfer_mode text DEFAULT 'exchange',
    p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public.exchange_currency(
        p_treasury_id   := p_treasury_id::text,
        p_from_currency := p_from_currency,
        p_to_currency   := p_to_currency,
        p_amount_from   := p_amount_from,
        p_amount_to     := p_amount_to,
        p_exchange_rate := p_exchange_rate,
        p_user_id       := p_user_id,
        p_transfer_mode := p_transfer_mode,
        p_description   := p_description
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_currency(bigint, text, text, numeric, numeric, numeric, uuid, text, text) TO authenticated, service_role, anon;

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
