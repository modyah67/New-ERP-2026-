-- Migration: Add safety guard in rpc_save_treasury_draft & rpc_update_treasury_draft
-- to prevent foreign key violation on expense_categories(id) when invalid or chart-of-accounts IDs are passed.

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
    p_payload JSONB DEFAULT '{}'::jsonb,
    p_cost_center_id TEXT DEFAULT NULL,
    p_branch_id BIGINT DEFAULT NULL,
    p_to_branch_id BIGINT DEFAULT NULL,
    p_to_cost_center_id TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
    v_payload JSONB;
    v_cc_id TEXT;
    v_branch_id BIGINT;
    v_cat_id BIGINT := p_category_id;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Safety check: ensure category_id actually exists in expense_categories to prevent FK 23503
    IF v_cat_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.expense_categories WHERE id = v_cat_id) THEN
        v_cat_id := NULL;
    END IF;

    v_cc_id := COALESCE(p_cost_center_id, p_payload->>'cost_center_id');
    v_branch_id := COALESCE(p_branch_id, CASE WHEN (p_payload->>'branch_id') ~ '^[0-9]+$' THEN (p_payload->>'branch_id')::BIGINT ELSE NULL END);

    v_payload := COALESCE(p_payload, '{}'::jsonb);
    IF v_cc_id IS NOT NULL THEN
        v_payload := jsonb_set(v_payload, '{cost_center_id}', to_jsonb(v_cc_id));
    END IF;
    IF v_branch_id IS NOT NULL THEN
        v_payload := jsonb_set(v_payload, '{branch_id}', to_jsonb(v_branch_id));
    END IF;
    IF p_to_branch_id IS NOT NULL THEN
        v_payload := jsonb_set(v_payload, '{to_branch_id}', to_jsonb(p_to_branch_id));
    END IF;
    IF p_to_cost_center_id IS NOT NULL THEN
        v_payload := jsonb_set(v_payload, '{to_cost_center_id}', to_jsonb(p_to_cost_center_id));
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
        cost_center_id,
        branch_id,
        to_branch_id,
        to_cost_center_id,
        created_by,
        created_at
    ) VALUES (
        p_treasury_id,
        p_type,
        p_amount,
        p_currency,
        p_description,
        p_notes,
        v_cat_id,
        p_expense_account_id,
        p_revenue_account_id,
        p_customer_id,
        p_supplier_id,
        p_clearing_agent_id,
        p_shipping_company_id,
        p_shareholder_id,
        'draft',
        v_payload,
        v_cc_id,
        v_branch_id,
        p_to_branch_id,
        p_to_cost_center_id,
        auth.uid(),
        NOW()
    )
    RETURNING id INTO v_tx_id;

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_treasury_draft(BIGINT, TEXT, NUMERIC, TEXT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, UUID, BIGINT, BIGINT, UUID, JSONB, TEXT, BIGINT, BIGINT, TEXT) TO authenticated, service_role, anon;


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
    p_payload JSONB DEFAULT NULL,
    p_cost_center_id TEXT DEFAULT NULL,
    p_branch_id BIGINT DEFAULT NULL,
    p_to_branch_id BIGINT DEFAULT NULL,
    p_to_cost_center_id TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_cc_id TEXT;
    v_branch_id BIGINT;
    v_payload JSONB;
    v_cat_id BIGINT := p_category_id;
BEGIN
    -- Safety check: ensure category_id actually exists in expense_categories to prevent FK 23503
    IF v_cat_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.expense_categories WHERE id = v_cat_id) THEN
        v_cat_id := NULL;
    END IF;

    v_cc_id := COALESCE(p_cost_center_id, p_payload->>'cost_center_id');
    v_branch_id := COALESCE(p_branch_id, CASE WHEN (p_payload->>'branch_id') ~ '^[0-9]+$' THEN (p_payload->>'branch_id')::BIGINT ELSE NULL END);

    UPDATE public.treasury_transactions
    SET
        treasury_id = COALESCE(p_treasury_id, treasury_id),
        amount = COALESCE(p_amount, amount),
        currency = COALESCE(p_currency, currency),
        description = COALESCE(p_description, description),
        notes = p_notes,
        category_id = v_cat_id,
        expense_account_id = p_expense_account_id,
        revenue_account_id = p_revenue_account_id,
        customer_id = p_customer_id,
        supplier_id = p_supplier_id,
        clearing_agent_id = p_clearing_agent_id,
        shipping_company_id = p_shipping_company_id,
        shareholder_id = p_shareholder_id,
        cost_center_id = COALESCE(v_cc_id, cost_center_id),
        branch_id = COALESCE(v_branch_id, branch_id),
        to_branch_id = COALESCE(p_to_branch_id, to_branch_id),
        to_cost_center_id = COALESCE(p_to_cost_center_id, to_cost_center_id),
        payload = CASE
            WHEN p_payload IS NOT NULL THEN
                COALESCE(payload, '{}'::jsonb) || p_payload
            ELSE payload
        END,
        updated_at = NOW()
    WHERE id = p_transaction_id;

    RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_update_treasury_draft(BIGINT, BIGINT, NUMERIC, TEXT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, UUID, BIGINT, BIGINT, UUID, JSONB, TEXT, BIGINT, BIGINT, TEXT) TO authenticated, service_role, anon;
