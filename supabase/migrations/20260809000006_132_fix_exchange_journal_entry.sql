-- Migration 132: Fix currency exchange journal entry balancing

BEGIN;

DROP FUNCTION IF EXISTS public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB);

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
    v_line_count    INT;
BEGIN
    -- Validate lines array
    v_line_count := jsonb_array_length(p_lines);
    IF v_line_count IS NULL OR v_line_count < 2 THEN
        RAISE EXCEPTION 'Journal entry must have at least 2 lines (got %)', v_line_count;
    END IF;

    -- Validate company exists
    IF NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = p_company_id) THEN
        RAISE EXCEPTION 'Company % not found', p_company_id;
    END IF;

    -- Generate entry number using the sequence function
    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    -- Create journal entry header with real entry number
    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, created_by, company_id
    ) VALUES (
        v_entry_number, p_entry_date, p_description, 'posted',
        true, p_source_type, p_source_id, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    -- Process each line
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit:= COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        -- Validate account exists
        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        -- Validate amounts
        IF v_debit < 0 OR v_credit < 0 THEN
            RAISE EXCEPTION 'Debit and credit amounts must be non-negative (debit=%, credit=%)', v_debit, v_credit;
        END IF;
        IF v_debit = 0 AND v_credit = 0 THEN
            RAISE EXCEPTION 'Both debit and credit cannot be zero for a single line';
        END IF;
        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'A single line cannot have both debit and credit (debit=%, credit=%)', v_debit, v_credit;
        END IF;

        v_total_debit  := v_total_debit + v_base_debit;
        v_total_credit := v_total_credit + v_base_credit;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, COALESCE(v_base_debit, 0) + COALESCE(v_base_credit, 0), v_desc, p_company_id
        );
    END LOOP;

    -- Validate balanced entry
    IF v_total_debit != v_total_credit THEN
        RAISE EXCEPTION 'Journal entry is not balanced: total debit % != total credit %', v_total_debit, v_total_credit;
    END IF;
    IF v_total_debit = 0 THEN
        RAISE EXCEPTION 'Journal entry has zero total amount';
    END IF;

    RETURN v_je_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;

CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id    BIGINT,
    p_from_currency  VARCHAR,
    p_to_currency    VARCHAR,
    p_amount_from    NUMERIC,
    p_amount_to      NUMERIC,
    p_exchange_rate  NUMERIC,
    p_user_id        UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance_before_from DECIMAL(15,2);
    v_balance_after_from  DECIMAL(15,2);
    v_balance_before_to   DECIMAL(15,2);
    v_balance_after_to    DECIMAL(15,2);
    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    SELECT balance INTO v_balance_before_from
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    INSERT INTO treasury_balances (treasury_id, currency, balance)
    VALUES (p_treasury_id, p_to_currency, 0.00)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance INTO v_balance_before_to
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

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

    UPDATE treasury_balances
    SET balance = v_balance_after_from
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency;

    v_je_id := public.post_journal_entry(
        'currency_exchange',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_from, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', p_amount_from, 'currency', p_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency, v_desc,
        v_balance_before_from, v_balance_after_from, v_je_id, p_user_id
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency, v_desc,
        v_balance_before_to, v_balance_after_to, v_je_id, p_user_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id
    );
END;
$$;

COMMIT;
