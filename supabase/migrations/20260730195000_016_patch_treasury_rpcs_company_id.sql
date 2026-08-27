-- Migration 016: Patch Treasury RPCs with company_id
-- Purpose: Injects company_id into journal entries and ledgers directly within the RPCs
--          by reading it from the source treasury, avoiding Dart signature changes.

BEGIN;

-- 1. Update deposit_treasury
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id   INTEGER,
    p_currency      TEXT,
    p_amount        NUMERIC,
    p_description   TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_journal_id      BIGINT;
    v_entry_num       TEXT;
    v_treasury_acc_id BIGINT;
    v_offset_acc_id   BIGINT;
    v_account_code    TEXT;
    v_rate            NUMERIC := 1.0;
    v_amount_base     NUMERIC := 0;
    v_company_id      UUID;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على الخزينة أو company_id غير متوفر';
    END IF;

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    INSERT INTO treasury_balances (treasury_id, currency, balance)
    VALUES (p_treasury_id, p_currency, v_new_balance)
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance;

    IF p_currency != 'EGP' THEN
        SELECT COALESCE(exchange_rate, 1.0) INTO v_rate 
        FROM public.currencies 
        WHERE code = p_currency 
        ORDER BY created_at DESC LIMIT 1;
    END IF;
    v_rate := COALESCE(v_rate, 1.0);
    v_amount_base := p_amount * v_rate;

    CASE p_currency
        WHEN 'EGP' THEN v_account_code := '11101';
        WHEN 'USD' THEN v_account_code := '11102';
        WHEN 'EUR' THEN v_account_code := '11103';
        WHEN 'GBP' THEN v_account_code := '11104';
        ELSE v_account_code := '11101';
    END CASE;

    SELECT id INTO v_treasury_acc_id FROM accounts WHERE account_code = v_account_code AND company_id = v_company_id;
    SELECT id INTO v_offset_acc_id FROM accounts WHERE account_code = '9000' AND company_id = v_company_id;

    IF v_treasury_acc_id IS NULL OR v_offset_acc_id IS NULL THEN
        SELECT id INTO v_treasury_acc_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
        SELECT id INTO v_offset_acc_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
    END IF;

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'إيداع في الخزينة'), 'posted', true, 'treasury_deposit', auth.uid(), v_company_id
    ) RETURNING id INTO v_journal_id;

    v_entry_num := fn_generate_journal_entry_number(v_journal_id);
    UPDATE journal_entries SET entry_number = v_entry_num, source_id = v_journal_id::text WHERE id = v_journal_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_journal_id, v_treasury_acc_id, p_amount, 0, p_currency, v_amount_base, p_description, v_company_id);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_journal_id, v_offset_acc_id, 0, p_amount, p_currency, v_amount_base, p_description, v_company_id);

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after, description, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount, COALESCE(v_current_balance, 0), v_new_balance, p_description, v_journal_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_journal_id,
        'entry_number', v_entry_num,
        'balance_after', v_new_balance
    );
END;
$$;


-- 2. Update disburse_treasury
CREATE OR REPLACE FUNCTION public.disburse_treasury(
    p_treasury_id   INTEGER,
    p_currency      TEXT,
    p_amount        NUMERIC,
    p_description   TEXT DEFAULT '',
    p_category_id   INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_journal_id      BIGINT;
    v_entry_num       TEXT;
    v_treasury_acc_id BIGINT;
    v_expense_acc_id  BIGINT;
    v_account_code    TEXT;
    v_rate            NUMERIC := 1.0;
    v_amount_base     NUMERIC := 0;
    v_company_id      UUID;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على الخزينة أو company_id غير متوفر';
    END IF;

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية. الرصيد الحالي: % %', v_current_balance, p_currency;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE treasury_balances
    SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF p_currency != 'EGP' THEN
        SELECT COALESCE(exchange_rate, 1.0) INTO v_rate 
        FROM public.currencies 
        WHERE code = p_currency 
        ORDER BY created_at DESC LIMIT 1;
    END IF;
    v_rate := COALESCE(v_rate, 1.0);
    v_amount_base := p_amount * v_rate;

    CASE p_currency
        WHEN 'EGP' THEN v_account_code := '11101';
        WHEN 'USD' THEN v_account_code := '11102';
        WHEN 'EUR' THEN v_account_code := '11103';
        WHEN 'GBP' THEN v_account_code := '11104';
        ELSE v_account_code := '11101';
    END CASE;

    SELECT id INTO v_treasury_acc_id FROM accounts WHERE account_code = v_account_code AND company_id = v_company_id;
    SELECT id INTO v_expense_acc_id FROM accounts WHERE account_code = '6000' AND company_id = v_company_id;

    IF v_treasury_acc_id IS NULL OR v_expense_acc_id IS NULL THEN
        SELECT id INTO v_treasury_acc_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
        SELECT id INTO v_expense_acc_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
    END IF;

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'سحب / مصروف من الخزينة'), 'posted', true, 'treasury_withdraw', auth.uid(), v_company_id
    ) RETURNING id INTO v_journal_id;

    v_entry_num := fn_generate_journal_entry_number(v_journal_id);
    UPDATE journal_entries SET entry_number = v_entry_num, source_id = v_journal_id::text WHERE id = v_journal_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_journal_id, v_expense_acc_id, p_amount, 0, p_currency, v_amount_base, p_description, v_company_id);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_journal_id, v_treasury_acc_id, 0, p_amount, p_currency, v_amount_base, p_description, v_company_id);

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after, description, category_id, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'expense', p_currency, p_amount, v_current_balance, v_new_balance, p_description, p_category_id, v_journal_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_journal_id,
        'entry_number', v_entry_num,
        'balance_after', v_new_balance
    );
END;
$$;

COMMIT;
