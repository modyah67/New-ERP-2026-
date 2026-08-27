-- ============================================================================
-- Migration 382: Set PAC-OB Prefix for Packaging Material Opening Balance GL Entries
-- ============================================================================
-- Ensures all opening balance journal entries for packaging materials (raw materials)
-- receive the exact prefix 'PAC-OB-' (e.g. PAC-OB-00001) in accordance with the 
-- system document type specification.
-- ============================================================================

BEGIN;

-- 1. Register / update raw_material_opening document type with prefix PAC-OB
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES ('raw_material_opening', 'Raw Material Opening Balance / رصيد افتتاحي مواد تعبئة', 'PAC-OB', true)
ON CONFLICT (code) DO UPDATE SET
    prefix = EXCLUDED.prefix,
    name = EXCLUDED.name,
    is_active = true;

-- 2. Ensure sequence exists for raw_material_opening in sys_sequences
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences') THEN
        INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
        SELECT c.id, 'raw_material_opening', 0, 5
        FROM public.sys_companies c
        WHERE NOT EXISTS (
            SELECT 1 FROM public.sys_sequences s
            WHERE s.company_id = c.id AND s.document_type_code = 'raw_material_opening'
        );
    END IF;
END $$;

-- 3. Update rpc_record_raw_material_opening_gl with PAC-OB prefix
CREATE OR REPLACE FUNCTION public.rpc_record_raw_material_opening_gl(
    p_raw_material_id UUID, 
    p_quantity NUMERIC, 
    p_unit_price NUMERIC, 
    p_currency TEXT, 
    p_company_id UUID DEFAULT NULL::UUID,
    p_exchange_rate NUMERIC DEFAULT NULL::NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_company_id UUID;
    v_rate NUMERIC;
    v_total_foreign NUMERIC;
    v_total_base NUMERIC;
    v_inv_acct BIGINT;
    v_equity_acct BIGINT;
    v_je_id BIGINT;
    v_material_name TEXT;
    v_desc TEXT;
    v_source_id TEXT;
    v_entry_number TEXT;
BEGIN
    IF p_quantity <= 0 OR p_unit_price <= 0 THEN
        RETURN jsonb_build_object('success', false, 'reason', 'Zero quantity or price');
    END IF;

    -- Resolve company_id with robust multi-level fallback
    v_company_id := p_company_id;
    IF v_company_id IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT tenant_id INTO v_company_id FROM public.tenant_users WHERE user_id = auth.uid() LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM public.treasuries WHERE type = 'main' AND company_id IS NOT NULL LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    SELECT name INTO v_material_name FROM public.raw_materials WHERE id = p_raw_material_id;
    v_desc := 'رصيد افتتاحي مخزون مادة تعبئة - ' || COALESCE(v_material_name, '');

    -- Exchange rate resolution:
    -- 1. If EGP -> 1.0
    -- 2. If user provided a specific exchange rate (p_exchange_rate > 0) -> use it directly!
    -- 3. Fallback to system exchange rate table fn_get_exchange_rate(p_currency)
    IF p_currency = 'EGP' OR p_currency IS NULL OR p_currency = '' THEN
        v_rate := 1.0;
    ELSIF p_exchange_rate IS NOT NULL AND p_exchange_rate > 0 THEN
        v_rate := p_exchange_rate;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
    END IF;

    IF v_rate IS NULL OR v_rate <= 0 THEN
        v_rate := 1.0;
    END IF;

    v_total_foreign := ROUND(p_quantity * p_unit_price, 2);
    v_total_base := ROUND(v_total_foreign * v_rate, 2);

    -- Resolve GL accounts:
    -- Debit 1040 (Packaging Materials Inventory - non-monetary asset in base currency EGP)
    v_inv_acct := public.resolve_gl_account('1040', v_company_id);
    IF v_inv_acct IS NULL THEN
        RAISE EXCEPTION 'Packing Materials Inventory account (1040) not found in chart of accounts';
    END IF;

    -- Credit 3901 (Opening Balance Equity - EGP)
    v_equity_acct := public.resolve_opening_balance_equity_account('EGP', v_company_id);
    IF v_equity_acct IS NULL THEN
        RAISE EXCEPTION 'Opening Balance Equity account (3901 - EGP) not found in chart of accounts';
    END IF;

    v_source_id := 'raw_material_' || p_raw_material_id::text;

    -- Idempotency check: check if a journal entry already exists for this raw material
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'raw_material_opening'
      AND (source_id = v_source_id OR source_id = p_raw_material_id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        -- Atomically wipe old lines within this transaction and update header
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

        UPDATE public.journal_entries
        SET description = v_desc,
            entry_date = CURRENT_DATE,
            status = 'posted'
        WHERE id = v_je_id;
    ELSE
        v_entry_number := 'PAC-OB-' || LPAD((COALESCE((SELECT MAX(id) FROM public.journal_entries), 0) + 1)::text, 5, '0');

        INSERT INTO public.journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
        ) VALUES (
            'raw_material_opening', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
        ) RETURNING id INTO v_je_id;
    END IF;

    -- Double entry lines (Denominated in Base Currency EGP for non-monetary inventory asset 1040)
    -- Debit: 1040 (Packing Materials Inventory)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_inv_acct, v_total_base, 0, 'EGP', v_total_base, v_desc, v_company_id
    );

    -- Credit: 3901 (Opening Balance Equity - EGP)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_equity_acct, 0, v_total_base, 'EGP', v_total_base, v_desc, v_company_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'amount_foreign', v_total_foreign,
        'amount_base', v_total_base,
        'currency', 'EGP',
        'original_currency', p_currency,
        'exchange_rate', v_rate
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_record_raw_material_opening_gl(uuid, numeric, numeric, text, uuid, numeric) TO authenticated, service_role, anon;

-- 4. Update existing journal entries for raw materials opening balance to have PAC-OB- prefix
UPDATE public.journal_entries
SET entry_number = 'PAC-OB-' || LPAD(id::text, 5, '0')
WHERE source_type = 'raw_material_opening'
  AND (entry_number IS NULL OR entry_number NOT LIKE 'PAC-OB-%');

NOTIFY pgrst, 'reload_schema';

COMMIT;
