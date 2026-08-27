-- ============================================================================
-- Migration 421: Auto Customer Shipment Realized FX Gain/Loss on Deposit & Cheques
-- ============================================================================
-- 1. In deposit_bank_account:
--    - When entity_type = 'customer' and foreign currency (USD, EUR, GBP):
--      - Matches customer's open export shipments (FIFO or by shipment_no in desc/notes).
--      - Calculates realized FX differences per shipment:
--          diff = alloc * (bank_spot_rate - shipment_rate)
--      - If diff > 0: posts to 4310 (Realized FX Gains).
--      - If diff < 0: posts to 6151 (Realized FX Losses).
--      - If diff = 0 (e.g. shipment page payment or same spot rate): clean 2-line JE.
--      - Updates export_shipments.paid_amount.
--      - Inserts into public.ledger_entries for customer statement.
-- 2. In clear_cheque:
--    - When incoming cheque from customer and foreign currency:
--      - Applies the exact same shipment FIFO matching and FX difference engine.
--      - Inserts into public.ledger_entries for customer statement.
-- 3. Strictly scoped to customers only; suppliers, shareholders, treasuries,
--    and EGP payments are completely unaffected.
-- ============================================================================

BEGIN;

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
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_entry_date      DATE;
    v_je_lines        JSONB;

    -- Shipment matching & FX calculation variables
    v_total_cust_base NUMERIC;
    v_total_gain      NUMERIC := 0;
    v_total_loss      NUMERIC := 0;
    v_remaining_alloc NUMERIC;
    v_alloc           NUMERIC;
    v_alloc_bank_base NUMERIC;
    v_alloc_cust_base NUMERIC;
    v_diff            NUMERIC;
    v_spec_shipment   RECORD;
    v_shipment        RECORD;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
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

    -- 3. Customer Foreign Currency Shipment Matching & Realized FX Calculation
    v_total_cust_base := v_base_amount;
    v_total_gain := 0;
    v_total_loss := 0;

    IF p_entity_type = 'customer' AND v_currency != 'EGP' AND p_entity_id IS NOT NULL THEN
        v_remaining_alloc := p_amount;
        v_total_cust_base := 0;

        -- Check if a specific shipment is referenced in description or notes
        SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
               (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
        INTO v_spec_shipment
        FROM public.export_shipments
        WHERE customer_id = p_entity_id::bigint
          AND is_confirmed = true
          AND status != 'cancelled'
          AND (
              (p_description IS NOT NULL AND p_description LIKE '%' || shipment_no || '%')
              OR (p_notes IS NOT NULL AND p_notes LIKE '%' || shipment_no || '%')
          )
        ORDER BY id DESC
        LIMIT 1;

        IF v_spec_shipment.id IS NOT NULL AND v_spec_shipment.due_foreign > 0.001 THEN
            v_alloc := LEAST(v_remaining_alloc, v_spec_shipment.due_foreign);
            v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
            v_alloc_cust_base := ROUND(v_alloc * v_spec_shipment.shipment_rate, 2);
            v_diff := v_alloc_bank_base - v_alloc_cust_base;

            v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

            IF v_diff > 0 THEN
                v_total_gain := v_total_gain + v_diff;
            ELSIF v_diff < 0 THEN
                v_total_loss := v_total_loss + ABS(v_diff);
            END IF;

            UPDATE public.export_shipments
            SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                updated_at = NOW()
            WHERE id = v_spec_shipment.id;

            v_remaining_alloc := v_remaining_alloc - v_alloc;
        END IF;

        -- Allocate remaining amount to open shipments in FIFO order
        IF v_remaining_alloc > 0.001 THEN
            FOR v_shipment IN
                SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                       (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
                FROM public.export_shipments
                WHERE customer_id = p_entity_id::bigint
                  AND is_confirmed = true
                  AND status != 'cancelled'
                  AND (v_spec_shipment.id IS NULL OR id != v_spec_shipment.id)
                  AND (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) > 0.001
                ORDER BY created_at ASC, id ASC
            LOOP
                EXIT WHEN v_remaining_alloc <= 0.001;

                v_alloc := LEAST(v_remaining_alloc, v_shipment.due_foreign);
                v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                v_alloc_cust_base := ROUND(v_alloc * v_shipment.shipment_rate, 2);
                v_diff := v_alloc_bank_base - v_alloc_cust_base;

                v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                IF v_diff > 0 THEN
                    v_total_gain := v_total_gain + v_diff;
                ELSIF v_diff < 0 THEN
                    v_total_loss := v_total_loss + ABS(v_diff);
                END IF;

                UPDATE public.export_shipments
                SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                    updated_at = NOW()
                WHERE id = v_shipment.id;

                v_remaining_alloc := v_remaining_alloc - v_alloc;
            END LOOP;
        END IF;

        -- If any advance amount remains (no open shipments)
        IF v_remaining_alloc > 0.001 THEN
            v_total_cust_base := v_total_cust_base + ROUND(v_remaining_alloc * v_rate, 2);
        END IF;
    END IF;

    -- 4. Build Journal Entry Lines
    v_je_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_bank_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc)
    );

    IF v_total_loss > 0 THEN
        v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_realized_loss_acct,
                'debit', v_total_loss,
                'credit', 0,
                'base_debit', v_total_loss,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'خسائر فروق أسعار عملة محققة - عميل ' || COALESCE(p_counterparty_name, '')
            )
        );
    END IF;

    v_je_lines := v_je_lines || jsonb_build_array(
        jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_total_cust_base, 'currency', v_currency, 'description', v_desc)
    );

    IF v_total_gain > 0 THEN
        v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_realized_gain_acct,
                'debit', 0,
                'credit', v_total_gain,
                'base_debit', 0,
                'base_credit', v_total_gain,
                'currency', 'EGP',
                'description', 'أرباح فروق أسعار عملة محققة - عميل ' || COALESCE(p_counterparty_name, '')
            )
        );
    END IF;

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, v_entry_date, v_company_id, auth.uid(),
        v_je_lines
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
        'rate_date', v_entry_date,
        'rate_source', 'exchange_rates_table',
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
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

    -- Update party balance & insert into public.ledger_entries for statement reflection
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id::text, 'credit', p_amount, v_currency,
            'payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id::text, 'debit', p_amount, v_currency,
            'payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
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
        'journal_entry_id', v_je_id,
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );
END;
$$;

-- ── 2. Update clear_cheque for Customer Shipment Realized FX & Ledger Sync ──
CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_je_id BIGINT;
    v_bank_tx_id BIGINT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_book_rate NUMERIC := 1.0;
    v_snapshot JSONB;
    v_entity_id TEXT;
    v_multi_res JSONB;
    v_je_lines JSONB;

    -- Shipment matching & FX calculation variables
    v_total_cust_base NUMERIC;
    v_total_gain      NUMERIC := 0;
    v_total_loss      NUMERIC := 0;
    v_remaining_alloc NUMERIC;
    v_alloc           NUMERIC;
    v_alloc_bank_base NUMERIC;
    v_alloc_cust_base NUMERIC;
    v_diff            NUMERIC;
    v_spec_shipment   RECORD;
    v_shipment        RECORD;
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
        WHERE ba.currency = v_currency AND ba.deleted_at IS NULL
        ORDER BY ba.id ASC
        LIMIT 1
        FOR UPDATE;
    END IF;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على حساب بنكي بعملة %', v_currency;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- ================================================================
    -- 1. OUTGOING CHEQUE: Dr Counterparty / Cr Bank (Book Rate)
    -- ================================================================
    IF v_cheque.type = 'outgoing' THEN
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_bank_bal;
        END IF;

        IF v_currency = 'EGP' THEN
            v_book_rate := 1.0;
            v_cost_released := v_cheque.amount;
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
            v_new_book_rate := v_book_rate;
            v_new_cost_base := 0;
        END IF;

        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - v_cheque.amount WHERE id = v_cheque.supplier_id;
        ELSIF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance + v_cheque.amount WHERE id = v_cheque.counterparty_id;
        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance - v_cheque.amount WHERE id = v_cheque.clearing_agent_id;
        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance - v_cheque.amount WHERE id = v_cheque.shipping_company_id;
        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;
        END IF;

        IF v_counterparty_acct IS NULL THEN
            v_counterparty_acct := public.resolve_gl_account('51101', v_company_id);
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        v_je_id := public.post_journal_entry(
            'bank_withdrawal',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_counterparty_acct, 'debit', v_cheque.amount, 'credit', 0, 'base_debit', v_cost_released, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_bank_acct,         'debit', 0, 'credit', v_cheque.amount, 'base_debit', 0, 'base_credit', v_cost_released, 'currency', v_currency, 'description', v_desc)
            )
        );

        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'withdraw', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_book_rate, v_cost_released, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_book_rate,
                'book_rate', v_new_book_rate,
                'cost_base', v_new_cost_base,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_cost_released,
                'rate_date', CURRENT_DATE,
                'rate_source', 'bank_book_rate'
             ))
        RETURNING id INTO v_bank_tx_id;

    -- ================================================================
    -- 2. INCOMING CHEQUE: Dr Bank / Cr Counterparty (Customer Shipment Matching & FX)
    -- ================================================================
    ELSIF v_cheque.type = 'incoming' THEN
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

            -- Sync to ledger_entries for statement reflection
            INSERT INTO public.ledger_entries (
                entity_type, entity_id, entry_type, amount, currency,
                reference_type, reference_id, reference_text, description, created_by
            ) VALUES (
                'customer', v_cheque.counterparty_id::text, 'credit', v_cheque.amount, v_currency,
                'payment', p_cheque_id, v_cheque.cheque_number, v_desc, auth.uid()
            );

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
                CASE v_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
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
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        -- Customer Shipment Matching & Realized FX Calculation (if foreign currency)
        v_total_cust_base := v_base_amount;
        v_total_gain := 0;
        v_total_loss := 0;

        IF v_cheque.counterparty_type = 'customer' AND v_currency != 'EGP' AND v_cheque.counterparty_id IS NOT NULL THEN
            v_remaining_alloc := v_cheque.amount;
            v_total_cust_base := 0;

            -- Check if a specific shipment is referenced in notes
            SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                   (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
            INTO v_spec_shipment
            FROM public.export_shipments
            WHERE customer_id = v_cheque.counterparty_id
              AND is_confirmed = true
              AND status != 'cancelled'
              AND (
                  (v_cheque.notes IS NOT NULL AND v_cheque.notes LIKE '%' || shipment_no || '%')
                  OR (v_desc IS NOT NULL AND v_desc LIKE '%' || shipment_no || '%')
              )
            ORDER BY id DESC
            LIMIT 1;

            IF v_spec_shipment.id IS NOT NULL AND v_spec_shipment.due_foreign > 0.001 THEN
                v_alloc := LEAST(v_remaining_alloc, v_spec_shipment.due_foreign);
                v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                v_alloc_cust_base := ROUND(v_alloc * v_spec_shipment.shipment_rate, 2);
                v_diff := v_alloc_bank_base - v_alloc_cust_base;

                v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                IF v_diff > 0 THEN
                    v_total_gain := v_total_gain + v_diff;
                ELSIF v_diff < 0 THEN
                    v_total_loss := v_total_loss + ABS(v_diff);
                END IF;

                UPDATE public.export_shipments
                SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                    updated_at = NOW()
                WHERE id = v_spec_shipment.id;

                v_remaining_alloc := v_remaining_alloc - v_alloc;
            END IF;

            -- Allocate remaining amount to open shipments in FIFO order
            IF v_remaining_alloc > 0.001 THEN
                FOR v_shipment IN
                    SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                           (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
                    FROM public.export_shipments
                    WHERE customer_id = v_cheque.counterparty_id
                      AND is_confirmed = true
                      AND status != 'cancelled'
                      AND (v_spec_shipment.id IS NULL OR id != v_spec_shipment.id)
                      AND (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) > 0.001
                    ORDER BY created_at ASC, id ASC
                LOOP
                    EXIT WHEN v_remaining_alloc <= 0.001;

                    v_alloc := LEAST(v_remaining_alloc, v_shipment.due_foreign);
                    v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                    v_alloc_cust_base := ROUND(v_alloc * v_shipment.shipment_rate, 2);
                    v_diff := v_alloc_bank_base - v_alloc_cust_base;

                    v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                    IF v_diff > 0 THEN
                        v_total_gain := v_total_gain + v_diff;
                    ELSIF v_diff < 0 THEN
                        v_total_loss := v_total_loss + ABS(v_diff);
                    END IF;

                    UPDATE public.export_shipments
                    SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                        updated_at = NOW()
                    WHERE id = v_shipment.id;

                    v_remaining_alloc := v_remaining_alloc - v_alloc;
                END LOOP;
            END IF;

            -- If any advance amount remains (no open shipments)
            IF v_remaining_alloc > 0.001 THEN
                v_total_cust_base := v_total_cust_base + ROUND(v_remaining_alloc * v_rate, 2);
            END IF;
        END IF;

        -- Build Journal Entry Lines
        v_je_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct, 'debit', v_cheque.amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc)
        );

        IF v_total_loss > 0 THEN
            v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_loss,
                    'credit', 0,
                    'base_debit', v_total_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - شيك ' || COALESCE(v_cheque.cheque_number, '')
                )
            );
        END IF;

        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object('account_id', v_counterparty_acct, 'debit', 0, 'credit', v_cheque.amount, 'base_debit', 0, 'base_credit', v_total_cust_base, 'currency', v_currency, 'description', v_desc)
        );

        IF v_total_gain > 0 THEN
            v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_gain,
                    'base_debit', 0,
                    'base_credit', v_total_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - شيك ' || COALESCE(v_cheque.cheque_number, '')
                )
            );
        END IF;

        -- Post journal entry
        v_je_id := public.post_journal_entry(
            'bank_deposit',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines
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
                'rate_source', 'exchange_rates_table',
                'realized_fx_gain', v_total_gain,
                'realized_fx_loss', v_total_loss
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
            'rate_source', 'exchange_rates_table',
            'realized_fx_gain', v_total_gain,
            'realized_fx_loss', v_total_loss
        )
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'bank_tx_id', v_bank_tx_id,
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.clear_cheque(bigint) TO authenticated, service_role;

COMMIT;
