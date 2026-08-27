-- Migration 033: Treasury Expense Subledger Builder
-- Purpose: Route _adjustVendorForExpense writes through a single atomic SQL function.
-- Replaces: direct Dart writes to ledger_entries + entity balance tables.

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_build_expense_subledger(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_entity_type TEXT;
    v_entity_id TEXT;
    v_amount NUMERIC;
    v_currency TEXT;
    v_reference_type TEXT;
    v_reference_id INTEGER;
    v_description TEXT;
    v_idempotency_key TEXT;
    v_exists BIGINT;
    v_balance_column TEXT;
    v_balance_table TEXT;
BEGIN
    v_entity_type := payload->>'entity_type';
    v_entity_id := payload->>'entity_id';
    v_amount := (payload->>'amount')::NUMERIC;
    v_currency := COALESCE(payload->>'currency', 'EGP');
    v_reference_type := payload->>'reference_type';
    v_reference_id := (payload->>'reference_id')::INTEGER;
    v_description := payload->>'description';
    v_idempotency_key := payload->>'idempotency_key';

    IF v_entity_type IS NULL OR v_entity_id IS NULL THEN
        RAISE EXCEPTION 'entity_type and entity_id are required';
    END IF;

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION 'amount must be positive';
    END IF;

    IF v_idempotency_key IS NOT NULL THEN
        SELECT COUNT(*) INTO v_exists FROM public.ledger_entries
        WHERE reference_type = v_reference_type
          AND reference_id = v_reference_id
          AND entity_type = v_entity_type
          AND entity_id = v_entity_id;
        IF v_exists > 0 THEN
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Already processed (idempotent skip)',
                'entity_type', v_entity_type,
                'entity_id', v_entity_id
            );
        END IF;
    END IF;

    IF v_entity_type = 'customer' THEN
        UPDATE public.customers
        SET balance = COALESCE(balance, 0) - v_amount
        WHERE id = v_entity_id::bigint;

    ELSIF v_entity_type = 'supplier' THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amount
        WHERE id = v_entity_id::uuid;

    ELSIF v_entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) - v_amount,
            balance = COALESCE(balance, 0) - v_amount
        WHERE id = v_entity_id::bigint;

    ELSIF v_entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) - v_amount,
            balance = COALESCE(balance, 0) - v_amount
        WHERE id = v_entity_id::bigint;

    ELSIF v_entity_type = 'shareholder' THEN
        IF v_currency = 'EGP' THEN
            UPDATE public.shareholders
            SET current_balance_egp = COALESCE(current_balance_egp, 0) - v_amount
            WHERE id = v_entity_id;
        ELSIF v_currency = 'USD' THEN
            UPDATE public.shareholders
            SET current_balance_usd = COALESCE(current_balance_usd, 0) - v_amount
            WHERE id = v_entity_id;
        ELSIF v_currency = 'EUR' THEN
            UPDATE public.shareholders
            SET current_balance_eur = COALESCE(current_balance_eur, 0) - v_amount
            WHERE id = v_entity_id;
        ELSIF v_currency = 'GBP' THEN
            UPDATE public.shareholders
            SET current_balance_gbp = COALESCE(current_balance_gbp, 0) - v_amount
            WHERE id = v_entity_id;
        END IF;

    ELSE
        RAISE EXCEPTION 'Invalid entity_type: %', v_entity_type;
    END IF;

    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        v_entity_type, v_entity_id, 'debit', v_amount, v_currency,
        v_reference_type, v_reference_id, v_description, auth.uid()
    );

    RETURN jsonb_build_object(
        'success', true,
        'entity_type', v_entity_type,
        'entity_id', v_entity_id,
        'amount', v_amount,
        'currency', v_currency
    );
END;
$$;

COMMIT;
