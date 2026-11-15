-- ============================================================================
-- Migration: 20261104000002_quick_custody_expense_accounts.sql
-- Description:
--   1. Seed and ensure dedicated Level-5 quick expense accounts for employee custodies:
--      - 31123: مصروفات انتقالات (Staff Transportation Expense)
--      - 31124: وجبات (Staff Meals Expense)
--      - 31125: عمالة (Temporary Labor Expense)
--   2. Bind them under parent 3112 (Other Employee Expenses Control / مصروفات عاملين اخري).
--   3. Ensure they are active, postable leaves (is_leaf = true, allow_posting = true).
-- ============================================================================

DO $$
DECLARE
    v_company_id UUID;
    v_parent_id BIGINT;
BEGIN
    -- 1. Resolve Company ID
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1' LIMIT 1;
    END IF;

    -- 2. Ensure parent control account 3112 exists
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '3112' LIMIT 1;
    IF v_parent_id IS NULL THEN
        -- Check parent 311
        DECLARE
            v_root_311 BIGINT;
        BEGIN
            SELECT id INTO v_root_311 FROM public.accounts WHERE account_code = '311' LIMIT 1;
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, normal_balance,
                is_active, is_leaf, allow_posting, sort_order, parent_id, company_id, level
            ) VALUES (
                '3112', 'Other Employee Expenses Control', 'مصروفات عاملين اخري', 'expense', 'Debit',
                true, false, false, 3112, v_root_311, v_company_id::text, 4
            ) RETURNING id INTO v_parent_id;
        END;
    END IF;

    -- 3. Upsert 31123 - مصروفات انتقالات
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, normal_balance,
        is_active, is_leaf, allow_posting, sort_order, parent_id, company_id, level
    ) VALUES (
        '31123', 'Staff Transportation Expense', 'مصروفات انتقالات', 'expense', 'Debit',
        true, true, true, 31123, v_parent_id, v_company_id::text, 5
    )
    ON CONFLICT (account_code) DO UPDATE
    SET account_name = 'مصروفات انتقالات',
        name = 'Staff Transportation Expense',
        account_type = 'expense',
        normal_balance = 'Debit',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(v_parent_id, public.accounts.parent_id),
        level = 5;

    -- 4. Upsert 31124 - وجبات
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, normal_balance,
        is_active, is_leaf, allow_posting, sort_order, parent_id, company_id, level
    ) VALUES (
        '31124', 'Staff Meals Expense', 'وجبات', 'expense', 'Debit',
        true, true, true, 31124, v_parent_id, v_company_id::text, 5
    )
    ON CONFLICT (account_code) DO UPDATE
    SET account_name = 'وجبات',
        name = 'Staff Meals Expense',
        account_type = 'expense',
        normal_balance = 'Debit',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(v_parent_id, public.accounts.parent_id),
        level = 5;

    -- 5. Upsert 31125 - عمالة
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, normal_balance,
        is_active, is_leaf, allow_posting, sort_order, parent_id, company_id, level
    ) VALUES (
        '31125', 'Temporary Labor Expense', 'عمالة', 'expense', 'Debit',
        true, true, true, 31125, v_parent_id, v_company_id::text, 5
    )
    ON CONFLICT (account_code) DO UPDATE
    SET account_name = 'عمالة',
        name = 'Temporary Labor Expense',
        account_type = 'expense',
        normal_balance = 'Debit',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(v_parent_id, public.accounts.parent_id),
        level = 5;

    -- Confirm parent linking
    UPDATE public.accounts a
    SET parent_id = v_parent_id,
        level = 5,
        is_leaf = true,
        allow_posting = true
    WHERE a.account_code IN ('31123', '31124', '31125')
      AND v_parent_id IS NOT NULL;

END $$;

