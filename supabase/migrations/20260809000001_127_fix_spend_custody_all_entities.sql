-- Migration 127: Fix spend_custody to support all entity types (not just supplier)
--
-- Bug: spend_custody only auto-resolves GL account for suppliers.
-- When paying a customer, clearing_agent, shipping_company, or shareholder
-- without an explicit expense_account_id, it raises an exception.
-- Fix: auto-resolve the GL account from each entity's account_id column.

DROP FUNCTION IF EXISTS public.spend_custody(BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT);

-- Step 0: Expand CHECK constraint to include all new entity payment types
ALTER TABLE public.treasury_transactions
    DROP CONSTRAINT IF EXISTS treasury_transactions_type_check;

ALTER TABLE public.treasury_transactions
    ADD CONSTRAINT treasury_transactions_type_check
    CHECK (type = ANY (ARRAY[
        'deposit',
        'expense',
        'withdrawal',
        'disbursement',
        'disbursement_out',
        'transfer_in',
        'transfer_out',
        'return_in',
        'return_out',
        'currency_exchange_out',
        'currency_exchange_in',
        'supplier_payment',
        'customer_payment',
        'clearing_agent_payment',
        'shipping_company_payment',
        'shareholder_withdrawal'
    ]));

-- Update trigger: entity payment types don't require expense_account_id
CREATE OR REPLACE FUNCTION public.fn_require_expense_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.type IN ('expense', 'withdrawal') AND NEW.expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
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

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

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
