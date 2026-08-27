-- =============================================================================
-- FIX DEPOSIT AND WITHDRAW TREASURY BALANCE BEFORE & AFTER CALCULATION
-- =============================================================================

-- 1. Fix deposit_treasury
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC := 0;
    v_tx_id BIGINT;
    v_account_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Fetch current balance before updating
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := v_current_balance + p_amount;

    -- Fetch account ID for double-entry
    SELECT id INTO v_account_id FROM accounts WHERE account_code = 
        CASE p_currency 
            WHEN 'EGP' THEN '11101'
            WHEN 'USD' THEN '11102'
            WHEN 'EUR' THEN '11103'
            WHEN 'GBP' THEN '11104'
            ELSE '11101'
        END;

    -- Upsert Treasury Balance
    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (p_treasury_id, p_currency, v_new_balance, v_account_id)
    ON CONFLICT (treasury_id, currency) 
    DO UPDATE SET 
        balance = v_new_balance,
        account_id = EXCLUDED.account_id;

    -- Record Transaction with CORRECT balance_before and balance_after
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, 
        balance_before, balance_after, description, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, p_description, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'balance_before', v_current_balance,
        'balance_after', v_new_balance
    );
END;
$$;


-- 2. Fix withdraw_treasury
CREATE OR REPLACE FUNCTION public.withdraw_treasury(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC := 0;
    v_tx_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Fetch current balance
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    -- Update Treasury Balance
    UPDATE treasury_balances
    SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Record Transaction
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, 
        balance_before, balance_after, description, created_by
    ) VALUES (
        p_treasury_id, 'expense', p_currency, p_amount,
        v_current_balance, v_new_balance, p_description, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'balance_before', v_current_balance,
        'balance_after', v_new_balance
    );
END;
$$;
