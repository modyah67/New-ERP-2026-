-- ==============================================================================
-- Migration: Fix withdraw_bank_account & Missing resolve_bank_gl_account
-- Fixes:
--   1. PostgrestException: function public.resolve_bank_gl_account(integer, text, uuid) does not exist
--   2. PostgrestException: missing FROM-clause entry for table "v_old_cc", code: 42P01
-- ==============================================================================

-- 1. Ensure account_id column exists on bank_accounts
ALTER TABLE public.bank_accounts 
ADD COLUMN IF NOT EXISTS account_id BIGINT REFERENCES public.accounts(id);

-- Dynamically map bank_accounts to GL leaf accounts based on currency and account code
UPDATE public.bank_accounts b
SET account_id = COALESCE(
    (SELECT a.id FROM public.accounts a WHERE a.code = '12111' LIMIT 1),
    (SELECT a.id FROM public.accounts a WHERE a.code = '11201' LIMIT 1)
)
WHERE UPPER(b.currency) = 'EGP' AND (b.account_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = b.account_id));

UPDATE public.bank_accounts b
SET account_id = COALESCE(
    (SELECT a.id FROM public.accounts a WHERE a.code = '12112' LIMIT 1),
    (SELECT a.id FROM public.accounts a WHERE a.code = '11202' LIMIT 1)
)
WHERE UPPER(b.currency) = 'USD' AND (b.account_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = b.account_id));

UPDATE public.bank_accounts b
SET account_id = COALESCE(
    (SELECT a.id FROM public.accounts a WHERE a.code = '12113' LIMIT 1),
    (SELECT a.id FROM public.accounts a WHERE a.code = '11203' LIMIT 1)
)
WHERE UPPER(b.currency) = 'EUR' AND (b.account_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = b.account_id));

UPDATE public.bank_accounts b
SET account_id = COALESCE(
    (SELECT a.id FROM public.accounts a WHERE a.code = '12114' LIMIT 1),
    (SELECT a.id FROM public.accounts a WHERE a.code = '11204' LIMIT 1)
)
WHERE UPPER(b.currency) = 'GBP' AND (b.account_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = b.account_id));

-- 2. Drop all overloads of resolve_bank_gl_account and withdraw_bank_account
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT oid::regprocedure AS func_sig 
             FROM pg_proc 
             WHERE proname IN ('withdraw_bank_account', 'resolve_bank_gl_account') 
               AND pronamespace = 'public'::regnamespace) 
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

-- 3. Core function: resolve_bank_gl_account (INTEGER)
CREATE OR REPLACE FUNCTION public.resolve_bank_gl_account(
    p_account_id INTEGER,
    p_currency TEXT DEFAULT NULL,
    p_company_id UUID DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id BIGINT;
    v_curr TEXT := UPPER(COALESCE(p_currency, 'EGP'));
    v_code TEXT;
    v_real_company_id UUID := p_company_id;
BEGIN
    IF p_account_id IS NOT NULL THEN
        SELECT b.account_id, COALESCE(p_currency, b.currency), COALESCE(v_real_company_id, b.company_id)
        INTO v_account_id, v_curr, v_real_company_id
        FROM public.bank_accounts b
        WHERE b.id = p_account_id;

        IF v_account_id IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM public.accounts WHERE id = v_account_id) THEN
                RETURN v_account_id;
            END IF;
        END IF;
    END IF;

    v_curr := UPPER(COALESCE(v_curr, 'EGP'));
    IF v_curr = 'EGP' THEN
        v_code := '12111';
    ELSIF v_curr = 'USD' THEN
        v_code := '12112';
    ELSIF v_curr = 'EUR' THEN
        v_code := '12113';
    ELSIF v_curr = 'GBP' THEN
        v_code := '12114';
    ELSE
        v_code := '12111';
    END IF;

    v_account_id := public.resolve_gl_account(v_code, v_real_company_id);

    IF v_account_id IS NULL THEN
        IF v_curr = 'EGP' THEN
            v_code := '11201';
        ELSIF v_curr = 'USD' THEN
            v_code := '11202';
        ELSIF v_curr = 'EUR' THEN
            v_code := '11203';
        ELSIF v_curr = 'GBP' THEN
            v_code := '11204';
        END IF;
        v_account_id := public.resolve_gl_account(v_code, v_real_company_id);
    END IF;

    IF v_account_id IS NULL THEN
        v_account_id := public.resolve_gl_account('1211', v_real_company_id);
    END IF;
    IF v_account_id IS NULL THEN
        v_account_id := public.resolve_gl_account('1120', v_real_company_id);
    END IF;
    IF v_account_id IS NULL THEN
        SELECT a.id INTO v_account_id FROM public.accounts a WHERE a.code = '12111' LIMIT 1;
    END IF;

    IF v_account_id IS NOT NULL AND p_account_id IS NOT NULL THEN
        UPDATE public.bank_accounts
        SET account_id = v_account_id
        WHERE id = p_account_id AND (account_id IS NULL OR account_id != v_account_id);
    END IF;

    RETURN v_account_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_bank_gl_account(INTEGER, TEXT, UUID) TO authenticated, anon, service_role;

-- Overload for BIGINT
CREATE OR REPLACE FUNCTION public.resolve_bank_gl_account(
    p_account_id BIGINT,
    p_currency TEXT DEFAULT NULL,
    p_company_id UUID DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.resolve_bank_gl_account(p_account_id::INTEGER, p_currency, p_company_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_bank_gl_account(BIGINT, TEXT, UUID) TO authenticated, anon, service_role;

-- 4. Clean and Resilient withdraw_bank_account (BIGINT signature)
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_cost_center_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_je_source_type  TEXT;
    v_source_type     TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_cc_name         TEXT;
    v_acct_name       TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب البنكي غير موجود: %', p_account_id;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_current_balance;
    END IF;

    IF v_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(v_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_je_source_type := 'bank_withdraw';
        v_desc := COALESCE(p_description, 'سحب من الحساب البنكي');
    ELSIF p_entity_type = 'supplier' THEN
        v_source_type := 'supplier_payment';
        v_je_source_type := 'purchase_payment';
        v_desc := COALESCE(p_description, 'سداد لمورد عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id = p_entity_id::uuid;
    ELSIF p_entity_type = 'customer' THEN
        v_source_type := 'customer_refund';
        v_je_source_type := 'customer_refund';
        v_desc := COALESCE(p_description, 'رد مالي لعميل عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id = p_entity_id::integer;
    ELSIF p_entity_type = 'clearing_agent' THEN
        v_source_type := 'clearing_agent_payment';
        v_je_source_type := 'clearing_agent_payment';
        v_desc := COALESCE(p_description, 'سداد لمخلص جمركي عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        v_source_type := 'shipping_company_payment';
        v_je_source_type := 'shipping_company_payment';
        v_desc := COALESCE(p_description, 'سداد لشركة شحن عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' THEN
        v_source_type := 'shareholder_withdrawal';
        v_je_source_type := 'shareholder_withdrawal';
        v_desc := COALESCE(p_description, 'مسحوبات مساهم عبر البنك');
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_entity_id::uuid;
    ELSE
        v_source_type := 'expense_payment';
        v_je_source_type := 'expense_payment';
        v_desc := COALESCE(p_description, 'صرف مصروف عبر البنك');
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    -- Resolve Bank GL Account safely
    BEGIN
        v_bank_acct := public.resolve_bank_gl_account(p_account_id::integer, v_currency, v_company_id);
    EXCEPTION WHEN OTHERS THEN
        v_bank_acct := NULL;
    END;

    IF v_bank_acct IS NULL THEN
        SELECT b.account_id INTO v_bank_acct FROM public.bank_accounts b WHERE b.id = p_account_id;
    END IF;

    IF v_bank_acct IS NULL THEN
        v_bank_acct := public.resolve_gl_account(
            CASE UPPER(v_currency) 
                WHEN 'EGP' THEN '12111' 
                WHEN 'USD' THEN '12112' 
                WHEN 'EUR' THEN '12113' 
                WHEN 'GBP' THEN '12114' 
                ELSE '12111' 
            END, 
            v_company_id
        );
    END IF;

    IF v_bank_acct IS NULL THEN
        v_bank_acct := public.resolve_gl_account(
            CASE UPPER(v_currency) 
                WHEN 'EGP' THEN '11201' 
                WHEN 'USD' THEN '11202' 
                WHEN 'EUR' THEN '11203' 
                WHEN 'GBP' THEN '11204' 
                ELSE '11201' 
            END, 
            v_company_id
        );
    END IF;

    IF v_bank_acct IS NULL THEN
        SELECT a.id INTO v_bank_acct FROM public.accounts a WHERE a.code = '12111' LIMIT 1;
    END IF;

    -- Post balanced Journal Entry with cost_center_id on debit line
    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_expense_acct,
                'debit', p_amount,
                'credit', 0,
                'base_debit', v_base_amount,
                'base_credit', 0,
                'currency', v_currency,
                'description', v_desc,
                'cost_center_id', p_cost_center_id
            ),
            jsonb_build_object(
                'account_id', v_bank_acct,
                'debit', 0,
                'credit', p_amount,
                'base_debit', 0,
                'base_credit', v_base_amount,
                'currency', v_currency,
                'description', v_desc
            )
        ),
        p_source_id := p_reference_id
    );

    UPDATE public.bank_accounts
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'cost_center_id', p_cost_center_id,
        'rate_date', CURRENT_DATE,
        'rate_source', 'bank_book_rate'
    );

    INSERT INTO public.bank_transactions (
        bank_account_id, type, amount, balance_after, currency,
        description, notes, counterparty_name, created_by,
        journal_entry_id, expense_account_id, exchange_rate,
        amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_new_balance, v_currency,
        v_desc, p_notes, p_counterparty_name, auth.uid(),
        v_je_id, v_expense_acct, v_book_rate,
        v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    -- Sync into cost_center_transactions if cost center specified
    IF p_cost_center_id IS NOT NULL AND p_cost_center_id != '' THEN
        SELECT name_ar INTO v_cc_name FROM public.cost_centers WHERE code = p_cost_center_id OR id::text = p_cost_center_id LIMIT 1;
        SELECT COALESCE(account_name, name) INTO v_acct_name FROM public.accounts WHERE id = v_expense_acct LIMIT 1;

        INSERT INTO public.cost_center_transactions (
            cost_center_id,
            cost_center_name,
            cost_center_type,
            source_type,
            source_id,
            transaction_date,
            supplier_name,
            product_id,
            item_name,
            category,
            quantity,
            unit_price,
            currency,
            exchange_rate,
            total_in_currency,
            amount,
            notes,
            is_confirmed
        ) VALUES (
            p_cost_center_id,
            COALESCE(v_cc_name, 'مركز تكلفة'),
            'operational',
            'expense',
            'bank_exp_' || v_tx_id::text,
            CURRENT_DATE,
            p_counterparty_name,
            NULL::bigint,
            COALESCE(v_acct_name, v_desc),
            'مصروفات عمومية وتشغيلية',
            1,
            p_amount,
            v_currency,
            v_book_rate,
            p_amount,
            v_base_amount,
            v_desc,
            TRUE
        )
        ON CONFLICT (source_type, source_id) DO UPDATE SET
            cost_center_id = EXCLUDED.cost_center_id,
            amount = EXCLUDED.amount,
            total_in_currency = EXCLUDED.total_in_currency,
            updated_at = NOW();
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(bigint, numeric, text, bigint, text, text, text, text, text, text, text) TO authenticated, service_role, anon;

-- Overload for INTEGER signature to guarantee 100% compatibility
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_cost_center_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    RETURN public.withdraw_bank_account(
        p_account_id::BIGINT,
        p_amount,
        p_description,
        p_expense_account_id,
        p_entity_type,
        p_entity_id,
        p_counterparty_name,
        p_reference_type,
        p_reference_id,
        p_notes,
        p_cost_center_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(integer, numeric, text, bigint, text, text, text, text, text, text, text) TO authenticated, service_role, anon;

-- 5. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
