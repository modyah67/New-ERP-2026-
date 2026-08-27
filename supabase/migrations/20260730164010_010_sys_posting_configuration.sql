-- Migration 010: Phase 2 - Posting Configuration Layer
-- Purpose: Defines the Enterprise Data-Driven Accounting Configuration Layer.

BEGIN;

DO $$
DECLARE
    v_default_company_id UUID;
BEGIN
    SELECT id INTO v_default_company_id FROM public.sys_companies WHERE name = 'Main Company' LIMIT 1;

    -- ==========================================================
    -- 1. posting_account_roles
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.posting_account_roles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        is_system BOOLEAN DEFAULT false,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (company_id, code)
    );
    COMMENT ON TABLE public.posting_account_roles IS 'Defines standard accounting roles (e.g., AR, AP, VAT).';

    -- ==========================================================
    -- 2. posting_profiles
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.posting_profiles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        is_default BOOLEAN DEFAULT false,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (company_id, code)
    );
    COMMENT ON TABLE public.posting_profiles IS 'Groupings (e.g., Local Customers) for mapping roles to GL accounts.';

    -- ==========================================================
    -- 3. posting_profile_rules
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.posting_profile_rules (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        posting_profile_id UUID NOT NULL REFERENCES public.posting_profiles(id) ON DELETE CASCADE,
        role_id UUID NOT NULL REFERENCES public.posting_account_roles(id) ON DELETE RESTRICT,
        account_id INTEGER NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
        priority INT DEFAULT 1,
        valid_from DATE DEFAULT CURRENT_DATE,
        valid_to DATE,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (posting_profile_id, role_id, valid_from),
        CONSTRAINT check_valid_dates CHECK (valid_to IS NULL OR valid_from <= valid_to)
    );
    COMMENT ON TABLE public.posting_profile_rules IS 'Maps a Profile and a Role to a specific GL Account, with effective dates.';

    -- ==========================================================
    -- 4. document_posting_templates
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.document_posting_templates (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        document_type_code TEXT NOT NULL REFERENCES public.sys_document_types(code) ON DELETE CASCADE,
        role_id UUID NOT NULL REFERENCES public.posting_account_roles(id) ON DELETE RESTRICT,
        is_required BOOLEAN DEFAULT true,
        sign_multiplier INT NOT NULL CHECK (sign_multiplier IN (1, -1)),
        display_order INT DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (company_id, document_type_code, role_id)
    );
    COMMENT ON TABLE public.document_posting_templates IS 'Defines required roles per document type and debit/credit natural sign.';

    -- ==========================================================
    -- 5. posting_validation_rules
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.posting_validation_rules (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        description TEXT,
        is_enabled BOOLEAN DEFAULT true,
        severity TEXT NOT NULL CHECK (severity IN ('ERROR', 'WARNING')),
        execution_order INT DEFAULT 10,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (company_id, code)
    );
    COMMENT ON TABLE public.posting_validation_rules IS 'Rules executed by the engine before committing a journal.';

    -- ==========================================================
    -- 6. tax_codes
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.tax_codes (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        tax_type TEXT NOT NULL CHECK (tax_type IN ('VAT', 'WITHHOLDING', 'SALES', 'EXEMPT')),
        rate NUMERIC(5,4) NOT NULL DEFAULT 0.0000 CHECK (rate >= 0),
        recoverable BOOLEAN DEFAULT true,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (company_id, code)
    );
    COMMENT ON TABLE public.tax_codes IS 'Defines the available tax codes.';

    -- ==========================================================
    -- 7. tax_rates
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.tax_rates (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id) ON DELETE CASCADE,
        tax_code_id UUID NOT NULL REFERENCES public.tax_codes(id) ON DELETE CASCADE,
        effective_from DATE NOT NULL,
        effective_to DATE,
        rate NUMERIC(5,4) NOT NULL CHECK (rate >= 0),
        created_at TIMESTAMPTZ DEFAULT now(),
        CONSTRAINT check_effective_dates CHECK (effective_to IS NULL OR effective_from <= effective_to)
    );
    COMMENT ON TABLE public.tax_rates IS 'Tracks historical tax rates for a given tax code.';

    -- ==========================================================
    -- INDEXES
    -- ==========================================================
    CREATE INDEX IF NOT EXISTS idx_posting_account_roles_company_id ON public.posting_account_roles(company_id);
    CREATE INDEX IF NOT EXISTS idx_posting_profiles_company_id ON public.posting_profiles(company_id);
    
    CREATE INDEX IF NOT EXISTS idx_posting_profile_rules_company_id ON public.posting_profile_rules(company_id);
    CREATE INDEX IF NOT EXISTS idx_posting_profile_rules_profile_id ON public.posting_profile_rules(posting_profile_id);
    CREATE INDEX IF NOT EXISTS idx_posting_profile_rules_role_id ON public.posting_profile_rules(role_id);
    CREATE INDEX IF NOT EXISTS idx_posting_profile_rules_account_id ON public.posting_profile_rules(account_id);
    
    CREATE INDEX IF NOT EXISTS idx_document_posting_templates_company_id ON public.document_posting_templates(company_id);
    CREATE INDEX IF NOT EXISTS idx_document_posting_templates_doc_type ON public.document_posting_templates(document_type_code);
    CREATE INDEX IF NOT EXISTS idx_document_posting_templates_role_id ON public.document_posting_templates(role_id);
    
    CREATE INDEX IF NOT EXISTS idx_posting_validation_rules_company_id ON public.posting_validation_rules(company_id);
    
    CREATE INDEX IF NOT EXISTS idx_tax_codes_company_id ON public.tax_codes(company_id);
    CREATE INDEX IF NOT EXISTS idx_tax_rates_company_id ON public.tax_rates(company_id);
    CREATE INDEX IF NOT EXISTS idx_tax_rates_tax_code_id ON public.tax_rates(tax_code_id);

    -- ==========================================================
    -- SEED DATA
    -- ==========================================================
    
    INSERT INTO public.posting_account_roles (company_id, code, name, is_system) VALUES
    (v_default_company_id, 'AR', 'Accounts Receivable', true),
    (v_default_company_id, 'AP', 'Accounts Payable', true),
    (v_default_company_id, 'REVENUE', 'Revenue', true),
    (v_default_company_id, 'COGS', 'Cost of Goods Sold', true),
    (v_default_company_id, 'VAT_OUTPUT', 'VAT Output (Collected)', true),
    (v_default_company_id, 'VAT_INPUT', 'VAT Input (Paid)', true),
    (v_default_company_id, 'CASH', 'Cash', true),
    (v_default_company_id, 'BANK', 'Bank', true),
    (v_default_company_id, 'INVENTORY', 'Inventory', true),
    (v_default_company_id, 'WIP', 'Work In Progress', true),
    (v_default_company_id, 'DISCOUNT', 'Discount Allowed/Received', true),
    (v_default_company_id, 'FX_GAIN', 'Exchange Gain', true),
    (v_default_company_id, 'FX_LOSS', 'Exchange Loss', true),
    (v_default_company_id, 'RETAINED_EARNINGS', 'Retained Earnings', true),
    (v_default_company_id, 'ROUNDING', 'Rounding Difference', true)
    ON CONFLICT (company_id, code) DO NOTHING;

    INSERT INTO public.posting_validation_rules (company_id, code, description, severity, execution_order) VALUES
    (v_default_company_id, 'CHECK_PERIOD_OPEN', 'Ensure the accounting period is open for the posting date.', 'ERROR', 10),
    (v_default_company_id, 'CHECK_BALANCED', 'Ensure total debits equal total credits.', 'ERROR', 20),
    (v_default_company_id, 'CHECK_PROFILE_EXISTS', 'Ensure the provided posting profile ID is active.', 'ERROR', 30),
    (v_default_company_id, 'CHECK_ACCOUNT_ACTIVE', 'Ensure all resolved GL accounts are active.', 'ERROR', 40),
    (v_default_company_id, 'CHECK_ACCOUNT_IS_LEAF', 'Ensure no postings are made to parent/header accounts.', 'ERROR', 50),
    (v_default_company_id, 'CHECK_CURRENCY', 'Ensure the currency and exchange rate match the snapshot.', 'ERROR', 60),
    (v_default_company_id, 'CHECK_DIMENSIONS', 'Ensure mandatory dimensions are provided.', 'ERROR', 70)
    ON CONFLICT (company_id, code) DO NOTHING;

    INSERT INTO public.tax_codes (company_id, code, name, tax_type, rate, recoverable) VALUES
    (v_default_company_id, 'VAT14', 'Standard VAT 14%', 'VAT', 0.1400, true),
    (v_default_company_id, 'VAT0', 'Zero Rated VAT 0%', 'VAT', 0.0000, true),
    (v_default_company_id, 'EXEMPT', 'Tax Exempt', 'EXEMPT', 0.0000, false)
    ON CONFLICT (company_id, code) DO NOTHING;

END $$;

-- ==========================================================
-- ROW LEVEL SECURITY
-- ==========================================================
DO $$
BEGIN
    ALTER TABLE public.posting_account_roles ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.posting_profiles ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.posting_profile_rules ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.document_posting_templates ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.posting_validation_rules ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.tax_codes ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.tax_rates ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS isolate_roles_by_company ON public.posting_account_roles;
    CREATE POLICY isolate_roles_by_company ON public.posting_account_roles FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_profiles_by_company ON public.posting_profiles;
    CREATE POLICY isolate_profiles_by_company ON public.posting_profiles FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_profile_rules_by_company ON public.posting_profile_rules;
    CREATE POLICY isolate_profile_rules_by_company ON public.posting_profile_rules FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_doc_templates_by_company ON public.document_posting_templates;
    CREATE POLICY isolate_doc_templates_by_company ON public.document_posting_templates FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_validation_rules_by_company ON public.posting_validation_rules;
    CREATE POLICY isolate_validation_rules_by_company ON public.posting_validation_rules FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_tax_codes_by_company ON public.tax_codes;
    CREATE POLICY isolate_tax_codes_by_company ON public.tax_codes FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_tax_rates_by_company ON public.tax_rates;
    CREATE POLICY isolate_tax_rates_by_company ON public.tax_rates FOR ALL USING (company_id = public.get_current_company_id());
END $$;

COMMIT;
