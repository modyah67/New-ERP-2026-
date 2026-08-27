-- Migration 009: Phase 1 - Financial Configuration
-- Purpose: Defines Document Types, Accounting Periods, and the Sequence Engine for gapless numbering.

BEGIN;

DO $$
DECLARE
    v_default_company_id UUID;
BEGIN
    -- Get the default company
    SELECT id INTO v_default_company_id FROM public.sys_companies WHERE name = 'Main Company' LIMIT 1;

    -- ==========================================================
    -- 1. Modify existing fiscal_years
    -- ==========================================================
    ALTER TABLE IF EXISTS public.fiscal_years 
        ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
        
    UPDATE public.fiscal_years SET company_id = v_default_company_id WHERE company_id IS NULL;
    ALTER TABLE IF EXISTS public.fiscal_years ALTER COLUMN company_id SET NOT NULL;
    
    CREATE INDEX IF NOT EXISTS idx_fiscal_years_company_id ON public.fiscal_years(company_id);

    -- ==========================================================
    -- 2. Create accounting_periods
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.accounting_periods (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id),
        fiscal_year_id INT NOT NULL REFERENCES public.fiscal_years(id) ON DELETE CASCADE,
        period_name TEXT NOT NULL, -- e.g. "Jan-2026"
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('OPEN', 'CLOSED', 'ADJUSTMENT')),
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (company_id, fiscal_year_id, period_name)
    );
    CREATE INDEX IF NOT EXISTS idx_accounting_periods_dates ON public.accounting_periods(company_id, start_date, end_date);

    -- ==========================================================
    -- 3. Create sys_document_types
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.sys_document_types (
        code TEXT PRIMARY KEY, -- e.g., 'SALES_INVOICE', 'JOURNAL_ENTRY'
        name TEXT NOT NULL,
        description TEXT,
        prefix TEXT NOT NULL, -- e.g., 'INV', 'JV'
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ
    );

    -- Insert standard document types
    INSERT INTO public.sys_document_types (code, name, prefix) VALUES
    ('JOURNAL_ENTRY', 'Manual Journal Entry', 'JV'),
    ('SALES_INVOICE', 'Sales Invoice', 'INV'),
    ('PURCHASE_RECEIPT', 'Purchase Receipt', 'BILL'),
    ('CUSTOMER_PAYMENT', 'Customer Payment', 'RCPT'),
    ('SUPPLIER_PAYMENT', 'Supplier Payment', 'PMT')
    ON CONFLICT (code) DO NOTHING;

    -- ==========================================================
    -- 4. Create sys_sequences (Document Numbering Engine)
    -- ==========================================================
    CREATE TABLE IF NOT EXISTS public.sys_sequences (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES public.sys_companies(id),
        document_type_code TEXT NOT NULL REFERENCES public.sys_document_types(code),
        fiscal_year_id INT REFERENCES public.fiscal_years(id), -- Nullable if sequences are continuous across years
        branch_id UUID, -- Nullable if sequences are company-wide, not branch-specific
        current_value BIGINT NOT NULL DEFAULT 0,
        padding_length INT NOT NULL DEFAULT 5, -- e.g., 5 means 00001
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        UNIQUE (company_id, document_type_code, fiscal_year_id, branch_id)
    );

END $$;

-- ==========================================================
-- 5. Create Sequence Generator Function
-- ==========================================================
CREATE OR REPLACE FUNCTION public.fn_get_next_sequence(
    p_company_id UUID,
    p_document_type_code TEXT,
    p_fiscal_year_id INT DEFAULT NULL,
    p_branch_id UUID DEFAULT NULL
)
RETURNS TEXT AS
$func$
DECLARE
    v_prefix TEXT;
    v_fiscal_year_name TEXT := '';
    v_current_value BIGINT;
    v_padding INT;
    v_next_val BIGINT;
    v_generated_number TEXT;
BEGIN
    -- 1. Get the prefix
    SELECT prefix INTO v_prefix 
    FROM public.sys_document_types 
    WHERE code = p_document_type_code;

    IF v_prefix IS NULL THEN
        RAISE EXCEPTION 'Document Type % not found.', p_document_type_code;
    END IF;

    -- 2. Get Fiscal Year string if provided (e.g. '26' or '2026')
    -- 2. Get Fiscal Year string if provided
IF p_fiscal_year_id IS NOT NULL THEN
    SELECT name INTO v_fiscal_year_name
    FROM public.fiscal_years
    WHERE id = p_fiscal_year_id;
END IF;

    -- 3. Lock the sequence row for gapless update
    SELECT current_value, padding_length
    INTO v_current_value, v_padding
    FROM public.sys_sequences
    WHERE company_id = p_company_id
      AND document_type_code = p_document_type_code
      AND (fiscal_year_id = p_fiscal_year_id OR (fiscal_year_id IS NULL AND p_fiscal_year_id IS NULL))
      AND (branch_id = p_branch_id OR (branch_id IS NULL AND p_branch_id IS NULL))
    FOR UPDATE;

    -- 4. If row doesn't exist, create it
    IF NOT FOUND THEN
        INSERT INTO public.sys_sequences (
            company_id, document_type_code, fiscal_year_id, branch_id, current_value, padding_length
        ) VALUES (
            p_company_id, p_document_type_code, p_fiscal_year_id, p_branch_id, 1, 5
        ) RETURNING current_value, padding_length INTO v_next_val, v_padding;
    ELSE
        -- Increment the sequence
        UPDATE public.sys_sequences
        SET current_value = current_value + 1,
            updated_at = now()
        WHERE company_id = p_company_id
          AND document_type_code = p_document_type_code
          AND (fiscal_year_id = p_fiscal_year_id OR (fiscal_year_id IS NULL AND p_fiscal_year_id IS NULL))
          AND (branch_id = p_branch_id OR (branch_id IS NULL AND p_branch_id IS NULL))
        RETURNING current_value INTO v_next_val;
    END IF;

    -- 5. Format the output string: Prefix-Year-PaddedNumber (e.g., INV-2026-00001)
    IF v_fiscal_year_name != '' THEN
        v_generated_number := v_prefix || '-' || v_fiscal_year_name || '-' || LPAD(v_next_val::TEXT, v_padding, '0');
    ELSE
        v_generated_number := v_prefix || '-' || LPAD(v_next_val::TEXT, v_padding, '0');
    END IF;

    RETURN v_generated_number;
END;
$func$ LANGUAGE plpgsql;

-- ==========================================================
-- 6. Enable Row Level Security
-- ==========================================================
DO $$
BEGIN
    ALTER TABLE public.fiscal_years ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.accounting_periods ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.sys_sequences ENABLE ROW LEVEL SECURITY;

    -- Drop old fiscal_years policy if it exists and recreate
    DROP POLICY IF EXISTS isolate_fiscal_years_by_company ON public.fiscal_years;
    CREATE POLICY isolate_fiscal_years_by_company ON public.fiscal_years
        FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_accounting_periods_by_company ON public.accounting_periods;
    CREATE POLICY isolate_accounting_periods_by_company ON public.accounting_periods
        FOR ALL USING (company_id = public.get_current_company_id());

    DROP POLICY IF EXISTS isolate_sys_sequences_by_company ON public.sys_sequences;
    CREATE POLICY isolate_sys_sequences_by_company ON public.sys_sequences
        FOR ALL USING (company_id = public.get_current_company_id());
END $$;

COMMIT;
