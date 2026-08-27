-- Migration 015: Patch Bank RPCs with company_id
-- Purpose: Injects company_id into journal entries and ledgers directly within the RPCs
--          by reading it from the source bank_account, avoiding Dart signature changes.

BEGIN;

-- 1. Update deposit_bank_account
CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC := 0;
    v_tx_id BIGINT;
    v_bank_account_id_code BIGINT;
    v_revenue_account_id BIGINT;
    v_currency TEXT;
    v_company_id UUID;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    v_new_balance := v_current_balance + p_amount;

    SELECT id INTO v_bank_account_id_code FROM accounts WHERE account_code = '11201' AND company_id = v_company_id;
    SELECT id INTO v_revenue_account_id FROM accounts WHERE account_code = '41101' AND company_id = v_company_id;

    IF v_bank_account_id_code IS NULL OR v_revenue_account_id IS NULL THEN
        SELECT id INTO v_bank_account_id_code FROM accounts WHERE company_id = v_company_id LIMIT 1;
        SELECT id INTO v_revenue_account_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
    END IF;

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'إيداع بنكي مباشر'), 'posted', true, 'bank_deposit', auth.uid(), v_company_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_bank_account_id_code, p_amount, 0, v_currency, p_amount, p_description, v_company_id);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_revenue_account_id, 0, p_amount, v_currency, p_amount, p_description, v_company_id);

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        p_description, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name
    ) RETURNING id INTO v_tx_id;

    RETURN json_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'balance_after', v_new_balance
    );
END;
$$;


-- 2. Update withdraw_bank_account
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC := 0;
    v_tx_id BIGINT;
    v_bank_account_id_code BIGINT;
    v_expense_account_id BIGINT;
    v_currency TEXT;
    v_company_id UUID;
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

    SELECT id INTO v_bank_account_id_code FROM accounts WHERE account_code = '11201' AND company_id = v_company_id;
    SELECT id INTO v_expense_account_id FROM accounts WHERE account_code = '51101' AND company_id = v_company_id;

    IF v_bank_account_id_code IS NULL OR v_expense_account_id IS NULL THEN
        SELECT id INTO v_bank_account_id_code FROM accounts WHERE company_id = v_company_id LIMIT 1;
        SELECT id INTO v_expense_account_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
    END IF;

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'سحب / مصروف بنكي مباشر'), 'posted', true, 'bank_withdraw', auth.uid(), v_company_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_expense_account_id, p_amount, 0, v_currency, p_amount, p_description, v_company_id);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_bank_account_id_code, 0, p_amount, v_currency, p_amount, p_description, v_company_id);

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_current_balance, v_new_balance,
        p_description, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name
    ) RETURNING id INTO v_tx_id;

    RETURN json_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'balance_after', v_new_balance
    );
END;
$$;

COMMIT;
