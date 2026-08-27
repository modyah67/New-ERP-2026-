-- Migration 342: Exchange Rate Integration for Treasury, Bank Accounts, and Cheques
-- Description: Adds exchange_rate and amount_in_base_currency columns, creates fn_get_exchange_rate, and updates all 11 financial RPCs to properly calculate base amounts and post balanced multi-currency journal entries.

BEGIN;

-- ============================================================================
-- 1. SCHEMA ENHANCEMENTS: Explicit Columns for Transactions & Cheques
-- ============================================================================

ALTER TABLE public.treasury_transactions
ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15, 6) DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS amount_in_base_currency NUMERIC(15, 2);

ALTER TABLE public.bank_account_transactions
ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15, 6) DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS amount_in_base_currency NUMERIC(15, 2);

ALTER TABLE public.cheques
ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15, 6) DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS amount_in_base_currency NUMERIC(15, 2);


-- ============================================================================
-- 2. CENTRAL EXCHANGE RATE RESOLVER FUNCTION
-- ============================================================================

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
    LIMIT 1;

    IF v_rate IS NULL OR v_rate <= 0 THEN
        RAISE EXCEPTION 'لم يتم العثور على سعر صرف معتمد للعملة (%) في جدول أسعار الصرف', p_currency;
    END IF;

    RETURN v_rate;
END;
$$;


-- ============================================================================
-- 3. TREASURY RPCS INTEGRATION
-- ============================================================================

-- 3.1 receive_payment
CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type character varying,
    p_amount numeric,
    p_currency character varying,
    p_counterparty_type character varying DEFAULT NULL::character varying,
    p_counterparty_id bigint DEFAULT NULL::bigint,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_description text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_treasury_id bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_treasury_id     BIGINT;
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_ar_acct         BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_source_type     TEXT;
    v_treasury_name   TEXT;
    v_je_source       TEXT;
    v_credit_acct     BIGINT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    IF p_treasury_id IS NOT NULL THEN
        v_treasury_id := p_treasury_id;
    ELSE
        SELECT id INTO v_treasury_id
        FROM public.treasuries
        WHERE type = 'main' AND user_id = auth.uid()
        LIMIT 1;
        IF v_treasury_id IS NULL THEN
            SELECT id INTO v_treasury_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        END IF;
        IF v_treasury_id IS NULL THEN
            RAISE EXCEPTION 'لم يتم العثور على الخزينة الرئيسية.';
        END IF;
    END IF;

    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = v_treasury_id;

    IF p_counterparty_type IS NULL THEN
        v_source_type := 'opening_balance';
        SELECT name INTO v_treasury_name FROM public.treasuries WHERE id = v_treasury_id;
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
        );
    ELSE
        v_source_type := p_counterparty_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'استلام ' || p_receipt_type);
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_counterparty_type = 'customer' THEN
        SELECT c.account_id INTO v_credit_acct FROM public.customers c WHERE c.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('1020', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'supplier' THEN
        SELECT s.account_id INTO v_credit_acct FROM public.suppliers s WHERE s.id = p_supplier_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'clearing_agent' THEN
        SELECT ca.account_id INTO v_credit_acct FROM public.clearing_agents ca WHERE ca.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shipping_company' THEN
        SELECT sc.account_id INTO v_credit_acct FROM public.shipping_companies sc WHERE sc.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id = p_shareholder_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
        END IF;
    ELSE
        v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
    END IF;

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_currency;

    v_new_balance := v_current_balance + p_amount;

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, source_type,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        created_by, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc, v_source_type,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        v_current_balance, v_new_balance,
        auth.uid(),
        v_credit_acct, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id = p_supplier_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'supplier_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'clearing_agent_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shipping_company_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shareholder' AND p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_shareholder_id;
        END IF;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shareholder_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSE
        v_je_source := 'opening_balance';
        v_je_id := public.post_journal_entry(
            v_je_source, v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    -- Sync treasury_balances
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, account_id, updated_at)
    VALUES (v_treasury_id, p_currency, v_new_balance, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance, updated_at = NOW();

    RETURN jsonb_build_object('success', true, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;


-- 3.2 spend_custody
CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_customer_id integer DEFAULT NULL::integer,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_clearing_agent_id bigint DEFAULT NULL::bigint,
    p_shipping_company_id bigint DEFAULT NULL::bigint,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_tx_type         TEXT;
    v_je_source_type  TEXT;
    v_entity_leaf     INTEGER;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    -- Resolve GL account
    IF p_expense_account_id IS NOT NULL THEN
        SELECT id INTO v_expense_acct FROM accounts 
        WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
        END IF;
        v_tx_type := 'expense';

    ELSIF p_supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_entity_leaf
        FROM suppliers s WHERE s.id = p_supplier_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'المورد لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المورد غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'supplier_payment';

    ELSIF p_customer_id IS NOT NULL THEN
        SELECT c.account_id INTO v_entity_leaf
        FROM customers c WHERE c.id = p_customer_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'العميل لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب العميل غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'customer_payment';

    ELSIF p_clearing_agent_id IS NOT NULL THEN
        SELECT ca.account_id INTO v_entity_leaf
        FROM clearing_agents ca WHERE ca.id = p_clearing_agent_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'المخلص لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المخلص غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'clearing_agent_payment';

    ELSIF p_shipping_company_id IS NOT NULL THEN
        SELECT sc.account_id INTO v_entity_leaf
        FROM shipping_companies sc WHERE sc.id = p_shipping_company_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'شركة الشحن لا تمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب شركة الشحن غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'shipping_company_payment';

    ELSIF p_shareholder_id IS NOT NULL THEN
        v_tx_type := 'shareholder_withdrawal';
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_shareholder_id;
        IF v_expense_acct IS NOT NULL THEN
            SELECT id INTO v_expense_acct FROM public.accounts WHERE id = v_expense_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_expense_acct IS NULL THEN
            v_expense_acct := public.resolve_equity_account(p_currency, v_company_id);
        END IF;

    ELSE
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد جهة للصرف';
    END IF;

    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE public.treasury_balances
    SET balance = v_new_balance, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_company_id IS NULL THEN
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف خزينة');

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        reference_type, reference_id,
        created_by, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id,
        auth.uid(), p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    -- Update Counterparty balances and ledger entries
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;

    -- Update Purchase Invoice or Lot Receipt if reference provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    v_je_source_type := CASE v_tx_type
        WHEN 'supplier_payment' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN 'customer_payment' THEN 'customer_refund'
        WHEN 'clearing_agent_payment' THEN 'clearing_agent_payment'
        WHEN 'shipping_company_payment' THEN 'shipping_company_payment'
        WHEN 'shareholder_withdrawal' THEN 'shareholder_withdrawal'
        ELSE 'expense_payment'
    END;

    -- Journal entry: Dr. Entity/Expense / Cr. Treasury with proper base amounts
    v_je_id := public.post_journal_entry(
        v_je_source_type,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        ),
        p_reference_id
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;


-- 3.3 deposit_treasury
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_revenue_account_id integer DEFAULT NULL::integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_revenue_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'إيداع نقدي ' || p_currency || ' في ' || COALESCE(v_treasury_name, 'الخزينة')
    );

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (p_treasury_id, p_currency, v_new_balance,
        public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        )
    )
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_equity_account(p_currency, v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        'treasury_deposit',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'treasury_deposit', v_je_id, auth.uid(),
        v_revenue_acct, v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance
    );
END;
$$;


-- 3.4 disburse_custody
CREATE OR REPLACE FUNCTION public.disburse_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_from_name    TEXT;
    v_to_name      TEXT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_rate         NUMERIC := 1.0;
    v_base_amount  NUMERIC;
    v_snapshot     JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL AND CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    -- Lock source balance
    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة المصدرة (المتوفر: %)', v_from_balance;
    END IF;

    -- Lock destination balance
    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT name, company_id INTO v_from_name, v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_to_treasury_id;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف عهدة إلى ' || COALESCE(v_to_name, 'موظف'));

    -- Resolve GL Accounts: Debit To (Employee Custody), Credit From (Main Treasury)
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    -- Update balances
    UPDATE treasury_balances SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
        VALUES (p_to_treasury_id, p_currency, p_amount, v_to_acct, NOW());
        v_to_balance := 0;
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount, updated_at = NOW()
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    -- Create GL Journal Entry with unique document_type 'custody_disbursement' (CDIS)
    v_je_id := public.post_journal_entry(
        'custody_disbursement',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام عهدة)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc || ' (صرف عهدة)')
        )
    );

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    -- Record transactions WITH exchange_rate and amount_in_base_currency
    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_from_treasury_id, 'disbursement_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id,
        v_rate, v_base_amount, v_snapshot);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_to_treasury_id, 'disbursement', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id,
        v_rate, v_base_amount, v_snapshot);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$$;


-- 3.5 transfer_custody
CREATE OR REPLACE FUNCTION public.transfer_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_from_name    TEXT;
    v_to_name      TEXT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_rate         NUMERIC := 1.0;
    v_base_amount  NUMERIC;
    v_snapshot     JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL AND CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_from_balance;
    END IF;

    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT name, company_id INTO v_from_name, v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_to_treasury_id;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل عهدة من ' || COALESCE(v_from_name, '') || ' إلى ' || COALESCE(v_to_name, ''));

    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    UPDATE treasury_balances SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
        VALUES (p_to_treasury_id, p_currency, p_amount, v_to_acct, NOW());
        v_to_balance := 0;
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount, updated_at = NOW()
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    -- Create GL Journal Entry with unique document_type 'custody_transfer' (CTRF)
    v_je_id := public.post_journal_entry(
        'custody_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام تحويل)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال تحويل)')
        )
    );

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_from_treasury_id, 'transfer_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id,
        v_rate, v_base_amount, v_snapshot);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_to_treasury_id, 'transfer_in', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id,
        v_rate, v_base_amount, v_snapshot);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$$;


-- 3.6 return_custody
CREATE OR REPLACE FUNCTION public.return_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_from_name    TEXT;
    v_to_name      TEXT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_rate         NUMERIC := 1.0;
    v_base_amount  NUMERIC;
    v_snapshot     JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL AND CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_from_balance;
    END IF;

    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT name, company_id INTO v_from_name, v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_to_treasury_id;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'إرجاع عهدة من ' || COALESCE(v_from_name, 'موظف'));

    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    UPDATE treasury_balances SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
        VALUES (p_to_treasury_id, p_currency, p_amount, v_to_acct, NOW());
        v_to_balance := 0;
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount, updated_at = NOW()
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    -- Create GL Journal Entry with unique document_type 'return_custody' (CRET)
    v_je_id := public.post_journal_entry(
        'return_custody',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام مرتجع عهدة)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc || ' (إرجاع عهدة)')
        )
    );

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_from_treasury_id, 'return_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id,
        v_rate, v_base_amount, v_snapshot);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_to_treasury_id, 'return_in', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id,
        v_rate, v_base_amount, v_snapshot);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$$;


-- ============================================================================
-- 4. BANK ACCOUNT RPCS INTEGRATION
-- ============================================================================

-- 4.1 deposit_bank_account
CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_revenue_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
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

    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

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
            jsonb_build_object('account_id', v_bank_acct,  'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END,
        p_notes,
        v_rate, v_base_amount, v_snapshot
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


-- 4.2 withdraw_bank_account
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    v_je_source_type  TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية (الرصيد الحالي: %)', v_current_balance;
    END IF;

    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    v_new_balance := v_current_balance - p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب رصيد افتتاحي من الحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM customers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM suppliers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM clearing_agents WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM shipping_companies WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM shareholders WHERE id::TEXT = p_entity_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    UPDATE bank_accounts
    SET balance = v_new_balance, updated_at = NOW()
    WHERE id = p_account_id;

    -- Update Purchase Invoice or Lot Receipt if reference provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    -- Distinct Journal Entry source_type resolution
    v_je_source_type := CASE
        WHEN p_entity_type = 'supplier' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_entity_type = 'shareholder' THEN 'shareholder_payment_received'
        ELSE 'bank_withdrawal'
    END;

    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        ),
        p_source_id := p_reference_id
    );

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, created_at, created_by, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_current_balance, v_new_balance,
        v_desc, p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id, NOW(), auth.uid(), p_notes,
        v_rate, v_base_amount, v_snapshot
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
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance
    );
END;
$$;


-- ============================================================================
-- 5. CHEQUES RPCS INTEGRATION
-- ============================================================================

-- 5.1 clear_cheque
CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cheque RECORD;
    v_desc TEXT;
    v_bank_id INTEGER;
    v_bank_bal NUMERIC;
    v_currency TEXT;
    v_company_id UUID;
    v_new_bank_bal NUMERIC;
    v_bank_acct BIGINT;
    v_counterparty_acct BIGINT;
    v_je_id BIGINT;
    v_bank_tx_id BIGINT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_snapshot JSONB;
BEGIN
    SELECT * INTO v_cheque
    FROM public.cheques
    WHERE id = p_cheque_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الشيك غير موجود';
    END IF;

    IF v_cheque.status != 'pending' THEN
        RAISE EXCEPTION 'لا يمكن تسوية شيك بحالة %', v_cheque.status;
    END IF;

    v_currency := v_cheque.currency;
    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(v_cheque.amount * v_rate, 2);

    IF v_cheque.type = 'outgoing' THEN
        v_desc := 'صرف شيك رقم: ' || v_cheque.cheque_number;
    ELSE
        v_desc := 'تحصيل شيك رقم: ' || v_cheque.cheque_number;
    END IF;

    -- Get bank account for this currency
    SELECT id, balance, ba.company_id INTO v_bank_id, v_bank_bal, v_company_id
    FROM public.bank_accounts ba
    WHERE ba.currency = v_cheque.currency
    LIMIT 1
    FOR UPDATE;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لا توجد حساب بنكي بهذه العملة';
    END IF;

    -- Resolve bank GL account by currency
    v_bank_acct := public.resolve_gl_account(
        CASE v_currency
            WHEN 'EGP' THEN '11201'
            WHEN 'USD' THEN '11202'
            WHEN 'EUR' THEN '11203'
            WHEN 'GBP' THEN '11204'
            ELSE '11201'
        END,
        v_company_id
    );

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'amount', v_cheque.amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    -- ================================================================
    -- OUTGOING CHEQUE: Dr Counterparty / Cr Bank
    -- ================================================================
    IF v_cheque.type = 'outgoing' THEN
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (% متوفر)', v_bank_bal;
        END IF;

        v_new_bank_bal := v_bank_bal - v_cheque.amount;
        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.counterparty_id;

        ELSIF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - v_cheque.amount
            WHERE id = v_cheque.supplier_id;

        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.clearing_agent_id;

        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.shipping_company_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            v_counterparty_acct := public.resolve_gl_account(
                CASE v_currency
                    WHEN 'EGP' THEN '11101'
                    WHEN 'USD' THEN '11102'
                    WHEN 'EUR' THEN '11103'
                    WHEN 'GBP' THEN '11104'
                    ELSE '11101'
                END,
                v_company_id
            );
        END IF;

        IF v_counterparty_acct IS NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_counterparty_acct IS NOT NULL THEN
                SELECT id INTO v_counterparty_acct FROM public.accounts WHERE id = v_counterparty_acct AND is_leaf = true AND is_active = true;
            END IF;
            IF v_counterparty_acct IS NULL THEN
                v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
            END IF;
        END IF;

        -- Post journal entry: Dr Counterparty / Cr Bank with base amounts
        v_je_id := public.post_journal_entry(
            'bank_withdraw',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_counterparty_acct,
                    'debit', v_cheque.amount,
                    'credit', 0,
                    'base_debit', v_base_amount,
                    'base_credit', 0,
                    'currency', v_currency,
                    'description', v_desc
                ),
                jsonb_build_object(
                    'account_id', v_bank_acct,
                    'debit', 0,
                    'credit', v_cheque.amount,
                    'base_debit', 0,
                    'base_credit', v_base_amount,
                    'currency', v_currency,
                    'description', v_desc
                )
            )
        );

        -- Update bank balance
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal, updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'withdrawal', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_rate, v_base_amount, v_snapshot)
        RETURNING id INTO v_bank_tx_id;

    -- ================================================================
    -- INCOMING CHEQUE: Dr Bank / Cr Counterparty
    -- ================================================================
    ELSIF v_cheque.type = 'incoming' THEN
        v_new_bank_bal := v_bank_bal + v_cheque.amount;
        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.counterparty_id;

        ELSIF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + v_cheque.amount
            WHERE id = v_cheque.supplier_id;

        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.clearing_agent_id;

        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.shipping_company_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            v_counterparty_acct := public.resolve_gl_account(
                CASE v_currency
                    WHEN 'EGP' THEN '11101'
                    WHEN 'USD' THEN '11102'
                    WHEN 'EUR' THEN '11103'
                    WHEN 'GBP' THEN '11104'
                    ELSE '11101'
                END,
                v_company_id
            );
        END IF;

        IF v_counterparty_acct IS NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_counterparty_acct IS NOT NULL THEN
                SELECT id INTO v_counterparty_acct FROM public.accounts WHERE id = v_counterparty_acct AND is_leaf = true AND is_active = true;
            END IF;
            IF v_counterparty_acct IS NULL THEN
                v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
            END IF;
        END IF;

        -- Post journal entry: Dr Bank / Cr Counterparty with base amounts
        v_je_id := public.post_journal_entry(
            'bank_deposit',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_bank_acct,
                    'debit', v_cheque.amount,
                    'credit', 0,
                    'base_debit', v_base_amount,
                    'base_credit', 0,
                    'currency', v_currency,
                    'description', v_desc
                ),
                jsonb_build_object(
                    'account_id', v_counterparty_acct,
                    'debit', 0,
                    'credit', v_cheque.amount,
                    'base_debit', 0,
                    'base_credit', v_base_amount,
                    'currency', v_currency,
                    'description', v_desc
                )
            )
        );

        -- Update bank balance
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal, updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_rate, v_base_amount, v_snapshot)
        RETURNING id INTO v_bank_tx_id;

    END IF;

    -- Update cheque status + freeze rate and amount_in_base_currency
    UPDATE public.cheques
    SET status = 'cleared',
        cleared_at = NOW(),
        journal_entry_id = v_je_id,
        exchange_rate = v_rate,
        amount_in_base_currency = v_base_amount,
        currency_snapshot = v_snapshot
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'bank_tx_id', v_bank_tx_id
    );
END;
$$;


-- ============================================================================
-- 6. CURRENCY EXCHANGE RPCS INTEGRATION (Strict single-foreign-currency rule)
-- ============================================================================

-- 6.1 exchange_currency (Treasury)
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id bigint,
    p_from_currency character varying,
    p_to_currency character varying,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid
)
RETURNS jsonb
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
    v_base_amount         NUMERIC;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    -- Strict Rule: One of the currencies MUST be EGP
    IF p_from_currency != 'EGP' AND p_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
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

    UPDATE treasury_balances
    SET balance = v_balance_after_from
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency;

    -- Base Amount is the EGP amount
    IF p_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    v_je_id := public.post_journal_entry(
        'currency_exchange',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after, journal_entry_id, created_by,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency, v_desc,
        v_balance_before_from, v_balance_after_from, v_je_id, p_user_id,
        p_exchange_rate, v_base_amount,
        jsonb_build_object('currency', p_from_currency, 'exchange_rate', p_exchange_rate, 'amount', p_amount_from, 'amount_in_base_currency', v_base_amount)
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after, journal_entry_id, created_by,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency, v_desc,
        v_balance_before_to, v_balance_after_to, v_je_id, p_user_id,
        p_exchange_rate, v_base_amount,
        jsonb_build_object('currency', p_to_currency, 'exchange_rate', p_exchange_rate, 'amount', p_amount_to, 'amount_in_base_currency', v_base_amount)
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id
    );
END;
$$;


-- 6.2 exchange_bank_currency (Banks)
CREATE OR REPLACE FUNCTION public.exchange_bank_currency(
    p_from_account_id integer,
    p_to_account_id integer,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_account_exists BOOLEAN;
    v_to_account_exists   BOOLEAN;
    v_from_currency       TEXT;
    v_to_currency         TEXT;
    v_old_from_balance    NUMERIC;
    v_old_to_balance      NUMERIC;
    v_new_from_balance    NUMERIC;
    v_new_to_balance      NUMERIC;
    v_transaction_id      BIGINT;
    v_result              JSONB;
    v_company_id          UUID;
    v_user_id             UUID;
    v_je_id                BIGINT;
    v_from_account_ledger  INTEGER;
    v_to_account_ledger    INTEGER;
    v_je_description       TEXT;
    v_base_amount          NUMERIC;
BEGIN
    SELECT company_id INTO v_company_id FROM bank_accounts WHERE id = p_from_account_id;
    v_user_id := auth.uid();

    IF p_amount_from <= 0 OR p_amount_to <= 0 OR p_exchange_rate <= 0 THEN
        RAISE EXCEPTION 'المبالغ وسعر الصرف يجب أن تكون أكبر من صفر';
    END IF;

    SELECT TRUE, currency, balance INTO v_from_account_exists, v_from_currency, v_old_from_balance
    FROM bank_accounts WHERE id = p_from_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source bank account not found';
    END IF;

    IF v_old_from_balance < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي المصدر';
    END IF;

    SELECT TRUE, currency, balance INTO v_to_account_exists, v_to_currency, v_old_to_balance
    FROM bank_accounts WHERE id = p_to_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Destination bank account not found';
    END IF;

    -- Strict Rule: One of the currencies MUST be EGP
    IF v_from_currency != 'EGP' AND v_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
    END IF;

    IF v_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    -- Update Balances
    UPDATE bank_accounts
    SET balance = balance - p_amount_from
    WHERE id = p_from_account_id
    RETURNING balance INTO v_new_from_balance;

    UPDATE bank_accounts
    SET balance = balance + p_amount_to
    WHERE id = p_to_account_id
    RETURNING balance INTO v_new_to_balance;

    -- Enterprise Accounting Integration
    v_from_account_ledger := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_account_ledger := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_je_description := 'تحويل بنكي من حساب ' || p_from_account_id || ' إلى حساب ' || p_to_account_id;

    v_je_id := public.post_journal_entry(
        'currency_exchange',
        v_je_description,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_account_ledger, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_to_currency, 'description', v_je_description || ' (وارد)'),
            jsonb_build_object('account_id', v_from_account_ledger, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_from_currency, 'description', v_je_description || ' (صادر)')
        )
    );

    -- Create Transaction Records
    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_from_account_id, 'currency_exchange_out', p_amount_from, v_old_from_balance, v_new_from_balance,
        'Exchange to ' || v_to_currency, 'exchange', v_je_id,
        p_exchange_rate, v_base_amount,
        jsonb_build_object('currency', v_from_currency, 'exchange_rate', p_exchange_rate, 'amount', p_amount_from, 'amount_in_base_currency', v_base_amount)
    ) RETURNING id INTO v_transaction_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_to_account_id, 'currency_exchange_in', p_amount_to, v_old_to_balance, v_new_to_balance,
        'Exchange from ' || v_from_currency, 'exchange', v_je_id,
        p_exchange_rate, v_base_amount,
        jsonb_build_object('currency', v_to_currency, 'exchange_rate', p_exchange_rate, 'amount', p_amount_to, 'amount_in_base_currency', v_base_amount)
    );

    v_result := jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_entry_id', v_je_id
    );

    RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload_schema';

COMMIT;
