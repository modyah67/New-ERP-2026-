-- Migration 021: Phase 2 - Cash Payment Builder
-- Purpose: SQL Builder for Cash Payments. Supports Supplier, Customer, and Other (Expense).

BEGIN;

DO $$
DECLARE
    v_company record;
    v_role_expense uuid;
    v_role_ar uuid;
    v_role_ap uuid;
    v_acc_expense int;
BEGIN
    -- Ensure EXPENSE role exists
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES (v_company.id, 'EXPENSE', 'General Expense', 'General expenses for direct cash payments', true)
        ON CONFLICT (company_id, code) DO NOTHING;
        
        SELECT id INTO v_role_expense FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'EXPENSE';
        SELECT id INTO v_role_ar FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AR';
        SELECT id INTO v_role_ap FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AP';
        
        -- Resolve an expense account for default mapping
        SELECT id INTO v_acc_expense FROM public.accounts WHERE (account_type = 'expense' OR account_code LIKE '5%') AND is_leaf = true AND allow_posting = true LIMIT 1;
        
        -- Map EXPENSE role in default profile
        IF v_acc_expense IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            SELECT v_company.id, id, v_role_expense, v_acc_expense
            FROM public.posting_profiles WHERE company_id = v_company.id AND is_default = true
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO NOTHING;
        END IF;

        -- Update templates for CASH_PAYMENT to make AP optional, and add EXPENSE and AR as optional debits
        UPDATE public.document_posting_templates 
        SET is_required = false 
        WHERE company_id = v_company.id AND document_type_code = 'CASH_PAYMENT' AND role_id = v_role_ap;

        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'CASH_PAYMENT', v_role_expense, false, 1),
            (v_company.id, 'CASH_PAYMENT', v_role_ar, false, 1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_build_cash_payment_journal(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
    v_date DATE;
    v_amount NUMERIC;
    v_mode TEXT;
    v_supplier_id UUID;
    v_customer_id UUID;
    v_description TEXT;
    
    v_journal_payload JSONB;
    v_debit_role TEXT;
    v_supplier_code TEXT;
    v_customer_code TEXT;
    v_ref TEXT;
BEGIN
    v_company_id := COALESCE((payload->>'company_id')::UUID, public.get_current_company_id());
    v_date := (payload->>'date')::DATE;
    v_amount := (payload->>'amount')::NUMERIC;
    v_mode := payload->>'mode';
    v_supplier_id := (payload->>'supplier_id')::UUID;
    v_customer_id := (payload->>'customer_id')::UUID;
    v_description := payload->>'description';
    
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Could not resolve company_id for Cash Payment.';
    END IF;

    -- Determine Debit Role based on mode
    IF v_mode = 'supplier' THEN
        v_debit_role := 'AP';
        SELECT code INTO v_supplier_code FROM public.suppliers WHERE id = v_supplier_id;
        v_ref := v_supplier_code;
    ELSIF v_mode = 'customer' THEN
        v_debit_role := 'AR';
        SELECT code INTO v_customer_code FROM public.customers WHERE id = v_customer_id;
        v_ref := v_customer_code;
    ELSE
        v_debit_role := 'EXPENSE';
        v_ref := 'EXPENSE';
    END IF;

    v_journal_payload := jsonb_build_object(
        'company_id', v_company_id,
        'document_type', 'CASH_PAYMENT',
        'posting_date', v_date,
        'reference', v_ref,
        'description', v_description,
        'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
        'idempotency_key', 'cash_pay_' || v_mode || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
        'lines', jsonb_build_array(
            jsonb_build_object(
                'role', v_debit_role,
                'debit', v_amount,
                'credit', 0,
                'description', v_description
            ),
            jsonb_build_object(
                'role', 'CASH',
                'debit', 0,
                'credit', v_amount,
                'description', v_description
            )
        )
    );
    
    RETURN public.rpc_post_journal(v_journal_payload);
END;
$$;

COMMIT;
