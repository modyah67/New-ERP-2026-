-- Migration 031: Fix Cash Payment and Receipt Builder Idempotency
-- Purpose: Allow payload-supplied idempotency_key in rpc_build_cash_payment_journal and rpc_build_cash_receipt_journal.

BEGIN;

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
    v_idempotency_key TEXT;
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

    -- Determine Debit Role and Update Party Balances
    IF v_mode = 'supplier' THEN
        v_debit_role := 'AP';
        SELECT code INTO v_supplier_code FROM public.suppliers WHERE id = v_supplier_id;
        v_ref := v_supplier_code;
        
        -- Update Supplier Balance
        UPDATE public.suppliers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_amount 
        WHERE id = v_supplier_id;
        
    ELSIF v_mode = 'customer' THEN
        v_debit_role := 'AR';
        SELECT code INTO v_customer_code FROM public.customers WHERE id = v_customer_id;
        v_ref := v_customer_code;
        
        -- Update Customer Balance
        UPDATE public.customers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amount 
        WHERE id = v_customer_id;
        
    ELSE
        v_debit_role := 'EXPENSE';
        v_ref := 'EXPENSE';
    END IF;

    v_idempotency_key := COALESCE(payload->>'idempotency_key', 'cash_pay_' || v_mode || '_' || v_ref || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT);

    -- Generate Journal Payload
    v_journal_payload := jsonb_build_object(
        'company_id', v_company_id,
        'document_type', 'CASH_PAYMENT',
        'posting_date', v_date,
        'reference', v_ref,
        'description', v_description,
        'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
        'idempotency_key', v_idempotency_key,
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
    v_idempotency_key TEXT;
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
        
        -- Update Customer Balance
        UPDATE public.customers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_amount 
        WHERE id = v_customer_id;
        
    ELSIF v_mode = 'supplier' THEN
        v_credit_role := 'AP';
        SELECT code INTO v_supplier_code FROM public.suppliers WHERE id = v_supplier_id;
        v_ref := v_supplier_code;
        
        -- Update Supplier Balance
        UPDATE public.suppliers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amount 
        WHERE id = v_supplier_id;
        
    ELSE
        v_credit_role := 'REVENUE';
        v_ref := 'REVENUE';
    END IF;

    v_idempotency_key := COALESCE(payload->>'idempotency_key', 'cash_rec_' || v_mode || '_' || v_ref || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT);

    -- Generate Journal Payload
    v_journal_payload := jsonb_build_object(
        'company_id', v_company_id,
        'document_type', 'CASH_RECEIPT',
        'posting_date', v_date,
        'reference', v_ref,
        'description', v_description,
        'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
        'idempotency_key', v_idempotency_key,
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
