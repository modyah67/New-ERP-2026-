-- Migration 064: Fix spend_with_category — drop old overload + fix supplier_id type
-- ============================================================================
-- The old overload (without p_expense_account_id) causes PostgREST positional
-- parameter mismatch: when Dart sends p_expense_account_id, the extra param
-- shifts all subsequent params, putting customer_id value "2" into
-- p_supplier_id (UUID) → "invalid input syntax for type uuid: '2'"

-- Step 1: Drop all overloads of spend_with_category
DROP FUNCTION IF EXISTS public.spend_with_category(
    BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT, BIGINT, UUID, BIGINT, BIGINT, UUID
);

DROP FUNCTION IF EXISTS public.spend_with_category(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER, BIGINT, BIGINT, BIGINT, UUID, INTEGER
);

-- Step 2: Recreate with correct types (p_supplier_id = UUID, not BIGINT)
CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id      BIGINT,
    p_currency         TEXT,
    p_amount           NUMERIC,
    p_description      TEXT DEFAULT '',
    p_category_id      INTEGER DEFAULT NULL,
    p_customer_id      INTEGER DEFAULT NULL,
    p_supplier_id      UUID DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id   UUID DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    IF p_expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات';
    END IF;

    SELECT id INTO v_expense_acct FROM accounts
    WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';

    IF v_expense_acct IS NULL THEN
        RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
    END IF;

    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'مصروف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, category_id,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, v_desc, p_category_id,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    v_je_id := public.post_journal_entry(
        'expense_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_with_category(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER
) TO authenticated;
