-- 045: Complete Chart of Accounts Integration
-- Make the ENTIRE financial system depend ONLY on Chart of Accounts.
-- Expense Categories become ONLY optional reporting groups.

-- ============================================================================
-- 1. ADD revenue_account_id TO bank_account_transactions
-- ============================================================================

ALTER TABLE bank_account_transactions
  ADD COLUMN IF NOT EXISTS expense_account_id INTEGER REFERENCES accounts(id),
  ADD COLUMN IF NOT EXISTS revenue_account_id INTEGER REFERENCES accounts(id);

CREATE INDEX IF NOT EXISTS idx_bank_tx_expense_account_id
  ON bank_account_transactions(expense_account_id) WHERE expense_account_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bank_tx_revenue_account_id
  ON bank_account_transactions(revenue_account_id) WHERE revenue_account_id IS NOT NULL;

-- ============================================================================
-- 2. ADD revenue_account_id TO treasury_transactions
-- ============================================================================

ALTER TABLE treasury_transactions
  ADD COLUMN IF NOT EXISTS revenue_account_id INTEGER REFERENCES accounts(id);

CREATE INDEX IF NOT EXISTS idx_treasury_tx_revenue_account_id
  ON treasury_transactions(revenue_account_id) WHERE revenue_account_id IS NOT NULL;

-- ============================================================================
-- 3. UPDATE withdraw_bank_account() to use expense_account_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id         INTEGER,
    p_amount             NUMERIC,
    p_description        TEXT DEFAULT NULL,
    p_entity_type        TEXT DEFAULT NULL,
    p_entity_id          TEXT DEFAULT NULL,
    p_counterparty_name  TEXT DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL
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

    -- Resolve bank account GL code based on currency
    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    -- Resolve expense account — MUST be provided, no fallback
    IF p_expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب تحديد حساب المصروفات — لا يمكن استخدام قيمة افتراضية';
    END IF;
    v_expense_acct := p_expense_account_id;

    -- Validate account is active and leaf
    PERFORM 1 FROM accounts WHERE id = v_expense_acct AND is_active = true AND is_leaf = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'حساب المصروفات غير صالح (يجب أن يكون حساب نشط وورقة)';
    END IF;

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
        description, created_by, entity_type, entity_id, counterparty_name, source_type, journal_entry_id,
        expense_account_id
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_source_type, v_je_id,
        p_expense_account_id
    ) RETURNING id INTO v_tx_id;

    -- Party balance updates
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
-- 4. UPDATE deposit_bank_account() to use revenue_account_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id         INTEGER,
    p_amount             NUMERIC,
    p_description        TEXT DEFAULT NULL,
    p_entity_type        TEXT DEFAULT NULL,
    p_entity_id          TEXT DEFAULT NULL,
    p_counterparty_name  TEXT DEFAULT NULL,
    p_revenue_account_id INTEGER DEFAULT NULL
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

    -- Resolve bank account GL code based on currency
    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    -- Resolve revenue account — MUST be provided, no fallback
    IF p_revenue_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب تحديد حساب الإيرادات — لا يمكن استخدام قيمة افتراضية';
    END IF;
    v_revenue_acct := p_revenue_account_id;

    -- Validate account is active and leaf
    PERFORM 1 FROM accounts WHERE id = v_revenue_acct AND is_active = true AND is_leaf = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'حساب الإيرادات غير صالح (يجب أن يكون حساب نشط وورقة)';
    END IF;

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
        description, created_by, entity_type, entity_id, counterparty_name, source_type, journal_entry_id,
        revenue_account_id
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name, v_source_type, v_je_id,
        p_revenue_account_id
    ) RETURNING id INTO v_tx_id;

    -- Party balance updates
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
-- 5. UPDATE deposit_treasury() to use revenue_account_id for income
-- ============================================================================

CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id        INTEGER,
    p_currency           TEXT,
    p_amount             NUMERIC,
    p_description        TEXT DEFAULT '',
    p_revenue_account_id INTEGER DEFAULT NULL
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
    v_revenue_acct    BIGINT;
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

    -- Use provided revenue account or fall back to 3000 (Owner Equity)
    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_gl_account('3000', v_company_id);
    END IF;

    -- Journal entry: Dr.Treasury / Cr.Revenue Account
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance', v_je_id, auth.uid(),
        p_revenue_account_id
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance
    );
END;
$$;

-- ============================================================================
-- 6. UPDATE v_unified_ledger_transactions view to include new account fields
-- ============================================================================

DROP VIEW IF EXISTS public.v_unified_ledger_transactions;

CREATE OR REPLACE VIEW public.v_unified_ledger_transactions AS
SELECT
    tt.id AS tx_id,
    tt.journal_entry_id,
    je.entry_number,
    'treasury'::TEXT AS account_category,
    tt.treasury_id AS account_source_id,
    t.name AS account_source_name,
    tt.type AS transaction_type,
    tt.currency,
    tt.amount,
    tt.balance_before,
    tt.balance_after,
    tt.description,
    CASE
      WHEN ea.account_name IS NOT NULL THEN ea.account_name
      WHEN ec.name IS NOT NULL THEN ec.name
      ELSE NULL
    END AS category_name,
    CASE
      WHEN ea.account_code IS NOT NULL THEN ea.account_code
      ELSE NULL
    END AS reference_number,
    tt.expense_account_id,
    ea.account_code AS expense_account_code,
    ea.account_name AS expense_account_name,
    tt.revenue_account_id,
    ra.account_code AS revenue_account_code,
    ra.account_name AS revenue_account_name,
    tt.created_by,
    u.full_name AS creator_name,
    tt.created_at
FROM treasury_transactions tt
LEFT JOIN treasuries t ON t.id = tt.treasury_id
LEFT JOIN expense_categories ec ON ec.id = tt.category_id
LEFT JOIN accounts ea ON ea.id = tt.expense_account_id
LEFT JOIN accounts ra ON ra.id = tt.revenue_account_id
LEFT JOIN journal_entries je ON je.id = tt.journal_entry_id
LEFT JOIN users u ON u.id = tt.created_by

UNION ALL

SELECT
    bat.id AS tx_id,
    bat.journal_entry_id,
    je.entry_number,
    'bank'::TEXT AS account_category,
    bat.bank_account_id AS account_source_id,
    ba.name AS account_source_name,
    bat.type AS transaction_type,
    ba.currency,
    bat.amount,
    bat.balance_before,
    bat.balance_after,
    bat.description,
    CASE
      WHEN ea.account_name IS NOT NULL THEN ea.account_name
      WHEN ra.account_name IS NOT NULL THEN ra.account_name
      ELSE NULL
    END AS category_name,
    CASE
      WHEN ea.account_code IS NOT NULL THEN ea.account_code
      WHEN ra.account_code IS NOT NULL THEN ra.account_code
      ELSE NULL
    END AS reference_number,
    bat.expense_account_id,
    ea.account_code AS expense_account_code,
    ea.account_name AS expense_account_name,
    bat.revenue_account_id,
    ra.account_code AS revenue_account_code,
    ra.account_name AS revenue_account_name,
    bat.created_by,
    u.full_name AS creator_name,
    bat.created_at
FROM bank_account_transactions bat
LEFT JOIN bank_accounts ba ON ba.id = bat.bank_account_id
LEFT JOIN accounts ea ON ea.id = bat.expense_account_id
LEFT JOIN accounts ra ON ra.id = bat.revenue_account_id
LEFT JOIN journal_entries je ON je.id = bat.journal_entry_id
LEFT JOIN users u ON u.id = bat.created_by;

-- ============================================================================
-- 7. UPDATE get_treasury_stats() to group by expense_account_id
-- ============================================================================

-- Drop old overloads with wrong parameter types
DROP FUNCTION IF EXISTS public.get_treasury_stats(INTEGER, BOOLEAN, DATE, DATE);
DROP FUNCTION IF EXISTS public.get_treasury_stats(INTEGER, BOOLEAN, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_treasury_stats(BIGINT, BOOLEAN, DATE, DATE);
DROP FUNCTION IF EXISTS public.get_treasury_stats(BIGINT, BOOLEAN, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_treasury_stats(
    p_main_treasury_id TEXT DEFAULT NULL,
    p_all_treasuries   BOOLEAN DEFAULT FALSE,
    p_start_date       TEXT DEFAULT NULL,
    p_end_date         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_result JSONB;
    v_total_expenses NUMERIC := 0;
    v_total_disbursements NUMERIC := 0;
    v_total_returns NUMERIC := 0;
    v_total_transfers NUMERIC := 0;
    v_total_deposits NUMERIC := 0;
    v_total_transactions INTEGER := 0;
    v_category_breakdown JSONB;
    v_currency_totals JSONB;
    v_employee_custody NUMERIC := 0;
    v_employee_custody_breakdown JSONB;
BEGIN
    -- Aggregates
    SELECT
        COALESCE(SUM(CASE WHEN type IN ('expense', 'withdrawal') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type IN ('disbursement', 'disbursement_out') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type IN ('return_in', 'return_out') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type IN ('transfer_in', 'transfer_out') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END), 0),
        COUNT(*)
    INTO v_total_expenses, v_total_disbursements, v_total_returns, v_total_transfers, v_total_deposits, v_total_transactions
    FROM treasury_transactions tt
    WHERE (p_start_date IS NULL OR tt.created_at >= p_start_date::timestamptz)
      AND (p_end_date IS NULL OR tt.created_at <= (p_end_date::timestamptz + interval '1 day'))
      AND (
        p_all_treasuries = TRUE
        OR tt.treasury_id::TEXT = p_main_treasury_id
        OR (p_main_treasury_id IS NULL AND tt.treasury_id IN (
            SELECT id FROM treasuries WHERE type = 'main' LIMIT 1
        ))
      );

    -- Expense account breakdown
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', sub.id,
        'name', sub.name,
        'code', sub.code,
        'color', sub.color,
        'total', sub.total
    )), '[]'::jsonb)
    INTO v_category_breakdown
    FROM (
        SELECT
            COALESCE(ea.id, 0) AS id,
            COALESCE(ea.name, 'غير مصنف') AS name,
            COALESCE(ea.account_code, '0000') AS code,
            CASE ea.account_type
                WHEN 'expense' THEN '#E65100'
                WHEN 'revenue' THEN '#2E7D32'
                WHEN 'asset' THEN '#1565C0'
                WHEN 'liability' THEN '#C62828'
                WHEN 'equity' THEN '#6A1B9A'
                ELSE '#6B7280'
            END AS color,
            SUM(td.amount) AS total
        FROM treasury_transactions td
        LEFT JOIN accounts ea ON ea.id = td.expense_account_id
        WHERE td.type IN ('expense', 'withdrawal')
          AND (p_start_date IS NULL OR td.created_at >= p_start_date::timestamptz)
          AND (p_end_date IS NULL OR td.created_at <= (p_end_date::timestamptz + interval '1 day'))
          AND (
            p_all_treasuries = TRUE
            OR td.treasury_id::TEXT = p_main_treasury_id
            OR (p_main_treasury_id IS NULL AND td.treasury_id IN (
                SELECT id FROM treasuries WHERE type = 'main' LIMIT 1
            ))
          )
        GROUP BY ea.id, ea.name, ea.account_code, ea.account_type
        ORDER BY total DESC
    ) sub;

    -- Currency totals
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'currency', sub.currency,
        'total', sub.expenses,
        'deposits', sub.deposits,
        'tx_count', sub.tx_count
    )), '[]'::jsonb)
    INTO v_currency_totals
    FROM (
        SELECT
            currency,
            SUM(CASE WHEN type IN ('expense', 'withdrawal') THEN amount ELSE 0 END) AS expenses,
            SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END) AS deposits,
            COUNT(*) AS tx_count
        FROM treasury_transactions tt
        WHERE (p_start_date IS NULL OR tt.created_at >= p_start_date::timestamptz)
          AND (p_end_date IS NULL OR tt.created_at <= (p_end_date::timestamptz + interval '1 day'))
          AND (
            p_all_treasuries = TRUE
            OR tt.treasury_id::TEXT = p_main_treasury_id
            OR (p_main_treasury_id IS NULL AND tt.treasury_id IN (
                SELECT id FROM treasuries WHERE type = 'main' LIMIT 1
            ))
          )
        GROUP BY currency
    ) sub;

    -- Employee custody
    SELECT COALESCE(SUM(tb.balance), 0) INTO v_employee_custody
    FROM treasury_balances tb
    JOIN treasuries t ON t.id = tb.treasury_id
    WHERE t.type = 'employee'
      AND (p_all_treasuries = TRUE OR t.id::TEXT != p_main_treasury_id);

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'currency', tb.currency,
        'total', tb.balance
    )), '[]'::jsonb)
    INTO v_employee_custody_breakdown
    FROM treasury_balances tb
    JOIN treasuries t ON t.id = tb.treasury_id
    WHERE t.type = 'employee'
      AND (p_all_treasuries = TRUE OR t.id::TEXT != p_main_treasury_id)
      AND tb.balance > 0;

    v_result := jsonb_build_object(
        'total_expenses', v_total_expenses,
        'total_disbursements', v_total_disbursements,
        'total_returns', v_total_returns,
        'total_transfers', v_total_transfers,
        'total_deposits', v_total_deposits,
        'total_transactions', v_total_transactions,
        'category_breakdown', v_category_breakdown,
        'currency_totals', v_currency_totals,
        'total_employee_custody', v_employee_custody,
        'employee_custody_breakdown', v_employee_custody_breakdown
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 8. GRANT EXECUTE on updated functions
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_treasury(INTEGER, TEXT, NUMERIC, TEXT, INTEGER) TO authenticated;
