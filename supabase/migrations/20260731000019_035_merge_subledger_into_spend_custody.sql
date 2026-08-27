-- Migration 035: Merge treasury expense subledger into spend_custody/spend_with_category
-- Architecture: one business operation = one SQL transaction = one RPC call
-- spend_custody now: treasury balance → treasury_transaction → party balance → ledger_entries
-- spend_with_category: same + category_id
-- No separate RPC needed from Dart for ledger_entries.

BEGIN;

-- Ensure old signatures are dropped (in case 034's DROP failed)
DROP FUNCTION IF EXISTS public.spend_custody(bigint, varchar, numeric, text, bigint, uuid, bigint, bigint, uuid);
DROP FUNCTION IF EXISTS public.spend_with_category(bigint, varchar, numeric, text, bigint, bigint, uuid, bigint, bigint, uuid);

-- ============================================================
-- 1. spend_custody: now writes ledger_entries in same transaction
-- ============================================================
CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id bigint,
    p_currency varchar,
    p_amount numeric,
    p_description text,
    p_customer_id bigint DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_clearing_agent_id bigint DEFAULT NULL,
    p_shipping_company_id bigint DEFAULT NULL,
    p_shareholder_id uuid DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance numeric;
    v_tx_id bigint;
    v_entity_type text;
    v_entity_id   text;
BEGIN
    -- 1. Treasury balance check
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    -- 2. Debit treasury
    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- 3. Create treasury transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, p_description,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- 4. Party balance updates
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
    END IF;

    -- 5. Subledger entry (ledger_entries)
    IF p_customer_id IS NOT NULL THEN
        v_entity_type := 'customer';
        v_entity_id   := p_customer_id::text;
    ELSIF p_supplier_id IS NOT NULL THEN
        v_entity_type := 'supplier';
        v_entity_id   := p_supplier_id::text;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        v_entity_type := 'clearing_agent';
        v_entity_id   := p_clearing_agent_id::text;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        v_entity_type := 'shipping_company';
        v_entity_id   := p_shipping_company_id::text;
    ELSIF p_shareholder_id IS NOT NULL THEN
        v_entity_type := 'shareholder';
        v_entity_id   := p_shareholder_id::text;
    END IF;

    IF v_entity_type IS NOT NULL THEN
        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, description, created_by
        ) VALUES (
            v_entity_type, v_entity_id, 'debit', p_amount, p_currency,
            'expense', v_tx_id, p_description, auth.uid()
        );
    END IF;

    RETURN v_tx_id;
END;
$$;

-- ============================================================
-- 2. spend_with_category: same — includes ledger_entries
-- ============================================================
CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id bigint,
    p_currency varchar,
    p_amount numeric,
    p_description text,
    p_category_id bigint,
    p_customer_id bigint DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_clearing_agent_id bigint DEFAULT NULL,
    p_shipping_company_id bigint DEFAULT NULL,
    p_shareholder_id uuid DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance numeric;
    v_tx_id bigint;
    v_entity_type text;
    v_entity_id   text;
BEGIN
    -- 1. Treasury balance check
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    -- 2. Debit treasury
    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- 3. Create treasury transaction (with category)
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, category_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, p_description, p_category_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- 4. Party balance updates
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
    END IF;

    -- 5. Subledger entry (ledger_entries)
    IF p_customer_id IS NOT NULL THEN
        v_entity_type := 'customer';
        v_entity_id   := p_customer_id::text;
    ELSIF p_supplier_id IS NOT NULL THEN
        v_entity_type := 'supplier';
        v_entity_id   := p_supplier_id::text;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        v_entity_type := 'clearing_agent';
        v_entity_id   := p_clearing_agent_id::text;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        v_entity_type := 'shipping_company';
        v_entity_id   := p_shipping_company_id::text;
    ELSIF p_shareholder_id IS NOT NULL THEN
        v_entity_type := 'shareholder';
        v_entity_id   := p_shareholder_id::text;
    END IF;

    IF v_entity_type IS NOT NULL THEN
        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, description, created_by
        ) VALUES (
            v_entity_type, v_entity_id, 'debit', p_amount, p_currency,
            'expense', v_tx_id, p_description, auth.uid()
        );
    END IF;

    RETURN v_tx_id;
END;
$$;

COMMIT;
