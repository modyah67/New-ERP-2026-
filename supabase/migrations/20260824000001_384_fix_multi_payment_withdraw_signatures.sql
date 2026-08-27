-- ============================================================================
-- Migration: 20260824000001_384_fix_multi_payment_withdraw_signatures.sql
-- Description: 
--   1. Register distinct document types & prefixes:
--      - 'treasury_multi_payment' -> Prefix 'TMPY'
--      - 'bank_multi_payment'     -> Prefix 'BMPY'
--   2. Timezone synchronization: Auto-correct all journal entry dates to local (Africa/Cairo / UTC+3).
--   3. Update post_journal_entry, deposit_treasury, deposit_bank_account, spend_custody, withdraw_bank_account.
--   4. Fix account_ledger_entries columns (amount_in_base_currency) in post_journal_entry.
--   5. Fix explicit type casts (text = bigint) in vw_unpaid_liabilities and rpc_entity_multi_payment.
--   6. Ensure single clean journal entry per multi-payment (prevent duplicates).
--   7. Retroactively fix recent journal entries created with UTC date offset.
-- ============================================================================

BEGIN;

-- 1. Register Document Types and Prefixes
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES 
  ('treasury_multi_payment', 'Treasury Multi-Payment / سداد متعدد من الخزينة', 'TMPY', true),
  ('bank_multi_payment',     'Bank Multi-Payment / سداد متعدد من البنك',         'BMPY', true)
ON CONFLICT (code) DO UPDATE SET 
  prefix = EXCLUDED.prefix,
  name = EXCLUDED.name,
  is_active = true;

-- 2. Retroactive correction for journal entries created within the last 48 hours with UTC offset
UPDATE public.journal_entries
SET entry_date = (created_at AT TIME ZONE 'Africa/Cairo')::DATE
WHERE entry_date != (created_at AT TIME ZONE 'Africa/Cairo')::DATE
  AND created_at >= NOW() - INTERVAL '48 hours';

-- 3. Clean up any orphaned duplicate journal entries from earlier test
DELETE FROM public.account_ledger_entries 
WHERE journal_entry_id IN (
    SELECT id FROM public.journal_entries 
    WHERE description LIKE '%سداد مستحقات لمورد%' 
      AND id NOT IN (SELECT journal_entry_id FROM public.bank_account_transactions WHERE journal_entry_id IS NOT NULL)
      AND id NOT IN (SELECT journal_entry_id FROM public.treasury_transactions WHERE journal_entry_id IS NOT NULL)
);
DELETE FROM public.journal_entries 
WHERE description LIKE '%سداد مستحقات لمورد%' 
  AND id NOT IN (SELECT journal_entry_id FROM public.bank_account_transactions WHERE journal_entry_id IS NOT NULL)
  AND id NOT IN (SELECT journal_entry_id FROM public.treasury_transactions WHERE journal_entry_id IS NOT NULL);

-- 4. Central Engine: post_journal_entry with Correct Columns & Timezone Safeguard
CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type   TEXT,
    p_description   TEXT,
    p_entry_date    DATE,
    p_company_id    UUID,
    p_created_by    UUID,
    p_lines         JSONB,
    p_source_id     TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_je_id         BIGINT;
    v_entry_number  TEXT;
    v_total_debit   NUMERIC := 0;
    v_total_credit  NUMERIC := 0;
    v_line          JSONB;
    v_account_id    BIGINT;
    v_debit         NUMERIC;
    v_credit        NUMERIC;
    v_base_debit    NUMERIC;
    v_base_credit   NUMERIC;
    v_currency      TEXT;
    v_desc          TEXT;
    v_actual_date   DATE;
    v_base_amount   NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = p_company_id) THEN
        RAISE EXCEPTION 'Company % not found', p_company_id;
    END IF;

    -- Timezone safeguard: if p_entry_date is null or matches UTC CURRENT_DATE while local Cairo date is ahead
    v_actual_date := COALESCE(p_entry_date, (NOW() AT TIME ZONE 'Africa/Cairo')::DATE);
    IF p_entry_date = CURRENT_DATE AND (NOW() AT TIME ZONE 'Africa/Cairo')::DATE != CURRENT_DATE THEN
        v_actual_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;
    END IF;

    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, created_by, company_id
    ) VALUES (
        v_entry_number, v_actual_date, p_description, 'posted',
        true, p_source_type, p_source_id, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit:= COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'Single line cannot have both debit and credit';
        END IF;

        IF v_debit = 0 AND v_credit = 0 THEN
            CONTINUE;
        END IF;

        v_total_debit  := v_total_debit + v_base_debit;
        v_total_credit := v_total_credit + v_base_credit;
        v_base_amount  := CASE WHEN v_debit > 0 THEN v_base_debit ELSE v_base_credit END;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, v_base_amount, v_desc, p_company_id
        );
    END LOOP;

    IF ABS(v_total_debit - v_total_credit) > 0.05 THEN
        RAISE EXCEPTION 'Journal entry unbalanced in base currency: Total Base Debit = %, Total Base Credit = %', v_total_debit, v_total_credit;
    END IF;

    RETURN v_je_id;
END;
$$;

-- 5. Update deposit_treasury with Local Timezone Date
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_revenue_account_id integer DEFAULT NULL::integer
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
    v_entry_date DATE;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Lock treasury balance row
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
        v_entry_date,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct,  'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- 5. Update / Upsert treasury_balances
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
        'rate_date', v_entry_date,
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

-- 6. Update deposit_bank_account with Local Timezone Date
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

-- 7. Ensure Unpaid Liabilities View has uniform TEXT IDs for casting safety
DROP VIEW IF EXISTS public.vw_unpaid_liabilities CASCADE;

CREATE OR REPLACE VIEW public.vw_unpaid_liabilities AS
-- 1. Purchase Invoices (مشتريات خامات)
SELECT 
    'purchase_invoice'::text as liability_type,
    id::text as liability_id,
    invoice_number as reference_number,
    'supplier'::text as entity_type,
    supplier_id::text as entity_id,
    currency,
    jsonb_build_object('exchange_rate', COALESCE((currency_snapshot->>'exchange_rate')::numeric, 1.0)) as currency_snapshot,
    (total_amount - discount_amount - COALESCE(paid_amount, 0)) as due_amount,
    invoice_date as liability_date
FROM public.purchase_invoices
WHERE payment_status IN ('unpaid', 'partial')
  AND (total_amount - discount_amount - COALESCE(paid_amount, 0)) > 0.001

UNION ALL

-- 2. Crop Purchases / Lot Receipts (مشتريات محاصيل)
SELECT 
    'lot_receipt'::text as liability_type,
    id::text as liability_id,
    COALESCE(lot_number, 'لوت #' || id::text) as reference_number,
    'supplier'::text as entity_type,
    supplier_id::text as entity_id,
    COALESCE(currency, 'EGP') as currency,
    jsonb_build_object('exchange_rate', COALESCE(exchange_rate, 1.0)) as currency_snapshot,
    (COALESCE(total_fruit_cost, 0) - COALESCE(paid_amount, 0)) as due_amount,
    receipt_date as liability_date
FROM public.lot_receipts
WHERE is_confirmed = true
  AND (COALESCE(total_fruit_cost, 0) - COALESCE(paid_amount, 0)) > 0.001
  AND supplier_id IS NOT NULL

UNION ALL

-- 3. Packing Order Cost Items (تكاليف تعبئة)
SELECT 
    'packing_cost_item'::text as liability_type,
    id::text as liability_id,
    COALESCE(name, 'تكلفة تعبئة') as reference_number,
    'supplier'::text as entity_type,
    supplier_id::text as entity_id,
    COALESCE(NULLIF(original_currency, ''), 'EGP') as currency,
    jsonb_build_object('exchange_rate', COALESCE(exchange_rate, 1.0)) as currency_snapshot,
    (COALESCE(original_amount, 0) - COALESCE(paid_amount, 0)) as due_amount,
    created_at::date as liability_date
FROM public.packing_order_cost_items
WHERE supplier_id IS NOT NULL 
  AND supplier_id != '' 
  AND payment_source_type IN (NULL, 'none') 
  AND treasury_transaction_id IS NULL 
  AND bank_transaction_id IS NULL
  AND payment_status IN ('unpaid', 'partial')
  AND (COALESCE(original_amount, 0) - COALESCE(paid_amount, 0)) > 0.001

UNION ALL

-- 4. Shipment Cost Items (تكاليف شحن، تخليص، وبنود تكلفة موردين من صفحة الربحية)
SELECT 
    'shipment_cost_item'::text as liability_type,
    id::text as liability_id,
    COALESCE(description, 'تكلفة شحن/تخليص') as reference_number,
    CASE 
        WHEN shipping_company_id IS NOT NULL THEN 'shipping_company'
        WHEN clearing_agent_id IS NOT NULL THEN 'clearing_agent'
        WHEN supplier_id IS NOT NULL AND supplier_id != '' THEN 'supplier'
        ELSE LOWER(COALESCE(vendor_type, 'supplier'))
    END as entity_type,
    CASE 
        WHEN shipping_company_id IS NOT NULL THEN shipping_company_id::text
        WHEN clearing_agent_id IS NOT NULL THEN clearing_agent_id::text
        WHEN supplier_id IS NOT NULL AND supplier_id != '' THEN supplier_id::text
        ELSE vendor_id::text
    END as entity_id,
    COALESCE(NULLIF(original_currency, ''), NULLIF(supplier_currency, ''), 'EGP') as currency,
    jsonb_build_object('exchange_rate', COALESCE(exchange_rate, 1.0)) as currency_snapshot,
    (COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) - COALESCE(paid_amount, 0)) as due_amount,
    created_at::date as liability_date
FROM public.shipment_cost_items
WHERE treasury_transaction_id IS NULL 
  AND bank_transaction_id IS NULL
  AND payment_source_type IN (NULL, 'none')
  AND payment_status IN ('unpaid', 'partial')
  AND (COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) - COALESCE(paid_amount, 0)) > 0.001;

-- 8. Unified Entity Multi-Payment Function with Explicit Safe Casting
CREATE OR REPLACE FUNCTION public.rpc_entity_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_entity_type text,
    p_entity_id text,
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
    v_initial_je_id BIGINT;
    v_je_id BIGINT;
    v_company_id UUID;
    v_source_acct BIGINT;
    v_entity_acct BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_book_rate NUMERIC := 1.0;
    v_remaining_to_allocate NUMERIC := p_amount;
    v_liab RECORD;
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
    v_entity_name TEXT;
    v_source_name TEXT;
    v_desc TEXT;
    v_supplier_uuid UUID;
    v_norm_entity_type TEXT;
    v_doc_type TEXT;
    v_entry_date DATE;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    v_norm_entity_type := LOWER(p_entity_type);
    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Fetch entity info & GL account based on normalized entity type
    IF v_norm_entity_type = 'supplier' THEN
        v_supplier_uuid := p_entity_id::uuid;
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.suppliers WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.shipping_companies WHERE id = p_entity_id::integer;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.clearing_agents WHERE id = p_entity_id::integer;
    ELSE
        RAISE EXCEPTION 'نوع الجهة غير صالح: %', p_entity_type;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_entity_acct IS NULL THEN
        IF v_norm_entity_type = 'supplier' THEN
            v_entity_acct := public.resolve_gl_account('2000', v_company_id);
        ELSIF v_norm_entity_type = 'shipping_company' THEN
            v_entity_acct := public.resolve_gl_account('2103', v_company_id);
        ELSIF v_norm_entity_type = 'clearing_agent' THEN
            v_entity_acct := public.resolve_gl_account('2104', v_company_id);
        END IF;
    END IF;

    -- 2. Resolve Source Book Rate and GL Account
    IF p_source_type = 'treasury' THEN
        v_doc_type := 'treasury_multi_payment';

        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.treasury_balances
        WHERE treasury_id::text = p_source_id::text AND currency = p_currency;

        SELECT name INTO v_source_name FROM public.treasuries WHERE id = p_source_id;
        v_source_acct := public.resolve_treasury_account(p_source_id::integer, p_currency, v_company_id);
    ELSIF p_source_type = 'bank' THEN
        v_doc_type := 'bank_multi_payment';

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

    -- 3. Execute Cash / Bank Payment (Withdrawal)
    IF p_source_type = 'treasury' THEN
        v_tx_id := public.spend_custody(
            p_treasury_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
            p_supplier_id := CASE WHEN v_norm_entity_type = 'supplier' THEN v_supplier_uuid ELSE NULL END,
            p_clearing_agent_id := CASE WHEN v_norm_entity_type = 'clearing_agent' THEN p_entity_id::bigint ELSE NULL END,
            p_shipping_company_id := CASE WHEN v_norm_entity_type = 'shipping_company' THEN p_entity_id::bigint ELSE NULL END,
            p_expense_account_id := COALESCE(p_expense_account_id, v_entity_acct::integer),
            p_reference_type := v_norm_entity_type || '_payment',
            p_reference_id := p_entity_id,
            p_notes := p_notes
        );
        SELECT journal_entry_id INTO v_initial_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
    ELSIF p_source_type = 'bank' THEN
        DECLARE
            v_bank_res JSONB;
        BEGIN
            v_bank_res := public.withdraw_bank_account(
                p_account_id := p_source_id::INTEGER,
                p_amount := p_amount,
                p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
                p_entity_type := v_norm_entity_type,
                p_entity_id := p_entity_id,
                p_counterparty_name := v_entity_name,
                p_expense_account_id := COALESCE(p_expense_account_id, v_entity_acct::integer),
                p_notes := p_notes,
                p_reference_type := v_norm_entity_type || '_payment',
                p_reference_id := p_entity_id
            );
            v_tx_id := (v_bank_res->>'transaction_id')::BIGINT;
            v_initial_je_id := (v_bank_res->>'journal_entry_id')::BIGINT;
        END;
    END IF;

    -- 4. Calculate Remaining Opening Balance to Allocate
    IF v_norm_entity_type = 'supplier' AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_opening_paid
        FROM public.supplier_payment_allocations
        WHERE supplier_id = v_supplier_uuid AND allocation_type = 'opening_balance';

        v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
    ELSIF v_norm_entity_type IN ('shipping_company', 'clearing_agent') AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        v_opening_remaining := v_initial_balance;
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

        IF v_norm_entity_type = 'supplier' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
            ) VALUES (
                p_source_type, v_tx_id, NULL, v_supplier_uuid, 'opening_balance', v_opening_alloc
            );
        END IF;

        v_total_ap_base := v_total_ap_base + ROUND(v_opening_alloc * v_book_rate, 2);
        v_remaining_to_allocate := v_remaining_to_allocate - v_opening_alloc;
    END IF;

    -- 6. Allocation Priority 2: Unpaid Liabilities (FIFO by liability_date)
    FOR v_liab IN 
        SELECT liability_type, liability_id, reference_number, currency, currency_snapshot, due_amount
        FROM public.vw_unpaid_liabilities
        WHERE LOWER(entity_type) = v_norm_entity_type
          AND entity_id = p_entity_id
          AND currency = p_currency
        ORDER BY liability_date ASC, liability_id ASC
    LOOP
        EXIT WHEN v_remaining_to_allocate <= 0;

        IF v_remaining_to_allocate >= v_liab.due_amount THEN
            v_allocation_amount := v_liab.due_amount;
        ELSE
            v_allocation_amount := v_remaining_to_allocate;
        END IF;

        -- Extract Invoice Original Pegged Exchange Rate
        v_inv_rate := COALESCE(
            (v_liab.currency_snapshot->>'exchange_rate')::NUMERIC,
            public.fn_get_exchange_rate(p_currency)
        );

        -- Realized FX Math (IAS 21):
        v_inv_base  := ROUND(v_allocation_amount * v_inv_rate, 2);
        v_paid_base := ROUND(v_allocation_amount * v_book_rate, 2);
        v_diff      := v_paid_base - v_inv_base;

        v_total_ap_base := v_total_ap_base + v_inv_base;

        IF v_diff < 0 THEN
            v_total_realized_gain := v_total_realized_gain + ABS(v_diff);
        ELSIF v_diff > 0 THEN
            v_total_realized_loss := v_total_realized_loss + v_diff;
        END IF;

        -- Update the specific liability table
        IF v_liab.liability_type = 'purchase_invoice' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::uuid, v_supplier_uuid, 'invoice', v_allocation_amount
                );
            END IF;
            UPDATE public.purchase_invoices
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= (total_amount - discount_amount) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id = v_liab.liability_id::uuid;
            
        ELSIF v_liab.liability_type = 'lot_receipt' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, lot_receipt_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'lot_receipt', v_allocation_amount
                );
            END IF;
            UPDATE public.lot_receipts
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(total_fruit_cost, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type,
                updated_at = NOW()
            WHERE id = v_liab.liability_id::bigint;
            
        ELSIF v_liab.liability_type = 'packing_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, packing_order_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'packing_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.packing_order_cost_items
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(original_amount, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id = v_liab.liability_id::bigint;
            
        ELSIF v_liab.liability_type = 'shipment_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, shipment_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'shipment_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.shipment_cost_items
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id = v_liab.liability_id::bigint;
        END IF;

        v_invoices_allocated_count := v_invoices_allocated_count + 1;
        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- 7. Allocation Priority 3: Advance Payment / Credit Balance
    IF v_remaining_to_allocate > 0 THEN
        v_advance_alloc := v_remaining_to_allocate;
        IF v_norm_entity_type = 'supplier' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, supplier_id, allocation_type, amount
            ) VALUES (
                p_source_type, v_tx_id, v_supplier_uuid, 'advance', v_advance_alloc
            );
        END IF;
        v_total_ap_base := v_total_ap_base + ROUND(v_advance_alloc * v_book_rate, 2);
    END IF;

    -- 8. Post Single Authoritative Multi-Payment Journal Entry (TMPY / BMPY)
    v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
    v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);

    v_desc := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name);

    v_je_lines := jsonb_build_array(
        jsonb_build_object(
            'account_id', v_entity_acct,
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
                'description', 'خسائر فروق أسعار عملة محققة - ' || v_entity_name
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
                'description', 'أرباح فروق أسعار عملة محققة - ' || v_entity_name
            )
        );
    END IF;

    -- Create single authoritative journal entry with TMPY or BMPY sequence
    v_je_id := public.post_journal_entry(
        v_doc_type,
        v_desc,
        v_entry_date,
        v_company_id,
        auth.uid(),
        v_je_lines,
        p_entity_id
    );

    -- Attach new authoritative journal entry to transaction
    IF p_source_type = 'treasury' THEN
        UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
    ELSIF p_source_type = 'bank' THEN
        UPDATE public.bank_account_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
    END IF;

    -- Clean up intermediate duplicate journal entry created by spend_custody / withdraw_bank_account
    IF v_initial_je_id IS NOT NULL AND v_initial_je_id != v_je_id THEN
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_initial_je_id;
        DELETE FROM public.journal_entries WHERE id = v_initial_je_id;
    END IF;

    -- 9. Recalculate & update outstanding_balance
    IF v_norm_entity_type = 'supplier' THEN
        UPDATE public.suppliers
        SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = v_supplier_uuid)
        WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET balance = balance - p_amount
        WHERE id = p_entity_id::integer;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET balance = balance - p_amount
        WHERE id = p_entity_id::integer;
    END IF;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'opening_balance_allocated', v_opening_alloc,
        'liabilities_allocated_count', v_invoices_allocated_count,
        'liabilities_allocated_amount', p_amount - v_opening_alloc - v_advance_alloc,
        'advance_amount', v_advance_alloc,
        'realized_fx_gain', v_total_realized_gain,
        'realized_fx_loss', v_total_realized_loss
    );
END;
$$;

-- 9. Update rpc_confirm_treasury_draft
CREATE OR REPLACE FUNCTION public.rpc_confirm_treasury_draft(
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
    v_receipt_type TEXT;
    v_counterparty_type TEXT;
    v_mp_source_type TEXT;
    v_mp_source_id BIGINT;
BEGIN
    SELECT * INTO v_tx
    FROM public.treasury_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    IF v_tx.type = 'deposit' OR v_tx.type = 'receipt' THEN
        v_receipt_type := COALESCE(v_tx.payload->>'receipt_type', 'cash');
        v_counterparty_type := v_tx.payload->>'counterparty_type';

        v_res := public.receive_payment(
            p_receipt_type      := v_receipt_type,
            p_amount            := v_tx.amount,
            p_currency          := v_tx.currency,
            p_counterparty_type := v_counterparty_type,
            p_counterparty_id   := v_tx.customer_id,
            p_supplier_id       := v_tx.supplier_id,
            p_shareholder_id    := v_tx.shareholder_id,
            p_description       := v_tx.description,
            p_notes             := v_tx.notes,
            p_treasury_id       := v_tx.treasury_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الاستلام وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'multi_payment' OR COALESCE((v_tx.payload->>'is_multi_payment')::boolean, false) = true THEN
        v_mp_source_type := COALESCE(v_tx.payload->>'source_type', 'treasury');
        v_mp_source_id   := COALESCE(
            (v_tx.payload->>'source_id')::bigint,
            v_tx.treasury_id::bigint
        );

        v_res := public.rpc_entity_multi_payment(
            p_source_type        := v_mp_source_type,
            p_source_id          := v_mp_source_id,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_entity_type        := LOWER(COALESCE(v_tx.payload->>'entity_type', 'supplier')),
            p_entity_id          := COALESCE(v_tx.payload->>'entity_id', v_tx.supplier_id::text),
            p_description        := COALESCE(v_tx.description, 'سداد متعدد'),
            p_expense_account_id := v_tx.expense_account_id,
            p_notes              := v_tx.notes
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد السداد المتعدد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'exchange' OR v_tx.type = 'currency_exchange' THEN
        PERFORM public.exchange_currency(
            p_treasury_id   := v_tx.treasury_id::text,
            p_from_currency := COALESCE(v_tx.payload->>'from_currency', v_tx.currency),
            p_to_currency   := (v_tx.payload->>'to_currency')::text,
            p_amount_from   := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to     := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate := (v_tx.payload->>'exchange_rate')::numeric,
            p_user_id       := v_tx.created_by,
            p_description   := COALESCE(v_tx.description, 'تحويل عملة')
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة بنجاح');

    ELSIF v_tx.type = 'expense' OR v_tx.type = 'withdrawal' THEN
        v_res := public.spend_custody(
            p_treasury_id        := v_tx.treasury_id::bigint,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_description        := v_tx.description,
            p_supplier_id        := CASE WHEN v_tx.supplier_id IS NOT NULL AND v_tx.supplier_id != '' THEN v_tx.supplier_id::uuid ELSE NULL END,
            p_expense_account_id := v_tx.expense_account_id,
            p_notes              := v_tx.notes,
            p_customer_id        := CASE WHEN v_tx.customer_id IS NOT NULL AND v_tx.customer_id != '' AND v_tx.customer_id != '0' THEN v_tx.customer_id::integer ELSE NULL END,
            p_clearing_agent_id  := CASE WHEN v_tx.clearing_agent_id IS NOT NULL AND v_tx.clearing_agent_id != '' AND v_tx.clearing_agent_id != '0' THEN v_tx.clearing_agent_id::integer ELSE NULL END,
            p_shipping_company_id := CASE WHEN v_tx.shipping_company_id IS NOT NULL AND v_tx.shipping_company_id != '' AND v_tx.shipping_company_id != '0' THEN v_tx.shipping_company_id::integer ELSE NULL END,
            p_shareholder_id     := CASE WHEN v_tx.shareholder_id IS NOT NULL AND v_tx.shareholder_id != '' THEN v_tx.shareholder_id::uuid ELSE NULL END
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد المصروف وترحيل القيد بنجاح', 'result', v_res);
    ELSE
        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;
    END IF;
END;
$$;

-- Replace wrapper
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
AS $$
BEGIN
    RETURN public.rpc_entity_multi_payment(
        p_source_type, p_source_id, p_currency, p_amount, 'supplier', p_supplier_id::text, p_description, p_expense_account_id, p_notes
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_journal_entry(text, text, date, uuid, uuid, jsonb, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.deposit_treasury(bigint, text, numeric, text, integer) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, integer, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_supplier_multi_payment(text, bigint, text, numeric, uuid, text, integer, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_confirm_treasury_draft(bigint) TO authenticated, anon, service_role;
GRANT SELECT ON public.vw_unpaid_liabilities TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';

COMMIT;
