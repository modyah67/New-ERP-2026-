-- Migration 184: Fix exchange_currency undefined variable
-- Bug: The function referenced undefined p_from_treasury_id and p_to_treasury_id 
-- instead of the passed parameter p_treasury_id.

BEGIN;

DROP FUNCTION IF EXISTS public.exchange_currency(BIGINT, VARCHAR, VARCHAR, NUMERIC, NUMERIC, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id    BIGINT,
    p_from_currency  VARCHAR,
    p_to_currency    VARCHAR,
    p_amount_from    NUMERIC,
    p_amount_to      NUMERIC,
    p_exchange_rate  NUMERIC,
    p_user_id        UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance_before_from DECIMAL(15,2);
    v_balance_after_from  DECIMAL(15,2);
    v_balance_before_to   DECIMAL(15,2);
    v_balance_after_to    DECIMAL(15,2);
    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    SELECT balance INTO v_balance_before_from
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    INSERT INTO treasury_balances (treasury_id, currency, balance)
    VALUES (p_treasury_id, p_to_currency, 0.00)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance INTO v_balance_before_to
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := 'تحويل عملة من ' || p_from_currency || ' إلى ' || p_to_currency || ' بسعر صرف ' || p_exchange_rate;

    -- Fix is here: Using p_treasury_id instead of p_from_treasury_id and p_to_treasury_id
    v_from_acct := public.resolve_treasury_account(p_treasury_id, p_from_currency, v_company_id);
    v_to_acct := public.resolve_treasury_account(p_treasury_id, p_to_currency, v_company_id);

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    UPDATE treasury_balances
    SET balance = v_balance_after_from
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency;

    v_je_id := public.post_journal_entry(
        'currency_exchange',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_from, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', p_amount_from, 'currency', p_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency, v_desc,
        v_balance_before_from, v_balance_after_from, v_je_id, p_user_id
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency, v_desc,
        v_balance_before_to, v_balance_after_to, v_je_id, p_user_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_currency(BIGINT, VARCHAR, VARCHAR, NUMERIC, NUMERIC, NUMERIC, UUID) TO authenticated, service_role;

COMMIT;
