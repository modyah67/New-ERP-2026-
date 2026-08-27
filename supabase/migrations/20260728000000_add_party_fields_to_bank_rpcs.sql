-- Add entity_type, entity_id, counterparty_name to bank_account_transactions INSERT
-- in deposit_bank_account and withdraw_bank_account RPCs.
-- These columns already exist in the table from the initial schema.
-- The Dart DAO already sends p_entity_type, p_entity_id, p_counterparty_name.

-- 1. Update deposit_bank_account to accept and store party fields
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
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency INTO v_current_balance, v_currency
    FROM bank_accounts WHERE id = p_account_id;

    v_new_balance := v_current_balance + p_amount;

    SELECT id INTO v_bank_account_id_code FROM accounts WHERE account_code = '11201';
    SELECT id INTO v_revenue_account_id FROM accounts WHERE account_code = '41101';

    IF v_bank_account_id_code IS NULL OR v_revenue_account_id IS NULL THEN
        SELECT id INTO v_bank_account_id_code FROM accounts LIMIT 1;
        SELECT id INTO v_revenue_account_id FROM accounts LIMIT 1;
    END IF;

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'إيداع بنكي مباشر'), 'posted', true, 'bank_deposit', auth.uid()
    ) RETURNING id INTO v_tx_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_tx_id, v_bank_account_id_code, p_amount, 0, v_currency, p_amount, p_description);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_tx_id, v_revenue_account_id, 0, p_amount, v_currency, p_amount, p_description);

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

-- 2. Update withdraw_bank_account to accept and store party fields
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
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency INTO v_current_balance, v_currency
    FROM bank_accounts WHERE id = p_account_id;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد البنكي غير كافٍ (المتوفر: %)', v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    SELECT id INTO v_bank_account_id_code FROM accounts WHERE account_code = '11201';
    SELECT id INTO v_expense_account_id FROM accounts WHERE account_code = '51101';

    IF v_bank_account_id_code IS NULL OR v_expense_account_id IS NULL THEN
        SELECT id INTO v_bank_account_id_code FROM accounts LIMIT 1;
        SELECT id INTO v_expense_account_id FROM accounts LIMIT 1;
    END IF;

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'سحب / مصروف بنكي مباشر'), 'posted', true, 'bank_withdraw', auth.uid()
    ) RETURNING id INTO v_tx_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_tx_id, v_expense_account_id, p_amount, 0, v_currency, p_amount, p_description);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_tx_id, v_bank_account_id_code, 0, p_amount, v_currency, p_amount, p_description);

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

-- 3. Grant execute permissions
GRANT EXECUTE ON FUNCTION public.deposit_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
