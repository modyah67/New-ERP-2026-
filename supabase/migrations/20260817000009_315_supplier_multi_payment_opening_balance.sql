-- Migration 315: Supplier Multi Payment Opening Balance & Priority Allocation

BEGIN;

-- 1. Ensure supplier_payment_allocations can hold opening_balance and advance allocations
ALTER TABLE public.supplier_payment_allocations 
    ALTER COLUMN purchase_invoice_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'supplier_payment_allocations' 
          AND column_name = 'supplier_id'
    ) THEN
        ALTER TABLE public.supplier_payment_allocations 
            ADD COLUMN supplier_id UUID REFERENCES public.suppliers(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'supplier_payment_allocations' 
          AND column_name = 'allocation_type'
    ) THEN
        ALTER TABLE public.supplier_payment_allocations 
            ADD COLUMN allocation_type TEXT NOT NULL DEFAULT 'invoice' CHECK (allocation_type IN ('opening_balance', 'invoice', 'advance'));
    END IF;
END $$;

-- 2. Update rpc_supplier_multi_payment with Opening Balance Priority Allocation
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
    v_remaining_to_allocate NUMERIC := p_amount;
    v_inv RECORD;
    v_allocation_amount NUMERIC;
    v_bank_result JSONB;
    v_initial_balance NUMERIC := 0;
    v_initial_direction TEXT := 'CREDIT';
    v_opening_paid NUMERIC := 0;
    v_opening_remaining NUMERIC := 0;
    v_opening_alloc NUMERIC := 0;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Fetch supplier opening balance info
    SELECT 
        COALESCE(initial_balance, 0),
        COALESCE(initial_balance_direction, 'CREDIT')
    INTO v_initial_balance, v_initial_direction
    FROM public.suppliers
    WHERE id = p_supplier_id;

    -- Calculate previously paid opening balance
    SELECT COALESCE(SUM(amount), 0)
    INTO v_opening_paid
    FROM public.supplier_payment_allocations
    WHERE supplier_id = p_supplier_id
      AND allocation_type = 'opening_balance';

    IF v_initial_direction = 'CREDIT' THEN
        v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
    ELSE
        v_opening_remaining := 0;
    END IF;

    -- 2. Execute the payment transaction from the source (treasury or bank)
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
        v_tx_id := (v_bank_result->>'transaction_id')::BIGINT;
        v_je_id := (v_bank_result->>'journal_entry_id')::BIGINT;
    ELSE
        RAISE EXCEPTION 'نوع المصدر غير صالح: %', p_source_type;
    END IF;

    -- 3. Allocation Priority 1: Opening Balance
    IF v_opening_remaining > 0 AND v_remaining_to_allocate > 0 THEN
        IF v_remaining_to_allocate >= v_opening_remaining THEN
            v_opening_alloc := v_opening_remaining;
        ELSE
            v_opening_alloc := v_remaining_to_allocate;
        END IF;

        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
        ) VALUES (
            p_source_type, v_tx_id, NULL, p_supplier_id, 'opening_balance', v_opening_alloc
        );

        v_remaining_to_allocate := v_remaining_to_allocate - v_opening_alloc;
    END IF;

    -- 4. Allocation Priority 2: Unpaid Purchase Invoices (FIFO by invoice_date)
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

        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
        ) VALUES (
            p_source_type, v_tx_id, v_inv.id, p_supplier_id, 'invoice', v_allocation_amount
        );

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

        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- 5. Allocation Priority 3: Advance Payment / Credit Balance
    IF v_remaining_to_allocate > 0 THEN
        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
        ) VALUES (
            p_source_type, v_tx_id, NULL, p_supplier_id, 'advance', v_remaining_to_allocate
        );
    END IF;

    -- 6. Recalculate & update supplier outstanding_balance
    UPDATE public.suppliers
    SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = p_supplier_id)
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'opening_balance_allocated', v_opening_alloc,
        'invoices_allocated', p_amount - v_opening_alloc - v_remaining_to_allocate,
        'advance_amount', v_remaining_to_allocate
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_supplier_multi_payment(TEXT, BIGINT, TEXT, NUMERIC, UUID, TEXT, INTEGER, TEXT) TO authenticated, anon, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
