-- ============================================================================
-- Migration 364: Shipment Taxes Allocation & GL Accounts
-- 1. Create Account 2101: وسيط ضرائب (Tax Intermediary / Clearing) - liability
-- 2. Create Account 2102: ضرائب محملة (Allocated Taxes) - liability
-- 3. Add allocated_taxes column to export_shipments
-- 4. Register 'shipment_taxes' document type in sys_document_types and sys_sequences
-- 5. Create rpc_save_shipment_taxes to post GL entry (DR 2102 / CR 2101)
-- ============================================================================

BEGIN;

-- ── 1. Create Chart of Accounts (2101 & 2102 under 2100) ──
DO $$
DECLARE
    v_company_id UUID;
    v_parent_liab BIGINT;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- Parent liability 2100 (الخصوم المتداولة الأخرى)
    SELECT id INTO v_parent_liab FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    IF v_parent_liab IS NULL THEN
        SELECT id INTO v_parent_liab FROM public.accounts WHERE account_code = '20' LIMIT 1;
    END IF;

    -- 2101: وسيط ضرائب (Tax Clearing / Intermediary) - Credit
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id
    ) VALUES (
        '2101', 'Tax Intermediary', 'وسيط ضرائب', 'liability', true, true, true, 2101, v_company_id, v_parent_liab
    )
    ON CONFLICT (account_code) DO UPDATE 
    SET name = 'Tax Intermediary',
        account_name = 'وسيط ضرائب',
        account_type = 'liability',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(accounts.parent_id, v_parent_liab);

    -- 2102: ضرائب محملة (Allocated Taxes) - Debit
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id
    ) VALUES (
        '2102', 'Allocated Taxes', 'ضرائب محملة', 'liability', true, true, true, 2102, v_company_id, v_parent_liab
    )
    ON CONFLICT (account_code) DO UPDATE 
    SET name = 'Allocated Taxes',
        account_name = 'ضرائب محملة',
        account_type = 'liability',
        is_active = true,
        is_leaf = true,
        allow_posting = true,
        parent_id = COALESCE(accounts.parent_id, v_parent_liab);
END $$;

-- ── 2. Add column to export_shipments ──
ALTER TABLE public.export_shipments 
    ADD COLUMN IF NOT EXISTS allocated_taxes NUMERIC(18,2) DEFAULT 0.00;

-- ── 3. Register Document Type & Sequence ──
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES ('shipment_taxes', 'ضرائب محملة على الشحنة', 'TAX', true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    prefix = EXCLUDED.prefix,
    is_active = true;

INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
SELECT c.id, 'shipment_taxes', 0, 5
FROM public.sys_companies c
WHERE NOT EXISTS (
  SELECT 1 FROM public.sys_sequences s
  WHERE s.company_id = c.id AND s.document_type_code = 'shipment_taxes'
);

-- ── 4. Create RPC for Shipment Taxes ──
CREATE OR REPLACE FUNCTION public.rpc_save_shipment_taxes(
    p_shipment_id INT,
    p_allocated_taxes NUMERIC,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_has_distribution BOOLEAN;
    v_company_id UUID;
    v_tax_debit_acc BIGINT;
    v_tax_credit_acc BIGINT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_amount NUMERIC := COALESCE(p_allocated_taxes, 0.00);
BEGIN
    -- A. Check Profit Distribution Lock
    SELECT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions
        WHERE shipment_id = p_shipment_id AND deleted_at IS NULL
    ) INTO v_has_distribution;

    IF v_has_distribution THEN
        RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل التكاليف أو الضرائب';
    END IF;

    -- B. Fetch Shipment
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
    END IF;

    -- C. Update Export Shipment Record
    UPDATE public.export_shipments
    SET allocated_taxes = v_amount
    WHERE id = p_shipment_id;

    -- D. Resolve Accounts
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '2102' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    -- 2102: ضرائب محملة (طرف مدين)
    SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code = '2102' LIMIT 1;
    IF v_tax_debit_acc IS NULL THEN
        SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    -- 2101: وسيط ضرائب (طرف دائن)
    SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code = '2101' LIMIT 1;
    IF v_tax_credit_acc IS NULL THEN
        SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    -- E. Manage GL Journal Entry
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'shipment_taxes' AND source_id = p_shipment_id::text AND deleted_at IS NULL
    LIMIT 1;

    IF v_amount > 0 THEN
        IF v_je_id IS NOT NULL THEN
            -- Update existing entry
            UPDATE public.journal_entries
            SET description = 'ضرائب محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                updated_at = now()
            WHERE id = v_je_id;

            -- Replace ledger lines
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

            -- DR 2102 (ضرائب محملة)
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_debit_acc, v_amount, 0, 'EGP', v_amount,
                'تحميل ضرائب على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            -- CR 2101 (وسيط ضرائب)
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_credit_acc, 0, v_amount, 'EGP', v_amount,
                'وسيط ضرائب لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        ELSE
            -- Create new journal entry
            INSERT INTO public.journal_entries (
                entry_number, entry_date, description, status,
                is_auto_generated, source_type, source_id, company_id,
                created_by, created_at, updated_at
            ) VALUES (
                'PENDING',
                COALESCE(v_shipment.shipment_date, CURRENT_DATE),
                'ضرائب محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                'posted', true, 'shipment_taxes', p_shipment_id::text, v_company_id,
                COALESCE(p_user_id, auth.uid()), now(), now()
            ) RETURNING id INTO v_je_id;

            v_entry_num := public.fn_get_next_sequence(v_company_id, 'shipment_taxes', NULL, NULL);
            IF v_entry_num IS NULL OR v_entry_num = '' THEN
                v_entry_num := 'TAX-' || LPAD(v_je_id::text, 5, '0');
            END IF;
            UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

            -- DR 2102 (ضرائب محملة)
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_debit_acc, v_amount, 0, 'EGP', v_amount,
                'تحميل ضرائب على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            -- CR 2101 (وسيط ضرائب)
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_credit_acc, 0, v_amount, 'EGP', v_amount,
                'وسيط ضرائب لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        END IF;
    ELSE
        -- If amount is 0 and JE exists, soft delete it
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries SET deleted_at = now() WHERE id = v_je_id;
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shipment_id', p_shipment_id,
        'allocated_taxes', v_amount,
        'journal_entry_id', v_je_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_shipment_taxes(INT, NUMERIC, UUID) TO authenticated;

COMMIT;
