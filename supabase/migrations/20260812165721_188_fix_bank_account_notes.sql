-- Migration 188: Fix bank account deposit and withdraw functions to include notes column

BEGIN;

DROP FUNCTION IF EXISTS public.deposit_bank_account(integer, numeric, text, text, text, text, integer);
DROP FUNCTION IF EXISTS public.withdraw_bank_account(integer, numeric, text, text, text, text, integer);

CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id         INTEGER,
    p_amount             NUMERIC,
    p_description        TEXT DEFAULT NULL,
    p_entity_type        TEXT DEFAULT NULL,
    p_entity_id          TEXT DEFAULT NULL,
    p_counterparty_name  TEXT DEFAULT NULL,
    p_revenue_account_id INTEGER DEFAULT NULL,
    p_notes              TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_credit_acct     BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id
      INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'رصيد افتتاحي');
    ELSIF p_entity_type = 'revenue' THEN
        v_source_type := 'revenue';
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيراد');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_credit_acct := NULL;

    IF p_entity_type IS NULL THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id = p_entity_id::uuid;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_equity_account(v_currency, v_company_id);
        END IF;
    ELSIF p_entity_type = 'revenue' THEN
        IF p_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب الإيرادات';
        END IF;
        v_credit_acct := p_revenue_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_credit_acct FROM customers WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_credit_acct FROM suppliers WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM shareholders WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_credit_acct FROM clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_credit_acct FROM shipping_companies WHERE id = p_entity_id::bigint;
    ELSE
        v_credit_acct := public.resolve_equity_account(v_currency, v_company_id);
    END IF;

    IF v_credit_acct IS NULL THEN
        v_credit_acct := public.resolve_equity_account(v_currency, v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct,  'debit', p_amount, 'credit', 0,            'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_credit_acct, 'debit', 0,       'credit', p_amount,    'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, revenue_account_id, notes
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END,
        p_notes
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'new_balance', v_new_balance,
        'journal_entry_id', v_je_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id        INTEGER,
    p_amount            NUMERIC,
    p_description       TEXT DEFAULT NULL,
    p_entity_type       TEXT DEFAULT NULL,
    p_entity_id         TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL,
    p_notes             TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id
      INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'expense';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف بنكي');
    ELSIF p_entity_type = 'expense' THEN
        v_source_type := 'expense';
        v_desc := COALESCE(NULLIF(p_description, ''), 'مصروف');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_expense_acct := NULL;

    IF p_entity_type IS NULL THEN
        v_expense_acct := public.resolve_equity_account(v_currency, v_company_id);
    ELSIF p_entity_type = 'expense' THEN
        IF p_expense_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب المصروفات';
        END IF;
        v_expense_acct := p_expense_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_expense_acct FROM customers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_expense_acct FROM suppliers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_expense_acct FROM shareholders WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_expense_acct FROM clearing_agents WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_expense_acct FROM shipping_companies WHERE id::TEXT = p_entity_id;
    ELSE
        v_expense_acct := public.resolve_equity_account(v_currency, v_company_id);
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_equity_account(v_currency, v_company_id);
    END IF;

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    v_je_id := public.post_journal_entry(
        'bank_withdraw',
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, created_at, created_by, notes
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_current_balance, v_new_balance,
        v_desc, p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id, NOW(), auth.uid(), p_notes
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id::TEXT = p_entity_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance
    );
END;
$$;

COMMIT;
