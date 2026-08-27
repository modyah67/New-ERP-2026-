-- Migration 007: Phase 0 - Core Foundation (Multi-Company & Soft Deletes)
-- Purpose: Injects mandatory enterprise foundation columns before creating the Unified Posting Engine.

BEGIN;

DO $$
DECLARE
    v_default_company_id UUID;
BEGIN
    -- ==========================================================
    -- 1. Create sys_companies
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.sys_companies (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        tax_number TEXT,
        commercial_register TEXT,
        base_currency TEXT DEFAULT 'EGP',
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ
    );

    -- Ensure a default company exists to satisfy NOT NULL constraints for existing data
    IF NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE name = 'Main Company') THEN
        INSERT INTO public.sys_companies (name) VALUES ('Main Company') RETURNING id INTO v_default_company_id;
    ELSE
        SELECT id INTO v_default_company_id FROM public.sys_companies WHERE name = 'Main Company' LIMIT 1;
    END IF;

    -- ==========================================================
    -- 2. Inject Foundation Columns into Financial Tables
    -- ==========================================================

    -- Table: accounts
    ALTER TABLE IF EXISTS public.accounts 
        ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
        
    UPDATE public.accounts SET company_id = v_default_company_id WHERE company_id IS NULL;
    ALTER TABLE IF EXISTS public.accounts ALTER COLUMN company_id SET NOT NULL;

    -- Table: customers
    ALTER TABLE IF EXISTS public.customers 
        ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

    UPDATE public.customers SET company_id = v_default_company_id WHERE company_id IS NULL;
    ALTER TABLE IF EXISTS public.customers ALTER COLUMN company_id SET NOT NULL;

    -- Table: suppliers
    ALTER TABLE IF EXISTS public.suppliers 
        ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

    UPDATE public.suppliers SET company_id = v_default_company_id WHERE company_id IS NULL;
    ALTER TABLE IF EXISTS public.suppliers ALTER COLUMN company_id SET NOT NULL;

    -- Table: treasuries
    ALTER TABLE IF EXISTS public.treasuries 
        ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

    UPDATE public.treasuries SET company_id = v_default_company_id WHERE company_id IS NULL;
    ALTER TABLE IF EXISTS public.treasuries ALTER COLUMN company_id SET NOT NULL;

    -- Table: bank_accounts
    ALTER TABLE IF EXISTS public.bank_accounts 
        ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

    UPDATE public.bank_accounts SET company_id = v_default_company_id WHERE company_id IS NULL;
    ALTER TABLE IF EXISTS public.bank_accounts ALTER COLUMN company_id SET NOT NULL;

    -- ==========================================================
    -- 3. Inject Foundation Columns into Ledger Tables (if they exist)
    -- ==========================================================

    -- Table: journal_entries
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'journal_entries') THEN
        ALTER TABLE public.journal_entries 
            ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
            ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
            
        UPDATE public.journal_entries SET company_id = v_default_company_id WHERE company_id IS NULL;
        ALTER TABLE public.journal_entries ALTER COLUMN company_id SET NOT NULL;
    END IF;

    -- Table: account_ledger_entries
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'account_ledger_entries') THEN
        ALTER TABLE public.account_ledger_entries 
            ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
            ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
            
        UPDATE public.account_ledger_entries SET company_id = v_default_company_id WHERE company_id IS NULL;
        ALTER TABLE public.account_ledger_entries ALTER COLUMN company_id SET NOT NULL;
    END IF;

    -- ==========================================================
    -- 4. Create Indexes for Company ID
    -- ==========================================================
    CREATE INDEX IF NOT EXISTS idx_accounts_company_id ON public.accounts(company_id);
    CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
    CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
    CREATE INDEX IF NOT EXISTS idx_treasuries_company_id ON public.treasuries(company_id);
    CREATE INDEX IF NOT EXISTS idx_bank_accounts_company_id ON public.bank_accounts(company_id);
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'journal_entries') THEN
        CREATE INDEX IF NOT EXISTS idx_journal_entries_company_id ON public.journal_entries(company_id);
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'account_ledger_entries') THEN
        CREATE INDEX IF NOT EXISTS idx_account_ledger_entries_company_id ON public.account_ledger_entries(company_id);
    END IF;

END $$;

COMMIT;
