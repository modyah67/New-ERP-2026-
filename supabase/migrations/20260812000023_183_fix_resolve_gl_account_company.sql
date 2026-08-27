-- Fix resolve_gl_account to fallback to ignoring company_id if not found, since account_code is globally unique
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

    IF v_id IS NULL THEN
        SELECT id INTO v_id
        FROM accounts
        WHERE account_code = p_account_code;
    END IF;

    IF v_id IS NULL AND p_account_code LIKE '111%' THEN
        -- For treasury cash accounts, try to find any matching account in the same range
        SELECT id INTO v_id
        FROM accounts
        WHERE account_code LIKE '111%' AND company_id = p_company_id AND is_active = true
        ORDER BY account_code
        LIMIT 1;
        
        IF v_id IS NULL THEN
            SELECT id INTO v_id
            FROM accounts
            WHERE account_code LIKE '111%' AND is_active = true
            ORDER BY account_code
            LIMIT 1;
        END IF;
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

-- Fix resolve_treasury_account to also fallback to ignoring company_id
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
    v_real_company_id UUID;
BEGIN
    -- Resolve company_id if NULL
    v_real_company_id := p_company_id;
    IF v_real_company_id IS NULL THEN
        SELECT company_id INTO v_real_company_id FROM treasuries WHERE id = p_treasury_id;
    END IF;
    IF v_real_company_id IS NULL THEN
        SELECT id INTO v_real_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- 1) Try treasuries.account_id
    SELECT account_id INTO v_account_id FROM treasuries WHERE id = p_treasury_id;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 2) Try treasury_balances.account_id
    SELECT tb.account_id INTO v_account_id
    FROM treasury_balances tb
    WHERE tb.treasury_id = p_treasury_id AND tb.currency = p_currency AND tb.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 3) Try standard code mapping
    v_code := CASE p_currency
        WHEN 'EGP' THEN '11101'
        WHEN 'USD' THEN '11102'
        WHEN 'EUR' THEN '11103'
        WHEN 'GBP' THEN '11104'
        ELSE '11101'
    END;
    
    SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code AND company_id = v_real_company_id LIMIT 1;
    
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
    END IF;

    IF v_account_id IS NOT NULL THEN
        -- Also backfill the treasury for next time
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 4) Try main treasury's account_id
    SELECT t.account_id INTO v_account_id
    FROM treasuries t
    WHERE t.type = 'main' AND t.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 5) Try any 111% account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '111%' AND company_id = v_real_company_id AND is_active = true
    ORDER BY account_code LIMIT 1;
    
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id
        FROM accounts
        WHERE account_code LIKE '111%' AND is_active = true
        ORDER BY account_code LIMIT 1;
    END IF;
    
    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 6) Try any 11% account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '11%' AND company_id = v_real_company_id AND is_active = true
    ORDER BY account_code LIMIT 1;
    
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id
        FROM accounts
        WHERE account_code LIKE '11%' AND is_active = true
        ORDER BY account_code LIMIT 1;
    END IF;

    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 7) Last resort: try ANY asset account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_type = 'asset' AND company_id = v_real_company_id AND is_leaf = true AND is_active = true
    ORDER BY account_code LIMIT 1;
    
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id
        FROM accounts
        WHERE account_type = 'asset' AND is_leaf = true AND is_active = true
        ORDER BY account_code LIMIT 1;
    END IF;

    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    RAISE EXCEPTION 'Could not resolve any treasury GL account for treasury % currency %', p_treasury_id, p_currency;
END;
$$;

NOTIFY pgrst, 'reload schema';
