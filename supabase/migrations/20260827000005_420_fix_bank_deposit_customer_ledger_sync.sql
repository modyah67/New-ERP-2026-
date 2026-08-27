-- ============================================================================
-- Migration 420: Sync Bank Account Deposits and Withdrawals to ledger_entries
-- ============================================================================
-- When a bank deposit or withdrawal is made for a customer or supplier:
-- 1. Updates bank account balance and entity balance.
-- 2. Inserts into bank_account_transactions and GL journal entries.
-- 3. Inserts into public.ledger_entries so customer and supplier account
--    statements (كشف الحساب) immediately reflect the payment and decrease the balance.
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
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_entry_date      DATE;
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

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, v_entry_date, v_company_id, auth.uid(),
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
        'rate_date', v_entry_date,
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
        'journal_entry_id', v_je_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
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
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_je_source_type  TEXT;
    v_source_type     TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
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
        RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_current_balance;
    END IF;

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

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id::text, 'debit', p_amount, v_currency,
            'refund', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::TEXT = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id::text, 'credit', p_amount, v_currency,
            'supplier_payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
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

GRANT EXECUTE ON FUNCTION public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(bigint, numeric, text, bigint, text, text, text, text, text, text) TO authenticated, service_role;

-- Backfill any existing customer deposits in bank_account_transactions that are missing from ledger_entries
INSERT INTO public.ledger_entries (
    entity_type, entity_id, entry_type, amount, currency,
    reference_type, reference_id, reference_text, description, created_by, created_at
)
SELECT 
    'customer', bat.entity_id, 
    CASE WHEN bat.type = 'deposit' THEN 'credit' ELSE 'debit' END,
    bat.amount, ba.currency,
    'payment', bat.id, bat.description, bat.description, bat.created_by, bat.created_at
FROM public.bank_account_transactions bat
JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id
WHERE bat.entity_type = 'customer'
  AND NOT EXISTS (
      SELECT 1 FROM public.ledger_entries le
      WHERE le.entity_type = 'customer'
        AND le.entity_id = bat.entity_id
        AND le.reference_type = 'payment'
        AND le.reference_id = bat.id
  );

COMMIT;
