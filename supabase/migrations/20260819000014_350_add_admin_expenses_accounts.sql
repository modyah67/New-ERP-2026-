-- ============================================================================
-- Migration 350: Add Admin Expenses and Provision Accounts to Chart of Accounts
-- 5210: Allocated Admin Expenses (مصروفات إدارية محملة) - expense
-- 5220: Actual Admin Expenses (مصروفات إدارية فعلية) - expense
-- 2105: Admin Expenses Provision / Clearing (مخصص / وسيط مصروفات إدارية) - liability
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_company_id UUID;
    v_parent_exp BIGINT;
    v_parent_liab BIGINT;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- Parent expense 6000 (Expenses / المصروفات) or fallback
    SELECT id INTO v_parent_exp FROM public.accounts WHERE account_code = '6000' LIMIT 1;
    IF v_parent_exp IS NULL THEN
        SELECT id INTO v_parent_exp FROM public.accounts WHERE account_code = '5000' LIMIT 1;
    END IF;

    -- Parent liability 2100 (Other Current Liabilities / الخصوم المتداولة الأخرى) or 20
    SELECT id INTO v_parent_liab FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    IF v_parent_liab IS NULL THEN
        SELECT id INTO v_parent_liab FROM public.accounts WHERE account_code = '20' LIMIT 1;
    END IF;

    -- 5210: Allocated Admin Expenses (مصروفات إدارية محملة)
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id
    ) VALUES (
        '5210', 'Allocated Admin Expenses', 'مصروفات إدارية محملة', 'expense', true, true, true, 5210, v_company_id, v_parent_exp
    )
    ON CONFLICT (account_code) DO UPDATE 
    SET name = 'Allocated Admin Expenses',
        account_name = 'مصروفات إدارية محملة',
        account_type = 'expense',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(accounts.parent_id, v_parent_exp);

    -- 5220: Actual Admin Expenses (مصروفات إدارية فعلية)
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id
    ) VALUES (
        '5220', 'Actual Admin Expenses', 'مصروفات إدارية فعلية', 'expense', true, true, true, 5220, v_company_id, v_parent_exp
    )
    ON CONFLICT (account_code) DO UPDATE 
    SET name = 'Actual Admin Expenses',
        account_name = 'مصروفات إدارية فعلية',
        account_type = 'expense',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(accounts.parent_id, v_parent_exp);

    -- 2105: Admin Expenses Provision / Clearing (مخصص / وسيط مصروفات إدارية)
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id
    ) VALUES (
        '2105', 'Admin Expenses Provision', 'مخصص / وسيط مصروفات إدارية', 'liability', true, true, true, 2105, v_company_id, v_parent_liab
    )
    ON CONFLICT (account_code) DO UPDATE 
    SET name = 'Admin Expenses Provision',
        account_name = 'مخصص / وسيط مصروفات إدارية',
        account_type = 'liability',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(accounts.parent_id, v_parent_liab);

END $$;

COMMIT;
