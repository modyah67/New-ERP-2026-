BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_supplier_multi_payment(
    p_source_type          TEXT, -- 'treasury' or 'bank'
    p_source_id            BIGINT, -- treasury_id or bank_account_id
    p_currency             TEXT,
    p_amount               NUMERIC,
    p_supplier_id          UUID,
    p_description          TEXT,
    p_expense_account_id   INTEGER DEFAULT NULL,
    p_notes                TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
    v_je_id BIGINT;
    v_total_unpaid NUMERIC := 0;
    v_remaining_to_allocate NUMERIC := p_amount;
    v_invoice RECORD;
    v_alloc_amount NUMERIC;
    v_res JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    -- Deduct from source and create main transaction using EXISTING logic
    IF p_source_type = 'treasury' THEN
        -- spend_custody handles creating the journal entry and treasury transaction
        -- We pass reference_type = 'multi_invoice' so it doesn't update any single invoice
        v_tx_id := public.spend_custody(
            p_treasury_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := p_description,
            p_customer_id := NULL,
            p_supplier_id := p_supplier_id,
            p_clearing_agent_id := NULL,
            p_shipping_company_id := NULL,
            p_shareholder_id := NULL,
            p_expense_account_id := p_expense_account_id,
            p_reference_type := 'multi_invoice',
            p_reference_id := NULL,
            p_notes := p_notes
        );
        
        -- spend_custody returns the journal_entry_id.
        v_je_id := v_tx_id; 

    ELSIF p_source_type = 'bank' THEN
        v_res := public.withdraw_bank_account(
            p_bank_account_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := p_description,
            p_supplier_id := p_supplier_id,
            p_customer_id := NULL,
            p_clearing_agent_id := NULL,
            p_shipping_company_id := NULL,
            p_shareholder_id := NULL,
            p_expense_account_id := p_expense_account_id,
            p_reference_type := 'multi_invoice',
            p_reference_id := NULL,
            p_notes := p_notes
        );
        
        v_tx_id := (v_res->>'transaction_id')::BIGINT;
        v_je_id := (v_res->>'journal_entry_id')::BIGINT;

    ELSE
        RAISE EXCEPTION 'Invalid source type: %', p_source_type;
    END IF;

    -- Now auto-allocate the amount across unpaid invoices from oldest to newest
    FOR v_invoice IN 
        SELECT id, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - COALESCE(paid_amount, 0) as remaining_amount
        FROM public.purchase_invoices
        WHERE supplier_id = p_supplier_id
          AND payment_status IN ('unpaid', 'partial')
        ORDER BY invoice_date ASC, id ASC
    LOOP
        IF v_remaining_to_allocate <= 0 THEN
            EXIT; -- We are done
        END IF;

        IF v_invoice.remaining_amount <= 0 THEN
            CONTINUE; -- Just in case
        END IF;

        -- How much to allocate to THIS invoice
        IF v_remaining_to_allocate >= v_invoice.remaining_amount THEN
            v_alloc_amount := v_invoice.remaining_amount;
        ELSE
            v_alloc_amount := v_remaining_to_allocate;
        END IF;

        -- Update invoice paid_amount and status
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + v_alloc_amount,
            payment_status = CASE 
                WHEN (COALESCE(paid_amount, 0) + v_alloc_amount) >= (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) THEN 'paid'
                ELSE 'partial'
            END
        WHERE id = v_invoice.id;

        -- Record the allocation mapping
        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, purchase_invoice_id, amount
        ) VALUES (
            p_source_type, v_tx_id, v_invoice.id, v_alloc_amount
        );

        -- Decrease remaining to allocate
        v_remaining_to_allocate := v_remaining_to_allocate - v_alloc_amount;
    END LOOP;

    RETURN v_je_id;
END;
$$;

COMMIT;
