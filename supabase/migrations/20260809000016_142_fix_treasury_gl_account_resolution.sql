-- Migration 141: Fix treasury GL account resolution to use treasuries.account_id

CREATE OR REPLACE FUNCTION public.resolve_treasury_account(
    p_treasury_id BIGINT,
    p_currency TEXT,
    p_company_id UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id BIGINT;
BEGIN
    SELECT account_id INTO v_account_id FROM treasuries WHERE id = p_treasury_id;
    IF v_account_id IS NULL THEN
        v_account_id := public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
            p_company_id
        );
    END IF;
    RETURN v_account_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id          BIGINT,
    p_currency             TEXT,
    p_amount               NUMERIC,
    p_description          TEXT DEFAULT '',
    p_customer_id          INTEGER DEFAULT NULL,
    p_supplier_id          UUID DEFAULT NULL,
    p_clearing_agent_id    BIGINT DEFAULT NULL,
    p_shipping_company_id  BIGINT DEFAULT NULL,
    p_shareholder_id       UUID DEFAULT NULL,
    p_expense_account_id   INTEGER DEFAULT NULL,
    p_reference_type       TEXT DEFAULT NULL,
    p_reference_id         TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
    v_entity_leaf     INTEGER;
BEGIN
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
        v_expense_acct := public.resolve_equity_account(p_currency, v_company_id);

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

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        reference_type, reference_id,
        created_by
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id,
        auth.uid()
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

    -- Update Purchase Invoice if reference provided
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
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    -- Journal entry: Dr. Entity/Expense / Cr. Treasury
    v_je_id := public.post_journal_entry(
        CASE v_tx_type
            WHEN 'supplier_payment' THEN 'purchase_payment'
            WHEN 'customer_payment' THEN 'customer_refund'
            WHEN 'clearing_agent_payment' THEN 'clearing_agent_payment'
            WHEN 'shipping_company_payment' THEN 'shipping_company_payment'
            WHEN 'shareholder_withdrawal' THEN 'shareholder_withdrawal'
            ELSE 'expense_payment'
        END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        ),
        p_reference_id
    );

    -- Link journal entry to treasury transaction
    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.spend_custody(BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type       VARCHAR,
    p_amount             NUMERIC,
    p_currency           VARCHAR,
    p_counterparty_type  VARCHAR   DEFAULT NULL,
    p_counterparty_id    BIGINT    DEFAULT NULL,
    p_supplier_id        UUID      DEFAULT NULL,
    p_shareholder_id     UUID      DEFAULT NULL,
    p_description        TEXT      DEFAULT NULL,
    p_notes              TEXT      DEFAULT NULL,
    p_treasury_id        BIGINT    DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

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
        v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
    ELSE
        v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
    END IF;

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_currency;

    v_new_balance := v_current_balance + p_amount;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, source_type,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        created_by, revenue_account_id
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc, v_source_type,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        v_current_balance, v_new_balance,
        auth.uid(),
        v_credit_acct
    ) RETURNING id INTO v_tx_id;

    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
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
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
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
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
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
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
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
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSE
        v_je_source := 'opening_balance';
        v_je_id := public.post_journal_entry(
            v_je_source, v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
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
GRANT EXECUTE ON FUNCTION public.receive_payment(VARCHAR, NUMERIC, VARCHAR, VARCHAR, BIGINT, UUID, UUID, TEXT, TEXT, BIGINT) TO authenticated;


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

    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_from_currency, v_company_id);
    v_to_acct := public.resolve_treasury_account(p_to_treasury_id, p_to_currency, v_company_id);

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
    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

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
    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

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


CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id   INTEGER,
    p_currency      TEXT,
    p_amount        NUMERIC,
    p_description   TEXT DEFAULT ''
)
RETURNS JSONB
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
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
    );

    -- Current balance
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    -- Upsert treasury balance
    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (p_treasury_id, p_currency, v_new_balance,
        public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        )
    )
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance;

    -- GL accounts
    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Treasury / Cr.Owner Equity
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_equity_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type,
        journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance',
        v_je_id, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$$;
GRANT EXECUTE ON FUNCTION deposit_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION public.withdraw_treasury(
    p_treasury_id INTEGER,
    p_currency    TEXT,
    p_amount      NUMERIC,
    p_description TEXT DEFAULT ''
)
RETURNS JSONB
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
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    -- Current balance check
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (الرصيد الحالي: % %)', v_current_balance, p_currency;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'سحب من ' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
    );

    -- GL accounts
    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Owner Equity / Cr.Treasury
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_equity_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Update treasury balance
    UPDATE treasury_balances SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Treasury transaction record (FIX: include expense_account_id to satisfy trigger)
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type,
        journal_entry_id, expense_account_id, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance',
        v_je_id, v_equity_acct, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$$;
GRANT EXECUTE ON FUNCTION withdraw_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;




