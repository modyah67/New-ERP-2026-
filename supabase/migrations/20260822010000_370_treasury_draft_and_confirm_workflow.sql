-- ============================================================================
-- Migration 370: Treasury Draft and Confirm Workflow
-- ============================================================================
-- Adds Draft & Confirm support to Treasury transactions:
-- 1. Adds 'status' and 'payload' columns to treasury_transactions.
-- 2. Updates validation triggers to allow inserting 'draft' rows without balance impact.
-- 3. Implements rpc_save_treasury_draft.
-- 4. Implements rpc_delete_treasury_draft.
-- 5. Implements rpc_confirm_treasury_draft.
-- ============================================================================

DO $$
BEGIN
    -- 1. Add status column (default 'confirmed' so all existing transactions remain confirmed)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'treasury_transactions' AND column_name = 'status'
    ) THEN
        ALTER TABLE public.treasury_transactions 
        ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed';
    END IF;

    -- 2. Add payload column (JSONB for storing draft parameters)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'treasury_transactions' AND column_name = 'payload'
    ) THEN
        ALTER TABLE public.treasury_transactions 
        ADD COLUMN payload JSONB DEFAULT '{}'::jsonb;
    END IF;
END $$;

-- ── Soften validation triggers for 'draft' transactions ──
CREATE OR REPLACE FUNCTION public.fn_require_expense_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Ignore draft transactions
    IF NEW.status = 'draft' THEN
        RETURN NEW;
    END IF;

    -- Check for expense account or entity
    IF NEW.type = 'expense' 
       AND NEW.expense_account_id IS NULL 
       AND NEW.supplier_id IS NULL 
       AND NEW.customer_id IS NULL 
       AND NEW.clearing_agent_id IS NULL 
       AND NEW.shipping_company_id IS NULL 
       AND NEW.shareholder_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Ignore draft transactions
    IF NEW.status = 'draft' THEN
        RETURN NEW;
    END IF;

    IF NEW.type = 'deposit' 
       AND NEW.revenue_account_id IS NULL 
       AND NEW.customer_id IS NULL 
       AND NEW.supplier_id IS NULL 
       AND NEW.clearing_agent_id IS NULL 
       AND NEW.shipping_company_id IS NULL 
       AND NEW.shareholder_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب إيرادات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;

    RETURN NEW;
END;
$$;

-- ── 1. RPC: Save Treasury Draft ──
CREATE OR REPLACE FUNCTION public.rpc_save_treasury_draft(
    p_treasury_id BIGINT,
    p_type TEXT,
    p_amount NUMERIC,
    p_currency TEXT,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_category_id BIGINT DEFAULT NULL,
    p_expense_account_id BIGINT DEFAULT NULL,
    p_revenue_account_id BIGINT DEFAULT NULL,
    p_customer_id BIGINT DEFAULT NULL,
    p_supplier_id UUID DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id,
        type,
        amount,
        currency,
        description,
        notes,
        category_id,
        expense_account_id,
        revenue_account_id,
        customer_id,
        supplier_id,
        clearing_agent_id,
        shipping_company_id,
        shareholder_id,
        status,
        payload,
        created_by,
        created_at
    ) VALUES (
        p_treasury_id,
        p_type,
        p_amount,
        p_currency,
        p_description,
        p_notes,
        p_category_id,
        p_expense_account_id,
        p_revenue_account_id,
        p_customer_id,
        p_supplier_id,
        p_clearing_agent_id,
        p_shipping_company_id,
        p_shareholder_id,
        'draft',
        COALESCE(p_payload, '{}'::jsonb),
        auth.uid(),
        NOW()
    )
    RETURNING id INTO v_tx_id;

    RETURN v_tx_id;
END;
$$;

-- ── 2. RPC: Update Treasury Draft ──
CREATE OR REPLACE FUNCTION public.rpc_update_treasury_draft(
    p_transaction_id BIGINT,
    p_treasury_id BIGINT DEFAULT NULL,
    p_amount NUMERIC DEFAULT NULL,
    p_currency TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_category_id BIGINT DEFAULT NULL,
    p_expense_account_id BIGINT DEFAULT NULL,
    p_revenue_account_id BIGINT DEFAULT NULL,
    p_customer_id BIGINT DEFAULT NULL,
    p_supplier_id UUID DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.treasury_transactions
    SET
        treasury_id = COALESCE(p_treasury_id, treasury_id),
        amount = COALESCE(p_amount, amount),
        currency = COALESCE(p_currency, currency),
        description = COALESCE(p_description, description),
        notes = p_notes,
        category_id = p_category_id,
        expense_account_id = p_expense_account_id,
        revenue_account_id = p_revenue_account_id,
        customer_id = p_customer_id,
        supplier_id = p_supplier_id,
        clearing_agent_id = p_clearing_agent_id,
        shipping_company_id = p_shipping_company_id,
        shareholder_id = p_shareholder_id,
        payload = CASE WHEN p_payload IS NOT NULL THEN p_payload ELSE payload END
    WHERE id = p_transaction_id AND status = 'draft';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو أنها مؤكدة بالفعل';
    END IF;

    RETURN TRUE;
END;
$$;

-- ── 3. RPC: Delete Treasury Draft ──
CREATE OR REPLACE FUNCTION public.rpc_delete_treasury_draft(
    p_transaction_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_deleted_count INT;
BEGIN
    DELETE FROM public.treasury_transactions
    WHERE id = p_transaction_id AND status = 'draft';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    IF v_deleted_count = 0 THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو تم تأكيدها مسبقاً';
    END IF;

    RETURN TRUE;
END;
$$;

-- ── 4. RPC: Confirm Treasury Draft ──
CREATE OR REPLACE FUNCTION public.rpc_confirm_treasury_draft(
    p_transaction_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx RECORD;
    v_res JSONB;
    v_receipt_type TEXT;
    v_counterparty_type TEXT;
BEGIN
    SELECT * INTO v_tx
    FROM public.treasury_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    -- Case 1: Deposit / Receive Payment
    IF v_tx.type = 'deposit' OR v_tx.type = 'receipt' THEN
        v_receipt_type := COALESCE(v_tx.payload->>'receipt_type', 'cash');
        v_counterparty_type := v_tx.payload->>'counterparty_type';

        v_res := public.receive_payment(
            p_receipt_type      := v_receipt_type,
            p_amount            := v_tx.amount,
            p_currency          := v_tx.currency,
            p_counterparty_type := v_counterparty_type,
            p_counterparty_id   := v_tx.customer_id,
            p_supplier_id       := v_tx.supplier_id,
            p_shareholder_id    := v_tx.shareholder_id,
            p_description       := v_tx.description,
            p_notes             := v_tx.notes,
            p_treasury_id       := v_tx.treasury_id
        );

        -- Delete the original draft row since receive_payment creates the confirmed transaction row
        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الاستلام وترحيل القيد بنجاح', 'result', v_res);

    -- Case 2: Multi-invoice Payment for Supplier/Entity
    ELSIF v_tx.type = 'multi_payment' OR COALESCE((v_tx.payload->>'is_multi_payment')::boolean, false) = true THEN
        v_res := public.rpc_entity_multi_payment(
            p_source_type        := 'treasury',
            p_source_id          := v_tx.treasury_id::integer,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_entity_type        := COALESCE(v_tx.payload->>'entity_type', 'SUPPLIER'),
            p_entity_id          := COALESCE(v_tx.payload->>'entity_id', v_tx.supplier_id::text),
            p_description        := COALESCE(v_tx.description, 'سداد متعدد'),
            p_notes              := v_tx.notes,
            p_expense_account_id := v_tx.expense_account_id
        );

        -- Delete the original draft row
        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد السداد المتعدد بنجاح', 'result', v_res);

    -- Case 3: Currency Exchange / FX Transfer
    ELSIF v_tx.type = 'exchange' OR v_tx.type = 'currency_exchange' THEN
        PERFORM public.exchange_currency(
            p_treasury_id   := v_tx.treasury_id::text,
            p_from_currency := COALESCE(v_tx.payload->>'from_currency', v_tx.currency),
            p_to_currency   := (v_tx.payload->>'to_currency')::text,
            p_amount_from   := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to     := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate := (v_tx.payload->>'exchange_rate')::numeric,
            p_user_id       := v_tx.created_by,
            p_transfer_mode := COALESCE(v_tx.payload->>'transfer_mode', 'exchange')
        );

        -- Delete the original draft row
        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة وترحيل القيد بنجاح');

    -- Case 4: Expense / Spend
    ELSE
        IF v_tx.category_id IS NOT NULL AND v_tx.category_id > 0 THEN
            PERFORM public.spend_with_category(
                p_treasury_id          := v_tx.treasury_id,
                p_currency             := v_tx.currency,
                p_amount               := v_tx.amount,
                p_description          := COALESCE(v_tx.description, ''),
                p_category_id          := v_tx.category_id::integer,
                p_customer_id          := v_tx.customer_id::integer,
                p_supplier_id          := v_tx.supplier_id,
                p_clearing_agent_id    := v_tx.clearing_agent_id,
                p_shipping_company_id  := v_tx.shipping_company_id,
                p_shareholder_id       := v_tx.shareholder_id,
                p_expense_account_id   := v_tx.expense_account_id::integer,
                p_reference_type       := v_tx.payload->>'reference_type',
                p_reference_id         := v_tx.payload->>'reference_id',
                p_notes                := v_tx.notes
            );
        ELSE
            PERFORM public.spend_custody(
                p_treasury_id          := v_tx.treasury_id,
                p_currency             := v_tx.currency,
                p_amount               := v_tx.amount,
                p_description          := COALESCE(v_tx.description, ''),
                p_expense_account_id   := v_tx.expense_account_id::integer,
                p_customer_id          := v_tx.customer_id::integer,
                p_supplier_id          := v_tx.supplier_id,
                p_clearing_agent_id    := v_tx.clearing_agent_id,
                p_shipping_company_id  := v_tx.shipping_company_id,
                p_shareholder_id       := v_tx.shareholder_id,
                p_reference_type       := v_tx.payload->>'reference_type',
                p_reference_id         := v_tx.payload->>'reference_id',
                p_notes                := v_tx.notes
            );
        END IF;

        -- Delete the original draft row
        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد صرف المصروف وترحيل القيد بنجاح');
    END IF;
END;
$$;
