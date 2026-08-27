-- ============================================================================
-- Migration 372: Fix Treasury Weighted Average Cost Base & Book Rate (IAS 21)
-- ============================================================================
-- Description:
-- 0. Expands type check constraints on treasury_transactions and bank_account_transactions.
-- 1. Updates receive_payment to properly compute & maintain cost_base and book_rate in treasury_balances.
-- 2. Updates exchange_currency to maintain cost_base and book_rate across conversions.
-- 3. Recalculates current treasury_balances cost_base and book_rate from confirmed historical deposits.
-- ============================================================================

-- 0. Expand check constraint for treasury_transactions & bank_account_transactions
ALTER TABLE public.treasury_transactions 
    DROP CONSTRAINT IF EXISTS treasury_transactions_type_check;

ALTER TABLE public.treasury_transactions 
    ADD CONSTRAINT treasury_transactions_type_check 
    CHECK (type = ANY (ARRAY[
        'deposit',
        'expense',
        'withdrawal',
        'withdraw',
        'disbursement',
        'disbursement_out',
        'transfer_in',
        'transfer_out',
        'transfer',
        'return_in',
        'return_out',
        'currency_exchange_out',
        'currency_exchange_in',
        'currency_exchange',
        'exchange',
        'exchange_out',
        'exchange_in',
        'supplier_payment',
        'customer_payment',
        'clearing_agent_payment',
        'shipping_company_payment',
        'shareholder_payment',
        'shareholder_withdrawal',
        'customer_refund',
        'revenue',
        'multi_payment',
        'receipt'
    ]));

ALTER TABLE public.bank_account_transactions 
    DROP CONSTRAINT IF EXISTS bank_account_transactions_type_check;

ALTER TABLE public.bank_account_transactions 
    ADD CONSTRAINT bank_account_transactions_type_check 
    CHECK (type = ANY (ARRAY[
        'deposit',
        'withdraw',
        'withdrawal',
        'exchange_in',
        'exchange_out',
        'currency_exchange_in',
        'currency_exchange_out',
        'currency_exchange',
        'exchange',
        'transfer_in',
        'transfer_out',
        'transfer',
        'supplier_payment',
        'customer_payment',
        'clearing_agent_payment',
        'shipping_company_payment',
        'shareholder_payment',
        'shareholder_withdrawal',
        'customer_refund',
        'revenue',
        'multi_payment',
        'receipt',
        'expense'
    ]));

-- 1. Update receive_payment RPC
CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type character varying,
    p_amount numeric,
    p_currency character varying,
    p_counterparty_type character varying DEFAULT NULL::character varying,
    p_counterparty_id bigint DEFAULT NULL::bigint,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_description text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_treasury_id bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_treasury_id       BIGINT;
    v_current_balance   NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance       NUMERIC := 0;
    v_new_cost_base     NUMERIC := 0;
    v_new_book_rate     NUMERIC := 1.0;
    v_tx_id             BIGINT;
    v_company_id        UUID;
    v_treasury_acct     BIGINT;
    v_ar_acct           BIGINT;
    v_je_id             BIGINT;
    v_desc              TEXT;
    v_source_type       TEXT;
    v_treasury_name     TEXT;
    v_je_source         TEXT;
    v_credit_acct       BIGINT;
    v_rate              NUMERIC := 1.0;
    v_base_amount       NUMERIC;
    v_snapshot          JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_treasury_id IS NOT NULL THEN
        v_treasury_id := p_treasury_id;
    ELSE
        SELECT id INTO v_treasury_id
        FROM public.treasuries
        WHERE type = 'main' AND user_id = auth.uid()
        LIMIT 1;
        IF v_treasury_id IS NULL THEN
            SELECT id INTO v_treasury_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        END IF;
        IF v_treasury_id IS NULL THEN
            RAISE EXCEPTION 'لم يتم العثور على الخزينة الرئيسية.';
        END IF;
    END IF;

    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = v_treasury_id;

    -- 1. Lock treasury balance row & retrieve current cost_base and book_rate
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = v_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    -- 2. Calculate spot exchange rate & base amount
    -- Weighted Average: New Cost Base = Old Cost Base + (Deposit Amount * Spot Rate)
    --                   New Book Rate = New Cost Base / New Balance
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

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    IF p_counterparty_type IS NULL OR p_counterparty_type = 'opening' THEN
        v_source_type := 'opening_balance';
        SELECT name INTO v_treasury_name FROM public.treasuries WHERE id = v_treasury_id;
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
        );
    ELSE
        v_source_type := p_counterparty_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'استلام ' || p_receipt_type);
    END IF;

    v_treasury_acct := public.resolve_treasury_account(v_treasury_id, p_currency, v_company_id);

    IF p_counterparty_type = 'customer' THEN
        SELECT c.account_id INTO v_credit_acct FROM public.customers c WHERE c.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('1020', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'supplier' THEN
        SELECT s.account_id INTO v_credit_acct FROM public.suppliers s WHERE s.id = p_supplier_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'clearing_agent' THEN
        SELECT ca.account_id INTO v_credit_acct FROM public.clearing_agents ca WHERE ca.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shipping_company' THEN
        SELECT sc.account_id INTO v_credit_acct FROM public.shipping_companies sc WHERE sc.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id = p_shareholder_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
        END IF;
    ELSE
        -- Route opening balance to Opening Balance Equity (3901-3904)
        v_credit_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

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
        treasury_id, type, amount, currency, description, source_type,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        created_by, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc, v_source_type,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        v_current_balance, v_new_balance,
        auth.uid(),
        v_credit_acct, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id = p_supplier_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'supplier_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'clearing_agent_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shipping_company_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shareholder' AND p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_shareholder_id;
        END IF;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shareholder_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSE
        v_je_source := 'opening_balance';
        v_je_id := public.post_journal_entry(
            v_je_source, v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    -- Sync treasury_balances with full cost_base and book_rate
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (v_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    RETURN jsonb_build_object('success', true, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$function$;


-- 2. Update exchange_currency RPC
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id text,
    p_from_currency character varying,
    p_to_currency character varying,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid,
    p_transfer_mode text DEFAULT 'exchange'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_treasury_id         BIGINT := p_treasury_id::bigint;
    v_balance_before_from DECIMAL(15,2);
    v_balance_after_from  DECIMAL(15,2);
    v_cost_before_from    DECIMAL(15,2);
    v_rate_before_from    DECIMAL(15,4);
    v_new_cost_from       DECIMAL(15,2);
    v_new_rate_from       DECIMAL(15,4);

    v_balance_before_to   DECIMAL(15,2);
    v_balance_after_to    DECIMAL(15,2);
    v_cost_before_to      DECIMAL(15,2);
    v_rate_before_to      DECIMAL(15,4);
    v_new_cost_to         DECIMAL(15,2);
    v_new_rate_to         DECIMAL(15,4);

    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_fx_gain_loss_acct   BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
    v_base_amount         NUMERIC;
    v_cost_base_released  NUMERIC;
    v_realized_fx_diff    NUMERIC;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    IF p_from_currency != 'EGP' AND p_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
    END IF;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_from, v_cost_before_from, v_rate_before_from
    FROM treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_from_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate)
    VALUES (v_treasury_id, p_to_currency, 0.00, 0.00, 1.0000)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_to, v_cost_before_to, v_rate_before_to
    FROM treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_to_currency
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = v_treasury_id;

    v_desc := 'تحويل عملة من ' || p_from_currency || ' إلى ' || p_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE p_from_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE p_to_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    IF p_from_currency != 'EGP' THEN
        -- Selling foreign currency
        v_cost_base_released := ROUND(p_amount_from * v_rate_before_from, 2);
        v_new_cost_from := GREATEST(0, v_cost_before_from - v_cost_base_released);
        v_new_rate_from := CASE WHEN v_balance_after_from > 0 THEN ROUND(v_new_cost_from / v_balance_after_from, 4) ELSE v_rate_before_from END;

        v_new_cost_to := v_balance_after_to;
        v_new_rate_to := 1.0;
        v_realized_fx_diff := p_amount_to - v_cost_base_released;
    ELSE
        -- Buying foreign currency
        v_new_cost_from := v_balance_after_from;
        v_new_rate_from := 1.0;

        v_new_cost_to := v_cost_before_to + p_amount_from;
        v_new_rate_to := CASE WHEN v_balance_after_to > 0 THEN ROUND(v_new_cost_to / v_balance_after_to, 4) ELSE p_exchange_rate END;
        v_realized_fx_diff := 0;
    END IF;

    UPDATE treasury_balances
    SET balance = v_balance_after_from,
        cost_base = v_new_cost_from,
        book_rate = v_new_rate_from,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to,
        cost_base = v_new_cost_to,
        book_rate = v_new_rate_to,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND currency = p_to_currency;

    -- Base Amount is the EGP amount
    IF p_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    IF v_realized_fx_diff != 0 THEN
        IF v_realized_fx_diff > 0 THEN
            v_fx_gain_loss_acct := public.resolve_gl_account('4200', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', p_from_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', 0, 'credit', v_realized_fx_diff, 'base_debit', 0, 'base_credit', v_realized_fx_diff, 'currency', 'EGP', 'description', 'أرباح فروق عملة محققة')
                )
            );
        ELSE
            v_fx_gain_loss_acct := public.resolve_gl_account('5200', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', ABS(v_realized_fx_diff), 'credit', 0, 'base_debit', ABS(v_realized_fx_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق عملة محققة'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', p_from_currency, 'description', v_desc)
                )
            );
        END IF;
    ELSE
        v_je_id := public.post_journal_entry(
            'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
            jsonb_build_array(
                jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_from_currency, 'description', v_desc)
            )
        );
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency,
        v_desc || ' (صادر)', v_balance_before_from, v_balance_after_from,
        p_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency,
        v_desc || ' (وارد)', v_balance_before_to, v_balance_after_to,
        p_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'amount_from', p_amount_from,
        'from_currency', p_from_currency,
        'amount_to', p_amount_to,
        'to_currency', p_to_currency,
        'exchange_rate', p_exchange_rate
    );
END;
$$;

-- Overload for bigint treasury_id
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id bigint,
    p_from_currency character varying,
    p_to_currency character varying,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid,
    p_transfer_mode text DEFAULT 'exchange'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public.exchange_currency(
        p_treasury_id   := p_treasury_id::text,
        p_from_currency := p_from_currency,
        p_to_currency   := p_to_currency,
        p_amount_from   := p_amount_from,
        p_amount_to     := p_amount_to,
        p_exchange_rate := p_exchange_rate,
        p_user_id       := p_user_id,
        p_transfer_mode := p_transfer_mode
    );
END;
$$;


-- 3. Recalculate cost_base and book_rate for existing historical Treasury transactions
DO $$
DECLARE
    r RECORD;
    v_running_bal NUMERIC := 0;
    v_running_cost NUMERIC := 0;
    v_running_rate NUMERIC := 1.0;
    tx RECORD;
BEGIN
    FOR r IN SELECT DISTINCT treasury_id, currency FROM public.treasury_balances WHERE currency != 'EGP' LOOP
        v_running_bal := 0;
        v_running_cost := 0;
        v_running_rate := 1.0;

        FOR tx IN 
            SELECT * FROM public.treasury_transactions 
            WHERE treasury_id = r.treasury_id AND currency = r.currency AND (status = 'confirmed' OR status IS NULL)
            ORDER BY id ASC
        LOOP
            IF tx.type IN ('deposit', 'receipt', 'income', 'currency_exchange_in') THEN
                v_running_bal := v_running_bal + tx.amount;
                v_running_cost := v_running_cost + COALESCE(tx.amount_in_base_currency, ROUND(tx.amount * COALESCE(tx.exchange_rate, public.fn_get_exchange_rate(r.currency)), 2));
                IF v_running_bal > 0 THEN
                    v_running_rate := ROUND(v_running_cost / v_running_bal, 4);
                END IF;
            ELSIF tx.type IN ('expense', 'withdraw', 'payment', 'currency_exchange_out') THEN
                v_running_bal := GREATEST(0, v_running_bal - tx.amount);
                v_running_cost := GREATEST(0, v_running_cost - ROUND(tx.amount * v_running_rate, 2));
            END IF;
        END LOOP;

        IF v_running_bal > 0 THEN
            UPDATE public.treasury_balances
            SET cost_base = v_running_cost,
                book_rate = v_running_rate,
                updated_at = NOW()
            WHERE treasury_id = r.treasury_id AND currency = r.currency;
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload_schema';
