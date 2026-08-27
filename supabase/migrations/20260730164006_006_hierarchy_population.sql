-- Migration 006: Hierarchy Population
-- Purpose: Resolve parent-child relationships and execute the hierarchy rebuild function.
-- Standards: Separated responsibilities, Safe existence checks, Validates paths.

BEGIN;

-- 1. Static Parent Mapping
-- Dynamically resolves UUIDs by querying account_code. Only updates if mapping is missing or incorrect.
WITH static_mappings(child_code, parent_code) AS (
    VALUES 
    ('10', '1'),
    ('11', '10'),
    ('1000', '11'),
    ('1010', '11'),
    ('1020', '10'),
    ('1030', '10'),
    ('1040', '10'),
    ('20', '2'),
    ('21', '20'),
    ('2000', '21'),
    ('2900', '20'),
    ('3000', '3'),
    ('3100', '3'),
    ('3200', '3'),
    ('4000', '4'),
    ('5000', '6'),
    ('6000', '6'),
    ('7000', '6000'),
    ('1050', '6000')
)
UPDATE public.accounts a
SET parent_id = p.id
FROM static_mappings m
JOIN public.accounts p ON p.account_code = m.parent_code
WHERE a.account_code = m.child_code
  AND (a.parent_id IS NULL OR a.parent_id != p.id);

-- 2. Dynamic Accounts Parent Mapping with Column Existence Checks (Portability)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = 'account_id') THEN
        EXECUTE 'UPDATE public.accounts a
        SET parent_id = p.id
        FROM public.accounts p
        WHERE p.account_code = ''1020''
          AND a.id IN (SELECT account_id FROM public.customers WHERE account_id IS NOT NULL)
          AND (a.parent_id IS NULL OR a.parent_id != p.id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'account_id') THEN
        EXECUTE 'UPDATE public.accounts a
        SET parent_id = p.id
        FROM public.accounts p
        WHERE p.account_code = ''2000''
          AND a.id IN (SELECT account_id FROM public.suppliers WHERE account_id IS NOT NULL)
          AND (a.parent_id IS NULL OR a.parent_id != p.id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'bank_accounts' AND column_name = 'account_id') THEN
        EXECUTE 'UPDATE public.accounts a
        SET parent_id = p.id
        FROM public.accounts p
        WHERE p.account_code = ''1010''
          AND a.id IN (SELECT account_id FROM public.bank_accounts WHERE account_id IS NOT NULL)
          AND (a.parent_id IS NULL OR a.parent_id != p.id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'treasuries' AND column_name = 'account_id') THEN
        EXECUTE 'UPDATE public.accounts a
        SET parent_id = p.id
        FROM public.accounts p
        WHERE p.account_code = ''1000''
          AND a.id IN (SELECT account_id FROM public.treasuries WHERE account_id IS NOT NULL)
          AND (a.parent_id IS NULL OR a.parent_id != p.id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'treasury_balances' AND column_name = 'account_id') THEN
        EXECUTE 'UPDATE public.accounts a
        SET parent_id = p.id
        FROM public.accounts p
        WHERE p.account_code = ''1000''
          AND a.id IN (SELECT account_id FROM public.treasury_balances WHERE account_id IS NOT NULL)
          AND (a.parent_id IS NULL OR a.parent_id != p.id)';
    END IF;
END $$;

-- 3. Execute the hierarchy build
SELECT public.rebuild_chart_of_accounts_hierarchy();

-- 4. Safety Gate: Verify paths calculate properly instead of relying on default levels
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.accounts WHERE path_ids IS NULL OR path_codes IS NULL) THEN
        RAISE EXCEPTION 'Hierarchy calculation failed: One or more accounts have NULL path_ids or path_codes.';
    END IF;
END $$;

COMMIT;
