-- 046: Final Accounting Hardening & Production Lock
-- Makes the Chart of Accounts system enterprise-grade with database-level safeguards.

-- ============================================================================
-- 1. PREVENT POSTING TO NON-LEAF ACCOUNTS
-- ============================================================================

-- Trigger function: reject journal entries that debit/credit non-leaf accounts
CREATE OR REPLACE FUNCTION public.fn_reject_non_leaf_account_posting()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_is_leaf BOOLEAN;
    v_is_active BOOLEAN;
    v_code TEXT;
BEGIN
    -- Check the debit account
    IF NEW.account_id IS NOT NULL THEN
        SELECT is_leaf, is_active, account_code INTO v_is_leaf, v_is_active, v_code
        FROM accounts WHERE id = NEW.account_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'الحساب غير موجود (ID: %)', NEW.account_id;
        END IF;

        IF v_is_leaf IS FALSE THEN
            RAISE EXCEPTION 'لا يمكن القيود على الحساب غير الورقي % — فقط الحسابات الورقية مسموح بها', v_code;
        END IF;

        IF v_is_active IS FALSE THEN
            RAISE EXCEPTION 'الحساب % معطل — لا يمكن استخدامه في أي قيد', v_code;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Apply trigger to account_ledger_entries (the GL posting table)
DROP TRIGGER IF EXISTS trg_reject_non_leaf ON account_ledger_entries;
CREATE TRIGGER trg_reject_non_leaf
    BEFORE INSERT ON account_ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_reject_non_leaf_account_posting();

-- ============================================================================
-- 2. PREVENT ARCHIVED ACCOUNTS FROM BEING USED IN TRANSACTIONS
-- ============================================================================

-- Trigger function: reject treasury transactions using archived accounts
CREATE OR REPLACE FUNCTION public.fn_reject_archived_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_is_active BOOLEAN;
    v_code TEXT;
BEGIN
    IF NEW.expense_account_id IS NOT NULL THEN
        SELECT is_active, account_code INTO v_is_active, v_code
        FROM accounts WHERE id = NEW.expense_account_id;
        IF v_is_active IS FALSE THEN
            RAISE EXCEPTION 'حساب المصروفات % معطل — لا يمكن استخدامه', v_code;
        END IF;
    END IF;

    IF NEW.revenue_account_id IS NOT NULL THEN
        SELECT is_active, account_code INTO v_is_active, v_code
        FROM accounts WHERE id = NEW.revenue_account_id;
        IF v_is_active IS FALSE THEN
            RAISE EXCEPTION 'حساب الإيرادات % معطل — لا يمكن استخدامه', v_code;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_archived_acct_treasury ON treasury_transactions;
CREATE TRIGGER trg_reject_archived_acct_treasury
    BEFORE INSERT ON treasury_transactions
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_reject_archived_account_treasury();

-- Trigger function: reject bank transactions using archived accounts
CREATE OR REPLACE FUNCTION public.fn_reject_archived_account_bank()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_is_active BOOLEAN;
    v_code TEXT;
BEGIN
    IF NEW.expense_account_id IS NOT NULL THEN
        SELECT is_active, account_code INTO v_is_active, v_code
        FROM accounts WHERE id = NEW.expense_account_id;
        IF v_is_active IS FALSE THEN
            RAISE EXCEPTION 'حساب المصروفات % معطل — لا يمكن استخدامه', v_code;
        END IF;
    END IF;

    IF NEW.revenue_account_id IS NOT NULL THEN
        SELECT is_active, account_code INTO v_is_active, v_code
        FROM accounts WHERE id = NEW.revenue_account_id;
        IF v_is_active IS FALSE THEN
            RAISE EXCEPTION 'حساب الإيرادات % معطل — لا يمكن استخدامه', v_code;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_archived_acct_bank ON bank_account_transactions;
CREATE TRIGGER trg_reject_archived_acct_bank
    BEFORE INSERT ON bank_account_transactions
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_reject_archived_account_bank();

-- ============================================================================
-- 3. PREVENT DELETION OF USED ACCOUNTS
-- ============================================================================

-- Trigger function: prevent deletion of accounts that have journal entries
CREATE OR REPLACE FUNCTION public.fn_prevent_account_deletion_if_used()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_usage_count BIGINT;
    v_code TEXT;
BEGIN
    SELECT account_code INTO v_code FROM accounts WHERE id = OLD.id;

    -- Check journal entries
    SELECT COUNT(*) INTO v_usage_count
    FROM account_ledger_entries
    WHERE account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف الحساب % — مستخدم في % قيد يومي', v_code, v_usage_count;
    END IF;

    -- Check treasury transactions
    SELECT COUNT(*) INTO v_usage_count
    FROM treasury_transactions
    WHERE expense_account_id = OLD.id OR revenue_account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف الحساب % — مستخدم في حركات الخزينة', v_code;
    END IF;

    -- Check bank transactions
    SELECT COUNT(*) INTO v_usage_count
    FROM bank_account_transactions
    WHERE expense_account_id = OLD.id OR revenue_account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف الحساب % — مستخدم في حركات البنك', v_code;
    END IF;

    -- Check treasury_balances
    SELECT COUNT(*) INTO v_usage_count
    FROM treasury_balances WHERE account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف الحساب % — مرتبط برصيد خزينة', v_code;
    END IF;

    -- Check if has children
    SELECT COUNT(*) INTO v_usage_count
    FROM accounts WHERE parent_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف الحساب % — يحتوي على حسابات فرعية', v_code;
    END IF;

    -- Check if system account
    IF OLD.is_system = TRUE THEN
        RAISE EXCEPTION 'لا يمكن حذف الحساب % — حساب نظامي', v_code;
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_account_deletion ON accounts;
CREATE TRIGGER trg_prevent_account_deletion
    BEFORE DELETE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_prevent_account_deletion_if_used();

-- ============================================================================
-- 4. PREVENT ACCOUNT TYPE CHANGES AFTER USE
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_prevent_account_type_change_if_used()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_usage_count BIGINT;
BEGIN
    -- Only check if type is actually changing
    IF OLD.account_type = NEW.account_type THEN
        RETURN NEW;
    END IF;

    -- Check journal entries
    SELECT COUNT(*) INTO v_usage_count
    FROM account_ledger_entries
    WHERE account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن تغيير نوع الحساب % — يحتوي على % قيد يومي', OLD.account_code, v_usage_count;
    END IF;

    -- Check treasury transactions
    SELECT COUNT(*) INTO v_usage_count
    FROM treasury_transactions
    WHERE expense_account_id = OLD.id OR revenue_account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن تغيير نوع الحساب % — مستخدم في حركات الخزينة', OLD.account_code;
    END IF;

    -- Check bank transactions
    SELECT COUNT(*) INTO v_usage_count
    FROM bank_account_transactions
    WHERE expense_account_id = OLD.id OR revenue_account_id = OLD.id;

    IF v_usage_count > 0 THEN
        RAISE EXCEPTION 'لا يمكن تغيير نوع الحساب % — مستخدم في حركات البنك', OLD.account_code;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_type_change ON accounts;
CREATE TRIGGER trg_prevent_type_change
    BEFORE UPDATE ON accounts
    FOR EACH ROW
    WHEN (OLD.account_type IS DISTINCT FROM NEW.account_type)
    EXECUTE FUNCTION public.fn_prevent_account_type_change_if_used();

-- ============================================================================
-- 5. PREVENT CODE REUSE AFTER DELETION
-- ============================================================================

-- Create table to track deleted account codes
CREATE TABLE IF NOT EXISTS public.deleted_account_codes (
    id BIGSERIAL PRIMARY KEY,
    account_code TEXT NOT NULL UNIQUE,
    deleted_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_deleted_account_codes_code ON deleted_account_codes(account_code);

-- Trigger function: prevent inserting an account with a previously deleted code
CREATE OR REPLACE FUNCTION public.fn_prevent_deleted_code_reuse()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM deleted_account_codes WHERE account_code = NEW.account_code) THEN
        RAISE EXCEPTION 'كود الحساب % كان مستخدماً ثم حُذف — لا يمكن إعادة استخدامه. استخدم كوداً جديداً', NEW.account_code;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_code_reuse ON accounts;
CREATE TRIGGER trg_prevent_code_reuse
    BEFORE INSERT ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_prevent_deleted_code_reuse();

-- Track deleted codes via a trigger on DELETE
CREATE OR REPLACE FUNCTION public.fn_track_deleted_account_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    INSERT INTO deleted_account_codes (account_code, deleted_by)
    VALUES (OLD.account_code, auth.uid())
    ON CONFLICT (account_code) DO NOTHING;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_track_deleted_code ON accounts;
CREATE TRIGGER trg_track_deleted_code
    BEFORE DELETE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_track_deleted_account_code();

-- ============================================================================
-- 6. FISCAL YEAR LOCK — DATABASE-LEVEL ENFORCEMENT
-- ============================================================================

-- Trigger function: reject financial transactions in closed fiscal years
CREATE OR REPLACE FUNCTION public.fn_reject_closed_fiscal_year()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_date DATE;
    v_fy_status TEXT;
BEGIN
    -- Get the transaction date
    IF TG_TABLE_NAME = 'treasury_transactions' THEN
        v_tx_date := COALESCE(NEW.created_at::date, CURRENT_DATE);
    ELSIF TG_TABLE_NAME = 'bank_account_transactions' THEN
        v_tx_date := COALESCE(NEW.created_at::date, CURRENT_DATE);
    ELSIF TG_TABLE_NAME = 'journal_entries' THEN
        v_tx_date := NEW.entry_date;
    ELSE
        RETURN NEW;
    END IF;

    -- Check fiscal year status
    SELECT fy.status INTO v_fy_status
    FROM fiscal_years fy
    WHERE v_tx_date >= fy.start_date AND v_tx_date <= fy.end_date
    LIMIT 1;

    IF v_fy_status IS NOT NULL AND v_fy_status IN ('closed', 'archived') THEN
        RAISE EXCEPTION 'السنة المالية % مغلقة — لا يمكن إنشاء أي معاملة مالية في هذه الفترة', v_fy_status;
    END IF;

    RETURN NEW;
END;
$$;

-- Apply to treasury_transactions
DROP TRIGGER IF EXISTS trg_reject_closed_fy_treasury ON treasury_transactions;
CREATE TRIGGER trg_reject_closed_fy_treasury
    BEFORE INSERT ON treasury_transactions
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_reject_closed_fiscal_year();

-- Apply to bank_account_transactions
DROP TRIGGER IF EXISTS trg_reject_closed_fy_bank ON bank_account_transactions;
CREATE TRIGGER trg_reject_closed_fy_bank
    BEFORE INSERT ON bank_account_transactions
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_reject_closed_fiscal_year();

-- Apply to journal_entries
DROP TRIGGER IF EXISTS trg_reject_closed_fy_je ON journal_entries;
CREATE TRIGGER trg_reject_closed_fy_je
    BEFORE INSERT ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_reject_closed_fiscal_year();

-- ============================================================================
-- 7. REQUIRE EXPENSE/REVENUE ACCOUNTS — NO FALLBACK
-- ============================================================================

-- Trigger: require expense_account_id for treasury expense transactions
CREATE OR REPLACE FUNCTION public.fn_require_expense_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.type = 'expense' AND NEW.expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_expense_acct ON treasury_transactions;
CREATE TRIGGER trg_require_expense_acct
    BEFORE INSERT ON treasury_transactions
    FOR EACH ROW
    WHEN (NEW.type = 'expense')
    EXECUTE FUNCTION public.fn_require_expense_account_treasury();

-- Trigger: require revenue_account_id for treasury deposit (income)
CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.type = 'deposit' AND NEW.revenue_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب إيرادات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_revenue_acct ON treasury_transactions;
CREATE TRIGGER trg_require_revenue_acct
    BEFORE INSERT ON treasury_transactions
    FOR EACH ROW
    WHEN (NEW.type = 'deposit')
    EXECUTE FUNCTION public.fn_require_revenue_account_treasury();

-- Trigger: require expense_account_id for bank withdrawals
CREATE OR REPLACE FUNCTION public.fn_require_expense_account_bank()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.type = 'withdrawal' AND NEW.expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_expense_acct_bank ON bank_account_transactions;
CREATE TRIGGER trg_require_expense_acct_bank
    BEFORE INSERT ON bank_account_transactions
    FOR EACH ROW
    WHEN (NEW.type = 'withdrawal')
    EXECUTE FUNCTION public.fn_require_expense_account_bank();

-- Trigger: require revenue_account_id for bank deposits
CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_bank()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.type = 'deposit' AND NEW.revenue_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب إيرادات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_revenue_acct_bank ON bank_account_transactions;
CREATE TRIGGER trg_require_revenue_acct_bank
    BEFORE INSERT ON bank_account_transactions
    FOR EACH ROW
    WHEN (NEW.type = 'deposit')
    EXECUTE FUNCTION public.fn_require_revenue_account_bank();

-- ============================================================================
-- 8. UPDATE spend_with_category() TO REMOVE FALLBACK
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
    -- Require expense account — no fallback
    IF p_expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات';
    END IF;

    -- Verify account exists, is leaf, and is active
    SELECT id INTO v_expense_acct FROM accounts
    WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';

    IF v_expense_acct IS NULL THEN
        RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
    END IF;

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

    -- GL: Dr.Expense / Cr.Treasury (no fallback — account already validated)
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

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
-- 9. UPDATE spend_custody() TO REMOVE FALLBACK
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
    -- Require expense account — no fallback
    IF p_expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات';
    END IF;

    SELECT id INTO v_expense_acct FROM accounts
    WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';

    IF v_expense_acct IS NULL THEN
        RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
    END IF;

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

    -- GL: Dr.Expense / Cr.Treasury (no fallback)
    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

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
-- 10. ENHANCED ACCOUNT SEARCH FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.search_accounts(
    p_query TEXT,
    p_account_type TEXT DEFAULT NULL,
    p_only_active BOOLEAN DEFAULT TRUE,
    p_only_leaf BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id BIGINT,
    account_code TEXT,
    name TEXT,
    account_name TEXT,
    account_type TEXT,
    parent_id BIGINT,
    balance NUMERIC,
    is_active BOOLEAN,
    is_leaf BOOLEAN,
    path TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.id,
        a.account_code,
        a.name,
        a.account_name,
        a.account_type,
        a.parent_id,
        a.balance,
        a.is_active,
        a.is_leaf,
        COALESCE(
            (SELECT string_agg(p2.account_code, ' → ' ORDER BY p2.account_code)
             FROM accounts p2
             WHERE a.path_ids @> ARRAY[p2.id] OR a.id = p2.id),
            a.account_code
        ) AS path
    FROM accounts a
    WHERE
        (p_only_active = FALSE OR a.is_active = TRUE)
        AND (p_only_leaf = FALSE OR a.is_leaf = TRUE)
        AND (p_account_type IS NULL OR a.account_type = p_account_type)
        AND (
            a.account_code ILIKE '%' || p_query || '%'
            OR a.name ILIKE '%' || p_query || '%'
            OR a.account_name ILIKE '%' || p_query || '%'
        )
    ORDER BY a.account_code ASC;
END;
$$;
