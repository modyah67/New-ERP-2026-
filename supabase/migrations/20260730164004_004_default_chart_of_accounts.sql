-- Migration 004: Seed Enterprise Chart of Accounts
-- Purpose: Safely insert missing default system grouping accounts only.
-- Standards: Idempotent, Transactional, Safe (ON CONFLICT DO NOTHING), Preserves backward compatibility.

BEGIN;

DO $$
DECLARE
    v_company_id TEXT;
    v_table_exists BOOLEAN;
    v_column_exists BOOLEAN;
BEGIN
    -- Check if sys_companies table exists safely
    SELECT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = 'sys_companies'
    ) INTO v_table_exists;

    IF v_table_exists THEN
        EXECUTE 'SELECT id::TEXT FROM public.sys_companies ORDER BY created_at ASC LIMIT 1' INTO v_company_id;
    END IF;

    -- Check if accounts.company_id column exists (using pg_attribute to avoid information_schema caching bugs)
    SELECT EXISTS (
        SELECT 1 FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relname = 'accounts'
          AND a.attname = 'company_id'
          AND NOT a.attisdropped
    ) INTO v_column_exists;

    IF v_column_exists THEN
        IF v_company_id IS NULL THEN
            RAISE EXCEPTION 'accounts table requires company_id, but no company found in sys_companies.';
        END IF;

        -- Use dynamic SQL to include company_id (safe for both UUID and INT via TEXT literal cast)
        EXECUTE format($sql$
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type, account_category,
                is_system, allow_posting, display_order, is_active, is_locked, normal_balance,
                company_id
            ) VALUES
            ('1',    'Assets',                   'الأصول',                    'asset',     'OTHER',    TRUE, FALSE, 10,  TRUE, TRUE, 'Debit',  %1$L),
            ('10',   'Current Assets',           'الأصول المتداولة',          'asset',     'OTHER',    TRUE, FALSE, 20,  TRUE, TRUE, 'Debit',  %1$L),
            ('11',   'Cash & Cash Equivalents',  'النقدية وما في حكمها',      'asset',     'CASH',     TRUE, FALSE, 25,  TRUE, TRUE, 'Debit',  %1$L),
            ('2',    'Liabilities',              'الخصوم',                    'liability', 'OTHER',    TRUE, FALSE, 100, TRUE, TRUE, 'Credit', %1$L),
            ('20',   'Current Liabilities',      'الخصوم المتداولة',          'liability', 'OTHER',    TRUE, FALSE, 110, TRUE, TRUE, 'Credit', %1$L),
            ('21',   'Trade Payables',           'الذمم الدائنة التجارية',    'liability', 'SUPPLIER', TRUE, FALSE, 115, TRUE, TRUE, 'Credit', %1$L),
            ('2900', 'Suspense Accounts',        'الحسابات المعلقة',          'liability', 'SUSPENSE', TRUE, FALSE, 140, TRUE, TRUE, 'Credit', %1$L),
            ('3',    'Equity',                   'حقوق الملكية',             'equity',    'EQUITY',   TRUE, FALSE, 200, TRUE, TRUE, 'Credit', %1$L),
            ('4',    'Revenue',                  'الإيرادات',                'revenue',   'SALES',    TRUE, FALSE, 300, TRUE, TRUE, 'Credit', %1$L),
            ('6',    'Expenses',                 'المصروفات',                'expense',   'EXPENSE',  TRUE, FALSE, 500, TRUE, TRUE, 'Debit',  %1$L)
            ON CONFLICT (account_code) DO NOTHING
        $sql$, v_company_id);
    ELSE
        -- company_id column does not exist yet; insert without it
        INSERT INTO public.accounts (
            account_code, name, account_name, account_type, account_category,
            is_system, allow_posting, display_order, is_active, is_locked, normal_balance
        ) VALUES
        ('1',    'Assets',                   'الأصول',                    'asset',     'OTHER',    TRUE, FALSE, 10,  TRUE, TRUE, 'Debit'),
        ('10',   'Current Assets',           'الأصول المتداولة',          'asset',     'OTHER',    TRUE, FALSE, 20,  TRUE, TRUE, 'Debit'),
        ('11',   'Cash & Cash Equivalents',  'النقدية وما في حكمها',      'asset',     'CASH',     TRUE, FALSE, 25,  TRUE, TRUE, 'Debit'),
        ('2',    'Liabilities',              'الخصوم',                    'liability', 'OTHER',    TRUE, FALSE, 100, TRUE, TRUE, 'Credit'),
        ('20',   'Current Liabilities',      'الخصوم المتداولة',          'liability', 'OTHER',    TRUE, FALSE, 110, TRUE, TRUE, 'Credit'),
        ('21',   'Trade Payables',           'الذمم الدائنة التجارية',    'liability', 'SUPPLIER', TRUE, FALSE, 115, TRUE, TRUE, 'Credit'),
        ('2900', 'Suspense Accounts',        'الحسابات المعلقة',          'liability', 'SUSPENSE', TRUE, FALSE, 140, TRUE, TRUE, 'Credit'),
        ('3',    'Equity',                   'حقوق الملكية',             'equity',    'EQUITY',   TRUE, FALSE, 200, TRUE, TRUE, 'Credit'),
        ('4',    'Revenue',                  'الإيرادات',                'revenue',   'SALES',    TRUE, FALSE, 300, TRUE, TRUE, 'Credit'),
        ('6',    'Expenses',                 'المصروفات',                'expense',   'EXPENSE',  TRUE, FALSE, 500, TRUE, TRUE, 'Debit')
        ON CONFLICT (account_code) DO NOTHING;
    END IF;
END $$;

COMMIT;
