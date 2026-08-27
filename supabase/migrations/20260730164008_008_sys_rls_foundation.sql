-- Migration 008: Phase 0 - Foundation RLS (Row Level Security)
-- Purpose: Enforce Multi-Company isolation across all foundational tables.

BEGIN;

DO $$
BEGIN

    -- 1. Helper Function to Get Current User's Company ID from JWT
    -- This assumes Supabase auth where the company_id is injected into app_metadata.
    CREATE OR REPLACE FUNCTION public.get_current_company_id()
    RETURNS UUID AS
    $func$
    BEGIN
        -- Default to the first company for testing/development if JWT is missing
        -- In production, this should STRICTLY read from auth.jwt() -> 'app_metadata' ->> 'company_id'
        RETURN COALESCE(
            NULLIF(current_setting('request.jwt.claim.app_metadata.company_id', true), ''),
            (SELECT id FROM public.sys_companies WHERE name = 'Main Company' LIMIT 1)
        )::UUID;
    END;
    $func$ LANGUAGE plpgsql SECURITY DEFINER;

    -- 2. Enable RLS on Tables
    ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.treasuries ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'journal_entries') THEN
        ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'account_ledger_entries') THEN
        ALTER TABLE public.account_ledger_entries ENABLE ROW LEVEL SECURITY;
    END IF;

    -- 3. Create RLS Policies
    
    -- Accounts
    DROP POLICY IF EXISTS isolate_accounts_by_company ON public.accounts;
    CREATE POLICY isolate_accounts_by_company ON public.accounts
        FOR ALL USING (company_id = public.get_current_company_id());

    -- Customers
    DROP POLICY IF EXISTS isolate_customers_by_company ON public.customers;
    CREATE POLICY isolate_customers_by_company ON public.customers
        FOR ALL USING (company_id = public.get_current_company_id());

    -- Suppliers
    DROP POLICY IF EXISTS isolate_suppliers_by_company ON public.suppliers;
    CREATE POLICY isolate_suppliers_by_company ON public.suppliers
        FOR ALL USING (company_id = public.get_current_company_id());

    -- Treasuries
    DROP POLICY IF EXISTS isolate_treasuries_by_company ON public.treasuries;
    CREATE POLICY isolate_treasuries_by_company ON public.treasuries
        FOR ALL USING (company_id = public.get_current_company_id());

    -- Bank Accounts
    DROP POLICY IF EXISTS isolate_bank_accounts_by_company ON public.bank_accounts;
    CREATE POLICY isolate_bank_accounts_by_company ON public.bank_accounts
        FOR ALL USING (company_id = public.get_current_company_id());

    -- Journals
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'journal_entries') THEN
        DROP POLICY IF EXISTS isolate_journal_entries_by_company ON public.journal_entries;
        CREATE POLICY isolate_journal_entries_by_company ON public.journal_entries
            FOR ALL USING (company_id = public.get_current_company_id());
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'account_ledger_entries') THEN
        DROP POLICY IF EXISTS isolate_account_ledger_entries_by_company ON public.account_ledger_entries;
        CREATE POLICY isolate_account_ledger_entries_by_company ON public.account_ledger_entries
            FOR ALL USING (company_id = public.get_current_company_id());
    END IF;

END $$;

COMMIT;
