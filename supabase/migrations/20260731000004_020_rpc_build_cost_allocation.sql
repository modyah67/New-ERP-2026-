-- Migration 020: Phase 2 - Cost Allocation Builder
-- Purpose: SQL Builder to generate Cost Allocation journals via rpc_post_journal.

CREATE OR REPLACE FUNCTION public.rpc_build_cost_allocation_journal(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
    v_date DATE;
    v_amount NUMERIC;
    v_supplier_id UUID;
    v_lot_number TEXT;
    v_product_name TEXT;
    v_currency_snapshot JSONB;
    v_journal_payload JSONB;
BEGIN
    -- Extract Business Event Data
    v_company_id := COALESCE((payload->>'company_id')::UUID, public.get_current_company_id());
    v_date := (payload->>'date')::DATE;
    v_amount := (payload->>'amount')::NUMERIC;
    v_supplier_id := (payload->>'supplier_id')::UUID;
    v_lot_number := payload->>'lot_number';
    v_product_name := payload->>'product_name';
    v_currency_snapshot := payload->'currency_snapshot';
    
    -- Ensure Company ID is resolved
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Could not resolve company_id for Cost Allocation.';
    END IF;

    -- Construct Journal Payload for the Posting Engine
    v_journal_payload := jsonb_build_object(
        'company_id', v_company_id,
        'document_type', 'COST_ALLOCATION',
        'posting_date', v_date,
        'reference', v_lot_number,
        'description', 'استلام محصول ' || v_lot_number || ' - ' || COALESCE(v_product_name, ''),
        'currency', v_currency_snapshot,
        'idempotency_key', 'cost_alloc_' || v_lot_number || '_' || EXTRACT(EPOCH FROM now())::BIGINT::TEXT,
        'lines', jsonb_build_array(
            jsonb_build_object(
                'role', 'INVENTORY',
                'debit', v_amount,
                'credit', 0,
                'description', 'استلام محصول ' || v_lot_number
            ),
            jsonb_build_object(
                'role', 'AP',
                'debit', 0,
                'credit', v_amount,
                'description', 'مستحقات المورد عن استلام محصول ' || v_lot_number
            )
        )
    );
    
    -- Dispatch to Posting Engine
    RETURN public.rpc_post_journal(v_journal_payload);
END;
$$;
