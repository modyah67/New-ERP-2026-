-- Migration 002: Constraints for Enterprise Chart of Accounts
-- Purpose: Safely enforces data integrity and relationship constraints.
-- Standards: Idempotent, Transactional, No schema adds, No data updates.

BEGIN;

-- 1. Enforce parent_id Foreign Key (Prevent orphaned branches)
DO $$ 
DECLARE
    fk_name TEXT;
BEGIN
    SELECT con.conname INTO fk_name
    FROM pg_constraint con
    JOIN pg_attribute a ON a.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'public.accounts'::regclass 
      AND con.contype = 'f' 
      AND a.attname = 'parent_id';

    IF fk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS ' || fk_name;
    END IF;
END $$;

ALTER TABLE public.accounts 
ADD CONSTRAINT fk_accounts_parent_id 
FOREIGN KEY (parent_id) REFERENCES public.accounts(id) 
ON DELETE RESTRICT ON UPDATE CASCADE;

-- 2. Update account_type Check Constraint (Core Accounting Types Only)
DO $$ 
DECLARE
    chk_name TEXT;
BEGIN
    SELECT conname INTO chk_name
    FROM pg_constraint
    WHERE conrelid = 'public.accounts'::regclass AND contype = 'c' 
      AND pg_get_constraintdef(oid) ILIKE '%account_type%';
      
    IF chk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS ' || chk_name;
    END IF;
END $$;

ALTER TABLE public.accounts 
ADD CONSTRAINT chk_accounts_type 
CHECK (account_type IN ('Asset', 'Liability', 'Equity', 'Revenue', 'Expense', 'asset', 'liability', 'equity', 'revenue', 'expense'));

-- 3. Enforce account_category Check Constraint (Business Purpose Taxonomy)
ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS chk_accounts_category;

ALTER TABLE public.accounts 
ADD CONSTRAINT chk_accounts_category 
CHECK (account_category IN (
    'CASH', 'BANK', 'CUSTOMER', 'SUPPLIER', 'INVENTORY', 
    'PACKING', 'SUSPENSE', 'SALES', 'PURCHASE', 'EXPENSE', 
    'EQUITY', 'OTHER'
));

COMMIT;
