-- Migration 068: Fix treasury transaction balances (before/after) and auto-reconcile purchase invoices
-- ============================================================================

-- 0. Ensure transaction reference columns support text/invoice IDs and exist on all transaction tables
ALTER TABLE IF EXISTS public.treasury_transactions 
    ALTER COLUMN reference_id TYPE TEXT USING reference_id::TEXT;

ALTER TABLE IF EXISTS public.cashbox_transactions 
    ALTER COLUMN reference_id TYPE TEXT USING reference_id::TEXT;

ALTER TABLE IF EXISTS public.bank_account_transactions 
    ADD COLUMN IF NOT EXISTS reference_type TEXT,
    ADD COLUMN IF NOT EXISTS reference_id TEXT;

-- 1. DROP and RECREATE spend_custody with balance_before, balance_after, and reference params
DROP FUNCTION IF EXISTS public.spend_custody(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER
);
DROP FUNCTION IF EXISTS public.spend_custody(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT
);

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
    v_supplier_leaf   INTEGER;
BEGIN
    -- ── Resolve GL account ──
    IF p_expense_account_id IS NOT NULL THEN
        -- Manual expense: user selected an expense account
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
        END IF;
        v_tx_type := 'expense';
    ELSIF p_supplier_id IS NOT NULL THEN
        -- Supplier payment: auto-resolve from suppliers.account_id
        SELECT s.account_id INTO v_supplier_leaf
        FROM suppliers s WHERE s.id = p_supplier_id;
        IF v_supplier_leaf IS NULL THEN
            RAISE EXCEPTION 'المورد لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_supplier_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المورد غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'supplier_payment';
    ELSE
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد مورد';
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

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

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

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    -- Journal entry: Dr. Expense/Supplier / Cr. Treasury
    v_je_id := public.post_journal_entry(
        CASE v_tx_type WHEN 'supplier_payment' THEN 'purchase_payment' ELSE 'expense_payment' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_custody(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT
) TO authenticated;


-- 2. DROP and RECREATE spend_with_category with balance_before, balance_after, and reference params
DROP FUNCTION IF EXISTS public.spend_with_category(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER
);
DROP FUNCTION IF EXISTS public.spend_with_category(
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id          BIGINT,
    p_currency             TEXT,
    p_amount               NUMERIC,
    p_description          TEXT DEFAULT '',
    p_category_id          INTEGER DEFAULT NULL,
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
    v_supplier_leaf   INTEGER;
BEGIN
    IF p_expense_account_id IS NOT NULL THEN
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
        END IF;
        v_tx_type := 'expense';
    ELSIF p_supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_supplier_leaf
        FROM suppliers s WHERE s.id = p_supplier_id;
        IF v_supplier_leaf IS NULL THEN
            RAISE EXCEPTION 'المورد لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_supplier_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المورد غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'supplier_payment';
    ELSE
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد مورد';
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

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'مصروف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, category_id,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        reference_type, reference_id,
        created_by
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc, p_category_id,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

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

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    v_je_id := public.post_journal_entry(
        CASE v_tx_type WHEN 'supplier_payment' THEN 'purchase_payment' ELSE 'expense_payment' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
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
    BIGINT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT
) TO authenticated;


-- Helper: resolve currency-specific equity account
CREATE OR REPLACE FUNCTION public.resolve_equity_account(
    p_currency   TEXT,
    p_company_id UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_acct BIGINT;
BEGIN
    v_acct := public.resolve_gl_account(
        CASE UPPER(COALESCE(p_currency, 'EGP'))
            WHEN 'USD' THEN '3002'
            WHEN 'EUR' THEN '3003'
            WHEN 'GBP' THEN '3004'
            ELSE '3001'
        END,
        p_company_id
    );
    RETURN v_acct;
END;
$$;

-- 3. DROP and RECREATE receive_payment with balance_before, balance_after, and currency-specific equity leaf posting
DROP FUNCTION IF EXISTS public.receive_payment(VARCHAR, NUMERIC, VARCHAR, VARCHAR, BIGINT, UUID, UUID, TEXT, TEXT, BIGINT);

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

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

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
        v_credit_acct := public.resolve_gl_account('41001', v_company_id);
    ELSIF p_counterparty_type = 'shipping_company' THEN
        v_credit_acct := public.resolve_gl_account('41001', v_company_id);
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

-- Ensure columns exist on public.users
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username TEXT;

-- Auto-Admin Trigger on Auth User Creation
CREATE OR REPLACE FUNCTION public.on_auth_user_created_combined()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_first_user BOOLEAN;
BEGIN
    SELECT NOT EXISTS (
        SELECT 1 FROM public.users WHERE is_admin = true
    ) INTO v_is_first_user;

    INSERT INTO public.users (
        id,
        full_name,
        email,
        phone,
        is_admin
    ) VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        NEW.email,
        NEW.raw_user_meta_data->>'phone',
        COALESCE(v_is_first_user, true)
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = COALESCE(EXCLUDED.full_name, public.users.full_name),
        email = EXCLUDED.email,
        phone = COALESCE(EXCLUDED.phone, public.users.phone),
        is_admin = CASE WHEN v_is_first_user THEN true ELSE public.users.is_admin END;

    IF v_is_first_user THEN
        UPDATE public.treasuries
        SET user_id = NEW.id
        WHERE type = 'main' AND (user_id IS NULL OR user_id = NEW.id);
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'on_auth_user_created_combined warning: %', SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.on_auth_user_created_combined();

-- RPC: sign_up_new_tenant
CREATE OR REPLACE FUNCTION public.sign_up_new_tenant(
  p_user_id UUID,
  p_full_name TEXT,
  p_phone TEXT,
  p_email TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_trial_days INTEGER := 7;
  v_expires_at TIMESTAMPTZ;
  v_email TEXT;
BEGIN
  v_email := COALESCE(p_email, p_phone || '@erp.local');

  BEGIN
    SELECT setting_value::INTEGER INTO v_trial_days
    FROM public.system_settings
    WHERE setting_key = 'trial_days';
  EXCEPTION WHEN OTHERS THEN
    v_trial_days := 7;
  END;
  v_trial_days := COALESCE(v_trial_days, 7);

  v_expires_at := now() + (v_trial_days || ' days')::INTERVAL;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenants') THEN
    INSERT INTO public.tenants (name, email, tenant_type, is_active, max_users, subscription_expires_at)
    VALUES (
      'متجر ' || COALESCE(p_full_name, 'الرئيسي'),
      v_email,
      'erp',
      true,
      50,
      v_expires_at
    )
    RETURNING id INTO v_tenant_id;

    IF v_tenant_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenant_users') THEN
      DELETE FROM public.tenant_users WHERE user_id = p_user_id;
      INSERT INTO public.tenant_users (tenant_id, user_id, role)
      VALUES (v_tenant_id, p_user_id, 'owner');

      UPDATE public.tenants
      SET current_users = 1
      WHERE id = v_tenant_id;
    END IF;
  -- Ensure sys_companies record exists with the tenant id
  IF v_tenant_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
    INSERT INTO public.sys_companies (id, name, created_at, updated_at)
    VALUES (v_tenant_id, 'متجر ' || COALESCE(p_full_name, 'الرئيسي'), now(), now())
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = now();
  END IF;

  UPDATE public.users
  SET full_name = COALESCE(p_full_name, full_name),
      phone = COALESCE(p_phone, phone),
      email = COALESCE(v_email, email),
      is_admin = true
  WHERE id = p_user_id;

  UPDATE public.treasuries
  SET user_id = p_user_id
  WHERE type = 'main' AND (user_id IS NULL OR user_id = p_user_id);

  RETURN json_build_object(
    'success', true,
    'tenant_id', v_tenant_id,
    'trial_days', v_trial_days,
    'expires_at', v_expires_at
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object(
    'success', true,
    'warning', SQLERRM
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sign_up_new_tenant(UUID, TEXT, TEXT, TEXT) TO authenticated, anon;

-- Guarantee Company ID Synchronization & Integrity
INSERT INTO public.sys_companies (id, name, created_at, updated_at)
SELECT id, name, COALESCE(created_at, now()), now()
FROM public.tenants
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

CREATE OR REPLACE FUNCTION public.sync_tenant_to_sys_companies()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO public.sys_companies (id, name, created_at, updated_at)
    VALUES (NEW.id, NEW.name, COALESCE(NEW.created_at, now()), now())
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_tenant_to_sys_companies ON public.tenants;
CREATE TRIGGER trg_sync_tenant_to_sys_companies
    AFTER INSERT OR UPDATE ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.sync_tenant_to_sys_companies();

CREATE OR REPLACE FUNCTION public.trg_ensure_valid_company_id()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_first_company_id UUID;
BEGIN
    IF NEW.company_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE id = NEW.company_id) THEN
            IF EXISTS (SELECT 1 FROM public.tenants WHERE id = NEW.company_id) THEN
                INSERT INTO public.sys_companies (id, name, created_at, updated_at)
                SELECT id, name, COALESCE(created_at, now()), now() FROM public.tenants WHERE id = NEW.company_id
                ON CONFLICT (id) DO NOTHING;
            ELSE
                INSERT INTO public.sys_companies (id, name, created_at, updated_at)
                VALUES (NEW.company_id, 'Company ' || SUBSTRING(NEW.company_id::TEXT, 1, 8), now(), now())
                ON CONFLICT (id) DO NOTHING;
            END IF;
        END IF;
    ELSE
        SELECT id INTO v_first_company_id FROM public.sys_companies ORDER BY created_at ASC LIMIT 1;
        IF v_first_company_id IS NULL THEN
            INSERT INTO public.sys_companies (name) VALUES ('Main Company') RETURNING id INTO v_first_company_id;
        END IF;
        NEW.company_id := v_first_company_id;
    END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    r RECORD;
BEGIN
    -- 1. Drop trigger from any tables that do not have company_id column
    FOR r IN (
        SELECT event_object_table AS table_name
        FROM information_schema.triggers
        WHERE trigger_name = 'trg_ensure_valid_company_id'
          AND trigger_schema = 'public'
    ) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = r.table_name 
              AND column_name = 'company_id'
        ) THEN
            EXECUTE format('DROP TRIGGER IF EXISTS trg_ensure_valid_company_id ON public.%I;', r.table_name);
        END IF;
    END LOOP;

    -- 2. Ensure trigger ONLY on tables that ACTUALLY have company_id column
    FOR r IN (
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'company_id'
          AND table_name IN (
            'suppliers', 'customers', 'accounts', 'treasuries', 'bank_accounts',
            'clearing_agents', 'shipping_companies', 'shareholders',
            'journal_entries', 'account_ledger_entries'
          )
    ) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_ensure_valid_company_id ON public.%I;', r.table_name);
        EXECUTE format('CREATE TRIGGER trg_ensure_valid_company_id BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.trg_ensure_valid_company_id();', r.table_name);
    END LOOP;
END;
$$;

-- Entity Account Code Generation & Auto-Account Creation
CREATE OR REPLACE FUNCTION public.get_next_entity_account_code(
  p_entity_type TEXT,
  p_company_id UUID DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pattern TEXT;
  v_start   INTEGER;
  v_next    INTEGER;
  v_code    TEXT;
BEGIN
  CASE p_entity_type
    WHEN 'customer'         THEN v_pattern := '^11[0-9]{3}$'; v_start := 11000;
    WHEN 'supplier'         THEN v_pattern := '^21[0-9]{3}$'; v_start := 21000;
    WHEN 'shipping_company' THEN v_pattern := '^200[0-9]{2}$'; v_start := 20000;
    WHEN 'clearing_agent'   THEN v_pattern := '^201[0-9]{2}$'; v_start := 20100;
    WHEN 'shareholder'      THEN v_pattern := '^300[0-9]{2}$'; v_start := 30000;
    ELSE RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
  END CASE;

  LOOP
    SELECT COALESCE(MAX(account_code::int), v_start) + 1 INTO v_next
    FROM accounts
    WHERE account_code ~ v_pattern;

    IF v_next <= v_start THEN
      v_next := v_start + 1;
    END IF;

    v_code := LPAD(v_next::TEXT, 5, '0');

    -- Ensure code is available in both accounts and deleted_account_codes
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM accounts WHERE account_code = v_code
    ) AND NOT EXISTS (
      SELECT 1 FROM deleted_account_codes WHERE account_code = v_code
    );

    v_start := v_next;
  END LOOP;

  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_supplier_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '2000'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  IF NEW.code IS NOT NULL AND NEW.code <> '' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = NEW.code) THEN
    v_code := NEW.code;
  ELSIF NEW.supplier_code IS NOT NULL AND NEW.supplier_code <> '' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = NEW.supplier_code) THEN
    v_code := NEW.supplier_code;
  ELSE
    v_code := public.get_next_entity_account_code('supplier', NEW.company_id);
  END IF;

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Supplier - ' || COALESCE(NEW.name, ''),
    'مورد - ' || COALESCE(NEW.name, ''),
    'liability', 10,
    NEW.company_id,
    v_parent_id,
    5, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'مورد - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Supplier - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE suppliers
  SET account_id = v_new_account_id,
      code = COALESCE(code, v_code),
      supplier_code = COALESCE(supplier_code, v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_create_supplier_account ON public.suppliers;
CREATE TRIGGER trigger_create_supplier_account
  AFTER INSERT ON public.suppliers
  FOR EACH ROW
  EXECUTE FUNCTION public.create_supplier_account();

CREATE OR REPLACE FUNCTION public.create_customer_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '1020'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  IF NEW.code IS NOT NULL AND NEW.code <> '' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = NEW.code) THEN
    v_code := NEW.code;
  ELSE
    v_code := public.get_next_entity_account_code('customer', NEW.company_id);
  END IF;

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset', 10,
    NEW.company_id,
    v_parent_id,
    4, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'عميل - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Customer - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE customers
  SET account_id = v_new_account_id,
      code = COALESCE(code, v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_create_customer_account ON public.customers;
CREATE TRIGGER trigger_create_customer_account
  AFTER INSERT ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.create_customer_account();

-- ============================================================================
-- UNIFIED REPORTING & GENERAL LEDGER ENGINE (Phase C Unified)
-- Supports recursive parent accounts (summary rows) and leaf accounts
-- ============================================================================

-- 1. get_account_totals_rpc
DROP FUNCTION IF EXISTS public.get_account_totals_rpc(DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_account_totals_rpc(
  p_from DATE DEFAULT NULL,
  p_to DATE DEFAULT NULL
)
RETURNS TABLE(account_id TEXT, debit NUMERIC, credit NUMERIC)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    ale.account_id::text AS account_id,
    COALESCE(SUM(ale.debit), 0)::numeric AS debit,
    COALESCE(SUM(ale.credit), 0)::numeric AS credit
  FROM account_ledger_entries ale
  INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE (je.deleted_at IS NULL)
    AND (ale.deleted_at IS NULL)
    AND (p_from IS NULL OR je.entry_date >= p_from)
    AND (p_to IS NULL OR je.entry_date <= p_to)
  GROUP BY ale.account_id;
$$;

-- 2. get_account_total_by_id_rpc (supports parent and leaf accounts)
DROP FUNCTION IF EXISTS public.get_account_total_by_id_rpc(TEXT, DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_account_total_by_id_rpc(
  p_account_id TEXT,
  p_from DATE DEFAULT NULL,
  p_to DATE DEFAULT NULL
)
RETURNS TABLE(debit NUMERIC, credit NUMERIC)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH RECURSIVE target_accounts AS (
    SELECT id FROM accounts WHERE p_account_id IS NOT NULL AND (id::TEXT = p_account_id OR account_code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  )
  SELECT
    COALESCE(SUM(ale.debit), 0)::numeric AS debit,
    COALESCE(SUM(ale.credit), 0)::numeric AS credit
  FROM account_ledger_entries ale
  INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE ale.account_id IN (SELECT id FROM target_accounts)
    AND (je.deleted_at IS NULL)
    AND (ale.deleted_at IS NULL)
    AND (p_from IS NULL OR je.entry_date >= p_from)
    AND (p_to IS NULL OR je.entry_date <= p_to);
$$;

-- 3. get_balance_before_date_rpc (supports parent and leaf accounts)
DROP FUNCTION IF EXISTS public.get_balance_before_date_rpc(TEXT, DATE);

CREATE OR REPLACE FUNCTION public.get_balance_before_date_rpc(
  p_account_id TEXT,
  p_before_date DATE
)
RETURNS TABLE(debit NUMERIC, credit NUMERIC)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH RECURSIVE target_accounts AS (
    SELECT id FROM accounts WHERE p_account_id IS NOT NULL AND (id::TEXT = p_account_id OR account_code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  )
  SELECT
    COALESCE(SUM(ale.debit), 0)::numeric AS debit,
    COALESCE(SUM(ale.credit), 0)::numeric AS credit
  FROM account_ledger_entries ale
  INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE ale.account_id IN (SELECT id FROM target_accounts)
    AND (je.deleted_at IS NULL)
    AND (ale.deleted_at IS NULL)
    AND je.entry_date < p_before_date;
$$;

-- 4. get_ledger_page_rpc (General Ledger with recursive parent accounts, pagination & opening balance)
DROP FUNCTION IF EXISTS public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.get_ledger_page_rpc(
  p_account_id TEXT DEFAULT NULL,
  p_from_date TEXT DEFAULT NULL,
  p_to_date TEXT DEFAULT NULL,
  p_cursor_date TEXT DEFAULT NULL,
  p_cursor_id TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
  id TEXT,
  date TEXT,
  entry_number TEXT,
  account_id TEXT,
  account_code TEXT,
  account_name TEXT,
  description TEXT,
  debit NUMERIC,
  credit NUMERIC,
  reference_type TEXT,
  reference_id TEXT,
  next_cursor_date TEXT,
  next_cursor_id TEXT,
  has_more BOOLEAN,
  opening_balance_debit NUMERIC,
  opening_balance_credit NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_cursor_ts TIMESTAMPTZ;
  v_ob_debit NUMERIC := 0;
  v_ob_credit NUMERIC := 0;
  v_cursor_entry_id BIGINT;
BEGIN
  -- Parse cursor
  IF p_cursor_date IS NOT NULL AND p_cursor_id IS NOT NULL AND p_cursor_date != '' AND p_cursor_id != '' THEN
    v_cursor_ts := p_cursor_date::TIMESTAMPTZ;
    v_cursor_entry_id := p_cursor_id::BIGINT;
  END IF;

  -- Compute opening balance
  IF v_cursor_ts IS NOT NULL THEN
    SELECT
      COALESCE(SUM(ale.debit), 0),
      COALESCE(SUM(ale.credit), 0)
    INTO v_ob_debit, v_ob_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    WHERE (p_account_id IS NULL OR ale.account_id IN (
      WITH RECURSIVE target_accounts AS (
        SELECT id FROM accounts WHERE p_account_id IS NOT NULL AND (id::TEXT = p_account_id OR account_code = p_account_id)
        UNION ALL
        SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
      )
      SELECT id FROM target_accounts
    ))
      AND (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND je.entry_date < (v_cursor_ts AT TIME ZONE 'UTC')::DATE;
  ELSE
    IF p_from_date IS NOT NULL AND p_from_date != '' THEN
      SELECT
        COALESCE(SUM(ale.debit), 0),
        COALESCE(SUM(ale.credit), 0)
      INTO v_ob_debit, v_ob_credit
      FROM account_ledger_entries ale
      INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
      WHERE (p_account_id IS NULL OR ale.account_id IN (
        WITH RECURSIVE target_accounts AS (
          SELECT id FROM accounts WHERE p_account_id IS NOT NULL AND (id::TEXT = p_account_id OR account_code = p_account_id)
          UNION ALL
          SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
        )
        SELECT id FROM target_accounts
      ))
        AND (je.deleted_at IS NULL)
        AND (ale.deleted_at IS NULL)
        AND je.entry_date < p_from_date::DATE;
    END IF;
  END IF;

  RETURN QUERY
  WITH target_accounts AS (
    SELECT id FROM accounts WHERE p_account_id IS NOT NULL AND (id::TEXT = p_account_id OR account_code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  ),
  raw_page AS (
    SELECT
      ale.id::TEXT AS p_id,
      je.entry_date::TEXT AS p_date,
      COALESCE(je.entry_number, '')::TEXT AS p_entry_number,
      ale.account_id::TEXT AS p_account_id,
      COALESCE(a.account_code, '')::TEXT AS p_account_code,
      COALESCE(a.account_name, a.name, '')::TEXT AS p_account_name,
      CASE
        WHEN je.source_type = 'opening_balance' THEN
          CASE
            WHEN a.account_code LIKE '111%' THEN 'قيد الرصيد الافتتاحي للخزينة'
            WHEN a.account_code LIKE '112%' THEN 'قيد الرصيد الافتتاحي للبنك'
            ELSE COALESCE(NULLIF(ale.description, ''), NULLIF(je.description, ''), 'قيد رصيد افتتاحي')
          END
        ELSE COALESCE(NULLIF(ale.description, ''), NULLIF(je.description, ''), '')
      END::TEXT AS p_description,
      COALESCE(ale.debit, 0) AS p_debit,
      COALESCE(ale.credit, 0) AS p_credit,
      COALESCE(je.source_type, '')::TEXT AS p_reference_type,
      COALESCE(je.source_id, '')::TEXT AS p_reference_id,
      ale.id AS ale_order_id,
      je.entry_date AS je_order_date
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    LEFT JOIN accounts a ON a.id = ale.account_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_account_id IS NULL OR ale.account_id IN (SELECT id FROM target_accounts))
      AND (p_from_date IS NULL OR p_from_date = '' OR je.entry_date >= p_from_date::DATE)
      AND (p_to_date IS NULL OR p_to_date = '' OR je.entry_date <= p_to_date::DATE)
      AND (
        v_cursor_ts IS NULL
        OR je.entry_date > (v_cursor_ts AT TIME ZONE 'UTC')::DATE
        OR (je.entry_date = (v_cursor_ts AT TIME ZONE 'UTC')::DATE
            AND ale.id > v_cursor_entry_id)
      )
    ORDER BY je.entry_date ASC, ale.id ASC
    LIMIT (p_limit + 1)
  ),
  page_data AS (
    SELECT * FROM raw_page LIMIT p_limit
  ),
  has_more_val AS (
    SELECT (COUNT(*) > p_limit) AS hm FROM raw_page
  )
  SELECT
    pd.p_id,
    pd.p_date,
    pd.p_entry_number,
    pd.p_account_id,
    pd.p_account_code,
    pd.p_account_name,
    pd.p_description,
    pd.p_debit,
    pd.p_credit,
    pd.p_reference_type,
    pd.p_reference_id,
    (SELECT p2.p_date FROM page_data p2 ORDER BY p2.je_order_date DESC, p2.ale_order_id DESC LIMIT 1)::TEXT,
    (SELECT p2.p_id FROM page_data p2 ORDER BY p2.je_order_date DESC, p2.ale_order_id DESC LIMIT 1)::TEXT,
    COALESCE((SELECT hm FROM has_more_val), false),
    v_ob_debit,
    v_ob_credit
  FROM page_data pd;
END;
$$;

-- 5. validate_trial_balance_rpc
DROP FUNCTION IF EXISTS public.validate_trial_balance_rpc(DATE, DATE);

CREATE OR REPLACE FUNCTION public.validate_trial_balance_rpc(
  p_from DATE DEFAULT NULL,
  p_to DATE DEFAULT NULL
)
RETURNS TABLE(
  total_debit NUMERIC,
  total_credit NUMERIC,
  is_balanced BOOLEAN,
  difference NUMERIC
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH totals AS (
    SELECT
      COALESCE(SUM(ale.debit), 0)::numeric AS total_debit,
      COALESCE(SUM(ale.credit), 0)::numeric AS total_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_from IS NULL OR je.entry_date >= p_from)
      AND (p_to IS NULL OR je.entry_date <= p_to)
  )
  SELECT
    t.total_debit,
    t.total_credit,
    ABS(t.total_debit - t.total_credit) < 0.01 AS is_balanced,
    t.total_debit - t.total_credit AS difference
  FROM totals t;
$$;

-- 6. validate_balance_sheet_rpc
DROP FUNCTION IF EXISTS public.validate_balance_sheet_rpc(DATE);

CREATE OR REPLACE FUNCTION public.validate_balance_sheet_rpc(
  p_as_of_date DATE DEFAULT NULL
)
RETURNS TABLE(
  total_assets NUMERIC,
  total_liabilities NUMERIC,
  total_equity NUMERIC,
  total_liabilities_and_equity NUMERIC,
  is_balanced BOOLEAN,
  difference NUMERIC
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH account_balances AS (
    SELECT
      ale.account_id,
      COALESCE(SUM(ale.debit), 0) AS total_debit,
      COALESCE(SUM(ale.credit), 0) AS total_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_as_of_date IS NULL OR je.entry_date <= p_as_of_date)
    GROUP BY ale.account_id
  ),
  classified AS (
    SELECT
      ab.total_debit,
      ab.total_credit,
      CASE
        WHEN a.account_type = 'asset' THEN 'asset'
        WHEN a.account_type = 'liability' THEN 'liability'
        WHEN a.account_type = 'equity' THEN 'equity'
        ELSE 'other'
      END AS classification,
      CASE
        WHEN a.account_type = 'asset' THEN ab.total_debit - ab.total_credit
        ELSE ab.total_credit - ab.total_debit
      END AS net_balance
    FROM account_balances ab
    INNER JOIN accounts a ON a.id = ab.account_id
    WHERE a.account_type IN ('asset', 'liability', 'equity')
  ),
  summed AS (
    SELECT
      COALESCE(SUM(CASE WHEN classification = 'asset' THEN net_balance ELSE 0 END), 0) AS total_assets,
      COALESCE(SUM(CASE WHEN classification = 'liability' THEN net_balance ELSE 0 END), 0) AS total_liabilities,
      COALESCE(SUM(CASE WHEN classification = 'equity' THEN net_balance ELSE 0 END), 0) AS total_equity
    FROM classified
  )
  SELECT
    s.total_assets,
    s.total_liabilities,
    s.total_equity,
    (s.total_liabilities + s.total_equity) AS total_liabilities_and_equity,
    ABS(s.total_assets - (s.total_liabilities + s.total_equity)) < 0.01 AS is_balanced,
    s.total_assets - (s.total_liabilities + s.total_equity) AS difference
  FROM summed s;
$$;

-- GRANTS FOR REPORTING FUNCTIONS
GRANT EXECUTE ON FUNCTION public.get_account_totals_rpc(DATE, DATE) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_account_total_by_id_rpc(TEXT, DATE, DATE) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_balance_before_date_rpc(TEXT, DATE) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_ledger_page_rpc(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.validate_trial_balance_rpc(DATE, DATE) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.validate_balance_sheet_rpc(DATE) TO authenticated, anon, service_role;





