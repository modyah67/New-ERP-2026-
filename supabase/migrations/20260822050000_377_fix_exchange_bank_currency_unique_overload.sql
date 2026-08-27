-- Migration 377: Fix Exchange Bank Currency Unique Overload & IAS 21 Multi-Currency Engine
-- ============================================================================
-- 1. Drops all conflicting/duplicate overloads of exchange_bank_currency (fixes 42725).
-- 2. Implements IAS 21 Weighted Average Cost Base and Realized FX Gain/Loss calculation:
--    - Calculates released cost base (v_cost_base_released) at book rate.
--    - Calculates Realized FX difference (v_realized_fx_diff).
--    - Routes gains to 4310 (أرباح فروق عملة محققة) and losses to 6151 (خسائر فروق عملة محققة).
--    - Updates cost_base and book_rate in bank_accounts.
-- 3. Ensures rpc_confirm_bank_draft calls the single unified exchange_bank_currency.
-- ============================================================================

BEGIN;

-- 1. Drop all existing overloads of exchange_bank_currency
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'exchange_bank_currency'
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.proname) || '(' || r.args || ') CASCADE;';
    END LOOP;
END $$;

-- 2. Create single unified exchange_bank_currency function with IAS 21 FX Engine
CREATE OR REPLACE FUNCTION public.exchange_bank_currency(
    p_from_account_id integer,
    p_to_account_id integer,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_currency       TEXT;
    v_to_currency         TEXT;
    v_balance_before_from NUMERIC;
    v_balance_before_to   NUMERIC;
    v_balance_after_from  NUMERIC;
    v_balance_after_to    NUMERIC;
    
    v_cost_before_from    NUMERIC;
    v_rate_before_from    NUMERIC;
    v_cost_before_to      NUMERIC;
    v_rate_before_to      NUMERIC;
    
    v_new_cost_from       NUMERIC;
    v_new_rate_from       NUMERIC;
    v_new_cost_to         NUMERIC;
    v_new_rate_to         NUMERIC;
    
    v_cost_base_released  NUMERIC := 0;
    v_realized_fx_diff    NUMERIC := 0;
    v_base_amount         NUMERIC;
    
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_fx_gain_loss_acct   BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
    v_company_id          UUID;
    v_user_id             UUID;
    v_transaction_id      BIGINT;
    v_result              JSONB;
BEGIN
    v_user_id := auth.uid();

    IF p_amount_from <= 0 OR p_amount_to <= 0 OR p_exchange_rate <= 0 THEN
        RAISE EXCEPTION 'المبالغ وسعر الصرف يجب أن تكون أكبر من صفر';
    END IF;

    -- 1. Lock from_account and fetch balances & cost base
    SELECT currency, COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), company_id
    INTO v_from_currency, v_balance_before_from, v_cost_before_from, v_rate_before_from, v_company_id
    FROM public.bank_accounts
    WHERE id = p_from_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب البنكي المصدر غير موجود';
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي المصدر. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    -- 2. Lock to_account and fetch balances & cost base
    SELECT currency, COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_currency, v_balance_before_to, v_cost_before_to, v_rate_before_to
    FROM public.bank_accounts
    WHERE id = p_to_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب البنكي المحول إليه غير موجود';
    END IF;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM public.bank_accounts WHERE id = p_to_account_id;
        IF v_company_id IS NULL THEN
            SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
        END IF;
    END IF;

    -- Strict Rule: One of the currencies MUST be EGP
    IF v_from_currency != 'EGP' AND v_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
    END IF;

    -- Fallback for uninitialized cost base
    IF v_from_currency != 'EGP' AND (v_cost_before_from <= 0 OR v_rate_before_from <= 0) THEN
        v_rate_before_from := COALESCE(NULLIF(v_rate_before_from, 0), public.fn_get_exchange_rate(v_from_currency));
        IF v_rate_before_from <= 0 THEN v_rate_before_from := p_exchange_rate; END IF;
        v_cost_before_from := ROUND(v_balance_before_from * v_rate_before_from, 2);
    END IF;

    v_desc := 'تحويل بنكي من ' || v_from_currency || ' إلى ' || v_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    -- 3. IAS 21 Multi-Currency Cost Base & Realized FX Calculation
    IF v_from_currency != 'EGP' THEN
        -- Case A: Selling foreign currency (e.g. USD -> EGP)
        v_cost_base_released := ROUND(p_amount_from * v_rate_before_from, 2);
        v_new_cost_from := GREATEST(0, v_cost_before_from - v_cost_base_released);
        v_new_rate_from := CASE WHEN v_balance_after_from > 0 THEN ROUND(v_new_cost_from / v_balance_after_from, 4) ELSE v_rate_before_from END;

        v_new_cost_to := v_balance_after_to;
        v_new_rate_to := 1.0;
        v_realized_fx_diff := p_amount_to - v_cost_base_released;
    ELSE
        -- Case B: Buying foreign currency (e.g. EGP -> USD)
        v_new_cost_from := v_balance_after_from;
        v_new_rate_from := 1.0;

        v_new_cost_to := v_cost_before_to + p_amount_from;
        v_new_rate_to := CASE WHEN v_balance_after_to > 0 THEN ROUND(v_new_cost_to / v_balance_after_to, 4) ELSE p_exchange_rate END;
        v_realized_fx_diff := 0;
    END IF;

    -- Update Bank Accounts balances, cost_base, and book_rate
    UPDATE public.bank_accounts
    SET balance = v_balance_after_from,
        cost_base = v_new_cost_from,
        book_rate = v_new_rate_from,
        updated_at = NOW()
    WHERE id = p_from_account_id;

    UPDATE public.bank_accounts
    SET balance = v_balance_after_to,
        cost_base = v_new_cost_to,
        book_rate = v_new_rate_to,
        updated_at = NOW()
    WHERE id = p_to_account_id;

    -- Base Amount is the EGP amount
    IF v_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    -- 4. Post Balanced Journal Entry with Realized FX Gain/Loss
    IF v_realized_fx_diff != 0 THEN
        IF v_realized_fx_diff > 0 THEN
            v_fx_gain_loss_acct := public.resolve_gl_account('4310', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', v_from_currency, 'description', v_desc || ' (صادر بالتكلفة الدفترية)'),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', 0, 'credit', v_realized_fx_diff, 'base_debit', 0, 'base_credit', v_realized_fx_diff, 'currency', 'EGP', 'description', 'أرباح فروق عملة محققة')
                )
            );
        ELSE
            v_fx_gain_loss_acct := public.resolve_gl_account('6151', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', ABS(v_realized_fx_diff), 'credit', 0, 'base_debit', ABS(v_realized_fx_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق عملة محققة'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', v_from_currency, 'description', v_desc || ' (صادر بالتكلفة الدفترية)')
                )
            );
        END IF;
    ELSE
        v_je_id := public.post_journal_entry(
            'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
            jsonb_build_array(
                jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
                jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
            )
        );
    END IF;

    -- 5. Insert Transaction Records
    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot, status
    ) VALUES (
        p_from_account_id, 'currency_exchange_out', p_amount_from, v_balance_before_from, v_balance_after_from,
        v_desc || ' (صادر)', 'exchange', v_je_id,
        p_exchange_rate, CASE WHEN v_from_currency != 'EGP' THEN v_cost_base_released ELSE v_base_amount END,
        jsonb_build_object('currency', v_from_currency, 'exchange_rate', p_exchange_rate, 'book_rate', v_new_rate_from, 'amount', p_amount_from, 'amount_in_base_currency', CASE WHEN v_from_currency != 'EGP' THEN v_cost_base_released ELSE v_base_amount END),
        'confirmed'
    ) RETURNING id INTO v_transaction_id;

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot, status
    ) VALUES (
        p_to_account_id, 'currency_exchange_in', p_amount_to, v_balance_before_to, v_balance_after_to,
        v_desc || ' (وارد)', 'exchange', v_je_id,
        p_exchange_rate, v_base_amount,
        jsonb_build_object('currency', v_to_currency, 'exchange_rate', p_exchange_rate, 'book_rate', v_new_rate_to, 'amount', p_amount_to, 'amount_in_base_currency', v_base_amount),
        'confirmed'
    );

    v_result := jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_entry_id', v_je_id,
        'realized_fx_diff', v_realized_fx_diff
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_bank_currency(integer, integer, numeric, numeric, numeric) TO authenticated, anon, service_role;

-- 3. Update rpc_confirm_bank_draft
CREATE OR REPLACE FUNCTION public.rpc_confirm_bank_draft(
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
BEGIN
    SELECT * INTO v_tx
    FROM public.bank_account_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    IF v_tx.type = 'deposit' THEN
        v_res := public.deposit_bank_account(
            p_account_id        := v_tx.bank_account_id::bigint,
            p_amount            := v_tx.amount,
            p_description       := v_tx.description,
            p_revenue_account_id := COALESCE((v_tx.payload->>'revenue_account_id')::bigint, NULL),
            p_entity_type       := v_tx.entity_type,
            p_entity_id         := v_tx.entity_id,
            p_counterparty_name := v_tx.counterparty_name,
            p_source_type       := COALESCE(v_tx.payload->>'source_type', 'deposit'),
            p_notes             := v_tx.notes
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الإيداع وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'withdraw' THEN
        v_res := public.withdraw_bank_account(
            p_account_id        := v_tx.bank_account_id,
            p_amount            := v_tx.amount,
            p_description       := v_tx.description,
            p_entity_type       := v_tx.entity_type,
            p_entity_id         := v_tx.entity_id,
            p_counterparty_name := v_tx.counterparty_name,
            p_expense_account_id := COALESCE((v_tx.payload->>'expense_account_id')::integer, NULL),
            p_notes             := v_tx.notes,
            p_reference_type    := v_tx.payload->>'reference_type',
            p_reference_id      := v_tx.payload->>'reference_id'
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الصرف وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type IN ('currency_exchange_out', 'currency_exchange_in', 'exchange') THEN
        v_res := public.exchange_bank_currency(
            p_from_account_id := v_tx.bank_account_id::integer,
            p_to_account_id   := (v_tx.payload->>'to_account_id')::integer,
            p_amount_from     := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to       := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate   := (v_tx.payload->>'exchange_rate')::numeric
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'transfer' THEN
        PERFORM public.bank_transfer(
            p_from_account_id := v_tx.bank_account_id::integer,
            p_to_account_id   := (v_tx.payload->>'to_account_id')::integer,
            p_amount          := v_tx.amount,
            p_description     := v_tx.description,
            p_bank_fee        := COALESCE((v_tx.payload->>'bank_fee')::numeric, 0),
            p_notes           := v_tx.notes
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد التحويل البنكي وترحيل القيد بنجاح');

    ELSE
        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_bank_draft(bigint) TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';

COMMIT;
