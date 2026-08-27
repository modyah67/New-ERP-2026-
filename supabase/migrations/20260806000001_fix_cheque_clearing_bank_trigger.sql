-- Migration: Fix bank withdrawal trigger for cheque clearing
--
-- ROOT CAUSE:
-- trg_require_expense_acct_bank fires on ALL bank_account_transactions with type='withdrawal'
-- and requires expense_account_id IS NOT NULL.
-- But withdraw_bank_account (used by cheque clearing) does NOT set expense_account_id
-- because the GL posting is handled separately via post_journal_entry().
--
-- The bank deposit trigger was already fixed in migration 069 to only require
-- revenue_account_id for 'revenue' source. This migration applies the same fix
-- for bank withdrawals: only require expense_account_id when source_type is NOT
-- a known entity-based operation (cheque, customer, supplier, etc.)
--
-- FIX:
-- 1. Update fn_require_expense_account_bank to exempt known entity-based source types
-- 2. Update clear_cheque to handle 'treasury' counterparty type (currently missing)

BEGIN;

-- ============================================================
-- 1. Fix bank withdrawal trigger — exempt entity-based operations
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_require_expense_account_bank()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Only require expense_account_id for generic/manual withdrawals.
    -- Entity-based operations (cheque, customer, supplier, etc.) resolve their
    -- GL accounts inside the RPC via post_journal_entry(), so they don't need
    -- expense_account_id on the transaction row.
    IF NEW.type = 'withdrawal'
       AND NEW.expense_account_id IS NULL
       AND COALESCE(NEW.source_type, '') NOT IN (
           'cheque', 'customer', 'supplier', 'clearing_agent',
           'shipping_company', 'shareholder', 'opening_balance',
           'treasury'
       )
    THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================
-- 2. Fix treasury expense trigger — exempt 'withdrawal' type
--    since withdraw_treasury already sets expense_account_id
--    but treasury cheque clearing uses 'withdrawal' type too
-- ============================================================

-- Also update the treasury transaction trigger to be smarter:
-- Only require expense_account_id for 'expense' type, not 'withdrawal'
-- (withdrawal is handled by withdraw_treasury which sets it already)
CREATE OR REPLACE FUNCTION public.fn_require_expense_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Only require expense_account_id for actual 'expense' transactions
    -- 'withdrawal' and 'supplier_payment' resolve their GL accounts differently
    IF NEW.type = 'expense' AND NEW.expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

-- Update treasury trigger WHEN clause to only fire for 'expense' type
DROP TRIGGER IF EXISTS trg_require_expense_acct ON treasury_transactions;
CREATE TRIGGER trg_require_expense_acct
    BEFORE INSERT ON treasury_transactions
    FOR EACH ROW
    WHEN (NEW.type = 'expense')
    EXECUTE FUNCTION public.fn_require_expense_account_treasury();

-- ============================================================
-- 3. Update clear_cheque to handle 'treasury' counterparty type
-- ============================================================
DROP FUNCTION IF EXISTS public.clear_cheque(BIGINT);

CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id BIGINT)
RETURNS JSONB
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
    SELECT id, balance, ba.company_id INTO v_bank_id, v_bank_bal, v_company_id
    FROM public.bank_accounts ba
    WHERE ba.currency = v_cheque.currency
    LIMIT 1
    FOR UPDATE;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لا توجد حساب بنكي بهذه العملة';
    END IF;

    v_currency := v_cheque.currency;

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

    -- ================================================================
    -- OUTGOING CHEQUE: Dr Counterparty / Cr Bank
    -- ================================================================
    IF v_cheque.type = 'outgoing' THEN
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (% متوفر)', v_bank_bal;
        END IF;

        v_new_bank_bal := v_bank_bal - v_cheque.amount;

        -- Determine debit account (counterparty)
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
            -- Treasury counterparty: use treasury GL account
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

        -- Fallback to equity if no counterparty account found
        IF v_counterparty_acct IS NULL THEN
            v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
        END IF;

        -- Post journal entry: Dr Counterparty / Cr Bank
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
                    'currency', v_currency,
                    'description', v_desc
                ),
                jsonb_build_object(
                    'account_id', v_bank_acct,
                    'debit', 0,
                    'credit', v_cheque.amount,
                    'currency', v_currency,
                    'description', v_desc
                )
            )
        );

        -- Update bank balance
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal, updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction WITH journal_entry_id
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type)
        VALUES
            (v_bank_id, 'withdrawal', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque')
        RETURNING id INTO v_bank_tx_id;

    -- ================================================================
    -- INCOMING CHEQUE: Dr Bank / Cr Counterparty
    -- ================================================================
    ELSIF v_cheque.type = 'incoming' THEN
        v_new_bank_bal := v_bank_bal + v_cheque.amount;

        -- Determine credit account (counterparty)
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
            -- Treasury counterparty: use treasury GL account
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

        -- Fallback to equity if no counterparty account found
        IF v_counterparty_acct IS NULL THEN
            v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
        END IF;

        -- Post journal entry: Dr Bank / Cr Counterparty
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
                    'currency', v_currency,
                    'description', v_desc
                ),
                jsonb_build_object(
                    'account_id', v_counterparty_acct,
                    'debit', 0,
                    'credit', v_cheque.amount,
                    'currency', v_currency,
                    'description', v_desc
                )
            )
        );

        -- Update bank balance
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal, updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction WITH journal_entry_id
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type)
        VALUES
            (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque')
        RETURNING id INTO v_bank_tx_id;

    END IF;

    -- Update cheque status + store journal_entry_id
    UPDATE public.cheques
    SET status = 'cleared',
        cleared_at = NOW(),
        journal_entry_id = v_je_id
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'bank_tx_id', v_bank_tx_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.clear_cheque(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
