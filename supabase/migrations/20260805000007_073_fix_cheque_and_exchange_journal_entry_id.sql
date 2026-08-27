-- Migration 073: Fix cheque clearing & exchange to store journal_entry_id
--
-- ROOT CAUSES:
-- 1. clear_cheque: NO post_journal_entry() call, NO journal_entry_id on bank tx
-- 2. exchange_bank_currency: creates JE but does NOT store journal_entry_id on bank tx
-- 3. cheques table: no journal_entry_id column for direct navigation
-- 4. withdraw_bank_account may be old version on live DB → re-apply
--
-- FIXES:
-- 1. Replace clear_cheque with enterprise-grade version (post_journal_entry + store je_id)
-- 2. Fix exchange_bank_currency to store journal_entry_id on both bank tx rows
-- 3. Add journal_entry_id to cheques table
-- 4. Re-apply withdraw_bank_account and deposit_bank_account (ensure journal_entry_id)
-- 5. Backfill existing cheques and bank transactions

BEGIN;

-- ============================================================
-- 1. Add journal_entry_id to cheques table
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cheques' AND column_name = 'journal_entry_id'
  ) THEN
    ALTER TABLE public.cheques
      ADD COLUMN journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- 2. Replace clear_cheque with enterprise-grade version
--    Creates journal entry + stores journal_entry_id on bank tx
-- ============================================================
DROP FUNCTION IF EXISTS public.clear_cheque(BIGINT);

CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_cheque RECORD;
    v_desc TEXT;
    v_bank_id INTEGER;
    v_bank_bal NUMERIC;
    v_currency TEXT;
    v_company_id UUID;
    v_bank_acct BIGINT;
    v_credit_acct BIGINT;
    v_debit_acct BIGINT;
    v_je_id BIGINT;
    v_bank_tx_id BIGINT;
    v_new_bank_bal NUMERIC;
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

    IF v_cheque.type = 'outgoing' THEN
        v_desc := 'صرف شيك رقم: ' || v_cheque.cheque_number;
    ELSE
        v_desc := 'تحصيل شيك رقم: ' || v_cheque.cheque_number;
    END IF;

    -- Get bank account for this currency
    SELECT id, balance INTO v_bank_id, v_bank_bal
    FROM public.bank_accounts
    WHERE currency = v_cheque.currency
    LIMIT 1
    FOR UPDATE;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لا توجد حساب بنكي بهذه العملة';
    END IF;

    -- Get company_id and resolve GL accounts
    SELECT company_id INTO v_company_id FROM bank_accounts WHERE id = v_bank_id;
    v_currency := v_cheque.currency;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    IF v_cheque.type = 'outgoing' THEN
        -- Outgoing cheque: bank balance decreases
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (% متوفر)', v_bank_bal;
        END IF;

        v_new_bank_bal := v_bank_bal - v_cheque.amount;
        UPDATE public.bank_accounts SET balance = v_new_bank_bal, updated_at = now() WHERE id = v_bank_id;

        -- Determine the counterparty GL account (debit side)
        v_debit_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_debit_acct FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance + v_cheque.amount WHERE id = v_cheque.counterparty_id;

        ELSIF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_debit_acct FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - v_cheque.amount WHERE id = v_cheque.supplier_id;

        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_debit_acct FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance - v_cheque.amount WHERE id = v_cheque.clearing_agent_id;

        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_debit_acct FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance - v_cheque.amount WHERE id = v_cheque.shipping_company_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_debit_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            -- Treasury cheque: fallback to equity
            v_debit_acct := public.resolve_gl_account(
                CASE v_currency WHEN 'EGP' THEN '3001' WHEN 'USD' THEN '3002' WHEN 'EUR' THEN '3003' WHEN 'GBP' THEN '3004' ELSE '3001' END,
                v_company_id
            );
        ELSE
            -- Fallback
            v_debit_acct := public.resolve_gl_account(
                CASE v_currency WHEN 'EGP' THEN '3001' WHEN 'USD' THEN '3002' WHEN 'EUR' THEN '3003' WHEN 'GBP' THEN '3004' ELSE '3001' END,
                v_company_id
            );
        END IF;

        -- Post journal: Dr Counterparty / Cr Bank
        IF v_debit_acct IS NOT NULL THEN
            v_je_id := public.post_journal_entry(
                'bank_withdraw', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_debit_acct, 'debit', v_cheque.amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', v_cheque.amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        END IF;

        -- Bank transaction WITH journal_entry_id
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after, description, created_by, journal_entry_id, entity_type, entity_id, source_type)
        VALUES (v_bank_id, 'withdrawal', v_cheque.amount, v_bank_bal, v_new_bank_bal, v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::text, 'cheque')
        RETURNING id INTO v_bank_tx_id;

    ELSIF v_cheque.type = 'incoming' THEN
        -- Incoming cheque: bank balance increases
        v_new_bank_bal := v_bank_bal + v_cheque.amount;
        UPDATE public.bank_accounts SET balance = v_new_bank_bal, updated_at = now() WHERE id = v_bank_id;

        -- Determine the counterparty GL account (credit side)
        v_credit_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acct FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance - v_cheque.amount WHERE id = v_cheque.counterparty_id;

        ELSIF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acct FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + v_cheque.amount WHERE id = v_cheque.supplier_id;

        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acct FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance + v_cheque.amount WHERE id = v_cheque.clearing_agent_id;

        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acct FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance + v_cheque.amount WHERE id = v_cheque.shipping_company_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            v_credit_acct := public.resolve_gl_account(
                CASE v_currency WHEN 'EGP' THEN '3001' WHEN 'USD' THEN '3002' WHEN 'EUR' THEN '3003' WHEN 'GBP' THEN '3004' ELSE '3001' END,
                v_company_id
            );
        ELSE
            v_credit_acct := public.resolve_gl_account(
                CASE v_currency WHEN 'EGP' THEN '3001' WHEN 'USD' THEN '3002' WHEN 'EUR' THEN '3003' WHEN 'GBP' THEN '3004' ELSE '3001' END,
                v_company_id
            );
        END IF;

        -- Post journal: Dr Bank / Cr Counterparty
        IF v_credit_acct IS NOT NULL THEN
            v_je_id := public.post_journal_entry(
                'bank_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_bank_acct, 'debit', v_cheque.amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', v_cheque.amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        END IF;

        -- Bank transaction WITH journal_entry_id
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after, description, created_by, journal_entry_id, entity_type, entity_id, source_type)
        VALUES (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_new_bank_bal, v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::text, 'cheque')
        RETURNING id INTO v_bank_tx_id;

    END IF;

    -- Update cheque status + store journal_entry_id
    UPDATE public.cheques
    SET status = 'cleared', cleared_at = NOW(), journal_entry_id = v_je_id
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'bank_tx_id', v_bank_tx_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.clear_cheque(BIGINT) TO authenticated;

-- ============================================================
-- 3. Fix exchange_bank_currency: store journal_entry_id on bank tx
-- ============================================================
DROP FUNCTION IF EXISTS public.exchange_bank_currency(INTEGER, INTEGER, NUMERIC, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION public.exchange_bank_currency(
    p_from_account_id INTEGER,
    p_to_account_id   INTEGER,
    p_amount_from     NUMERIC,
    p_amount_to       NUMERIC,
    p_exchange_rate   NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_balance_before_from NUMERIC(18,2);
    v_balance_after_from  NUMERIC(18,2);
    v_balance_before_to   NUMERIC(18,2);
    v_balance_after_to    NUMERIC(18,2);
    v_from_currency       TEXT;
    v_to_currency         TEXT;
    v_user_id             UUID := auth.uid();
    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس الحساب';
    END IF;

    SELECT balance, currency INTO v_balance_before_from, v_from_currency
    FROM bank_accounts WHERE id = p_from_account_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'حساب المصدر غير موجود';
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في حساب المصدر (المتوفر: %)', v_balance_before_from;
    END IF;

    SELECT balance, currency INTO v_balance_before_to, v_to_currency
    FROM bank_accounts WHERE id = p_to_account_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب الهدف غير موجود';
    END IF;

    IF v_from_currency = v_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل بين حسابات بنفس العملة (يجب أن تكون العملات مختلفة)';
    END IF;

    v_company_id := (SELECT company_id FROM bank_accounts WHERE id = p_from_account_id);
    v_desc := 'تحويل عملة بنكي من ' || v_from_currency || ' إلى ' || v_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to   := v_balance_before_to + p_amount_to;

    UPDATE bank_accounts SET balance = v_balance_after_from, updated_at = now() WHERE id = p_from_account_id;
    UPDATE bank_accounts SET balance = v_balance_after_to, updated_at = now() WHERE id = p_to_account_id;

    v_je_id := public.post_journal_entry(
        'bank_currency_exchange',
        v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct,   'debit', p_amount_to,   'credit', 0,            'currency', v_to_currency,   'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0,            'credit', p_amount_from, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    -- FIX: Store journal_entry_id on both bank transactions
    INSERT INTO bank_account_transactions (bank_account_id, type, amount, balance_before, balance_after, description, created_by, journal_entry_id, source_type)
    VALUES (p_from_account_id, 'currency_exchange_out', p_amount_from, v_balance_before_from, v_balance_after_from, v_desc, v_user_id, v_je_id, 'currency_exchange');

    INSERT INTO bank_account_transactions (bank_account_id, type, amount, balance_before, balance_after, description, created_by, journal_entry_id, source_type)
    VALUES (p_to_account_id, 'currency_exchange_in', p_amount_to, v_balance_before_to, v_balance_after_to, v_desc, v_user_id, v_je_id, 'currency_exchange');

    RETURN jsonb_build_object('success', true, 'journal_entry_id', v_je_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_bank_currency(INTEGER, INTEGER, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

-- ============================================================
-- 4. Re-apply withdraw_bank_account (ensure journal_entry_id stored)
-- ============================================================
DROP FUNCTION IF EXISTS public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id      INTEGER,
    p_amount          NUMERIC,
    p_description     TEXT DEFAULT NULL,
    p_entity_type     TEXT DEFAULT NULL,
    p_entity_id       TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL
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

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية (الرصيد الحالي: %)', v_current_balance;
    END IF;

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

    -- Determine the debit account based on entity_type
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        -- Bank withdraw to customer: Dr Customer / Cr Bank
        DECLARE v_cust_acct BIGINT;
        BEGIN
            SELECT account_id INTO v_cust_acct FROM customers WHERE id = p_entity_id::bigint;
            IF v_cust_acct IS NOT NULL THEN
                v_expense_acct := v_cust_acct;
            ELSE
                v_expense_acct := public.resolve_gl_account('51101', v_company_id);
            END IF;
        END;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        DECLARE v_sup_acct BIGINT;
        BEGIN
            SELECT account_id INTO v_sup_acct FROM suppliers WHERE id::text = p_entity_id;
            IF v_sup_acct IS NOT NULL THEN
                v_expense_acct := v_sup_acct;
            ELSE
                v_expense_acct := public.resolve_gl_account('51101', v_company_id);
            END IF;
        END;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        CASE WHEN v_source_type = 'opening_balance' THEN 'opening_balance' ELSE 'bank_withdraw' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name, source_type, journal_entry_id
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_source_type, v_je_id
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('customer', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::text = p_entity_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('supplier', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('clearing_agent', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shipping_company', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shareholder', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    END IF;

    RETURN jsonb_build_object('success', true, 'bank_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ============================================================
-- 5. Re-apply deposit_bank_account (ensure journal_entry_id stored)
-- ============================================================
DROP FUNCTION IF EXISTS public.deposit_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id         INTEGER,
    p_amount             NUMERIC,
    p_description        TEXT DEFAULT NULL,
    p_entity_type        TEXT DEFAULT NULL,
    p_entity_id          TEXT DEFAULT NULL,
    p_counterparty_name  TEXT DEFAULT NULL,
    p_revenue_account_id INTEGER DEFAULT NULL
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
        CASE v_currency
            WHEN 'EGP' THEN '11201'
            WHEN 'USD' THEN '11202'
            WHEN 'EUR' THEN '11203'
            WHEN 'GBP' THEN '11204'
            ELSE '11201'
        END,
        v_company_id
    );

    v_credit_acct := NULL;

    IF p_entity_type IS NULL THEN
        v_credit_acct := public.resolve_gl_account(
            CASE v_currency
                WHEN 'EGP' THEN '3001'
                WHEN 'USD' THEN '3002'
                WHEN 'EUR' THEN '3003'
                WHEN 'GBP' THEN '3004'
                ELSE '3001'
            END,
            v_company_id
        );
    ELSIF p_entity_type = 'revenue' THEN
        IF p_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب الإيرادات';
        END IF;
        v_credit_acct := p_revenue_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_credit_acct
        FROM customers WHERE id = p_entity_id::bigint;
        IF v_credit_acct IS NULL THEN
            RAISE EXCEPTION 'العميل لا يملك حساب محاسبي مرتبط';
        END IF;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_credit_acct
        FROM suppliers WHERE id::text = p_entity_id;
        IF v_credit_acct IS NULL THEN
            RAISE EXCEPTION 'المورد لا يملك حساب محاسبي مرتبط';
        END IF;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct
        FROM shareholders WHERE id::text = p_entity_id;
        IF v_credit_acct IS NULL THEN
            RAISE EXCEPTION 'المساهم لا يملك حساب محاسبي مرتبط';
        END IF;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_credit_acct
        FROM clearing_agents WHERE id = p_entity_id::bigint;
        IF v_credit_acct IS NULL THEN
            RAISE EXCEPTION 'المخلص لا يملك حساب محاسبي مرتبط';
        END IF;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_credit_acct
        FROM shipping_companies WHERE id = p_entity_id::bigint;
        IF v_credit_acct IS NULL THEN
            RAISE EXCEPTION 'شركة الشحن لا تملك حساب محاسبي مرتبط';
        END IF;
    ELSE
        v_credit_acct := public.resolve_gl_account(
            CASE v_currency
                WHEN 'EGP' THEN '3001'
                WHEN 'USD' THEN '3002'
                WHEN 'EUR' THEN '3003'
                WHEN 'GBP' THEN '3004'
                ELSE '3001'
            END,
            v_company_id
        );
    END IF;

    IF v_credit_acct IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على الحساب المحاسبي للائتمان';
    END IF;

    PERFORM 1 FROM accounts WHERE id = v_credit_acct AND is_active = true AND is_leaf = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'حساب الائتمان غير صالح (يجب أن يكون حساب نشط وورقة)';
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
        source_type, journal_entry_id, revenue_account_id
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('customer', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('supplier', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('clearing_agent', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shipping_company', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_entity_id::uuid;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shareholder', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'new_balance', v_new_balance,
        'journal_entry_id', v_je_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deposit_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

-- ============================================================
-- 6. Backfill existing bank tx that went through clear_cheque
--    (type = 'withdraw' or 'deposit' without journal_entry_id, source_type = 'cheque')
-- ============================================================
DO $$
DECLARE
    v_rec RECORD;
    v_je_id BIGINT;
    v_cnt INT := 0;
BEGIN
    -- For bank tx rows created by old clear_cheque that have no journal_entry_id
    FOR v_rec IN
        SELECT bat.id, bat.bank_account_id, bat.type, bat.amount, bat.description, bat.created_at,
               ba.currency, ba.company_id
        FROM public.bank_account_transactions bat
        JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id
        WHERE bat.journal_entry_id IS NULL
          AND bat.description ~* '(صرف شيك|تحصيل شيك)'
    LOOP
        -- Try to find matching journal entry by description
        SELECT je.id INTO v_je_id
        FROM public.journal_entries je
        WHERE je.deleted_at IS NULL
          AND je.description ILIKE '%' || v_rec.description || '%'
        ORDER BY ABS(EXTRACT(EPOCH FROM (je.entry_date::timestamp - v_rec.created_at))) ASC
        LIMIT 1;

        IF v_je_id IS NOT NULL THEN
            UPDATE public.bank_account_transactions SET journal_entry_id = v_je_id WHERE id = v_rec.id;
            v_cnt := v_cnt + 1;
        END IF;
    END LOOP;

    RAISE NOTICE 'Backfilled % cheque bank transactions with journal_entry_id', v_cnt;
END $$;

-- ============================================================
-- 7. Backfill cheques.journal_entry_id from their bank transactions
-- ============================================================
DO $$
DECLARE
    v_cnt INT := 0;
BEGIN
    UPDATE public.cheques c
    SET journal_entry_id = (
        SELECT bat.journal_entry_id
        FROM public.bank_account_transactions bat
        WHERE bat.source_type = 'cheque'
          AND bat.entity_type = 'cheque'
          AND bat.entity_id = c.id::text
          AND bat.journal_entry_id IS NOT NULL
        ORDER BY bat.id DESC
        LIMIT 1
    )
    WHERE c.journal_entry_id IS NULL
      AND c.status = 'cleared'
      AND EXISTS (
        SELECT 1 FROM public.bank_account_transactions bat
        WHERE bat.source_type = 'cheque'
          AND bat.entity_type = 'cheque'
          AND bat.entity_id = c.id::text
          AND bat.journal_entry_id IS NOT NULL
      );

    GET DIAGNOSTICS v_cnt = ROW_COUNT;
    RAISE NOTICE 'Backfilled % cheques with journal_entry_id', v_cnt;
END $$;

-- ============================================================
-- 8. Final verification
-- ============================================================
DO $$
DECLARE
    v_bank_total INT;
    v_bank_linked INT;
    v_bank_unlinked INT;
    v_cheque_total INT;
    v_cheque_linked INT;
BEGIN
    SELECT COUNT(*) INTO v_bank_total FROM public.bank_account_transactions;
    SELECT COUNT(*) INTO v_bank_linked FROM public.bank_account_transactions WHERE journal_entry_id IS NOT NULL;
    v_bank_unlinked := v_bank_total - v_bank_linked;

    SELECT COUNT(*) INTO v_cheque_total FROM public.cheques WHERE status = 'cleared';
    SELECT COUNT(*) INTO v_cheque_linked FROM public.cheques WHERE status = 'cleared' AND journal_entry_id IS NOT NULL;

    RAISE NOTICE 'Bank transactions: total=%, linked=%, unlinked=%', v_bank_total, v_bank_linked, v_bank_unlinked;
    RAISE NOTICE 'Cleared cheques: total=%, linked=%', v_cheque_total, v_cheque_linked;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
