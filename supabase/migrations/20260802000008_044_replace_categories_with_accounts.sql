-- 044: Replace expense categories with Chart of Accounts
-- Chart of Accounts becomes the single source of truth for all financial operations.

-- ============================================================================
-- 1. ADD expense_account_id TO treasury_transactions
-- ============================================================================

ALTER TABLE treasury_transactions
  ADD COLUMN IF NOT EXISTS expense_account_id INTEGER REFERENCES accounts(id);

CREATE INDEX IF NOT EXISTS idx_treasury_tx_expense_account_id
  ON treasury_transactions(expense_account_id) WHERE expense_account_id IS NOT NULL;

-- ============================================================================
-- 2. MIGRATE EXISTING DATA: map category_id → expense_account_id
-- ============================================================================

-- Strategy: Map old expense_categories to accounts by name matching.
-- If no match found, fall back to 51101 (General Expenses).
UPDATE treasury_transactions tt
SET expense_account_id = COALESCE(
  (SELECT a.id FROM accounts a
   WHERE a.account_type = 'expense'
     AND a.is_leaf = true
     AND a.is_active = true
     AND (
       a.account_name ILIKE '%' || ec.name || '%'
       OR a.name ILIKE '%' || ec.name || '%'
     )
   LIMIT 1),
  (SELECT id FROM accounts WHERE account_code = '51101' LIMIT 1)
)
FROM expense_categories ec
WHERE tt.category_id = ec.id
  AND tt.expense_account_id IS NULL;

-- For transactions without any category, default to 51101
UPDATE treasury_transactions
SET expense_account_id = (SELECT id FROM accounts WHERE account_code = '51101' LIMIT 1)
WHERE expense_account_id IS NULL
  AND type = 'expense';

-- ============================================================================
-- 3. UPDATE spend_with_category() to use expense_account_id for GL entries
-- ============================================================================

CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id      BIGINT,
    p_currency         TEXT,
    p_amount           NUMERIC,
    p_description      TEXT DEFAULT '',
    p_category_id      INTEGER DEFAULT NULL,
    p_customer_id      INTEGER DEFAULT NULL,
    p_supplier_id      BIGINT DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id   UUID DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, v_desc, p_category_id,
        p_expense_account_id,
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
    -- Use p_expense_account_id if provided, otherwise fall back to 51101
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        'expense_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;

-- ============================================================================
-- 4. UPDATE spend_custody() to use expense_account_id for GL entries
-- ============================================================================

CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id      BIGINT,
    p_currency         TEXT,
    p_amount           NUMERIC,
    p_description      TEXT DEFAULT '',
    p_customer_id      INTEGER DEFAULT NULL,
    p_supplier_id      BIGINT DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id   UUID DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف عهدة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, v_desc,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Party balance updates (same as spend_with_category)
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

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        'expense_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;

-- ============================================================================
-- 5. REBUILD the v_unified_ledger_transactions view to include expense_account info
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
      WHEN ec.name IS NOT NULL THEN ec.name
      WHEN ea.account_name IS NOT NULL THEN ea.account_name
      ELSE NULL
    END AS category_name,
    CASE
      WHEN ea.account_code IS NOT NULL THEN ea.account_code
      ELSE NULL
    END AS reference_number,
    ea.id AS expense_account_id,
    ea.account_code AS expense_account_code,
    ea.account_name AS expense_account_name,
    tt.created_by,
    u.full_name AS creator_name,
    tt.created_at
FROM treasury_transactions tt
LEFT JOIN treasuries t ON t.id = tt.treasury_id
LEFT JOIN expense_categories ec ON ec.id = tt.category_id
LEFT JOIN accounts ea ON ea.id = tt.expense_account_id
LEFT JOIN journal_entries je ON je.id = tt.journal_entry_id
LEFT JOIN users u ON u.id = tt.created_by;
