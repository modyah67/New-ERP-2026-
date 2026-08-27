-- Migration 037: Phase B — Unified Accounting Engine
-- Architecture: all financial ops → post_journal_entry → journal_entries + account_ledger_entries
-- No more transactions table writes. No more LIMIT 1 fallbacks.
--
-- 1. Ensure missing GL accounts exist
-- 2. Create unified post_journal_entry() function
-- 3. Rewrite ALL 12 financial operations to use it
-- 4. Create new bank_transfer and transfer_between_treasuries functions

-- ============================================================================
-- SECTION 1: MISSING GL ACCOUNTS
-- ============================================================================

-- SECTION 1: MISSING GL ACCOUNTS

-- 11201: Bank Company Account (was missing)
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '11201', 'Bank - Company Account', 'Bank Company Account', 'asset',
       (SELECT id FROM accounts WHERE account_code = '1010' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '11201' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 41101: General Revenue (was missing)
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '41101', 'General Revenue', 'General Revenue', 'revenue',
       (SELECT id FROM accounts WHERE account_code = '4000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Credit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '41101' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 4200: Export Revenue
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '4200', 'Export Revenue', 'Export Revenue', 'revenue',
       (SELECT id FROM accounts WHERE account_code = '4' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Credit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '4200' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 4300: Other Revenue
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '4300', 'Other Revenue', 'Other Revenue', 'revenue',
       (SELECT id FROM accounts WHERE account_code = '4' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Credit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '4300' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 51101: General Expenses (was missing)
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '51101', 'General Expenses', 'General Expenses', 'expense',
       (SELECT id FROM accounts WHERE account_code = '6000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '51101' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 6110: Shipping Expenses
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '6110', 'Shipping Expenses', 'Shipping Expenses', 'expense',
       (SELECT id FROM accounts WHERE account_code = '6000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '6110' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 6120: Packing Expenses
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '6120', 'Packing Expenses', 'Packing Expenses', 'expense',
       (SELECT id FROM accounts WHERE account_code = '6000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '6120' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 6130: Operating Expenses
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '6130', 'Operating Expenses', 'Operating Expenses', 'expense',
       (SELECT id FROM accounts WHERE account_code = '6000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '6130' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 6140: Administrative Expenses
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '6140', 'Administrative Expenses', 'Administrative Expenses', 'expense',
       (SELECT id FROM accounts WHERE account_code = '6000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '6140' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 6150: Currency Differences
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '6150', 'Currency Differences', 'Currency Differences', 'expense',
       (SELECT id FROM accounts WHERE account_code = '6000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '6150' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 2200: Taxes Payable
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '2200', 'Taxes Payable', 'Taxes Payable', 'liability',
       (SELECT id FROM accounts WHERE account_code = '20' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Credit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '2200' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 2300: Accrued Liabilities
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '2300', 'Accrued Liabilities', 'Accrued Liabilities', 'liability',
       (SELECT id FROM accounts WHERE account_code = '20' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Credit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '2300' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 3300: Capital Reserve
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '3300', 'Capital Reserve', 'Capital Reserve', 'equity',
       (SELECT id FROM accounts WHERE account_code = '3' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Credit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '3300' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 11111: Treasury USD
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '11111', 'Treasury - USD', 'Treasury USD', 'asset',
       (SELECT id FROM accounts WHERE account_code = '1000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '11111' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 11112: Treasury EUR
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '11112', 'Treasury - EUR', 'Treasury EUR', 'asset',
       (SELECT id FROM accounts WHERE account_code = '1000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '11112' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');

-- 11113: Treasury GBP
INSERT INTO accounts (account_code, name, account_name, account_type, parent_id, is_leaf, is_system, allow_posting, normal_balance, company_id)
SELECT '11113', 'Treasury - GBP', 'Treasury GBP', 'asset',
       (SELECT id FROM accounts WHERE account_code = '1000' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5' LIMIT 1),
       true, false, true, 'Debit', 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '11113' AND company_id = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5');
-- ============================================================================

-- post_journal_entry: the single entry point for ALL GL posting
-- Receives: source_type, description, entry_date, company_id, created_by, array of lines
-- Each line: {account_id, debit, credit, currency, description}
-- Returns: the journal_entry_id
-- Validates: debits = credits, all accounts exist, no zero amounts

CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type   TEXT,
    p_description   TEXT,
    p_entry_date    DATE,
    p_company_id    UUID,
    p_created_by    UUID,
    p_lines         JSONB
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
    v_entry_number := public.fn_get_next_sequence(v_company_id, p_source_type, NULL, NULL);

    -- Create journal entry header with real entry number
    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        v_entry_number, p_entry_date, p_description, 'posted',
        true, p_source_type, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    -- Process each line
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        -- Validate account exists — NO fallback, NO LIMIT 1
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

-- Helper: resolve GL account ID by code and company — RAISES on missing
CREATE OR REPLACE FUNCTION public.resolve_gl_account(
    p_account_code TEXT,
    p_company_id   UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT id INTO v_id
    FROM accounts
    WHERE account_code = p_account_code AND company_id = p_company_id;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'GL Account % not found for company %', p_account_code, p_company_id;
    END IF;

    RETURN v_id;
END;
$$;


-- ============================================================================
-- SECTION 3: REWRITE ALL FINANCIAL OPERATIONS
-- ============================================================================

-- ============================================================================
-- 3.1 deposit_treasury: treasury deposit + GL (Dr.Treasury / Cr.Owner Equity)
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
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Resolve company from treasury
    SELECT tb.account_id, t.company_id INTO v_treasury_acct, v_company_id
    FROM treasury_balances tb
    JOIN treasuries t ON t.id = tb.treasury_id
    WHERE tb.treasury_id = p_treasury_id AND tb.currency = p_currency;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع خزينة');

    -- Upsert treasury balance
    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (p_treasury_id, p_currency, p_amount,
        (SELECT id FROM accounts WHERE account_code = (
            CASE p_currency
                WHEN 'EGP' THEN '11101'
                WHEN 'USD' THEN '11102'
                WHEN 'EUR' THEN '11103'
                WHEN 'GBP' THEN '11104'
            END
        ) AND company_id = v_company_id)
    )
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = treasury_balances.balance + p_amount
    RETURNING balance INTO v_new_balance;

    IF NOT FOUND THEN
        SELECT balance INTO v_current_balance
        FROM treasury_balances
        WHERE treasury_id = p_treasury_id AND currency = p_currency;
        v_new_balance := v_current_balance + p_amount;
        UPDATE treasury_balances SET balance = v_new_balance
        WHERE treasury_id = p_treasury_id AND currency = p_currency;
    ELSE
        v_current_balance := v_new_balance - p_amount;
    END IF;

    -- Treasury GL account for this currency
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency
            WHEN 'EGP' THEN '11101'
            WHEN 'USD' THEN '11102'
            WHEN 'EUR' THEN '11103'
            WHEN 'GBP' THEN '11104'
        END,
        v_company_id
    );
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Treasury / Cr.Owner Equity
    v_je_id := public.post_journal_entry(
        'treasury_deposit',
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
        balance_before, balance_after, description, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        COALESCE(v_current_balance, 0), v_new_balance, v_desc, v_je_id, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$$;


-- ============================================================================
-- 3.2 withdraw_treasury: treasury withdrawal + GL (Dr.Owner Equity / Cr.Treasury)
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
    v_desc            TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT balance INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد لهذه العملة';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE treasury_balances
    SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Resolve company
    SELECT t.company_id INTO v_company_id
    FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف خزينة');

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency
            WHEN 'EGP' THEN '11101'
            WHEN 'USD' THEN '11102'
            WHEN 'EUR' THEN '11103'
            WHEN 'GBP' THEN '11104'
        END,
        v_company_id
    );
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Owner Equity / Cr.Treasury
    v_je_id := public.post_journal_entry(
        'treasury_withdrawal',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_equity_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_je_id, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;


-- ============================================================================
-- 3.3 disburse_custody: transfer between treasuries + GL
--   Dr.Destination Treasury / Cr.Source Treasury
-- ============================================================================
CREATE OR REPLACE FUNCTION public.disburse_custody(
    p_from_treasury_id INTEGER,
    p_to_treasury_id   INTEGER,
    p_currency         TEXT,
    p_amount           NUMERIC,
    p_description      TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_je_id        BIGINT;
    v_desc         TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Lock and check source treasury balance
    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة المصدرة (المتوفر: %)', v_from_balance;
    END IF;

    -- Lock destination treasury balance
    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    -- Resolve company
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_from_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل بين خزائن');

    v_from_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    -- For destination, we use the same currency account since it's the same GL code
    -- (both treasuries map to the same currency GL account)
    v_to_acct := v_from_acct;

    -- Deduct from source
    UPDATE treasury_balances SET balance = balance - p_amount
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    -- Add to destination
    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance)
        VALUES (p_to_treasury_id, p_currency, p_amount);
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    -- Journal entry: Dr.Destination / Cr.Source
    v_je_id := public.post_journal_entry(
        'treasury_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (وصول)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال)')
        )
    );

    -- Record treasury transactions
    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_from_treasury_id, 'disbursement_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, auth.uid());

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_to_treasury_id, 'disbursement', p_currency, p_amount,
        COALESCE(v_to_balance, 0), COALESCE(v_to_balance, 0) + p_amount, v_desc,
        p_from_treasury_id, auth.uid());

    RETURN jsonb_build_object('journal_entry_id', v_je_id);
END;
$$;


-- ============================================================================
-- 3.4 receive_payment: customer payment + GL (Dr.Treasury / Cr.AR)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type       VARCHAR,
    p_amount             NUMERIC,
    p_currency           VARCHAR,
    p_counterparty_type  VARCHAR   DEFAULT NULL,
    p_counterparty_id    BIGINT    DEFAULT NULL,
    p_supplier_id        UUID      DEFAULT NULL,
    p_shareholder_id     UUID      DEFAULT NULL,
    p_description        TEXT      DEFAULT NULL,
    p_notes              TEXT      DEFAULT NULL,
    p_treasury_id        BIGINT    DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_treasury_id   BIGINT;
    v_balance       NUMERIC;
    v_tx_id         BIGINT;
    v_company_id    UUID;
    v_treasury_acct BIGINT;
    v_ar_acct       BIGINT;
    v_je_id         BIGINT;
    v_desc          TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Resolve treasury
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

    -- Resolve company
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = v_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'استلام ' || p_receipt_type);

    -- Upsert treasury balance
    INSERT INTO public.treasury_balances (treasury_id, currency, balance)
    VALUES (v_treasury_id, p_currency, p_amount)
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = treasury_balances.balance + p_amount
    RETURNING balance INTO v_balance;

    -- Treasury transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Resolve GL accounts
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    -- Journal entry: Dr.Treasury / Cr.Counterparty (AR for customer)
    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := public.resolve_gl_account('1020', v_company_id);
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id = p_supplier_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := public.resolve_gl_account('2000', v_company_id);
        v_je_id := public.post_journal_entry(
            'supplier_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_je_id := public.post_journal_entry(
            'clearing_agent_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_je_id := public.post_journal_entry(
            'shipping_company_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
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

        v_je_id := public.post_journal_entry(
            'shareholder_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSE
        -- No counterparty: just treasury deposit, GL only
        v_je_id := public.post_journal_entry(
            'treasury_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', public.resolve_gl_account('3000', v_company_id), 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    RETURN jsonb_build_object('success', true, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;


-- ============================================================================
-- 3.5 record_supplier_payment: supplier payment + GL (Dr.AP / Cr.Treasury)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_supplier_payment(
    p_supplier_id   UUID,
    p_amount        NUMERIC,
    p_currency      TEXT DEFAULT 'EGP',
    p_description   TEXT DEFAULT '',
    p_treasury_id   INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ledger_id     BIGINT;
    v_tx_id         INTEGER;
    v_company_id    UUID;
    v_treasury_acct BIGINT;
    v_ap_acct       BIGINT;
    v_je_id         BIGINT;
    v_desc          TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'دفع مورد');

    UPDATE suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;

    INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, 'debit', p_amount, p_currency, 'payment', v_desc, auth.uid())
    RETURNING id INTO v_ledger_id;

    IF p_treasury_id IS NOT NULL THEN
        -- Resolve company from treasury
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

        -- Treasury balance check + update
        DECLARE
            v_bal NUMERIC;
        BEGIN
            SELECT balance INTO v_bal
            FROM treasury_balances
            WHERE treasury_id = p_treasury_id AND currency = p_currency
            FOR UPDATE;

            IF v_bal IS NULL OR v_bal < p_amount THEN
                RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %)', COALESCE(v_bal, 0);
            END IF;

            UPDATE treasury_balances
            SET balance = balance - p_amount
            WHERE treasury_id = p_treasury_id AND currency = p_currency;
        END;

        INSERT INTO treasury_transactions (treasury_id, type, currency, amount, description, supplier_id, created_by)
        VALUES (p_treasury_id, 'supplier_payment', p_currency, p_amount, v_desc, p_supplier_id, auth.uid())
        RETURNING id INTO v_tx_id;

        -- GL: Dr.AP / Cr.Treasury
        v_treasury_acct := public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        );
        v_ap_acct := public.resolve_gl_account('2000', v_company_id);

        v_je_id := public.post_journal_entry(
            'supplier_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_ap_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;


-- ============================================================================
-- 3.6 deposit_bank_account: bank deposit + GL (Dr.Bank / Cr.Revenue)
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
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');

    -- Resolve GL accounts — RAISE on missing, NO fallback
    v_bank_acct := public.resolve_gl_account('11201', v_company_id);
    v_revenue_acct := public.resolve_gl_account('41101', v_company_id);

    -- GL: Dr.Bank / Cr.Revenue
    v_je_id := public.post_journal_entry(
        'bank_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    -- Bank balance
    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    -- Bank transaction record
    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name, journal_entry_id
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_je_id
    ) RETURNING id INTO v_tx_id;

    -- Party balance + subledger
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
        IF v_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_entity_id::uuid;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shareholder', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    END IF;

    RETURN json_build_object('success', true, 'transaction_id', v_tx_id, 'journal_entry_id', v_je_id, 'balance_after', v_new_balance);
END;
$$;


-- ============================================================================
-- 3.7 withdraw_bank_account: bank withdrawal + GL (Dr.Expense / Cr.Bank)
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
    v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');

    v_bank_acct := public.resolve_gl_account('11201', v_company_id);
    v_expense_acct := public.resolve_gl_account('51101', v_company_id);

    -- GL: Dr.Expense / Cr.Bank
    v_je_id := public.post_journal_entry(
        'bank_withdraw', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    -- Bank balance
    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    -- Bank transaction record
    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name, journal_entry_id
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_je_id
    ) RETURNING id INTO v_tx_id;

    -- Party balance + subledger
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
        IF v_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
        VALUES ('shareholder', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', p_counterparty_name, v_desc, auth.uid());
    END IF;

    RETURN json_build_object('success', true, 'transaction_id', v_tx_id, 'journal_entry_id', v_je_id, 'balance_after', v_new_balance);
END;
$$;


-- ============================================================================
-- 3.8 deposit_bank_with_counterparty (legacy wrapper — same as deposit_bank_account with params)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deposit_bank_with_counterparty(
    p_account_id        INT,
    p_amount            NUMERIC,
    p_description       TEXT DEFAULT NULL,
    p_counterparty_type TEXT DEFAULT NULL,
    p_entity_id         TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT public.deposit_bank_account(p_account_id, p_amount, p_description, p_counterparty_type, p_entity_id, p_counterparty_name)
    INTO v_result;
    RETURN v_result;
END;
$$;


-- ============================================================================
-- 3.9 rpc_deposit_customer_treasury: treasury deposit + customer + GL
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_deposit_customer_treasury(
    p_treasury_id BIGINT,
    p_currency    VARCHAR,
    p_amount      NUMERIC,
    p_description TEXT,
    p_customer_id BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_ar_acct         BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    -- Treasury balance check
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL THEN
        RAISE EXCEPTION 'الخزينة غير موجودة';
    END IF;

    -- Resolve company
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع خزينة من عميل');

    -- Credit treasury
    UPDATE public.treasury_balances
    SET balance = balance + p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Create treasury transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_amount, p_currency, v_desc,
        p_customer_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Customer balance: decrease
    UPDATE public.customers SET balance = balance - p_amount WHERE id = p_customer_id;

    -- Subledger entry
    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        'customer', p_customer_id::text, 'credit', p_amount, p_currency,
        'treasury_deposit', v_tx_id, v_desc, auth.uid()
    );

    -- GL: Dr.Treasury / Cr.AR
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    v_ar_acct := public.resolve_gl_account('1020', v_company_id);

    v_je_id := public.post_journal_entry(
        'customer_treasury_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    RETURN v_tx_id;
END;
$$;


-- ============================================================================
-- 3.10 rpc_withdraw_customer_treasury: treasury withdraw + customer + GL
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_withdraw_customer_treasury(
    p_treasury_id BIGINT,
    p_currency    VARCHAR,
    p_amount      NUMERIC,
    p_description TEXT,
    p_customer_id BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_ar_acct         BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف خزينة لعميل');

    -- Debit treasury
    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Create treasury transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, v_desc,
        p_customer_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Customer balance: increase
    UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;

    -- Subledger entry
    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        'customer', p_customer_id::text, 'debit', p_amount, p_currency,
        'treasury_withdrawal', v_tx_id, v_desc, auth.uid()
    );

    -- GL: Dr.AR / Cr.Treasury
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    v_ar_acct := public.resolve_gl_account('1020', v_company_id);

    v_je_id := public.post_journal_entry(
        'customer_treasury_withdrawal', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_ar_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    RETURN v_tx_id;
END;
$$;


-- ============================================================================
-- 3.11 spend_custody: treasury expense + GL (Dr.Expense / Cr.Treasury)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id         BIGINT,
    p_currency            VARCHAR,
    p_amount              NUMERIC,
    p_description         TEXT,
    p_customer_id         BIGINT DEFAULT NULL,
    p_supplier_id         UUID   DEFAULT NULL,
    p_clearing_agent_id   BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id      UUID   DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'مصروف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, v_desc,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Party balance updates
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;

    -- GL: Dr.Expense / Cr.Treasury
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    v_expense_acct := public.resolve_gl_account('51101', v_company_id);

    v_je_id := public.post_journal_entry(
        'expense_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Update treasury transaction with journal_entry_id
    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;


-- ============================================================================
-- 3.12 spend_with_category: treasury expense with category + GL
-- ============================================================================
CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id         BIGINT,
    p_currency            VARCHAR,
    p_amount              NUMERIC,
    p_description         TEXT,
    p_category_id         BIGINT,
    p_customer_id         BIGINT DEFAULT NULL,
    p_supplier_id         UUID   DEFAULT NULL,
    p_clearing_agent_id   BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id      UUID   DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
BEGIN
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'مصروف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, category_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, v_desc, p_category_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Party balance updates
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, 'expense', v_tx_id, v_desc, auth.uid());
    END IF;

    -- GL: Dr.Expense / Cr.Treasury
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );
    v_expense_acct := public.resolve_gl_account('51101', v_company_id);

    v_je_id := public.post_journal_entry(
        'expense_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Update treasury transaction with journal_entry_id
    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;


-- ============================================================================
-- 3.13 bank_transfer: transfer between bank accounts + GL
-- ============================================================================
CREATE OR REPLACE FUNCTION public.bank_transfer(
    p_from_account_id INTEGER,
    p_to_account_id   INTEGER,
    p_amount          NUMERIC,
    p_description     TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_currency TEXT;
    v_to_currency  TEXT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_je_id        BIGINT;
    v_desc         TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'لا يمكن التحويل للحساب نفسه';
    END IF;

    -- Lock and check source
    SELECT COALESCE(balance, 0), currency, company_id INTO v_from_balance, v_from_currency, v_company_id
    FROM bank_accounts WHERE id = p_from_account_id FOR UPDATE;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب المصدر (المتوفر: %)', v_from_balance;
    END IF;

    -- Check destination
    SELECT COALESCE(balance, 0), currency INTO v_to_balance, v_to_currency
    FROM bank_accounts WHERE id = p_to_account_id FOR UPDATE;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل بنكي');

    -- Resolve GL accounts
    v_from_acct := public.resolve_gl_account('11201', v_company_id);
    v_to_acct := public.resolve_gl_account('11201', v_company_id);

    -- GL: Dr.Destination Bank / Cr.Source Bank
    v_je_id := public.post_journal_entry(
        'bank_transfer', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', v_from_currency, 'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    -- Update balances
    UPDATE bank_accounts SET balance = balance - p_amount WHERE id = p_from_account_id;
    UPDATE bank_accounts SET balance = balance + p_amount WHERE id = p_to_account_id;

    -- Record transactions
    INSERT INTO bank_account_transactions (bank_account_id, type, amount, balance_before, balance_after, description, created_by)
    VALUES (p_from_account_id, 'transfer_out', p_amount, v_from_balance, v_from_balance - p_amount, v_desc, auth.uid());

    INSERT INTO bank_account_transactions (bank_account_id, type, amount, balance_before, balance_after, description, created_by)
    VALUES (p_to_account_id, 'transfer_in', p_amount, v_to_balance, v_to_balance + p_amount, v_desc, auth.uid());

    RETURN json_build_object('success', true, 'journal_entry_id', v_je_id);
END;
$$;


-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================
GRANT EXECUTE ON FUNCTION public.post_journal_entry TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_gl_account TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_gl_account(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disburse_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.receive_payment(VARCHAR, NUMERIC, VARCHAR, VARCHAR, BIGINT, UUID, UUID, TEXT, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_supplier_payment(UUID, NUMERIC, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_bank_with_counterparty(INT, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_deposit_customer_treasury(BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_withdraw_customer_treasury(BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.spend_custody(BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT, UUID, BIGINT, BIGINT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.spend_with_category(BIGINT, VARCHAR, NUMERIC, TEXT, BIGINT, BIGINT, UUID, BIGINT, BIGINT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bank_transfer(INTEGER, INTEGER, NUMERIC, TEXT) TO authenticated;
