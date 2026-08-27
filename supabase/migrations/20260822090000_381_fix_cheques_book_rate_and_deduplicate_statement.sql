-- Migration 381: Fix Cheque Foreign Currency Book Rate Recalculation & Deduplicate Entity Statement
-- ============================================================================
-- 1. Ensure public.cheques has all required columns
-- 2. Clean up any existing bank transactions originating from cheques so entity_type = 'cheque'
-- 3. Update clear_cheque to:
--    a) Recalculate cost_base and weighted average book_rate on bank accounts for incoming cheques (IAS 21)
--    b) Prevent duplicate line items on supplier/clearing/shipping statements for outgoing cheques
--    c) Preserve multi-payment FIFO invoice allocation and realized FX calculations
-- ============================================================================

BEGIN;

-- 1. Ensure all required columns exist on public.cheques
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'bank_account_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN bank_account_id INTEGER REFERENCES public.bank_accounts(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'journal_entry_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'exchange_rate'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN exchange_rate NUMERIC(15,6) DEFAULT 1.0;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'amount_in_base_currency'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN amount_in_base_currency NUMERIC(15,2);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'treasury_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN treasury_id BIGINT REFERENCES public.treasuries(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 2. Retroactively fix any existing bank transactions linked to cheques to avoid duplicate statement lines
UPDATE public.bank_account_transactions
SET entity_type = 'cheque',
    entity_id = reference_id,
    source_type = 'cheque'
WHERE reference_type = 'cheque' AND entity_type != 'cheque';

-- 3. Replace clear_cheque with complete IAS 21 and Single-Entry Entity Statement Support
CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cheque RECORD;
    v_desc TEXT;
    v_bank_id INTEGER;
    v_bank_bal NUMERIC;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_cost_released NUMERIC := 0;
    v_currency TEXT;
    v_company_id UUID;
    v_new_bank_bal NUMERIC;
    v_bank_acct BIGINT;
    v_counterparty_acct BIGINT;
    v_je_id BIGINT;
    v_bank_tx_id BIGINT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_book_rate NUMERIC := 1.0;
    v_snapshot JSONB;
    v_entity_id TEXT;
    v_multi_res JSONB;
BEGIN
    SELECT * INTO v_cheque
    FROM public.cheques
    WHERE id = p_cheque_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الشيك غير موجود';
    END IF;

    IF v_cheque.status != 'pending' THEN
        RAISE EXCEPTION 'لا يمكن تسوية شيك بحالة %', v_cheque.status;
    END IF;

    v_currency := v_cheque.currency;
    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(v_cheque.amount * v_rate, 2);

    IF v_cheque.type = 'outgoing' THEN
        v_desc := 'صرف شيك رقم: ' || v_cheque.cheque_number;
    ELSE
        v_desc := 'تحصيل شيك رقم: ' || v_cheque.cheque_number;
    END IF;

    -- Get bank account (use cheque's assigned bank if present, otherwise match currency)
    IF v_cheque.bank_account_id IS NOT NULL THEN
        SELECT id, balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), ba.company_id
        INTO v_bank_id, v_bank_bal, v_current_cost_base, v_current_book_rate, v_company_id
        FROM public.bank_accounts ba
        WHERE ba.id = v_cheque.bank_account_id
        FOR UPDATE;
    ELSE
        SELECT id, balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), ba.company_id
        INTO v_bank_id, v_bank_bal, v_current_cost_base, v_current_book_rate, v_company_id
        FROM public.bank_accounts ba
        WHERE ba.currency = v_cheque.currency
        LIMIT 1
        FOR UPDATE;
    END IF;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لا يوجد حساب بنكي متطابق مع عملة الشيك (%)', v_currency;
    END IF;

    -- ================================================================
    -- 1. OUTGOING CHEQUE: Supplier / Clearing Agent / Shipping Company
    -- (Delegated to Unified Multi-Payment FIFO & IAS 21 Engine)
    -- ================================================================
    IF v_cheque.type = 'outgoing' THEN
        v_entity_id := CASE 
            WHEN v_cheque.counterparty_type = 'supplier' THEN COALESCE(v_cheque.supplier_id::text, v_cheque.counterparty_id::text)
            WHEN v_cheque.counterparty_type = 'clearing_agent' THEN COALESCE(v_cheque.clearing_agent_id::text, v_cheque.counterparty_id::text)
            WHEN v_cheque.counterparty_type = 'shipping_company' THEN COALESCE(v_cheque.shipping_company_id::text, v_cheque.counterparty_id::text)
            ELSE NULL
        END;

        IF v_cheque.counterparty_type IN ('supplier', 'clearing_agent', 'shipping_company') AND v_entity_id IS NOT NULL THEN
            IF v_bank_bal < v_cheque.amount THEN
                RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (% متوفر، % مطلوب)', v_bank_bal, v_cheque.amount;
            END IF;

            -- Execute through unified multi-payment engine
            v_multi_res := public.rpc_entity_multi_payment(
                p_source_type := 'bank',
                p_source_id   := v_bank_id,
                p_currency    := v_currency,
                p_amount      := v_cheque.amount,
                p_entity_type := LOWER(v_cheque.counterparty_type),
                p_entity_id   := v_entity_id,
                p_description := v_desc,
                p_notes       := v_cheque.notes
            );
            v_je_id := (v_multi_res->>'journal_entry_id')::BIGINT;
            v_bank_tx_id := (v_multi_res->>'transaction_id')::BIGINT;

            -- Update cheque status
            UPDATE public.cheques
            SET status = 'cleared',
                cleared_at = NOW(),
                bank_account_id = v_bank_id,
                journal_entry_id = v_je_id,
                exchange_rate = v_rate,
                amount_in_base_currency = v_base_amount,
                currency_snapshot = jsonb_build_object(
                    'currency', v_currency,
                    'exchange_rate', v_rate,
                    'amount', v_cheque.amount,
                    'amount_in_base_currency', v_base_amount,
                    'rate_date', CURRENT_DATE,
                    'rate_source', 'exchange_rates_table'
                )
            WHERE id = p_cheque_id;

            -- Link bank transaction with cheque reference & normalize entity_type to 'cheque'
            -- so entity statement shows the cheque ONCE from cheques table without duplicate
            IF v_bank_tx_id IS NOT NULL THEN
                UPDATE public.bank_account_transactions
                SET entity_type = 'cheque',
                    entity_id = p_cheque_id::text,
                    source_type = 'cheque',
                    reference_type = 'cheque',
                    reference_id = p_cheque_id::text,
                    notes = COALESCE(notes, '') || ' (شيك رقم: ' || v_cheque.cheque_number || ')'
                WHERE id = v_bank_tx_id;
            END IF;

            RETURN jsonb_build_object(
                'success', true,
                'cheque_id', p_cheque_id,
                'status', 'cleared',
                'journal_entry_id', v_je_id,
                'bank_tx_id', v_bank_tx_id
            );
        END IF;

        -- Other Outgoing Counterparties (Shareholder, Customer, Treasury)
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (% متوفر)', v_bank_bal;
        END IF;

        -- Deduct from bank balance and cost_base at current book_rate
        IF v_currency = 'EGP' THEN
            v_new_cost_base := GREATEST(0, v_current_cost_base - v_cheque.amount);
            v_new_book_rate := 1.0;
        ELSE
            v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), v_rate);
            v_cost_released := ROUND(v_cheque.amount * v_book_rate, 2);
            v_new_cost_base := GREATEST(0, v_current_cost_base - v_cost_released);
        END IF;

        v_new_bank_bal := v_bank_bal - v_cheque.amount;

        IF v_new_bank_bal > 0 AND v_currency != 'EGP' THEN
            v_new_book_rate := ROUND(v_new_cost_base / v_new_bank_bal, 4);
        ELSIF v_currency = 'EGP' THEN
            v_new_book_rate := 1.0;
        ELSE
            v_new_book_rate := v_current_book_rate;
        END IF;

        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.counterparty_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            v_counterparty_acct := public.resolve_gl_account(
                CASE v_currency
                    WHEN 'EGP' THEN '11101'
                    WHEN 'USD' THEN '11102'
                    WHEN 'EUR' THEN '11103'
                    WHEN 'GBP' THEN '11104'
                    ELSE '11101'
                END,
                v_company_id
            );
        END IF;

        IF v_counterparty_acct IS NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_counterparty_acct IS NOT NULL THEN
                SELECT id INTO v_counterparty_acct FROM public.accounts WHERE id = v_counterparty_acct AND is_leaf = true AND is_active = true;
            END IF;
            IF v_counterparty_acct IS NULL THEN
                v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
            END IF;
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency
                WHEN 'EGP' THEN '11201'
                WHEN 'USD' THEN '11202'
                WHEN 'EUR' THEN '11203'
                WHEN 'GBP' THEN '11204'
                ELSE '11201'
            END,
            v_company_id
        );

        -- Post journal entry: Dr Counterparty / Cr Bank with base amounts
        v_je_id := public.post_journal_entry(
            'bank_withdraw',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_counterparty_acct,
                    'debit', v_cheque.amount,
                    'credit', 0,
                    'base_debit', v_base_amount,
                    'base_credit', 0,
                    'currency', v_currency,
                    'description', v_desc
                ),
                jsonb_build_object(
                    'account_id', v_bank_acct,
                    'debit', 0,
                    'credit', v_cheque.amount,
                    'base_debit', 0,
                    'base_credit', v_base_amount,
                    'currency', v_currency,
                    'description', v_desc
                )
            )
        );

        -- Update bank balance, cost_base and book_rate
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'withdrawal', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_rate, v_base_amount, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_rate,
                'book_rate', v_new_book_rate,
                'cost_base', v_new_cost_base,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_base_amount,
                'rate_date', CURRENT_DATE,
                'rate_source', 'exchange_rates_table'
             ))
        RETURNING id INTO v_bank_tx_id;

    -- ================================================================
    -- 2. INCOMING CHEQUE: Dr Bank / Cr Counterparty (IAS 21 Weighted Average)
    -- ================================================================
    ELSIF v_cheque.type = 'incoming' THEN
        -- Recalculate Weighted Average Cost Base & Book Rate on Inflow
        IF v_currency = 'EGP' THEN
            v_new_cost_base := v_current_cost_base + v_cheque.amount;
            v_new_book_rate := 1.0;
        ELSE
            v_new_cost_base := v_current_cost_base + v_base_amount;
        END IF;

        v_new_bank_bal := v_bank_bal + v_cheque.amount;

        IF v_new_bank_bal > 0 AND v_currency != 'EGP' THEN
            v_new_book_rate := ROUND(v_new_cost_base / v_new_bank_bal, 4);
        ELSIF v_currency = 'EGP' THEN
            v_new_book_rate := 1.0;
        ELSE
            v_new_book_rate := v_rate;
        END IF;

        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.counterparty_id;

        ELSIF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + v_cheque.amount
            WHERE id = v_cheque.supplier_id;

        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.clearing_agent_id;

        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.shipping_company_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            v_counterparty_acct := public.resolve_gl_account(
                CASE v_currency
                    WHEN 'EGP' THEN '11101'
                    WHEN 'USD' THEN '11102'
                    WHEN 'EUR' THEN '11103'
                    WHEN 'GBP' THEN '11104'
                    ELSE '11101'
                END,
                v_company_id
            );
        END IF;

        IF v_counterparty_acct IS NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_counterparty_acct IS NOT NULL THEN
                SELECT id INTO v_counterparty_acct FROM public.accounts WHERE id = v_counterparty_acct AND is_leaf = true AND is_active = true;
            END IF;
            IF v_counterparty_acct IS NULL THEN
                v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
            END IF;
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency
                WHEN 'EGP' THEN '11201'
                WHEN 'USD' THEN '11202'
                WHEN 'EUR' THEN '11203'
                WHEN 'GBP' THEN '11204'
                ELSE '11201'
            END,
            v_company_id
        );

        -- Post journal entry: Dr Bank / Cr Counterparty with base amounts
        v_je_id := public.post_journal_entry(
            'bank_deposit',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_bank_acct,
                    'debit', v_cheque.amount,
                    'credit', 0,
                    'base_debit', v_base_amount,
                    'base_credit', 0,
                    'currency', v_currency,
                    'description', v_desc
                ),
                jsonb_build_object(
                    'account_id', v_counterparty_acct,
                    'debit', 0,
                    'credit', v_cheque.amount,
                    'base_debit', 0,
                    'base_credit', v_base_amount,
                    'currency', v_currency,
                    'description', v_desc
                )
            )
        );

        -- Update bank balance, cost_base and weighted average book_rate
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_rate, v_base_amount, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_rate,
                'book_rate', v_new_book_rate,
                'cost_base', v_new_cost_base,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_base_amount,
                'rate_date', CURRENT_DATE,
                'rate_source', 'exchange_rates_table'
             ))
        RETURNING id INTO v_bank_tx_id;

    END IF;

    -- Update cheque status + freeze rate and amount_in_base_currency
    UPDATE public.cheques
    SET status = 'cleared',
        cleared_at = NOW(),
        bank_account_id = v_bank_id,
        journal_entry_id = v_je_id,
        exchange_rate = v_rate,
        amount_in_base_currency = v_base_amount,
        currency_snapshot = jsonb_build_object(
            'currency', v_currency,
            'exchange_rate', v_rate,
            'amount', v_cheque.amount,
            'amount_in_base_currency', v_base_amount,
            'rate_date', CURRENT_DATE,
            'rate_source', 'exchange_rates_table'
        )
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'bank_tx_id', v_bank_tx_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.clear_cheque(bigint) TO authenticated, anon, service_role;

COMMIT;
