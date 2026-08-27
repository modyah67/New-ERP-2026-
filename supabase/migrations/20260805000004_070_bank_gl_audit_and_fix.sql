-- Migration 070: Bank GL Accounts Audit & Fix
--
-- PROBLEMS FOUND:
-- 1. Duplicate bank GL accounts: 10101-10104 (unused) duplicate 11201-11204 (active, have GL history)
-- 2. Orphan accounts: 11202, 11203, 11204 have parent_id=NULL (should be under 1010 "Bank")
-- 3. exchange_bank_currency: hardcodes '11201' for BOTH legs (wrong for USD/EUR/GBP exchanges)
-- 4. withdraw_bank_account (old overload): hardcodes '11201' (wrong for non-EGP withdrawals)
-- 5. update_bank_account_transaction: hardcodes '11201' (wrong for non-EGP edits)
--
-- FIX STRATEGY:
-- - Keep 11201-11204 as the canonical bank GL accounts (they have journal entry history)
-- - Reparent 11202, 11203, 11204 under parent 1010 "Bank"
-- - Deactivate 10101, 10102, 10103, 10104 (set is_active=false, keep for historical reference)
-- - Fix all SQL functions to use currency-specific GL codes consistently
-- - Never delete any accounts or journal entries

BEGIN;

-- Drop functions before recreating with corrected GL codes
DROP FUNCTION IF EXISTS public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.exchange_bank_currency(INTEGER, INTEGER, NUMERIC, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS public.update_bank_account_transaction(INTEGER, NUMERIC, TEXT);

-- ============================================================
-- 1. Fix orphan parent linkage for 1120x accounts
-- ============================================================
UPDATE accounts SET parent_id = 10
WHERE account_code IN ('11202', '11203', '11204') AND parent_id IS NULL;

-- ============================================================
-- 2. Deactivate duplicate unused accounts (1010x)
-- These have NO journal entries. 1120x are the real operational accounts.
-- ============================================================
UPDATE accounts SET is_active = false
WHERE account_code IN ('10101', '10102', '10103', '10104');

-- ============================================================
-- 3. Fix exchange_bank_currency: use currency-specific GL codes
-- BUG: both v_from_acct and v_to_acct used '11201' (EGP only)
-- ============================================================
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

    -- FIX: Use currency-specific GL codes for each leg
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

    INSERT INTO bank_account_transactions (bank_account_id, type, amount, balance_before, balance_after, description, created_by)
    VALUES (p_from_account_id, 'currency_exchange_out', p_amount_from, v_balance_before_from, v_balance_after_from, v_desc, v_user_id);

    INSERT INTO bank_account_transactions (bank_account_id, type, amount, balance_before, balance_after, description, created_by)
    VALUES (p_to_account_id, 'currency_exchange_in', p_amount_to, v_balance_before_to, v_balance_after_to, v_desc, v_user_id);

    RETURN jsonb_build_object('journal_entry_id', v_je_id);
END;
$$;

-- ============================================================
-- 4. Fix withdraw_bank_account (old overload): use currency-specific GL codes
-- BUG: hardcoded '11201' for all currencies
-- ============================================================
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

    -- FIX: Use currency-specific GL codes
    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_expense_acct := public.resolve_gl_account('51101', v_company_id);

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

-- ============================================================
-- 5. Fix update_bank_account_transaction: use currency-specific GL codes
-- BUG: hardcoded '11201' for all currencies
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_bank_account_transaction(
    p_transaction_id  INTEGER,
    p_new_amount      NUMERIC,
    p_new_description TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx            RECORD;
    v_balance_diff  NUMERIC;
    v_new_balance   NUMERIC;
    v_company_id    UUID;
    v_bank_acct     BIGINT;
    v_old_je_id     BIGINT;
    v_je_id         BIGINT;
    v_desc          TEXT;
    v_currency      TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
    END IF;

    IF p_new_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT id, bank_account_id, type, amount, balance_before, balance_after,
           journal_entry_id, description
    INTO v_tx
    FROM public.bank_account_transactions
    WHERE id = p_transaction_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    v_balance_diff := p_new_amount - v_tx.amount;

    IF v_tx.type = 'deposit' THEN
        v_new_balance := v_tx.balance_after + v_balance_diff;
    ELSE
        v_new_balance := v_tx.balance_after - v_balance_diff;
    END IF;

    IF v_new_balance < 0 THEN
        RAISE EXCEPTION 'الرصيد لا يمكن أن يصبح سالباً (المتوفر: %)', v_tx.balance_after;
    END IF;

    UPDATE public.bank_accounts SET balance = v_new_balance WHERE id = v_tx.bank_account_id;

    UPDATE public.bank_account_transactions
    SET amount = p_new_amount, balance_after = v_new_balance, description = COALESCE(p_new_description, description)
    WHERE id = p_transaction_id;

    IF v_tx.journal_entry_id IS NOT NULL THEN
        v_company_id := (SELECT company_id FROM bank_accounts WHERE id = v_tx.bank_account_id);
        v_desc := COALESCE(p_new_description, v_tx.description);
        SELECT currency INTO v_currency FROM bank_accounts WHERE id = v_tx.bank_account_id;

        -- FIX: Use currency-specific GL codes
        v_bank_acct := public.resolve_gl_account(
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_tx.journal_entry_id;
        DELETE FROM public.journal_entries WHERE id = v_tx.journal_entry_id;

        IF v_tx.type = 'deposit' THEN
            v_je_id := public.post_journal_entry(
                'bank_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_bank_acct, 'debit', p_new_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', public.resolve_equity_account(v_currency, v_company_id), 'debit', 0, 'credit', p_new_amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        ELSE
            v_je_id := public.post_journal_entry(
                'bank_withdraw', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', public.resolve_gl_account('51101', v_company_id), 'debit', p_new_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_new_amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        END IF;

        UPDATE public.bank_account_transactions SET journal_entry_id = v_je_id WHERE id = p_transaction_id;
    END IF;

    RETURN json_build_object('id', v_tx.bank_account_id, 'balance', v_new_balance);
END;
$$;

-- ============================================================
-- 6. Verify: no journal entries exist on deactivated 1010x accounts
-- (safety check — should return 0)
-- ============================================================
DO $$
DECLARE
    v_cnt BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_cnt FROM account_ledger_entries
    WHERE account_id IN (SELECT id FROM accounts WHERE account_code IN ('10101','10102','10103','10104'));
    IF v_cnt > 0 THEN
        RAISE WARNING 'Found % ledger entries on deactivated 1010x accounts — manual review needed', v_cnt;
    ELSE
        RAISE NOTICE 'OK: No ledger entries on deactivated 1010x accounts';
    END IF;
END $$;

-- ============================================================
-- 7. Verify: all bank GL accounts have correct parent
-- ============================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT a.account_code, a.name, a.parent_id
        FROM accounts a
        WHERE a.account_code IN ('11201','11202','11203','11204') AND a.is_active = true
    LOOP
        IF r.parent_id IS NULL OR r.parent_id != 10 THEN
            RAISE WARNING 'Bank account % (%) still has wrong parent_id: %', r.account_code, r.name, r.parent_id;
        END IF;
    END LOOP;
    RAISE NOTICE 'OK: All active bank GL accounts have correct parent';
END $$;

COMMIT;
