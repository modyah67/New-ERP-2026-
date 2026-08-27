-- Migration 157: Seed chart of accounts to fix PHASE0b_FAILED
-- Root cause: accounts table is missing supplier account (2000) for confirm_purchase RPC

DO $$
DECLARE
    v_company_id UUID;
    v_rec RECORD;
BEGIN
    -- Get company_id
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'No company found in sys_companies';
    END IF;

    -- Ensure company_id column exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = 'accounts' AND a.attname = 'company_id' AND NOT a.attisdropped
    ) THEN
        RAISE EXCEPTION 'company_id column does not exist on accounts table';
    END IF;

    FOR v_rec IN (
        SELECT * FROM (VALUES
            ('1000', 'Cash', 'الصندوق', 'asset', 1000),
            ('1010', 'Bank', 'البنك', 'asset', 1010),
            ('1020', 'Accounts Receivable', 'العملاء (مدينون)', 'asset', 1020),
            ('1030', 'Inventory', 'المخزون', 'asset', 1030),
            ('1040', 'Packing Materials Inventory', 'مخزون التعبئة', 'asset', 1040),
            ('1050', 'Export Expenses', 'مصروفات التصدير', 'expense', 1050),
            ('11101','Main Treasury - EGP', 'الخزينة الرئيسية - جنيه', 'asset', 11101),
            ('11102','Main Treasury - USD', 'الخزينة الرئيسية - دولار', 'asset', 11102),
            ('11103','Main Treasury - EUR', 'الخزينة الرئيسية - يورو', 'asset', 11103),
            ('11104','Main Treasury - GBP', 'الخزينة الرئيسية - جنيه إسترليني','asset', 11104),
            ('2000', 'Accounts Payable', 'الموردون (دائنون)', 'liability', 2000)
        ) AS t(account_code, name, account_name, account_type, sort_order)
    )
    LOOP
        -- Check if account exists
        IF EXISTS (SELECT 1 FROM public.accounts WHERE account_code = v_rec.account_code) THEN
            -- Update company_id just to be sure it's accessible to the current company
            EXECUTE format('UPDATE public.accounts SET company_id = %L WHERE account_code = %L', v_company_id, v_rec.account_code);
        ELSE
            -- Insert the missing account
            EXECUTE format(
                'INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, sort_order, company_id) ' ||
                'VALUES (%L, %L, %L, %L, true, %L, %L)',
                v_rec.account_code, v_rec.name, v_rec.account_name, v_rec.account_type, v_rec.sort_order, v_company_id
            );
        END IF;
    END LOOP;
END $$;
