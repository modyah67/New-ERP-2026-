-- ==============================================================================
-- MIGRATION: 20260819_ias21_multicurrency_fx_engine.sql
-- Description: Complete Backend IAS 21 Multi-Currency & FX Engine Implementation
--   - Phase 1: Treasury & Bank Operations (Weighted Average Cost & Book Rate)
--   - Phase 2: Trade AP Payments & Realized FX Gains/Losses (FIFO on 4310/6151)
--   - Phase 3: Period-End Revaluation for Monetary Assets & Liabilities (4320/6152)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- HELPER FUNCTIONS FOR FX ACCOUNTS RESOLUTION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_realized_fx_gain_account(p_company_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT id INTO v_id FROM public.accounts WHERE account_code = '4310' AND (company_id = p_company_id OR company_id IS NULL) LIMIT 1;
    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM public.accounts WHERE account_code = '4310' LIMIT 1;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_realized_fx_loss_account(p_company_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT id INTO v_id FROM public.accounts WHERE account_code = '6151' AND (company_id = p_company_id OR company_id IS NULL) LIMIT 1;
    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM public.accounts WHERE account_code = '6151' LIMIT 1;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_unrealized_fx_gain_account(p_company_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT id INTO v_id FROM public.accounts WHERE account_code = '4320' AND (company_id = p_company_id OR company_id IS NULL) LIMIT 1;
    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM public.accounts WHERE account_code = '4320' LIMIT 1;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_unrealized_fx_loss_account(p_company_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT id INTO v_id FROM public.accounts WHERE account_code = '6152' AND (company_id = p_company_id OR company_id IS NULL) LIMIT 1;
    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM public.accounts WHERE account_code = '6152' LIMIT 1;
    END IF;
    RETURN v_id;
END;
$$;


-- ==============================================================================
-- PHASE 1: TREASURY & BANK OPERATIONS (WEIGHTED AVERAGE COST & BOOK RATE)
-- ==============================================================================

-- Drop legacy conflicting overloads of deposit_treasury
DROP FUNCTION IF EXISTS public.deposit_treasury(integer, text, numeric, text);
DROP FUNCTION IF EXISTS public.deposit_treasury(integer, text, numeric, text, integer);

-- 1.1 Deposit into Treasury (Inbound)
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance NUMERIC := 0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_tx_id BIGINT;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_revenue_acct BIGINT;
    v_desc TEXT;
    v_je_id BIGINT;
    v_source_type TEXT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_snapshot JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock treasury balance row & retrieve current cost_base and book_rate
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
    -- Math: New Cost Base = Old Cost Base + (Deposit Amount * Spot Rate)
    --       New Book Rate = New Cost Base / New Balance
    IF p_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    -- 3. Resolve GL accounts
    v_source_type := CASE WHEN p_revenue_account_id IS NOT NULL THEN 'revenue' ELSE 'opening_balance' END;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع في الخزينة');

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    -- 4. Post Journal Entry
    v_je_id := public.post_journal_entry(
        'treasury_deposit',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct,  'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- 5. Update / Upsert treasury_balances with new balance, cost_base, and book_rate
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (p_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    -- 6. Insert transaction
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_source_type, v_je_id, auth.uid(),
        CASE WHEN p_revenue_account_id IS NOT NULL THEN p_revenue_account_id ELSE NULL END,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$$;


-- 1.2 Deposit into Bank Account (Inbound)
CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_source_type text DEFAULT 'deposit'::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_credit_acct     BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
    -- Math: New Cost Base = Old Cost Base + (Deposit Amount * Spot Rate)
    --       New Book Rate = New Cost Base / New Balance
    IF v_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(v_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'رصيد افتتاحي');
    ELSIF p_entity_type = 'revenue' THEN
        v_source_type := 'revenue';
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيراد');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_credit_acct := NULL;

    IF p_entity_type IS NULL OR p_entity_type = 'opening_balance' THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    ELSIF p_entity_type = 'revenue' THEN
        IF p_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب الإيرادات';
        END IF;
        v_credit_acct := p_revenue_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_credit_acct FROM public.customers WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_credit_acct FROM public.suppliers WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_credit_acct FROM public.clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_credit_acct FROM public.shipping_companies WHERE id = p_entity_id::bigint;
    ELSE
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    IF v_credit_acct IS NULL THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct,  'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE public.bank_accounts 
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END,
        p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate,
        'journal_entry_id', v_je_id
    );
END;
$$;


-- 1.3 Spend Custody from Treasury (Outbound - Uses Book Rate)
CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_customer_id integer DEFAULT NULL::integer,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_clearing_agent_id bigint DEFAULT NULL::bigint,
    p_shipping_company_id bigint DEFAULT NULL::bigint,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_je_source_type  TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock treasury balance row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %, المطلوب: %)', v_current_balance, p_amount;
    END IF;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Use Treasury Book Rate for disbursement in Base Currency (IAS 21)
    -- Math: Base Deducted = Amount * Current Book Rate
    --       New Cost Base = Old Cost Base - Base Deducted
    IF p_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    -- 3. Resolve entity and GL accounts
    IF p_customer_id IS NOT NULL THEN
        v_source_type := 'customer';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لعميل');
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id = p_customer_id;
    ELSIF p_supplier_id IS NOT NULL THEN
        v_source_type := 'supplier';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمورد');
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id = p_supplier_id;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        v_source_type := 'clearing_agent';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمخلص جمركي');
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id = p_clearing_agent_id;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        v_source_type := 'shipping_company';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لشركة شحن');
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id = p_shipping_company_id;
    ELSIF p_shareholder_id IS NOT NULL THEN
        v_source_type := 'shareholder';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف لمساهم');
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_shareholder_id;
    ELSE
        v_source_type := 'expense';
        v_desc := COALESCE(NULLIF(p_description, ''), 'صرف مصروفات');
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id::integer, p_currency, v_company_id);

    -- 4. Update Invoice / Lot reference if provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    -- 5. Distinct Journal Entry source_type
    v_je_source_type := CASE
        WHEN p_supplier_id IS NOT NULL THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_customer_id IS NOT NULL THEN 'customer_refund'
        WHEN p_clearing_agent_id IS NOT NULL THEN 'clearing_agent_payment'
        WHEN p_shipping_company_id IS NOT NULL THEN 'shipping_company_payment'
        WHEN p_shareholder_id IS NOT NULL THEN 'shareholder_withdrawal'
        ELSE 'expense_payment'
    END;

    -- 6. Post balanced Journal Entry with base amounts calculated at book_rate
    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct,  'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        ),
        p_source_id := p_reference_id
    );

    -- 7. Update treasury balances (balance, cost_base, book_rate)
    UPDATE public.treasury_balances
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency;

    -- 8. Insert transaction snapshot
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'treasury_book_rate'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after,
        description, created_by, customer_id, supplier_id, clearing_agent_id,
        shipping_company_id, shareholder_id, source_type, journal_entry_id,
        expense_account_id, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'expense', p_currency, p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_customer_id, p_supplier_id, p_clearing_agent_id,
        p_shipping_company_id, p_shareholder_id, v_source_type, v_je_id,
        v_expense_acct, v_book_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    -- 9. Update Counterparty Balances
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
    ELSIF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
    ELSIF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_clearing_agent_id;
    ELSIF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_shipping_company_id;
    ELSIF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
    END IF;

    RETURN v_tx_id;
END;
$$;


-- 1.4 Withdraw from Bank Account (Outbound - Uses Book Rate)
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_je_source_type  TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id 
    INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية (الرصيد الحالي: %)', v_current_balance;
    END IF;

    -- 2. Use Bank Account Book Rate for disbursement in Base Currency (IAS 21)
    -- Math: Base Deducted = Amount * Current Book Rate
    --       New Cost Base = Old Cost Base - Base Deducted
    IF v_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(v_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب رصيد افتتاحي من الحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id::TEXT = p_entity_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    UPDATE public.bank_accounts
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    -- Update Purchase Invoice or Lot Receipt if reference provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    -- Distinct Journal Entry source_type resolution
    v_je_source_type := CASE
        WHEN p_entity_type = 'supplier' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_entity_type = 'shareholder' THEN 'shareholder_payment_received'
        ELSE 'bank_withdrawal'
    END;

    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct,    'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        ),
        p_source_id := p_reference_id
    );

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'bank_book_rate'
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, created_at, created_by, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_current_balance, v_new_balance,
        v_desc, p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id, NOW(), auth.uid(), p_notes,
        v_book_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id::TEXT = p_entity_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$$;


-- ==============================================================================
-- PHASE 2: TRADE AP PAYMENTS & REALIZED FX (THE CORE FIX)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_supplier_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_supplier_id uuid,
    p_description text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
    v_je_id BIGINT;
    v_company_id UUID;
    v_source_acct BIGINT;
    v_supplier_acct BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_book_rate NUMERIC := 1.0;
    v_remaining_to_allocate NUMERIC := p_amount;
    v_inv RECORD;
    v_allocation_amount NUMERIC;
    v_inv_rate NUMERIC;
    v_inv_base NUMERIC;
    v_paid_base NUMERIC;
    v_diff NUMERIC;
    v_total_realized_gain NUMERIC := 0.0;
    v_total_realized_loss NUMERIC := 0.0;
    v_total_ap_base NUMERIC := 0.0;
    v_total_cash_base NUMERIC := 0.0;
    v_initial_balance NUMERIC := 0;
    v_initial_direction TEXT := 'CREDIT';
    v_opening_paid NUMERIC := 0;
    v_opening_remaining NUMERIC := 0;
    v_opening_alloc NUMERIC := 0;
    v_advance_alloc NUMERIC := 0;
    v_invoices_allocated_count INT := 0;
    v_je_lines JSONB := '[]'::jsonb;
    v_supplier_name TEXT;
    v_source_name TEXT;
    v_desc TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Fetch supplier info & GL account
    SELECT 
        name,
        COALESCE(initial_balance, 0),
        COALESCE(initial_balance_direction, 'CREDIT'),
        company_id,
        account_id
    INTO v_supplier_name, v_initial_balance, v_initial_direction, v_company_id, v_supplier_acct
    FROM public.suppliers
    WHERE id = p_supplier_id;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_supplier_acct IS NULL THEN
        v_supplier_acct := public.resolve_gl_account('2000', v_company_id);
    END IF;

    -- 2. Resolve Source Book Rate and GL Account
    IF p_source_type = 'treasury' THEN
        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.treasury_balances
        WHERE treasury_id::text = p_source_id::text AND currency = p_currency;

        SELECT name INTO v_source_name FROM public.treasuries WHERE id = p_source_id;
        v_source_acct := public.resolve_treasury_account(p_source_id::integer, p_currency, v_company_id);
    ELSIF p_source_type = 'bank' THEN
        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.bank_accounts
        WHERE id = p_source_id::integer;

        SELECT name INTO v_source_name FROM public.bank_accounts WHERE id = p_source_id::integer;
        v_source_acct := public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );
    ELSE
        RAISE EXCEPTION 'نوع المصدر غير صالح: %', p_source_type;
    END IF;

    IF v_book_rate IS NULL OR v_book_rate <= 0 THEN
        v_book_rate := public.fn_get_exchange_rate(p_currency);
    END IF;

    v_total_cash_base := ROUND(p_amount * v_book_rate, 2);

    -- 3. Execute the cash payment transaction from treasury or bank
    IF p_source_type = 'treasury' THEN
        v_tx_id := public.spend_custody(
            p_treasury_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := p_description,
            p_supplier_id := p_supplier_id,
            p_expense_account_id := COALESCE(p_expense_account_id, v_supplier_acct::integer),
            p_notes := p_notes
        );
    ELSIF p_source_type = 'bank' THEN
        DECLARE
            v_bank_res JSONB;
        BEGIN
            v_bank_res := public.withdraw_bank_account(
                p_account_id := p_source_id::INTEGER,
                p_amount := p_amount,
                p_description := p_description,
                p_entity_type := 'supplier'::TEXT,
                p_entity_id := p_supplier_id::TEXT,
                p_counterparty_name := v_supplier_name,
                p_expense_account_id := COALESCE(p_expense_account_id, v_supplier_acct::integer),
                p_notes := p_notes,
                p_reference_type := 'supplier_payment'::TEXT,
                p_reference_id := p_supplier_id::TEXT
            );
            v_tx_id := (v_bank_res->>'transaction_id')::BIGINT;
        END;
    END IF;

    -- 4. Calculate previously paid opening balance
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

    -- 5. Allocation Priority 1: Opening Balance
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

        -- Opening balance settled at book rate (no realized gain/loss unless specific pegged rate)
        v_total_ap_base := v_total_ap_base + ROUND(v_opening_alloc * v_book_rate, 2);
        v_remaining_to_allocate := v_remaining_to_allocate - v_opening_alloc;
    END IF;

    -- 6. Allocation Priority 2: Unpaid Purchase Invoices (FIFO by invoice_date)
    FOR v_inv IN 
        SELECT id, invoice_number, currency, currency_snapshot, (total_amount - discount_amount - paid_amount) as due_amount
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

        -- Extract Invoice Original Pegged Exchange Rate
        v_inv_rate := COALESCE(
            (v_inv.currency_snapshot->>'exchange_rate')::NUMERIC,
            public.fn_get_exchange_rate(p_currency)
        );

        -- Realized FX Math (IAS 21):
        -- Invoice Base Liability Settled = Allocation * Invoice Rate
        -- Cash Outflow Base = Allocation * Treasury Book Rate
        -- Realized FX Diff = Cash Outflow Base - Invoice Base Settled
        v_inv_base  := ROUND(v_allocation_amount * v_inv_rate, 2);
        v_paid_base := ROUND(v_allocation_amount * v_book_rate, 2);
        v_diff      := v_paid_base - v_inv_base;

        v_total_ap_base := v_total_ap_base + v_inv_base;

        IF v_diff < 0 THEN
            -- Paid less base currency to extinguish liability -> Realized Gain
            v_total_realized_gain := v_total_realized_gain + ABS(v_diff);
        ELSIF v_diff > 0 THEN
            -- Paid more base currency to extinguish liability -> Realized Loss
            v_total_realized_loss := v_total_realized_loss + v_diff;
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
            payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
            payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
            payment_source_type = p_source_type
        WHERE id = v_inv.id;

        v_invoices_allocated_count := v_invoices_allocated_count + 1;
        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- 7. Allocation Priority 3: Advance Payment / Credit Balance
    IF v_remaining_to_allocate > 0 THEN
        v_advance_alloc := v_remaining_to_allocate;
        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
        ) VALUES (
            p_source_type, v_tx_id, NULL, p_supplier_id, 'advance', v_advance_alloc
        );
        v_total_ap_base := v_total_ap_base + ROUND(v_advance_alloc * v_book_rate, 2);
    END IF;

    -- 8. Post / Adjust GL Journal Entry for Realized FX Differences
    -- If FX Gain or Loss exists, post the Realized FX entry
    IF v_total_realized_gain > 0 OR v_total_realized_loss > 0 THEN
        v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
        v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);

        v_desc := COALESCE(NULLIF(p_description, ''), 'سداد فواتير مورد مع تسوية فروق عملة محققة: ' || v_supplier_name);

        -- Build balanced multi-line journal entry:
        -- Dr. Supplier AP (v_supplier_acct) -> v_total_ap_base
        -- Dr. Realized FX Loss (if any)     -> v_total_realized_loss
        -- Cr. Cash / Bank (v_source_acct)   -> v_total_cash_base
        -- Cr. Realized FX Gain (if any)     -> v_total_realized_gain
        v_je_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_supplier_acct,
                'debit', p_amount,
                'credit', 0,
                'base_debit', v_total_ap_base,
                'base_credit', 0,
                'currency', p_currency,
                'description', v_desc || ' (تسوية ذمم دائنة)'
            )
        );

        IF v_total_realized_loss > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_realized_loss,
                    'credit', 0,
                    'base_debit', v_total_realized_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - سداد مورد ' || v_supplier_name
                )
            );
        END IF;

        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_source_acct,
                'debit', 0,
                'credit', p_amount,
                'base_debit', 0,
                'base_credit', v_total_cash_base,
                'currency', p_currency,
                'description', v_desc || ' (صرف من ' || v_source_name || ')'
            )
        );

        IF v_total_realized_gain > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_realized_gain,
                    'base_debit', 0,
                    'base_credit', v_total_realized_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - سداد مورد ' || v_supplier_name
                )
            );
        END IF;

        v_je_id := public.post_journal_entry(
            'supplier_payment',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines,
            p_supplier_id::text
        );

        -- Link the journal entry to the transaction
        IF p_source_type = 'treasury' THEN
            UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        ELSIF p_source_type = 'bank' THEN
            UPDATE public.bank_account_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        END IF;
    ELSE
        -- Retrieve JE id from transaction
        IF p_source_type = 'treasury' THEN
            SELECT journal_entry_id INTO v_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
        ELSIF p_source_type = 'bank' THEN
            SELECT journal_entry_id INTO v_je_id FROM public.bank_account_transactions WHERE id = v_tx_id;
        END IF;
    END IF;

    -- 9. Recalculate & update supplier outstanding_balance
    UPDATE public.suppliers
    SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = p_supplier_id)
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'opening_balance_allocated', v_opening_alloc,
        'invoices_allocated_count', v_invoices_allocated_count,
        'invoices_allocated_amount', p_amount - v_opening_alloc - v_advance_alloc,
        'advance_amount', v_advance_alloc,
        'realized_fx_gain', v_total_realized_gain,
        'realized_fx_loss', v_total_realized_loss
    );
END;
$$;


-- ==============================================================================
-- PHASE 3: PERIOD-END REVALUATION (UNREALIZED FX FOR AR/AP & MONETARY ITEMS)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_revalue_period_end_fx(
    p_period_date date,
    p_revaluation_type text DEFAULT 'month_end'::text,
    p_company_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id UUID := COALESCE(p_company_id, (SELECT id FROM public.sys_companies LIMIT 1));
    v_user_id UUID := auth.uid();
    v_tb RECORD;
    v_ba RECORD;
    v_cust RECORD;
    v_supp RECORD;
    v_sc RECORD;
    v_ca RECORD;
    v_closing_rate NUMERIC;
    v_book_base NUMERIC;
    v_revalued_base NUMERIC;
    v_diff NUMERIC;
    v_total_gain NUMERIC := 0.0;
    v_total_loss NUMERIC := 0.0;
    v_je_id BIGINT;
    v_unrealized_gain_acct BIGINT;
    v_unrealized_loss_acct BIGINT;
    v_target_acct BIGINT;
    v_lines JSONB := '[]'::jsonb;
    v_reval_count INT := 0;
BEGIN
    v_unrealized_gain_acct := public.resolve_unrealized_fx_gain_account(v_company_id);
    v_unrealized_loss_acct := public.resolve_unrealized_fx_loss_account(v_company_id);

    -- --------------------------------------------------------------------------
    -- 1. Revalue Foreign Currency Treasury Balances (Monetary Cash)
    -- --------------------------------------------------------------------------
    FOR v_tb IN 
        SELECT tb.id, tb.treasury_id, tb.currency, tb.balance, COALESCE(tb.cost_base, 0) as cost_base, t.name as treasury_name
        FROM public.treasury_balances tb
        JOIN public.treasuries t ON t.id = tb.treasury_id
        WHERE tb.currency != 'EGP' AND tb.balance > 0
    LOOP
        v_closing_rate := public.fn_get_exchange_rate(v_tb.currency);
        v_revalued_base := ROUND(v_tb.balance * v_closing_rate, 2);
        v_diff := v_revalued_base - v_tb.cost_base;

        IF v_diff != 0 THEN
            v_reval_count := v_reval_count + 1;
            v_target_acct := public.resolve_gl_account(
                CASE v_tb.currency WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
                v_company_id
            );

            INSERT INTO public.fx_revaluations (
                revaluation_date, revaluation_type, currency, closing_rate,
                source_type, source_id, source_name, foreign_balance,
                book_value_base, revalued_value_base, unrealized_gain_loss,
                company_id, created_by
            ) VALUES (
                p_period_date, p_revaluation_type, v_tb.currency, v_closing_rate,
                'treasury', v_tb.treasury_id::text, v_tb.treasury_name, v_tb.balance,
                v_tb.cost_base, v_revalued_base, v_diff,
                v_company_id, v_user_id
            );

            IF v_diff > 0 THEN
                v_total_gain := v_total_gain + v_diff;
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_target_acct, 'debit', v_diff, 'credit', 0, 'base_debit', v_diff, 'base_credit', 0, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - ' || v_tb.treasury_name),
                    jsonb_build_object('account_id', v_unrealized_gain_acct, 'debit', 0, 'credit', v_diff, 'base_debit', 0, 'base_credit', v_diff, 'currency', 'EGP', 'description', 'أرباح فروق أسعار عملة غير محققة - ' || v_tb.treasury_name)
                );
            ELSE
                v_total_loss := v_total_loss + ABS(v_diff);
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_unrealized_loss_acct, 'debit', ABS(v_diff), 'credit', 0, 'base_debit', ABS(v_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق أسعار عملة غير محققة - ' || v_tb.treasury_name),
                    jsonb_build_object('account_id', v_target_acct, 'debit', 0, 'credit', ABS(v_diff), 'base_debit', 0, 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - ' || v_tb.treasury_name)
                );
            END IF;
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 2. Revalue Foreign Currency Bank Accounts (Monetary Bank)
    -- --------------------------------------------------------------------------
    FOR v_ba IN 
        SELECT ba.id, ba.name, ba.currency, ba.balance, COALESCE(ba.cost_base, 0) as cost_base
        FROM public.bank_accounts ba
        WHERE ba.currency != 'EGP' AND ba.balance > 0 AND ba.deleted_at IS NULL
    LOOP
        v_closing_rate := public.fn_get_exchange_rate(v_ba.currency);
        v_revalued_base := ROUND(v_ba.balance * v_closing_rate, 2);
        v_diff := v_revalued_base - v_ba.cost_base;

        IF v_diff != 0 THEN
            v_reval_count := v_reval_count + 1;
            v_target_acct := public.resolve_gl_account(
                CASE v_ba.currency WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
                v_company_id
            );

            INSERT INTO public.fx_revaluations (
                revaluation_date, revaluation_type, currency, closing_rate,
                source_type, source_id, source_name, foreign_balance,
                book_value_base, revalued_value_base, unrealized_gain_loss,
                company_id, created_by
            ) VALUES (
                p_period_date, p_revaluation_type, v_ba.currency, v_closing_rate,
                'bank', v_ba.id::text, v_ba.name, v_ba.balance,
                v_ba.cost_base, v_revalued_base, v_diff,
                v_company_id, v_user_id
            );

            IF v_diff > 0 THEN
                v_total_gain := v_total_gain + v_diff;
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_target_acct, 'debit', v_diff, 'credit', 0, 'base_debit', v_diff, 'base_credit', 0, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - ' || v_ba.name),
                    jsonb_build_object('account_id', v_unrealized_gain_acct, 'debit', 0, 'credit', v_diff, 'base_debit', 0, 'base_credit', v_diff, 'currency', 'EGP', 'description', 'أرباح فروق أسعار عملة غير محققة - ' || v_ba.name)
                );
            ELSE
                v_total_loss := v_total_loss + ABS(v_diff);
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_unrealized_loss_acct, 'debit', ABS(v_diff), 'credit', 0, 'base_debit', ABS(v_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق أسعار عملة غير محققة - ' || v_ba.name),
                    jsonb_build_object('account_id', v_target_acct, 'debit', 0, 'credit', ABS(v_diff), 'base_debit', 0, 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - ' || v_ba.name)
                );
            END IF;
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 3. Revalue Foreign Currency Customers (Monetary AR - Account 1020)
    -- --------------------------------------------------------------------------
    FOR v_cust IN
        SELECT c.id, c.name, c.currency, c.balance, c.account_id, c.initial_balance_snapshot
        FROM public.customers c
        WHERE c.currency IS NOT NULL AND c.currency != 'EGP' AND c.balance != 0 AND c.deleted_at IS NULL
    LOOP
        v_closing_rate := public.fn_get_exchange_rate(v_cust.currency);
        v_revalued_base := ROUND(v_cust.balance * v_closing_rate, 2);

        -- Retrieve current base book value from account ledger entries or fallback
        IF v_cust.account_id IS NOT NULL THEN
            SELECT COALESCE(SUM(debit - credit), 0) INTO v_book_base
            FROM public.account_ledger_entries
            WHERE account_id = v_cust.account_id;
            
            IF v_book_base = 0 THEN
                v_book_base := ROUND(v_cust.balance * COALESCE((v_cust.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            END IF;
            v_target_acct := v_cust.account_id;
        ELSE
            v_book_base := ROUND(v_cust.balance * COALESCE((v_cust.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            v_target_acct := public.resolve_gl_account('1020', v_company_id);
        END IF;

        v_diff := v_revalued_base - v_book_base;

        IF v_diff != 0 THEN
            v_reval_count := v_reval_count + 1;

            INSERT INTO public.fx_revaluations (
                revaluation_date, revaluation_type, currency, closing_rate,
                source_type, source_id, source_name, foreign_balance,
                book_value_base, revalued_value_base, unrealized_gain_loss,
                company_id, created_by
            ) VALUES (
                p_period_date, p_revaluation_type, v_cust.currency, v_closing_rate,
                'customer', v_cust.id::text, v_cust.name, v_cust.balance,
                v_book_base, v_revalued_base, v_diff,
                v_company_id, v_user_id
            );

            IF v_diff > 0 THEN
                -- AR asset increased in EGP -> Unrealized Gain
                v_total_gain := v_total_gain + v_diff;
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_target_acct, 'debit', v_diff, 'credit', 0, 'base_debit', v_diff, 'base_credit', 0, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - عميل ' || v_cust.name),
                    jsonb_build_object('account_id', v_unrealized_gain_acct, 'debit', 0, 'credit', v_diff, 'base_debit', 0, 'base_credit', v_diff, 'currency', 'EGP', 'description', 'أرباح فروق أسعار عملة غير محققة - عميل ' || v_cust.name)
                );
            ELSE
                -- AR asset decreased in EGP -> Unrealized Loss
                v_total_loss := v_total_loss + ABS(v_diff);
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_unrealized_loss_acct, 'debit', ABS(v_diff), 'credit', 0, 'base_debit', ABS(v_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق أسعار عملة غير محققة - عميل ' || v_cust.name),
                    jsonb_build_object('account_id', v_target_acct, 'debit', 0, 'credit', ABS(v_diff), 'base_debit', 0, 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - عميل ' || v_cust.name)
                );
            END IF;
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 4. Revalue Foreign Currency Suppliers (Monetary AP - Account 2000)
    -- --------------------------------------------------------------------------
    FOR v_supp IN
        SELECT s.id, s.name, s.currency, s.outstanding_balance, s.account_id, s.initial_balance_snapshot
        FROM public.suppliers s
        WHERE s.currency IS NOT NULL AND s.currency != 'EGP' AND s.outstanding_balance != 0 AND s.deleted_at IS NULL
    LOOP
        v_closing_rate := public.fn_get_exchange_rate(v_supp.currency);
        v_revalued_base := ROUND(v_supp.outstanding_balance * v_closing_rate, 2);

        IF v_supp.account_id IS NOT NULL THEN
            SELECT COALESCE(SUM(credit - debit), 0) INTO v_book_base
            FROM public.account_ledger_entries
            WHERE account_id = v_supp.account_id;

            IF v_book_base = 0 THEN
                v_book_base := ROUND(v_supp.outstanding_balance * COALESCE((v_supp.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            END IF;
            v_target_acct := v_supp.account_id;
        ELSE
            v_book_base := ROUND(v_supp.outstanding_balance * COALESCE((v_supp.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            v_target_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;

        v_diff := v_revalued_base - v_book_base;

        IF v_diff != 0 THEN
            v_reval_count := v_reval_count + 1;

            INSERT INTO public.fx_revaluations (
                revaluation_date, revaluation_type, currency, closing_rate,
                source_type, source_id, source_name, foreign_balance,
                book_value_base, revalued_value_base, unrealized_gain_loss,
                company_id, created_by
            ) VALUES (
                p_period_date, p_revaluation_type, v_supp.currency, v_closing_rate,
                'supplier', v_supp.id::text, v_supp.name, v_supp.outstanding_balance,
                v_book_base, v_revalued_base, -v_diff,
                v_company_id, v_user_id
            );

            IF v_diff > 0 THEN
                -- AP liability increased in EGP -> Unrealized Loss
                v_total_loss := v_total_loss + v_diff;
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_unrealized_loss_acct, 'debit', v_diff, 'credit', 0, 'base_debit', v_diff, 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق أسعار عملة غير محققة - مورد ' || v_supp.name),
                    jsonb_build_object('account_id', v_target_acct, 'debit', 0, 'credit', v_diff, 'base_debit', 0, 'base_credit', v_diff, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - مورد ' || v_supp.name)
                );
            ELSE
                -- AP liability decreased in EGP -> Unrealized Gain
                v_total_gain := v_total_gain + ABS(v_diff);
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_target_acct, 'debit', ABS(v_diff), 'credit', 0, 'base_debit', ABS(v_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - مورد ' || v_supp.name),
                    jsonb_build_object('account_id', v_unrealized_gain_acct, 'debit', 0, 'credit', ABS(v_diff), 'base_debit', 0, 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', 'أرباح فروق أسعار عملة غير محققة - مورد ' || v_supp.name)
                );
            END IF;
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 5. Revalue Foreign Currency Shipping Companies (Freight AP - Account 2103)
    -- --------------------------------------------------------------------------
    FOR v_sc IN
        SELECT sc.id, sc.name, sc.currency, sc.balance, sc.account_id, sc.initial_balance_snapshot
        FROM public.shipping_companies sc
        WHERE sc.currency IS NOT NULL AND sc.currency != 'EGP' AND sc.balance != 0
    LOOP
        v_closing_rate := public.fn_get_exchange_rate(v_sc.currency);
        v_revalued_base := ROUND(v_sc.balance * v_closing_rate, 2);

        IF v_sc.account_id IS NOT NULL THEN
            SELECT COALESCE(SUM(credit - debit), 0) INTO v_book_base
            FROM public.account_ledger_entries
            WHERE account_id = v_sc.account_id;

            IF v_book_base = 0 THEN
                v_book_base := ROUND(v_sc.balance * COALESCE((v_sc.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            END IF;
            v_target_acct := v_sc.account_id;
        ELSE
            v_book_base := ROUND(v_sc.balance * COALESCE((v_sc.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            v_target_acct := public.resolve_gl_account('2103', v_company_id);
        END IF;

        v_diff := v_revalued_base - v_book_base;

        IF v_diff != 0 THEN
            v_reval_count := v_reval_count + 1;

            INSERT INTO public.fx_revaluations (
                revaluation_date, revaluation_type, currency, closing_rate,
                source_type, source_id, source_name, foreign_balance,
                book_value_base, revalued_value_base, unrealized_gain_loss,
                company_id, created_by
            ) VALUES (
                p_period_date, p_revaluation_type, v_sc.currency, v_closing_rate,
                'shipping_company', v_sc.id::text, v_sc.name, v_sc.balance,
                v_book_base, v_revalued_base, -v_diff,
                v_company_id, v_user_id
            );

            IF v_diff > 0 THEN
                v_total_loss := v_total_loss + v_diff;
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_unrealized_loss_acct, 'debit', v_diff, 'credit', 0, 'base_debit', v_diff, 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق أسعار عملة غير محققة - شركة شحن ' || v_sc.name),
                    jsonb_build_object('account_id', v_target_acct, 'debit', 0, 'credit', v_diff, 'base_debit', 0, 'base_credit', v_diff, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - شركة شحن ' || v_sc.name)
                );
            ELSE
                v_total_gain := v_total_gain + ABS(v_diff);
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_target_acct, 'debit', ABS(v_diff), 'credit', 0, 'base_debit', ABS(v_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - شركة شحن ' || v_sc.name),
                    jsonb_build_object('account_id', v_unrealized_gain_acct, 'debit', 0, 'credit', ABS(v_diff), 'base_debit', 0, 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', 'أرباح فروق أسعار عملة غير محققة - شركة شحن ' || v_sc.name)
                );
            END IF;
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 6. Revalue Foreign Currency Clearing Agents (Customs AP - Account 2104)
    -- --------------------------------------------------------------------------
    FOR v_ca IN
        SELECT ca.id, ca.name, ca.currency, ca.balance, ca.account_id, ca.initial_balance_snapshot
        FROM public.clearing_agents ca
        WHERE ca.currency IS NOT NULL AND ca.currency != 'EGP' AND ca.balance != 0
    LOOP
        v_closing_rate := public.fn_get_exchange_rate(v_ca.currency);
        v_revalued_base := ROUND(v_ca.balance * v_closing_rate, 2);

        IF v_ca.account_id IS NOT NULL THEN
            SELECT COALESCE(SUM(credit - debit), 0) INTO v_book_base
            FROM public.account_ledger_entries
            WHERE account_id = v_ca.account_id;

            IF v_book_base = 0 THEN
                v_book_base := ROUND(v_ca.balance * COALESCE((v_ca.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            END IF;
            v_target_acct := v_ca.account_id;
        ELSE
            v_book_base := ROUND(v_ca.balance * COALESCE((v_ca.initial_balance_snapshot->>'exchange_rate')::NUMERIC, v_closing_rate), 2);
            v_target_acct := public.resolve_gl_account('2104', v_company_id);
        END IF;

        v_diff := v_revalued_base - v_book_base;

        IF v_diff != 0 THEN
            v_reval_count := v_reval_count + 1;

            INSERT INTO public.fx_revaluations (
                revaluation_date, revaluation_type, currency, closing_rate,
                source_type, source_id, source_name, foreign_balance,
                book_value_base, revalued_value_base, unrealized_gain_loss,
                company_id, created_by
            ) VALUES (
                p_period_date, p_revaluation_type, v_ca.currency, v_closing_rate,
                'clearing_agent', v_ca.id::text, v_ca.name, v_ca.balance,
                v_book_base, v_revalued_base, -v_diff,
                v_company_id, v_user_id
            );

            IF v_diff > 0 THEN
                v_total_loss := v_total_loss + v_diff;
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_unrealized_loss_acct, 'debit', v_diff, 'credit', 0, 'base_debit', v_diff, 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق أسعار عملة غير محققة - مخلص جمركي ' || v_ca.name),
                    jsonb_build_object('account_id', v_target_acct, 'debit', 0, 'credit', v_diff, 'base_debit', 0, 'base_credit', v_diff, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - مخلص جمركي ' || v_ca.name)
                );
            ELSE
                v_total_gain := v_total_gain + ABS(v_diff);
                v_lines := v_lines || jsonb_build_array(
                    jsonb_build_object('account_id', v_target_acct, 'debit', ABS(v_diff), 'credit', 0, 'base_debit', ABS(v_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'إعادة تقييم فروق عملة غير محققة - مخلص جمركي ' || v_ca.name),
                    jsonb_build_object('account_id', v_unrealized_gain_acct, 'debit', 0, 'credit', ABS(v_diff), 'base_debit', 0, 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', 'أرباح فروق أسعار عملة غير محققة - مخلص جمركي ' || v_ca.name)
                );
            END IF;
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 7. Post Summary Journal Entry if differences exist
    -- --------------------------------------------------------------------------
    IF jsonb_array_length(v_lines) > 0 THEN
        v_je_id := public.post_journal_entry(
            'period_end_fx_revaluation',
            'إعادة تقييم فروق أسعار العملات غير المحققة للفترة المنتهية في ' || p_period_date,
            p_period_date,
            v_company_id,
            v_user_id,
            v_lines
        );

        UPDATE public.fx_revaluations
        SET journal_entry_id = v_je_id
        WHERE revaluation_date = p_period_date AND journal_entry_id IS NULL;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'revaluation_date', p_period_date,
        'revalued_items_count', v_reval_count,
        'total_unrealized_gain', v_total_gain,
        'total_unrealized_loss', v_total_loss,
        'net_unrealized_gain_loss', v_total_gain - v_total_loss,
        'journal_entry_id', v_je_id
    );
END;
$$;
