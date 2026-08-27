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
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
    v_je_id BIGINT;
    v_total_unpaid NUMERIC := 0;
    v_remaining_to_allocate NUMERIC := p_amount;
    v_inv RECORD;
    v_allocation_amount NUMERIC;
    v_bank_result JSONB;
BEGIN
    -- 1. Calculate total unpaid amount for the supplier (same currency as payment)
    SELECT COALESCE(SUM(total_amount - discount_amount - paid_amount), 0)
    INTO v_total_unpaid
    FROM public.purchase_invoices
    WHERE supplier_id = p_supplier_id
      AND currency = p_currency
      AND payment_status IN ('unpaid', 'partial');

    -- We now ALLOW overpayment. No exception is thrown if p_amount > v_total_unpaid.

    -- 2. Insert the payment transaction into the source (treasury or bank)
    IF p_source_type = 'treasury' THEN
        v_tx_id := public.spend_custody(
            p_treasury_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := p_description,
            p_supplier_id := p_supplier_id,
            p_expense_account_id := p_expense_account_id,
            p_notes := p_notes
        );
        -- Get the journal entry ID from the treasury transaction
        SELECT journal_entry_id INTO v_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
    ELSIF p_source_type = 'bank' THEN
        v_bank_result := public.withdraw_bank_account(
            p_account_id := p_source_id::INTEGER,
            p_amount := p_amount,
            p_description := p_description,
            p_entity_type := 'supplier',
            p_entity_id := p_supplier_id::TEXT,
            p_expense_account_id := p_expense_account_id,
            p_notes := p_notes
        );
        
        -- Extract transaction_id and journal_entry_id from JSONB result
        v_tx_id := (v_bank_result->>'transaction_id')::BIGINT;
        v_je_id := (v_bank_result->>'journal_entry_id')::BIGINT;
    ELSE
        RAISE EXCEPTION 'نوع المصدر غير صالح: %', p_source_type;
    END IF;

    -- 3. Loop through unpaid invoices and allocate the payment (FIFO by invoice_date)
    FOR v_inv IN 
        SELECT id, invoice_number, (total_amount - discount_amount - paid_amount) as due_amount
        FROM public.purchase_invoices
        WHERE supplier_id = p_supplier_id
          AND currency = p_currency
          AND payment_status IN ('unpaid', 'partial')
        ORDER BY invoice_date ASC, id ASC
    LOOP
        EXIT WHEN v_remaining_to_allocate <= 0;

        IF v_remaining_to_allocate >= v_inv.due_amount THEN
            v_allocation_amount := v_inv.due_amount;
        ELSE
            v_allocation_amount := v_remaining_to_allocate;
        END IF;

        -- Create allocation record
        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, purchase_invoice_id, amount
        ) VALUES (
            p_source_type, v_tx_id, v_inv.id, v_allocation_amount
        );

        -- Update invoice paid_amount and payment_status
        UPDATE public.purchase_invoices
        SET paid_amount = paid_amount + v_allocation_amount,
            payment_status = CASE 
                WHEN (paid_amount + v_allocation_amount) >= (total_amount - discount_amount) THEN 'paid'
                ELSE 'partial'
            END,
            payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id END,
            payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id END,
            payment_source_type = p_source_type,
            journal_entry_id = v_je_id
        WHERE id = v_inv.id;

        -- Decrease remaining to allocate
        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- If v_remaining_to_allocate > 0, the supplier's balance logic (which is handled by spend_custody/withdraw_bank_account) 
    -- will naturally reflect this as an advance payment.

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'allocated_amount', p_amount - v_remaining_to_allocate,
        'advance_amount', v_remaining_to_allocate
    );
END;
$$;

COMMIT;
