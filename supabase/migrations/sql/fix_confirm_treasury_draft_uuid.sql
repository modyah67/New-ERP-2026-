-- ==============================================================================
-- Migration: Fix rpc_confirm_treasury_draft UUID parsing & Type Coercion Bug
-- Fixes: PostgrestException(message: invalid input syntax for type uuid: "", code: 22P02)
-- ==============================================================================

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
    v_spend_id BIGINT;
    v_receipt_type TEXT;
    v_counterparty_type TEXT;
    v_mp_source_type TEXT;
    v_mp_source_id BIGINT;
    v_cost_center_id TEXT;
    v_branch_id BIGINT;
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

    v_cost_center_id := COALESCE(v_tx.cost_center_id, NULLIF(v_tx.payload->>'cost_center_id', ''));
    v_branch_id := COALESCE(
        v_tx.branch_id, 
        CASE WHEN (v_tx.payload->>'branch_id') ~ '^[0-9]+$' THEN (v_tx.payload->>'branch_id')::BIGINT ELSE NULL END
    );

    IF v_tx.type = 'deposit' OR v_tx.type = 'receipt' THEN
        v_receipt_type := COALESCE(v_tx.payload->>'receipt_type', 'cash');
        v_counterparty_type := v_tx.payload->>'counterparty_type';

        v_res := public.receive_payment(
            p_receipt_type      := v_receipt_type,
            p_amount            := v_tx.amount,
            p_currency          := v_tx.currency,
            p_counterparty_type := v_counterparty_type,
            p_counterparty_id   := COALESCE(v_tx.customer_id, NULLIF(v_tx.payload->>'counterparty_id', '')::integer, NULLIF(v_tx.payload->>'customer_id', '')::integer),
            p_supplier_id       := COALESCE(v_tx.supplier_id, NULLIF(v_tx.payload->>'supplier_id', '')::uuid),
            p_shareholder_id    := COALESCE(v_tx.shareholder_id, NULLIF(v_tx.payload->>'shareholder_id', '')::uuid),
            p_description       := v_tx.description,
            p_notes             := v_tx.notes,
            p_treasury_id       := v_tx.treasury_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الاستلام وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'multi_payment' OR COALESCE((v_tx.payload->>'is_multi_payment')::boolean, false) = true THEN
        v_mp_source_type := COALESCE(v_tx.payload->>'source_type', 'treasury');
        v_mp_source_id   := COALESCE(
            (v_tx.payload->>'source_id')::bigint,
            v_tx.treasury_id::bigint
        );

        v_res := public.rpc_entity_multi_payment(
            p_source_type        := v_mp_source_type,
            p_source_id          := v_mp_source_id,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_entity_type        := LOWER(COALESCE(v_tx.payload->>'entity_type', 'supplier')),
            p_entity_id          := COALESCE(v_tx.payload->>'entity_id', v_tx.supplier_id::text),
            p_description        := COALESCE(v_tx.description, 'سداد متعدد'),
            p_expense_account_id := v_tx.expense_account_id,
            p_notes              := v_tx.notes
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد السداد المتعدد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'exchange' OR v_tx.type = 'currency_exchange' THEN
        PERFORM public.exchange_currency(
            p_treasury_id   := v_tx.treasury_id::text,
            p_from_currency := COALESCE(v_tx.payload->>'from_currency', v_tx.currency),
            p_to_currency   := (v_tx.payload->>'to_currency')::text,
            p_amount_from   := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to     := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate := (v_tx.payload->>'exchange_rate')::numeric,
            p_user_id       := v_tx.created_by,
            p_transfer_mode := COALESCE(v_tx.payload->>'transfer_mode', 'exchange'),
            p_description   := COALESCE(v_tx.description, 'تحويل عملة')
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة بنجاح');

    ELSIF v_tx.type = 'expense' OR v_tx.type = 'withdrawal' THEN
        v_spend_id := public.spend_custody(
            p_treasury_id        := v_tx.treasury_id::bigint,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_description        := v_tx.description,
            p_supplier_id        := COALESCE(v_tx.supplier_id, NULLIF(v_tx.payload->>'supplier_id', '')::uuid),
            p_expense_account_id := COALESCE(
                v_tx.expense_account_id::integer, 
                NULLIF(v_tx.payload->>'expense_account_id', '')::integer, 
                v_tx.category_id::integer
            ),
            p_notes              := v_tx.notes,
            p_customer_id        := COALESCE(v_tx.customer_id, NULLIF(v_tx.payload->>'customer_id', '')::integer),
            p_clearing_agent_id  := COALESCE(v_tx.clearing_agent_id, NULLIF(v_tx.payload->>'clearing_agent_id', '')::bigint),
            p_shipping_company_id := COALESCE(v_tx.shipping_company_id, NULLIF(v_tx.payload->>'shipping_company_id', '')::bigint),
            p_shareholder_id     := COALESCE(v_tx.shareholder_id, NULLIF(v_tx.payload->>'shareholder_id', '')::uuid),
            p_cost_center_id     := v_cost_center_id,
            p_branch_id          := v_branch_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object(
            'success', true, 
            'message', 'تم تأكيد المصروف وترحيل القيد بنجاح', 
            'result', jsonb_build_object('transaction_id', v_spend_id)
        );
    ELSE
        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_treasury_draft(bigint) TO authenticated, anon, service_role;
