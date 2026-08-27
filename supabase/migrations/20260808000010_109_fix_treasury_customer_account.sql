-- Migration 109: Fix Treasury Deposit/Withdrawal Customer Account
-- 
-- Fixes:
-- Uses the specific customer sub-account (e.g. 102001) instead of the root AR account (1020) for treasury journal entries.

CREATE OR REPLACE FUNCTION public.rpc_deposit_customer_treasury(
    p_treasury_id BIGINT,
    p_currency    VARCHAR,
    p_amount      NUMERIC,
    p_description TEXT,
    p_customer_id BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_ar_acct         BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL THEN
        RAISE EXCEPTION 'الخزينة غير موجودة';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع خزينة من عميل');

    UPDATE public.treasury_balances
    SET balance = balance + p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Resolve AR account
    SELECT account_id INTO v_ar_acct FROM customers WHERE id = p_customer_id;
    IF v_ar_acct IS NULL THEN
        v_ar_acct := public.resolve_gl_account('1020', v_company_id);
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, revenue_account_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_amount, p_currency, v_desc,
        p_customer_id, v_ar_acct, auth.uid()
    ) RETURNING id INTO v_tx_id;

    UPDATE public.customers SET balance = balance - p_amount WHERE id = p_customer_id;

    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        'customer', p_customer_id::text, 'credit', p_amount, p_currency,
        'treasury_deposit', v_tx_id, v_desc, auth.uid()
    );

    -- GL: Dr.Treasury / Cr.AR
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    v_je_id := public.post_journal_entry(
        'customer_treasury_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_deposit_customer_treasury(BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_withdraw_customer_treasury(
    p_treasury_id BIGINT,
    p_currency    VARCHAR,
    p_amount      NUMERIC,
    p_description TEXT,
    p_customer_id BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_ar_acct         BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL THEN
        RAISE EXCEPTION 'الخزينة غير موجودة';
    END IF;
    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'رصيد الخزينة لا يكفي';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'سحب خزينة لعميل');

    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Resolve AR account
    SELECT account_id INTO v_ar_acct FROM customers WHERE id = p_customer_id;
    IF v_ar_acct IS NULL THEN
        v_ar_acct := public.resolve_gl_account('1020', v_company_id);
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, revenue_account_id, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_amount, p_currency, v_desc,
        p_customer_id, v_ar_acct, auth.uid()
    ) RETURNING id INTO v_tx_id;

    UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;

    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        'customer', p_customer_id::text, 'debit', p_amount, p_currency,
        'treasury_withdrawal', v_tx_id, v_desc, auth.uid()
    );

    -- GL: Dr.AR / Cr.Treasury
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    v_je_id := public.post_journal_entry(
        'customer_treasury_withdrawal', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_ar_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_withdraw_customer_treasury(BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';
