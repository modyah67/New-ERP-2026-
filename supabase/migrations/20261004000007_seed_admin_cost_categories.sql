-- ============================================================================
-- Migration: Seed and Support Administrative Expenses Cost Categories
-- Ensures that administrative cost categories (supplier_type = 'admin')
-- are created with linked accounts under control account 3133.
-- ============================================================================

DO $$
DECLARE
    v_company_id UUID;
    v_parent_313_id BIGINT;
    v_parent_3133_id BIGINT;
    v_cost_center_code TEXT := 'CC-ADMIN-EXPENSES';
    v_acc_id BIGINT;
    v_admin_cats TEXT[][] := ARRAY[
        ['31331', 'مصاريف إدارية وعمومية'],
        ['31332', 'أتعاب واستشارات إدارية'],
        ['31333', 'رسوم واشتراكات وتراخيص'],
        ['31334', 'انتقالات وضيافة إدارية'],
        ['31335', 'مصاريف بنكية وإدارية'],
        ['31336', 'مصاريف تشغيل إدارية']
    ];
    i INT;
    v_code TEXT;
    v_name TEXT;
BEGIN
    -- 1. Safely resolve company_id
    SELECT company_id INTO v_company_id FROM public.accounts WHERE company_id IS NOT NULL LIMIT 1;
    IF v_company_id IS NULL THEN
        BEGIN
            SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_company_id := NULL;
        END;
    END IF;

    -- 2. Locate Parent Branch 313 (مصروفات إدارية)
    SELECT id INTO v_parent_313_id 
    FROM public.accounts 
    WHERE account_code = '313' 
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_313_id IS NULL THEN
        SELECT id INTO v_parent_313_id 
        FROM public.accounts 
        WHERE account_code = '313'
        LIMIT 1;
    END IF;

    IF v_parent_313_id IS NULL THEN
        SELECT id INTO v_parent_313_id FROM public.accounts WHERE account_code = '3' LIMIT 1;
    END IF;

    -- 3. Verify or create Level 4 Control Account: 3133 (مصاريف إدارية)
    SELECT id INTO v_parent_3133_id 
    FROM public.accounts 
    WHERE account_code = '3133'
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_3133_id IS NULL THEN
        SELECT id INTO v_parent_3133_id FROM public.accounts WHERE account_code = '3133' LIMIT 1;
    END IF;

    IF v_parent_3133_id IS NULL THEN
        INSERT INTO public.accounts (
            account_code, name, account_name, account_type,
            normal_balance, is_leaf, allow_posting, is_active, level,
            parent_id, company_id
        ) VALUES (
            '3133', 'مصاريف إدارية', 'مصاريف إدارية', 'expense',
            'Debit', FALSE, FALSE, TRUE, 4,
            v_parent_313_id, v_company_id
        )
        RETURNING id INTO v_parent_3133_id;
    END IF;

    -- 4. Ensure Cost Center for Administrative Expenses
    INSERT INTO public.cost_centers (
        code, name, name_ar, name_en, cost_center_type, is_active, color, icon, description
    ) VALUES (
        v_cost_center_code,
        'مصاريف إدارية',
        'مصاريف إدارية',
        'Administrative Expenses',
        'operational',
        TRUE,
        '#0284C7',
        'business_center_rounded',
        'مركز تكلفة مخصص للمصاريف الإدارية والعمومية'
    )
    ON CONFLICT (code) DO UPDATE
    SET is_active = TRUE,
        name_ar = 'مصاريف إدارية';

    -- 5. Seed categories and leaf accounts
    FOR i IN 1 .. array_length(v_admin_cats, 1) LOOP
        v_code := v_admin_cats[i][1];
        v_name := v_admin_cats[i][2];

        -- Ensure leaf account
        SELECT id INTO v_acc_id 
        FROM public.accounts 
        WHERE account_code = v_code 
          AND (company_id = v_company_id OR company_id IS NULL)
          AND deleted_at IS NULL
        LIMIT 1;

        IF v_acc_id IS NULL THEN
            SELECT id INTO v_acc_id FROM public.accounts WHERE account_code = v_code LIMIT 1;
        END IF;

        IF v_acc_id IS NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type,
                normal_balance, is_leaf, allow_posting, is_active, level,
                parent_id, company_id, cost_center_id
            ) VALUES (
                v_code, v_name, v_name, 'expense',
                'Debit', TRUE, TRUE, TRUE, 5,
                v_parent_3133_id, v_company_id, v_cost_center_code
            )
            RETURNING id INTO v_acc_id;
        ELSE
            UPDATE public.accounts
            SET is_active = TRUE,
                allow_posting = TRUE,
                account_name = v_name,
                cost_center_id = v_cost_center_code
            WHERE id = v_acc_id;
        END IF;

        -- Insert or update category
        INSERT INTO public.cost_report_categories (
            name, scope, is_system, type, account_id, supplier_type, cost_center_id
        ) VALUES (
            v_name, 'all', FALSE, 'indirect', v_acc_id, 'admin', v_cost_center_code
        )
        ON CONFLICT (name) DO UPDATE
        SET scope = 'all',
            account_id = v_acc_id,
            supplier_type = 'admin',
            cost_center_id = v_cost_center_code;
    END LOOP;

    -- Also ensure default 'مصاريف إدارية' category is linked
    SELECT id INTO v_acc_id FROM public.accounts WHERE account_code = '31331' LIMIT 1;
    INSERT INTO public.cost_report_categories (
        name, scope, is_system, type, account_id, supplier_type, cost_center_id
    ) VALUES (
        'مصاريف إدارية', 'all', FALSE, 'indirect', v_acc_id, 'admin', v_cost_center_code
    )
    ON CONFLICT (name) DO UPDATE
    SET scope = 'all',
        account_id = COALESCE(cost_report_categories.account_id, v_acc_id),
        supplier_type = 'admin',
        cost_center_id = v_cost_center_code;

    RAISE NOTICE 'Administrative expense categories seeded successfully.';
END;
$$;
