-- ============================================================================
-- 040_fix_v_company_id_and_drop_legacy_overloads.sql
--
-- CRITICAL FIX: post_journal_entry used undeclared variable v_company_id
-- instead of parameter p_company_id. This broke ALL financial operations.
--
-- CLEANUP: Drop old BIGINT overloads that write 'PENDING' as entry_number
-- and bypass the unified posting engine. These overloads are never called
-- by the current Dart code (which uses INTEGER overloads).
--
-- FIX: Add source_type column to bank_account_transactions if missing.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. CRITICAL FIX: post_journal_entry — v_company_id → p_company_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type  TEXT,
    p_description  TEXT,
    p_entry_date   DATE,
    p_company_id   UUID,
    p_created_by   UUID,
    p_lines        JSONB
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
    v_currency      TEXT;
    v_desc          TEXT;
    v_line_count    INT;
BEGIN
    v_line_count := jsonb_array_length(p_lines);
    IF v_line_count IS NULL OR v_line_count < 2 THEN
        RAISE EXCEPTION 'Journal entry must have at least 2 lines (got %)', v_line_count;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = p_company_id) THEN
        RAISE EXCEPTION 'Company % not found', p_company_id;
    END IF;

    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        v_entry_number, p_entry_date, p_description, 'posted',
        true, p_source_type, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        IF v_debit < 0 OR v_credit < 0 THEN
            RAISE EXCEPTION 'Debit and credit amounts must be non-negative (debit=%, credit=%)', v_debit, v_credit;
        END IF;
        IF v_debit = 0 AND v_credit = 0 THEN
            RAISE EXCEPTION 'Both debit and credit cannot be zero for a single line';
        END IF;
        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'A single line cannot have both debit and credit (debit=%, credit=%)', v_debit, v_credit;
        END IF;

        v_total_debit  := v_total_debit + v_debit;
        v_total_credit := v_total_credit + v_credit;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, COALESCE(v_debit, 0) + COALESCE(v_credit, 0), v_desc, p_company_id
        );
    END LOOP;

    IF v_total_debit != v_total_credit THEN
        RAISE EXCEPTION 'Journal entry is not balanced: total debit % != total credit %', v_total_debit, v_total_credit;
    END IF;
    IF v_total_debit = 0 THEN
        RAISE EXCEPTION 'Journal entry has zero total amount';
    END IF;

    RETURN v_je_id;
END;
$$;

-- ============================================================================
-- 2. DROP old BIGINT overloads that bypass unified engine
-- ============================================================================

-- Drop old deposit_treasury(BIGINT) overload — writes 'PENDING' entry_number
DROP FUNCTION IF EXISTS public.deposit_treasury(
    p_treasury_id BIGINT, p_currency TEXT, p_amount NUMERIC,
    p_description TEXT, p_customer_id BIGINT, p_supplier_id TEXT,
    p_shareholder_id TEXT, p_clearing_agent_id BIGINT,
    p_shipping_company_id BIGINT, p_exchange_rate NUMERIC
);

-- Drop old withdraw_treasury(BIGINT) overload — writes 'PENDING' entry_number
DROP FUNCTION IF EXISTS public.withdraw_treasury(
    p_treasury_id BIGINT, p_currency TEXT, p_amount NUMERIC,
    p_description TEXT, p_customer_id BIGINT, p_supplier_id TEXT,
    p_shareholder_id TEXT, p_clearing_agent_id BIGINT,
    p_shipping_company_id BIGINT, p_exchange_rate NUMERIC
);

-- Drop old deposit_bank_account(BIGINT) overload — writes 'PENDING' entry_number
DROP FUNCTION IF EXISTS public.deposit_bank_account(
    p_bank_account_id BIGINT, p_currency TEXT, p_amount NUMERIC,
    p_description TEXT, p_exchange_rate NUMERIC
);

-- Drop old withdraw_bank_account(BIGINT) overload — writes 'PENDING' entry_number
DROP FUNCTION IF EXISTS public.withdraw_bank_account(
    p_bank_account_id BIGINT, p_currency TEXT, p_amount NUMERIC,
    p_description TEXT, p_exchange_rate NUMERIC
);

-- ============================================================================
-- 3. Ensure deposit_bank_account has source_type in INSERT
-- ============================================================================

CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id        INTEGER,
    p_amount            NUMERIC,
    p_description       TEXT DEFAULT NULL,
    p_entity_type       TEXT DEFAULT NULL,
    p_entity_id         TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_revenue_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'الرصيد الافتتاحي للحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account('11201', v_company_id);
    v_revenue_acct := public.resolve_gl_account('41101', v_company_id);

    v_je_id := public.post_journal_entry(
        CASE WHEN v_source_type = 'opening_balance' THEN 'opening_balance' ELSE 'bank_deposit' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name, source_type, journal_entry_id
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_source_type, v_je_id
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('customer', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('supplier', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('clearing_agent', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shipping_company', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shareholder', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    END IF;

    RETURN jsonb_build_object('success', true, 'bank_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;

-- ============================================================================
-- 4. Ensure withdraw_bank_account has source_type in INSERT
-- ============================================================================

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id        INTEGER,
    p_amount            NUMERIC,
    p_description       TEXT DEFAULT NULL,
    p_entity_type       TEXT DEFAULT NULL,
    p_entity_id         TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية (الرصيد الحالي: %)', v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب رصيد افتتاحي من الحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account('11201', v_company_id);
    v_expense_acct := public.resolve_gl_account('51101', v_company_id);

    v_je_id := public.post_journal_entry(
        CASE WHEN v_source_type = 'opening_balance' THEN 'opening_balance' ELSE 'bank_withdraw' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name, source_type, journal_entry_id
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_source_type, v_je_id
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('customer', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::text = p_entity_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('supplier', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('clearing_agent', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id = p_entity_id::bigint;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shipping_company', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shareholder', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    END IF;

    RETURN jsonb_build_object('success', true, 'bank_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;

-- ============================================================================
-- 5. Ensure deposit_treasury(INTEGER) has source_type and opening balance desc
-- ============================================================================

CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id   INTEGER,
    p_currency      TEXT,
    p_amount        NUMERIC,
    p_description   TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
    );

    -- Current balance
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    -- Upsert treasury balance
    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (p_treasury_id, p_currency, v_new_balance,
        public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        )
    )
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance;

    -- GL accounts
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Treasury / Cr.Owner Equity
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_equity_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        COALESCE(v_current_balance, 0), v_new_balance, v_desc, 'opening_balance', v_je_id, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$$;

-- ============================================================================
-- 6. Ensure withdraw_treasury(INTEGER) has source_type
-- ============================================================================

CREATE OR REPLACE FUNCTION public.withdraw_treasury(
    p_treasury_id INTEGER,
    p_currency    TEXT,
    p_amount      NUMERIC,
    p_description TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    -- Current balance check
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (الرصيد الحالي: % %)', v_current_balance, p_currency;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'سحب من ' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
    );

    -- GL accounts
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Owner Equity / Cr.Treasury
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_equity_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Update treasury balance
    UPDATE treasury_balances SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance', v_je_id, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$$;

-- ============================================================================
-- 7. GRANT permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION deposit_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION withdraw_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION deposit_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 8. Cleanup orphaned journal entries with PENDING entry_number
-- ============================================================================

-- Delete orphaned journal entries and their ledger lines that have PENDING entry_number
-- (These were created by the old BIGINT overloads)
DO $$
DECLARE
    v_pending_je RECORD;
BEGIN
    FOR v_pending_je IN
        SELECT id FROM journal_entries WHERE entry_number = 'PENDING'
    LOOP
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_pending_je.id;
        DELETE FROM journal_entries WHERE id = v_pending_je.id;
    END LOOP;
END;
$$;

-- Delete orphaned account_ledger_entries with no matching journal_entry
DELETE FROM account_ledger_entries
WHERE journal_entry_id NOT IN (SELECT id FROM journal_entries);

-- Delete orphaned treasury_transactions with no matching journal_entry (where journal_entry_id is set)
DELETE FROM treasury_transactions
WHERE journal_entry_id IS NOT NULL
AND journal_entry_id NOT IN (SELECT id FROM journal_entries);

COMMIT;
