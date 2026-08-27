-- Migration 225: Fix Bank Exchange Base Currency
-- Bank currency exchanges (foreign to EGP or vice versa) were inserting the "from" amount
-- as the base currency amount for BOTH sides of the transaction. This corrupted the EGP 
-- ledger balances in the base-currency trial balance.

-- 1. Fix the RPC function
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
    v_from_account_ledger  INTEGER;
    v_to_account_ledger    INTEGER;
    v_je_description       TEXT;
    v_base_amount          NUMERIC;
BEGIN
    -- 1. Setup & Context
    SELECT company_id INTO v_company_id FROM bank_accounts WHERE id = p_from_account_id;
    v_user_id := auth.uid();

    -- Validate inputs
    IF p_amount_from <= 0 THEN
        RAISE EXCEPTION 'From amount must be greater than zero';
    END IF;
    IF p_amount_to <= 0 THEN
        RAISE EXCEPTION 'To amount must be greater than zero';
    END IF;
    IF p_exchange_rate <= 0 THEN
        RAISE EXCEPTION 'Exchange rate must be greater than zero';
    END IF;

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

    -- Determine base amount for accounting (Assuming EGP is base currency)
    IF v_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSIF v_to_currency = 'EGP' THEN
        v_base_amount := p_amount_to;
    ELSE
        -- Fallback: Use from amount
        v_base_amount := p_amount_from;
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
        description,
        entity_type
    ) VALUES (
        p_from_account_id,
        'currency_exchange_out',
        p_amount_from,
        v_old_from_balance,
        v_new_from_balance,
        'Exchange to ' || v_to_currency,
        'exchange'
    ) RETURNING id INTO v_transaction_id;

    INSERT INTO bank_account_transactions (
        bank_account_id,
        type,
        amount,
        balance_before,
        balance_after,
        description,
        entity_type
    ) VALUES (
        p_to_account_id,
        'currency_exchange_in',
        p_amount_to,
        v_old_to_balance,
        v_new_to_balance,
        'Exchange from ' || v_from_currency,
        'exchange'
    );

    -- 5. Enterprise Accounting Integration
    -- Get Ledger Accounts
    v_from_account_ledger := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_account_ledger := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

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
        v_base_amount,
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
        v_base_amount,
        v_je_description,
        v_company_id
    );

    v_result := jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_entry_id', v_je_id
    );

    RETURN v_result;
END;
$$;


-- 2. Fix corrupted historic ledger entries
-- Find exchange journal entries and sync their amount_in_base_currency to the EGP side's actual amount
WITH exchange_jes AS (
    SELECT id 
    FROM journal_entries 
    WHERE source_type = 'exchange_currency' OR description LIKE 'تحويل بنكي من حساب%'
)
UPDATE account_ledger_entries ale
SET amount_in_base_currency = (
    SELECT COALESCE(MAX(a.debit + a.credit), 0)
    FROM account_ledger_entries a
    WHERE a.journal_entry_id = ale.journal_entry_id
      AND a.currency = 'EGP'
)
WHERE journal_entry_id IN (SELECT id FROM exchange_jes)
  AND (
    amount_in_base_currency != (
        SELECT COALESCE(MAX(a.debit + a.credit), 0)
        FROM account_ledger_entries a
        WHERE a.journal_entry_id = ale.journal_entry_id
          AND a.currency = 'EGP'
    )
  )
  AND EXISTS (
      SELECT 1 FROM account_ledger_entries a 
      WHERE a.journal_entry_id = ale.journal_entry_id AND a.currency = 'EGP'
  );

