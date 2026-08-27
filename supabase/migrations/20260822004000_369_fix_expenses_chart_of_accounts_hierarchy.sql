-- ============================================================================
-- Migration 369: Fix Expenses Chart of Accounts Hierarchy (Root 6, 5000, 5110, 6000, 6150)
-- ============================================================================
-- Purpose:
-- 1. Ensure Root Account '6' ('المصروفات' / 'Expenses') exists as level 1 Header.
-- 2. Link '5000' (تكلفة البضاعة المباعة), '5110' (تكاليف تشغيل محملة),
--    and '6000' (المصروفات) under parent '6'.
-- 3. Link '51101', '51102', '51104' under parent '5110'.
-- 4. Ensure '6150' (فروق العملة / Currency Differences) is a Header under '6000'.
-- 5. Link '6151' & '6152' under parent '6150'.
-- 6. Link '6001', '6002', '6130', '6150' under parent '6000'.
-- 7. Keep '5210' and '2105' under '2100' (Other Current Liabilities).
-- ============================================================================

DO $$
DECLARE
    v_parent_6_id    BIGINT;
    v_parent_5110_id BIGINT;
    v_parent_6000_id BIGINT;
    v_parent_6150_id BIGINT;
    v_parent_2100_id BIGINT;
    v_company_id     TEXT;
    v_col_type       TEXT;
BEGIN
    -- Detect company_id column type
    SELECT data_type INTO v_col_type
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id';

    -- Get first company id if available
    BEGIN
        SELECT id::text INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_company_id := NULL;
    END;

    -- ── 1. Ensure Root Account '6' exists ──
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '6') THEN
        IF v_col_type = 'uuid' AND v_company_id IS NOT NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, level
            ) VALUES (
                '6', 'Expenses', 'المصروفات', 'expense', true, false, false, 6, v_company_id::uuid, 1
            );
        ELSIF v_company_id IS NOT NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, level
            ) VALUES (
                '6', 'Expenses', 'المصروفات', 'expense', true, false, false, 6, v_company_id, 1
            );
        ELSE
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, level
            ) VALUES (
                '6', 'Expenses', 'المصروفات', 'expense', true, false, false, 6, 1
            );
        END IF;
    END IF;

    UPDATE public.accounts
    SET name = 'Expenses',
        account_name = 'المصروفات',
        account_type = 'expense',
        is_active = true,
        is_leaf = false,
        allow_posting = false,
        parent_id = NULL,
        level = 1,
        deleted_at = NULL
    WHERE account_code = '6';

    SELECT id INTO v_parent_6_id FROM public.accounts WHERE account_code = '6' LIMIT 1;

    -- ── 2. Link Sub-branches directly under '6' (5000, 5110, 6000) ──
    UPDATE public.accounts
    SET parent_id = v_parent_6_id,
        level = 2,
        account_type = 'expense',
        is_active = true,
        deleted_at = NULL
    WHERE account_code IN ('5000', '5110', '6000');

    -- Adjust Header vs Leaf flags
    UPDATE public.accounts SET is_leaf = true, allow_posting = true WHERE account_code IN ('5000');
    UPDATE public.accounts SET is_leaf = false, allow_posting = false WHERE account_code IN ('5110', '6000');

    -- ── 3. Link Sub-accounts under '5110' (51101, 51102, 51104) ──
    SELECT id INTO v_parent_5110_id FROM public.accounts WHERE account_code = '5110' LIMIT 1;
    IF v_parent_5110_id IS NOT NULL THEN
        UPDATE public.accounts
        SET parent_id = v_parent_5110_id,
            level = 3,
            is_leaf = true,
            allow_posting = true,
            account_type = 'expense',
            is_active = true,
            deleted_at = NULL
        WHERE account_code IN ('51101', '51102', '51104');
    END IF;

    -- ── 4. Ensure Account '6150' exists as Header under '6000' ──
    SELECT id INTO v_parent_6000_id FROM public.accounts WHERE account_code = '6000' LIMIT 1;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '6150') THEN
        IF v_col_type = 'uuid' AND v_company_id IS NOT NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level
            ) VALUES (
                '6150', 'Currency Differences', 'فروق أسعار العملة', 'expense', true, false, false, 6150, v_company_id::uuid, v_parent_6000_id, 3
            );
        ELSIF v_company_id IS NOT NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level
            ) VALUES (
                '6150', 'Currency Differences', 'فروق أسعار العملة', 'expense', true, false, false, 6150, v_company_id, v_parent_6000_id, 3
            );
        ELSE
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, parent_id, level
            ) VALUES (
                '6150', 'Currency Differences', 'فروق أسعار العملة', 'expense', true, false, false, 6150, v_parent_6000_id, 3
            );
        END IF;
    ELSE
        UPDATE public.accounts
        SET parent_id = v_parent_6000_id,
            is_leaf = false,
            allow_posting = false,
            level = 3,
            account_type = 'expense',
            is_active = true,
            deleted_at = NULL
        WHERE account_code = '6150';
    END IF;

    SELECT id INTO v_parent_6150_id FROM public.accounts WHERE account_code = '6150' LIMIT 1;

    -- ── 5. Link Sub-accounts under '6000' (6001, 6002, 6130) ──
    IF v_parent_6000_id IS NOT NULL THEN
        UPDATE public.accounts
        SET parent_id = v_parent_6000_id,
            level = 3,
            is_leaf = true,
            allow_posting = true,
            account_type = 'expense',
            is_active = true,
            deleted_at = NULL
        WHERE account_code IN ('6001', '6002', '6130');
    END IF;

    -- ── 6. Link 6151 & 6152 under '6150' ──
    IF v_parent_6150_id IS NOT NULL THEN
        UPDATE public.accounts
        SET parent_id = v_parent_6150_id,
            level = 4,
            is_leaf = true,
            allow_posting = true,
            account_type = 'expense',
            is_active = true,
            deleted_at = NULL
        WHERE account_code IN ('6151', '6152');
    END IF;

    -- ── 7. Link 5210 and 2105 under 2100 (Other Current Liabilities) ──
    SELECT id INTO v_parent_2100_id FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    IF v_parent_2100_id IS NOT NULL THEN
        UPDATE public.accounts
        SET parent_id = v_parent_2100_id,
            level = 3,
            is_leaf = true,
            allow_posting = true,
            is_active = true,
            deleted_at = NULL
        WHERE account_code IN ('2105', '5210');
    END IF;

    RAISE NOTICE 'Migration 369: Expenses Chart of Accounts Hierarchy (including 6150 -> 6151, 6152) restored successfully.';
END $$;
