-- Migration 407: Fix Custody Account Naming in Chart of Accounts
-- Ensures that when an employee custody treasury is created or resolved,
-- its GL account name in the Chart of Accounts is named "عهدة [اسم الموظف]"
-- (e.g. "عهدة محمد") instead of "عهدة - [اسم الخزينة]".

BEGIN;

-- 1. Update create_treasury to generate custody account named "عهدة [اسم الموظف]"
CREATE OR REPLACE FUNCTION public.create_treasury(
    p_name text, 
    p_type text, 
    p_company_id uuid, 
    p_employee_id uuid DEFAULT NULL::uuid, 
    p_notes text DEFAULT NULL::text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_id INTEGER;
    v_account_id BIGINT;
    v_currency TEXT;
    v_emp_name TEXT;
    v_parent_id BIGINT;
    v_code TEXT;
    v_acct_name TEXT;
    v_eng_name TEXT;
BEGIN
    INSERT INTO public.treasuries (name, type, company_id, user_id, notes)
    VALUES (p_name, p_type, p_company_id, p_employee_id, p_notes)
    RETURNING id INTO v_new_id;

    IF p_type = 'main' THEN
        FOREACH v_currency IN ARRAY ARRAY['EGP','USD','EUR','GBP']
        LOOP
            SELECT id INTO v_account_id FROM accounts 
            WHERE account_code = CASE v_currency
                WHEN 'EGP' THEN '11101'
                WHEN 'USD' THEN '11102'
                WHEN 'EUR' THEN '11103'
                WHEN 'GBP' THEN '11104'
            END
            AND (company_id = p_company_id OR company_id IS NULL)
            ORDER BY (company_id = p_company_id) DESC, id ASC
            LIMIT 1;

            INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
            VALUES (v_new_id, v_currency, 0, v_account_id)
            ON CONFLICT (treasury_id, currency) DO UPDATE SET account_id = EXCLUDED.account_id;
        END LOOP;
    ELSE
        -- Employee Custody Treasury
        IF p_employee_id IS NOT NULL THEN
            SELECT full_name INTO v_emp_name FROM public.users WHERE id = p_employee_id;
        END IF;

        IF v_emp_name IS NOT NULL AND TRIM(v_emp_name) != '' THEN
            IF v_emp_name ILIKE 'عهدة%' OR v_emp_name ILIKE 'عهده%' THEN
                v_acct_name := TRIM(v_emp_name);
            ELSE
                v_acct_name := 'عهدة ' || TRIM(v_emp_name);
            END IF;
            v_eng_name := 'Custody - ' || TRIM(v_emp_name);
        ELSE
            v_acct_name := 'عهدة ' || COALESCE(NULLIF(TRIM(p_name), ''), 'موظف');
            v_eng_name := 'Custody - ' || COALESCE(NULLIF(TRIM(p_name), ''), 'Employee');
        END IF;

        -- Check if an account already exists with this name or code
        SELECT id INTO v_account_id
        FROM accounts
        WHERE (account_name = v_acct_name OR name = v_eng_name)
          AND is_active = true
          AND (company_id = p_company_id OR company_id IS NULL)
        ORDER BY (company_id = p_company_id) DESC, id ASC
        LIMIT 1;

        IF v_account_id IS NULL THEN
            SELECT id INTO v_parent_id
            FROM accounts
            WHERE account_code = '1000'
            ORDER BY (company_id = p_company_id) DESC, id ASC
            LIMIT 1;

            v_code := '1115' || LPAD(v_new_id::TEXT, 2, '0');

            INSERT INTO accounts (
                account_code, name, account_name, account_type, sort_order,
                company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
            )
            VALUES (
                v_code,
                v_eng_name,
                v_acct_name,
                'asset', 1115,
                p_company_id,
                v_parent_id,
                5, true, true, false, true
            )
            ON CONFLICT (account_code) DO UPDATE SET
                account_name = EXCLUDED.account_name,
                name = EXCLUDED.name
            RETURNING id INTO v_account_id;

            IF v_account_id IS NULL THEN
                SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
            END IF;
        END IF;

        IF v_account_id IS NOT NULL THEN
            UPDATE public.treasuries SET account_id = v_account_id WHERE id = v_new_id;
        END IF;

        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
        VALUES (v_new_id, 'EGP', 0, v_account_id)
        ON CONFLICT (treasury_id, currency) DO UPDATE SET account_id = EXCLUDED.account_id;
    END IF;

    RETURN v_new_id;
END;
$$;


-- 2. Update resolve_treasury_account to use employee full_name for custody naming
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
    v_treasury_type TEXT;
    v_treasury_name TEXT;
    v_user_id UUID;
    v_emp_name TEXT;
    v_parent_id BIGINT;
    v_acct_name TEXT;
    v_eng_name TEXT;
BEGIN
    -- Resolve company_id if NULL
    v_real_company_id := p_company_id;
    IF v_real_company_id IS NULL THEN
        SELECT company_id INTO v_real_company_id FROM treasuries WHERE id = p_treasury_id;
    END IF;
    IF v_real_company_id IS NULL THEN
        SELECT id INTO v_real_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- Get treasury info
    SELECT type, name, account_id, user_id INTO v_treasury_type, v_treasury_name, v_account_id, v_user_id
    FROM treasuries WHERE id = p_treasury_id;

    -- 1) If treasury already has an explicit account_id set
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

    -- 3) If this is an Employee Custody treasury (type = 'employee'):
    IF v_treasury_type = 'employee' THEN
        IF v_user_id IS NOT NULL THEN
            SELECT full_name INTO v_emp_name FROM public.users WHERE id = v_user_id;
        END IF;

        IF v_emp_name IS NOT NULL AND TRIM(v_emp_name) != '' THEN
            IF v_emp_name ILIKE 'عهدة%' OR v_emp_name ILIKE 'عهده%' THEN
                v_acct_name := TRIM(v_emp_name);
            ELSE
                v_acct_name := 'عهدة ' || TRIM(v_emp_name);
            END IF;
            v_eng_name := 'Custody - ' || TRIM(v_emp_name);
        ELSE
            v_acct_name := 'عهدة ' || COALESCE(NULLIF(TRIM(v_treasury_name), ''), 'موظف');
            v_eng_name := 'Custody - ' || COALESCE(NULLIF(TRIM(v_treasury_name), ''), 'Employee');
        END IF;

        -- Check if an account already exists with name matching this custody
        SELECT id INTO v_account_id
        FROM accounts
        WHERE (account_name = v_acct_name OR name = v_eng_name OR account_name = 'عهدة - ' || v_treasury_name OR name = 'Custody - ' || v_treasury_name)
          AND is_active = true
        LIMIT 1;

        IF v_account_id IS NULL THEN
            -- Find parent account (1000 / Cash & Equivalents)
            SELECT id INTO v_parent_id
            FROM accounts
            WHERE account_code = '1000'
            ORDER BY (company_id = v_real_company_id) DESC, id ASC
            LIMIT 1;

            v_code := '1115' || LPAD(p_treasury_id::TEXT, 2, '0');

            INSERT INTO accounts (
                account_code, name, account_name, account_type, sort_order,
                company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
            )
            VALUES (
                v_code,
                v_eng_name,
                v_acct_name,
                'asset', 1115,
                v_real_company_id,
                v_parent_id,
                5, true, true, false, true
            )
            ON CONFLICT (account_code) DO UPDATE SET
                account_name = EXCLUDED.account_name,
                name = EXCLUDED.name
            RETURNING id INTO v_account_id;

            IF v_account_id IS NULL THEN
                SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
            END IF;
        END IF;

        IF v_account_id IS NOT NULL THEN
            UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id;
            RETURN v_account_id;
        END IF;
    END IF;

    -- 4) Main Treasury currency-based GL accounts (11101..11104)
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
        RETURN v_account_id;
    END IF;

    -- 5) Fallback to any 111% or 11% or asset account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '111%' AND is_active = true
    ORDER BY (company_id = v_real_company_id) DESC, account_code LIMIT 1;

    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_type = 'asset' AND is_leaf = true AND is_active = true
    ORDER BY (company_id = v_real_company_id) DESC, account_code LIMIT 1;

    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    RAISE EXCEPTION 'Could not resolve any treasury GL account for treasury % currency %', p_treasury_id, p_currency;
END;
$$;


-- 3. Backfill/Update existing employee custody accounts in the chart of accounts
UPDATE accounts a
SET 
  account_name = CASE 
    WHEN u.full_name ILIKE 'عهدة%' OR u.full_name ILIKE 'عهده%' THEN TRIM(u.full_name)
    ELSE 'عهدة ' || TRIM(u.full_name)
  END,
  name = 'Custody - ' || TRIM(u.full_name)
FROM treasuries t
JOIN users u ON t.user_id = u.id
WHERE t.account_id = a.id
  AND t.type = 'employee'
  AND u.full_name IS NOT NULL
  AND TRIM(u.full_name) != '';

-- Also clean up any orphan 1115 accounts
UPDATE accounts
SET account_name = 'عهدة حسين', name = 'Custody - حسين'
WHERE account_code = '111503' AND account_name = 'عهدة - خزينة حسين';

UPDATE accounts
SET account_name = 'عهدة مندوب 1 (أحمد)', name = 'Custody - أحمد'
WHERE account_code = '111506' AND account_name = 'عهدة - عهدة مندوب 1 (أحمد)';

UPDATE accounts
SET account_name = 'عهدة مندوب 2 (محمود)', name = 'Custody - محمود'
WHERE account_code = '111507' AND account_name = 'عهدة - عهدة مندوب 2 (محمود)';

COMMIT;
