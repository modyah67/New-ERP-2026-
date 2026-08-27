-- ============================================================================
-- Migration: 353_add_notes_to_treasury_and_bank_rpcs
-- Description: Add p_notes parameter to Treasury & Bank transaction RPCs
--              and map to treasury_transactions.notes / bank_account_transactions.notes
-- Zero Accounting Impact: GL journal entry descriptions (v_desc) remain untouched.
-- ============================================================================

-- 1. deposit_treasury
DROP FUNCTION IF EXISTS public.deposit_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_revenue_account_id integer, p_reference_type text, p_reference_id text);
DROP FUNCTION IF EXISTS public.deposit_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_revenue_account_id integer, p_reference_type text, p_reference_id text, p_notes text);

CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance NUMERIC := 0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_tx_id BIGINT;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_revenue_acct BIGINT;
    v_desc TEXT;
    v_je_id BIGINT;
    v_source_type TEXT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_snapshot JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock treasury balance row & retrieve current cost_base and book_rate
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
    IF p_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    -- 3. Resolve GL accounts
    v_source_type := CASE WHEN p_revenue_account_id IS NOT NULL THEN 'revenue' ELSE 'opening_balance' END;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع في الخزينة');

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    -- 4. Post Journal Entry
    v_je_id := public.post_journal_entry(
        'treasury_deposit',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct,  'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- 5. Update / Upsert treasury_balances
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (p_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    -- 6. Insert transaction with notes mapped to p_notes
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, reference_type, reference_id, notes, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_source_type, v_je_id, auth.uid(),
        CASE WHEN p_revenue_account_id IS NOT NULL THEN p_revenue_account_id ELSE NULL END,
        p_reference_type, p_reference_id, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$function$;

-- 2. withdraw_treasury
DROP FUNCTION IF EXISTS public.withdraw_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.withdraw_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.withdraw_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type,
        journal_entry_id, expense_account_id, notes, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance',
        v_je_id, v_equity_acct, p_notes, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$function$;

-- 3. spend_with_category
DROP FUNCTION IF EXISTS public.spend_with_category(p_treasury_id bigint, p_currency text, p_amount numeric, p_description text, p_category_id integer, p_customer_id integer, p_supplier_id uuid, p_clearing_agent_id bigint, p_shipping_company_id bigint, p_shareholder_id uuid, p_expense_account_id integer, p_reference_type text, p_reference_id text);
DROP FUNCTION IF EXISTS public.spend_with_category(p_treasury_id bigint, p_currency text, p_amount numeric, p_description text, p_category_id integer, p_customer_id integer, p_supplier_id uuid, p_clearing_agent_id bigint, p_shipping_company_id bigint, p_shareholder_id uuid, p_expense_account_id integer, p_reference_type text, p_reference_id text, p_notes text);

CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_category_id integer DEFAULT NULL::integer,
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
SET search_path TO 'public'
AS $function$
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
        reference_type, reference_id, notes,
        created_by
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc, p_category_id,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id, p_notes,
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
$function$;

-- 4. disburse_custody
DROP FUNCTION IF EXISTS public.disburse_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.disburse_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.disburse_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

    -- Record transactions with notes mapped to p_notes
    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        notes, exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_from_treasury_id, 'disbursement_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id,
        p_notes, v_rate, v_base_amount, v_snapshot);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        notes, exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_to_treasury_id, 'disbursement', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id,
        p_notes, v_rate, v_base_amount, v_snapshot);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$function$;

-- 5. transfer_custody
DROP FUNCTION IF EXISTS public.transfer_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.transfer_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.transfer_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
        notes, exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_from_treasury_id, 'transfer_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id,
        p_notes, v_rate, v_base_amount, v_snapshot);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        notes, exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_to_treasury_id, 'transfer_in', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id,
        p_notes, v_rate, v_base_amount, v_snapshot);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$function$;

-- 6. return_custody
DROP FUNCTION IF EXISTS public.return_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.return_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.return_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
        notes, exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_from_treasury_id, 'return_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id,
        p_notes, v_rate, v_base_amount, v_snapshot);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id,
        notes, exchange_rate, amount_in_base_currency, currency_snapshot)
    VALUES (p_to_treasury_id, 'return_in', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id,
        p_notes, v_rate, v_base_amount, v_snapshot);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$function$;

-- 7. bank_transfer
DROP FUNCTION IF EXISTS public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text, p_bank_fee numeric);
DROP FUNCTION IF EXISTS public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text, p_bank_fee numeric, p_notes text);

CREATE OR REPLACE FUNCTION public.bank_transfer(
    p_from_account_id integer,
    p_to_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_bank_fee numeric DEFAULT 0.0,
    p_notes text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_currency TEXT;
    v_to_currency  TEXT;
    v_cost_base_from NUMERIC;
    v_cost_base_to NUMERIC;
    v_book_rate_from NUMERIC;
    v_transfer_cost NUMERIC;
    v_fee_base NUMERIC := 0.0;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_bank_fee_acct BIGINT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_lines        JSONB := '[]'::jsonb;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'لا يمكن التحويل للحساب نفسه';
    END IF;

    -- Lock and check source
    SELECT COALESCE(balance, 0), currency, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), company_id 
    INTO v_from_balance, v_from_currency, v_cost_base_from, v_book_rate_from, v_company_id
    FROM public.bank_accounts WHERE id = p_from_account_id FOR UPDATE;

    IF v_from_balance < (p_amount + COALESCE(p_bank_fee, 0)) THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب المصدر (المتوفر: %)', v_from_balance;
    END IF;

    -- Check destination
    SELECT COALESCE(balance, 0), currency, COALESCE(cost_base, 0)
    INTO v_to_balance, v_to_currency, v_cost_base_to
    FROM public.bank_accounts WHERE id = p_to_account_id FOR UPDATE;

    IF v_from_currency != v_to_currency THEN
        RAISE EXCEPTION 'التحويل البنكي المباشر مخصص للحسابات من نفس العملة. للتحويل بين عملات مختلفة استخدم صرف العملة البنكي.';
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل بنكي داخلي (' || v_from_currency || ')');

    IF v_from_currency = 'EGP' THEN
        v_transfer_cost := p_amount;
        v_fee_base := COALESCE(p_bank_fee, 0);
    ELSE
        v_transfer_cost := ROUND(p_amount * v_book_rate_from, 2);
        v_fee_base := ROUND(COALESCE(p_bank_fee, 0) * v_book_rate_from, 2);
    END IF;

    -- Update balances & cost bases
    UPDATE public.bank_accounts 
    SET balance = balance - (p_amount + COALESCE(p_bank_fee, 0)),
        cost_base = GREATEST(0.00, v_cost_base_from - v_transfer_cost - v_fee_base),
        updated_at = NOW()
    WHERE id = p_from_account_id;

    UPDATE public.bank_accounts 
    SET balance = balance + p_amount,
        cost_base = v_cost_base_to + v_transfer_cost,
        book_rate = CASE WHEN (balance + p_amount) > 0 THEN ROUND((v_cost_base_to + v_transfer_cost) / (balance + p_amount), 4) ELSE v_book_rate_from END,
        updated_at = NOW()
    WHERE id = p_to_account_id;

    -- Resolve GL accounts
    v_from_acct := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_bank_fee_acct := public.resolve_bank_charges_account(v_company_id);

    v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_transfer_cost, 'base_credit', 0, 'currency', v_from_currency, 'description', v_desc || ' (وارد)'),
        jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_transfer_cost, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
    );

    IF COALESCE(p_bank_fee, 0) > 0 THEN
        v_lines := v_lines || jsonb_build_array(
            jsonb_build_object('account_id', v_bank_fee_acct, 'debit', p_bank_fee, 'credit', 0, 'base_debit', v_fee_base, 'base_credit', 0, 'currency', v_from_currency, 'description', 'مصاريف وعمولات تحويل بنكي'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_bank_fee, 'base_debit', 0, 'base_credit', v_fee_base, 'currency', v_from_currency, 'description', 'خصم عمولة التحويل البنكي')
        );
    END IF;

    -- GL: Dr.Destination Bank / Cr.Source Bank (Zero Net Effect)
    v_je_id := public.post_journal_entry(
        'bank_transfer', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        v_lines
    );

    -- Record transactions with notes mapped to p_notes
    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after, description, 
        created_by, journal_entry_id, amount_in_base_currency, cost_base_released, bank_fee, transfer_mode, notes
    ) VALUES (
        p_from_account_id, 'transfer_out', p_amount, v_from_balance, v_from_balance - (p_amount + COALESCE(p_bank_fee, 0)), 
        v_desc, auth.uid(), v_je_id, v_transfer_cost, v_transfer_cost, p_bank_fee, 'internal_transfer', p_notes
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after, description, 
        created_by, journal_entry_id, amount_in_base_currency, cost_base_released, transfer_mode, notes
    ) VALUES (
        p_to_account_id, 'transfer_in', p_amount, v_to_balance, v_to_balance + p_amount, 
        v_desc, auth.uid(), v_je_id, v_transfer_cost, 0, 'internal_transfer', p_notes
    );

    RETURN json_build_object('success', true, 'journal_entry_id', v_je_id, 'cost_base', v_transfer_cost);
END;
$function$;

NOTIFY pgrst, 'reload schema';
