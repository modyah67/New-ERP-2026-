-- Migration 144: Fix resolve_treasury_account to handle missing GL accounts gracefully
-- The sub-treasuries don't have account codes like 11101 in the accounts table.
-- This migration adds multiple fallback strategies.

CREATE OR REPLACE FUNCTION public.resolve_treasury_account(
    p_treasury_id BIGINT,
    p_currency TEXT,
    p_company_id UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id BIGINT;
    v_code TEXT;
BEGIN
    -- 1) Try treasuries.account_id
    SELECT account_id INTO v_account_id FROM treasuries WHERE id = p_treasury_id;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 2) Try treasury_balances.account_id for this treasury+currency
    SELECT tb.account_id INTO v_account_id
    FROM treasury_balances tb
    WHERE tb.treasury_id = p_treasury_id AND tb.currency = p_currency AND tb.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 3) Try the standard code mapping
    v_code := CASE p_currency
        WHEN 'EGP' THEN '11101'
        WHEN 'USD' THEN '11102'
        WHEN 'EUR' THEN '11103'
        WHEN 'GBP' THEN '11104'
        ELSE '11101'
    END;
    SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code AND company_id = p_company_id LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 4) Try the main treasury's account_id (type = 'main')
    SELECT t.account_id INTO v_account_id
    FROM treasuries t
    WHERE t.type = 'main' AND t.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 5) Try any account in the 111xx range for this company
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '111%' AND company_id = p_company_id AND is_active = true
    ORDER BY account_code
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 6) Try any cash/treasury account (1xxxx range) for this company
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '11%' AND company_id = p_company_id AND is_active = true
    ORDER BY account_code
    LIMIT 1;

    RETURN v_account_id;
END;
$$;

-- Also fix resolve_gl_account to be more lenient for treasury accounts (11xxx range)
-- by trying partial matches when exact match fails
CREATE OR REPLACE FUNCTION public.resolve_gl_account(
    p_account_code TEXT,
    p_company_id   UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT id INTO v_id
    FROM accounts
    WHERE account_code = p_account_code AND company_id = p_company_id;

    IF v_id IS NULL AND p_account_code LIKE '111%' THEN
        -- For treasury cash accounts, try to find any matching account in the same range
        SELECT id INTO v_id
        FROM accounts
        WHERE account_code LIKE '111%' AND company_id = p_company_id AND is_active = true
        ORDER BY account_code
        LIMIT 1;
    END IF;

    IF v_id IS NULL AND p_account_code LIKE '111%' THEN
        -- Last resort: try the main treasury's account_id
        SELECT t.account_id INTO v_id
        FROM treasuries t
        WHERE t.type = 'main' AND t.account_id IS NOT NULL
        LIMIT 1;
    END IF;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'GL Account % not found for company %', p_account_code, p_company_id;
    END IF;

    RETURN v_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
