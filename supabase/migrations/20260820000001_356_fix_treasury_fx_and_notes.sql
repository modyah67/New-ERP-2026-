-- Description: Fixes IAS 21 FX logic for treasury withdrawals (lost in migration 353), restoring base_amount, book_rate, and cost_base calculations while preserving p_notes.

-- 1. withdraw_treasury
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
    v_current_cost_base NUMERIC;
    v_current_book_rate NUMERIC;
    v_new_balance     NUMERIC;
    v_new_cost_base   NUMERIC;
    v_new_book_rate   NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
    v_base_amount     NUMERIC;
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

    -- Current balance check & fetch rates
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف (الرصيد الحالي: % %)', v_current_balance, p_currency;
    END IF;

    -- IAS 21 Multi-Currency FX Engine Logic
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
        v_new_book_rate := 1.0;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
    ELSE
        v_new_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_new_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
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
            jsonb_build_object('account_id', v_equity_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    -- Update treasury balance
    UPDATE treasury_balances 
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
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

-- 2. spend_with_category
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
    v_current_cost_base NUMERIC;
    v_current_book_rate NUMERIC;
    v_new_balance     NUMERIC;
    v_new_cost_base   NUMERIC;
    v_new_book_rate   NUMERIC;
    v_base_amount     NUMERIC;
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

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    -- IAS 21 Multi-Currency FX Engine Logic
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
        v_new_book_rate := 1.0;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
    ELSE
        v_new_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_new_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE public.treasury_balances
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
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
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$function$;

-- 3. disburse_custody
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
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
BEGIN
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف في الخزينة المصدرة';
    END IF;

    -- IAS 21 Outbound from Source Treasury
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    -- Update Source Treasury
    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    -- Update/Upsert Destination Treasury
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    -- IAS 21 Inbound to Destination Treasury
    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    -- Transaction Record
    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by
    ) VALUES (
        p_from_treasury_id, 'custody_disbursement', p_amount, p_currency, COALESCE(NULLIF(p_description, ''), 'صرف عهدة'),
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- GL Posting
    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_transfer', COALESCE(NULLIF(p_description, ''), 'صرف عهدة'), CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', p_description, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', p_description, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    UPDATE treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$function$;

-- 4. transfer_custody
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
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
BEGIN
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف للتحويل';
    END IF;

    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by
    ) VALUES (
        p_from_treasury_id, 'custody_transfer', p_amount, p_currency, COALESCE(NULLIF(p_description, ''), 'تحويل عهدة'),
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, auth.uid()
    ) RETURNING id INTO v_tx_id;

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_transfer', COALESCE(NULLIF(p_description, ''), 'تحويل عهدة'), CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', p_description, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', p_description, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    UPDATE treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$function$;

-- 5. return_custody
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
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
BEGIN
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف لرد العهدة';
    END IF;

    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by
    ) VALUES (
        p_from_treasury_id, 'custody_return', p_amount, p_currency, COALESCE(NULLIF(p_description, ''), 'رد عهدة'),
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, auth.uid()
    ) RETURNING id INTO v_tx_id;

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_return', COALESCE(NULLIF(p_description, ''), 'رد عهدة'), CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', p_description, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', p_description, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    UPDATE treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$function$;
