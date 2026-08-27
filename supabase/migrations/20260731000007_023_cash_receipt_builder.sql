-- Migration 023: Phase 2 - Cash Receipt Builder
-- Purpose: SQL Builder for Cash Receipts. Supports Customer, Supplier, and Other (Revenue).

BEGIN;

DO $$
DECLARE
    v_company record;
    v_role_revenue uuid;
    v_role_ar uuid;
    v_role_ap uuid;
    v_acc_revenue int;
BEGIN
    -- Ensure REVENUE role exists
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        INSERT INTO public.posting_account_roles (company_id, code, name, description, is_active)
        VALUES (v_company.id, 'REVENUE', 'General Revenue', 'General revenue for direct cash receipts', true)
        ON CONFLICT (company_id, code) DO NOTHING;
        
        SELECT id INTO v_role_revenue FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'REVENUE';
        SELECT id INTO v_role_ar FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AR';
        SELECT id INTO v_role_ap FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AP';
        
        -- Resolve a revenue account for default mapping
        SELECT id INTO v_acc_revenue FROM public.accounts WHERE (account_type = 'revenue' OR account_code LIKE '4%') AND is_leaf = true AND allow_posting = true LIMIT 1;
        
        -- Map REVENUE role in default profile
        IF v_acc_revenue IS NOT NULL THEN
            INSERT INTO public.posting_profile_rules (company_id, posting_profile_id, role_id, account_id)
            SELECT v_company.id, id, v_role_revenue, v_acc_revenue
            FROM public.posting_profiles WHERE company_id = v_company.id AND is_default = true
            ON CONFLICT (posting_profile_id, role_id, valid_from) DO NOTHING;
        END IF;

        -- Update templates for CASH_RECEIPT to make AR optional, and add REVENUE and AP as optional credits
        UPDATE public.document_posting_templates 
        SET is_required = false 
        WHERE company_id = v_company.id AND document_type_code = 'CASH_RECEIPT' AND role_id = v_role_ar;

        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'CASH_RECEIPT', v_role_revenue, false, -1),
            (v_company.id, 'CASH_RECEIPT', v_role_ap, false, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_build_cash_receipt_journal(payload JSONB)
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
    v_credit_role TEXT;
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
        RAISE EXCEPTION 'Could not resolve company_id for Cash Receipt.';
    END IF;

    -- Determine Credit Role and Update Party Balances
    IF v_mode = 'customer' THEN
        v_credit_role := 'AR';
        SELECT code INTO v_customer_code FROM public.customers WHERE id = v_customer_id;
        v_ref := v_customer_code;
        
        -- Update Customer Balance: Cash Receipt from customer reduces what they owe us (-amount)
        UPDATE public.customers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_amount 
        WHERE id = v_customer_id;
        
    ELSIF v_mode = 'supplier' THEN
        v_credit_role := 'AP';
        SELECT code INTO v_supplier_code FROM public.suppliers WHERE id = v_supplier_id;
        v_ref := v_supplier_code;
        
        -- Update Supplier Balance: Cash Receipt from supplier (refund) increases AP (liability) / what we owe them
        UPDATE public.suppliers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amount 
        WHERE id = v_supplier_id;
        
    ELSE
        v_credit_role := 'REVENUE';
        v_ref := 'REVENUE';
    END IF;

    -- Generate Journal Payload
    v_journal_payload := jsonb_build_object(
        'company_id', v_company_id,
        'document_type', 'CASH_RECEIPT',
        'posting_date', v_date,
        'reference', v_ref,
        'description', v_description,
        'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
        'idempotency_key', 'cash_rec_' || v_mode || '_' || v_ref || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
        'lines', jsonb_build_array(
            jsonb_build_object(
                'role', 'CASH',
                'debit', v_amount,
                'credit', 0,
                'description', v_description
            ),
            jsonb_build_object(
                'role', v_credit_role,
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
