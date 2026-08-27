BEGIN;

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
    v_from_account_exists BOOLEAN;
    v_to_account_exists   BOOLEAN;
    v_from_currency       TEXT;
    v_to_currency         TEXT;
    v_old_from_balance    NUMERIC;
    v_old_to_balance      NUMERIC;
    v_new_from_balance    NUMERIC;
    v_new_to_balance      NUMERIC;
    v_transaction_id      BIGINT;
    v_result              JSONB;
    v_company_id          UUID;
    v_user_id             UUID;
    
    -- Accounting Variables
    v_je_id                BIGINT;
    v_from_account_ledger  BIGINT;
    v_to_account_ledger    BIGINT;
    v_je_description       TEXT;
BEGIN
    -- 1. Validate inputs
    IF p_amount_from <= 0 THEN
        RAISE EXCEPTION 'From amount must be greater than zero';
    END IF;
    IF p_amount_to <= 0 THEN
        RAISE EXCEPTION 'To amount must be greater than zero';
    END IF;
    IF p_exchange_rate <= 0 THEN
        RAISE EXCEPTION 'Exchange rate must be greater than zero';
    END IF;

    -- Get Context
    v_company_id := current_setting('app.current_company_id', true)::UUID;
    v_user_id := auth.uid();

    -- 2. Verify bank accounts exist & have sufficient balance
    SELECT TRUE, currency, balance INTO v_from_account_exists, v_from_currency, v_old_from_balance
    FROM bank_accounts WHERE id = p_from_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source bank account not found';
    END IF;

    IF v_old_from_balance < p_amount_from THEN
        RAISE EXCEPTION 'Insufficient balance in source bank account';
    END IF;

    SELECT TRUE, currency, balance INTO v_to_account_exists, v_to_currency, v_old_to_balance
    FROM bank_accounts WHERE id = p_to_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Destination bank account not found';
    END IF;

    -- 3. Update Balances
    UPDATE bank_accounts
    SET balance = balance - p_amount_from
    WHERE id = p_from_account_id
    RETURNING balance INTO v_new_from_balance;

    UPDATE bank_accounts
    SET balance = balance + p_amount_to
    WHERE id = p_to_account_id
    RETURNING balance INTO v_new_to_balance;

    -- 4. Create Transaction Record
    INSERT INTO bank_account_transactions (
        bank_account_id,
        type,
        amount,
        balance_before,
        balance_after,
        description
    ) VALUES (
        p_from_account_id,
        'withdrawal',
        p_amount_from,
        v_old_from_balance,
        v_new_from_balance,
        'Exchange to ' || v_to_currency
    ) RETURNING id INTO v_transaction_id;

    INSERT INTO bank_account_transactions (
        bank_account_id,
        type,
        amount,
        balance_before,
        balance_after,
        description
    ) VALUES (
        p_to_account_id,
        'deposit',
        p_amount_to,
        v_old_to_balance,
        v_new_to_balance,
        'Exchange from ' || v_from_currency
    );

    -- 5. Enterprise Accounting Integration
    -- Get Ledger Accounts
    SELECT account_id INTO v_from_account_ledger
    FROM sys_entity_accounts 
    WHERE entity_type = 'bank' AND entity_id = p_from_account_id::TEXT;

    SELECT account_id INTO v_to_account_ledger
    FROM sys_entity_accounts 
    WHERE entity_type = 'bank' AND entity_id = p_to_account_id::TEXT;

    IF v_from_account_ledger IS NULL OR v_to_account_ledger IS NULL THEN
        RAISE EXCEPTION 'GL Accounts not found for bank accounts (from: %, to: %)', v_from_account_ledger, v_to_account_ledger;
    END IF;

    v_je_description := 'تحويل بنكي من حساب ' || p_from_account_id || ' إلى حساب ' || p_to_account_id;

    -- Create Journal Entry
    INSERT INTO journal_entries (
        entry_number,
        entry_date,
        description,
        status,
        is_auto_generated,
        source_type,
        source_id,
        created_by,
        company_id
    ) VALUES (
        public.fn_get_next_sequence(v_company_id, 'exchange_currency', NULL, NULL),
        CURRENT_DATE,
        v_je_description,
        'posted',
        true,
        'exchange_currency',
        v_transaction_id::TEXT,
        v_user_id,
        v_company_id
    ) RETURNING id INTO v_je_id;

    -- Update Transaction with JE ID
    UPDATE bank_account_transactions
    SET journal_entry_id = v_je_id
    WHERE id = v_transaction_id;

    -- Create Journal Entry Lines
    -- Credit From Account (Asset Decrease)
    INSERT INTO account_ledger_entries (
        journal_entry_id,
        account_id,
        debit,
        credit,
        currency,
        amount_in_base_currency,
        description,
        company_id
    ) VALUES (
        v_je_id,
        v_from_account_ledger,
        0,
        p_amount_from,
        v_from_currency,
        p_amount_from, -- Base amount is the "from" amount
        v_je_description,
        v_company_id
    );

    -- Debit To Account (Asset Increase)
    INSERT INTO account_ledger_entries (
        journal_entry_id,
        account_id,
        debit,
        credit,
        currency,
        amount_in_base_currency,
        description,
        company_id
    ) VALUES (
        v_je_id,
        v_to_account_ledger,
        p_amount_to,
        0,
        v_to_currency,
        p_amount_from, -- Base amount MUST match the credit line's base amount to balance
        v_je_description,
        v_company_id
    );


    -- 6. Construct result
    v_result := jsonb_build_object(
        'transaction_id', v_transaction_id,
        'journal_entry_id', v_je_id,
        'from_currency', v_from_currency,
        'to_currency', v_to_currency,
        'from_balance', v_new_from_balance,
        'to_balance', v_new_to_balance
    );

    RETURN v_result;
END;
$$;

COMMIT;
