-- Migration 019: Phase 1 - Enterprise Posting Templates
-- Purpose: Seeds the missing document_posting_templates to make the Posting Engine fully deployable.

BEGIN;

DO $$
DECLARE
    v_company record;
    
    v_role_ar uuid;
    v_role_ap uuid;
    v_role_revenue uuid;
    v_role_cogs uuid;
    v_role_cash uuid;
    v_role_bank uuid;
    v_role_inv uuid;
    v_role_discount uuid;
    v_role_vat_in uuid;
    v_role_vat_out uuid;
BEGIN

    -- Iterate over all existing companies
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        -- Retrieve Role IDs
        SELECT id INTO v_role_ar FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AR';
        SELECT id INTO v_role_ap FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AP';
        SELECT id INTO v_role_revenue FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'REVENUE';
        SELECT id INTO v_role_cogs FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'COGS';
        SELECT id INTO v_role_cash FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'CASH';
        SELECT id INTO v_role_inv FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'INVENTORY';
        SELECT id INTO v_role_discount FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'DISCOUNT';
        SELECT id INTO v_role_vat_in FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'VAT_INPUT';
        SELECT id INTO v_role_vat_out FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'VAT_OUTPUT';
        SELECT id INTO v_role_bank FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'BANK';

        -- JOURNAL_ENTRY: Flexible manual entry.
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES (v_company.id, 'JOURNAL_ENTRY', v_role_cash, false, 1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- SALES_INVOICE
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'SALES_INVOICE', v_role_ar, true, 1),
            (v_company.id, 'SALES_INVOICE', v_role_revenue, true, -1),
            (v_company.id, 'SALES_INVOICE', v_role_vat_out, false, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- PURCHASE_RECEIPT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'PURCHASE_RECEIPT', v_role_inv, true, 1),
            (v_company.id, 'PURCHASE_RECEIPT', v_role_ap, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- COST_ALLOCATION
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'COST_ALLOCATION', v_role_inv, true, 1),
            (v_company.id, 'COST_ALLOCATION', v_role_ap, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- EXPORT_SHIPMENT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'EXPORT_SHIPMENT', v_role_ar, true, 1),
            (v_company.id, 'EXPORT_SHIPMENT', v_role_revenue, true, -1),
            (v_company.id, 'EXPORT_SHIPMENT', v_role_cogs, false, 1),
            (v_company.id, 'EXPORT_SHIPMENT', v_role_inv, false, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- CASH_PAYMENT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'CASH_PAYMENT', v_role_ap, true, 1),
            (v_company.id, 'CASH_PAYMENT', v_role_cash, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- CASH_RECEIPT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'CASH_RECEIPT', v_role_cash, true, 1),
            (v_company.id, 'CASH_RECEIPT', v_role_ar, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
        
        -- CUSTOMER_PAYMENT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'CUSTOMER_PAYMENT', v_role_cash, true, 1),
            (v_company.id, 'CUSTOMER_PAYMENT', v_role_ar, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- SUPPLIER_PAYMENT
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'SUPPLIER_PAYMENT', v_role_ap, true, 1),
            (v_company.id, 'SUPPLIER_PAYMENT', v_role_cash, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;

        -- PURCHASE_WORKFLOW
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'PURCHASE_WORKFLOW', v_role_inv, true, 1),
            (v_company.id, 'PURCHASE_WORKFLOW', v_role_ap, true, -1),
            (v_company.id, 'PURCHASE_WORKFLOW', v_role_cash, false, -1),
            (v_company.id, 'PURCHASE_WORKFLOW', v_role_discount, false, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
        
    END LOOP;
END $$;

-- =======================================================================
-- INTERNAL VALIDATION
-- =======================================================================
DO $$
DECLARE
    v_doc_type record;
    v_missing int;
    v_orphans int;
    v_invalid_roles int;
BEGIN
    -- 1. Ensure every active doc type has at least one template
    FOR v_doc_type IN SELECT code FROM public.sys_document_types WHERE is_active = true
    LOOP
        SELECT COUNT(*) INTO v_missing 
        FROM public.document_posting_templates 
        WHERE document_type_code = v_doc_type.code;
        
        IF v_missing = 0 THEN
            RAISE EXCEPTION 'Validation Failed: Document type % has no templates.', v_doc_type.code;
        END IF;
    END LOOP;

    -- 2. Ensure no orphan templates
    SELECT COUNT(*) INTO v_orphans 
    FROM public.document_posting_templates t
    LEFT JOIN public.sys_document_types d ON d.code = t.document_type_code
    WHERE d.code IS NULL;
    
    IF v_orphans > 0 THEN
        RAISE EXCEPTION 'Validation Failed: Found % orphan templates for invalid document types.', v_orphans;
    END IF;

    -- 3. Ensure all templates reference valid existing roles
    SELECT COUNT(*) INTO v_invalid_roles 
    FROM public.document_posting_templates t
    LEFT JOIN public.posting_account_roles r ON r.id = t.role_id
    WHERE r.id IS NULL;

    IF v_invalid_roles > 0 THEN
        RAISE EXCEPTION 'Validation Failed: Found % templates referencing non-existent posting roles.', v_invalid_roles;
    END IF;
END $$;

COMMIT;
