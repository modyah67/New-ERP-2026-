-- Migration 304: Fix Custody Journal Entries, Account Resolution, and Transaction Linking
-- Ensures disburse_custody, transfer_custody, and return_custody create accurate GL entries
-- and properly store journal_entry_id in treasury_transactions.

BEGIN;

-- 1. Ensure Document Types exist in sys_document_types
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES 
  ('treasury_transfer', 'Treasury Transfer / تحويل وصرف خزينة', 'TT', true),
  ('custody_transfer', 'Custody Transfer / تحويل عهدة', 'CT', true),
  ('return_custody', 'Return Custody / إرجاع عهدة', 'RC', true)
ON CONFLICT (code) DO NOTHING;

-- 2. Ensure/Update resolve_treasury_account to handle employee custody treasuries
CREATE OR REPLACE FUNCTION public.resolve_treasury_account(
    p_treasury_id BIGINT,
    p_currency TEXT,
    p_company_id UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id BIGINT;
    v_code TEXT;
    v_real_company_id UUID;
    v_treasury_type TEXT;
    v_treasury_name TEXT;
    v_parent_id BIGINT;
BEGIN
    -- Resolve company_id if NULL
    v_real_company_id := p_company_id;
    IF v_real_company_id IS NULL THEN
        SELECT company_id INTO v_real_company_id FROM treasuries WHERE id = p_treasury_id;
    END IF;
    IF v_real_company_id IS NULL THEN
        SELECT id INTO v_real_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- Get treasury info
    SELECT type, name, account_id INTO v_treasury_type, v_treasury_name, v_account_id
    FROM treasuries WHERE id = p_treasury_id;

    -- 1) If treasury already has an explicit account_id set
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 2) Try treasury_balances.account_id
    SELECT tb.account_id INTO v_account_id
    FROM treasury_balances tb
    WHERE tb.treasury_id = p_treasury_id AND tb.currency = p_currency AND tb.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 3) If this is an Employee Custody treasury (type = 'employee'):
    IF v_treasury_type = 'employee' THEN
        -- Check if an account already exists with name matching this custody
        SELECT id INTO v_account_id
        FROM accounts
        WHERE (account_name = 'عهدة - ' || v_treasury_name OR name = 'Custody - ' || v_treasury_name)
          AND is_active = true
        LIMIT 1;

        IF v_account_id IS NULL THEN
            -- Find parent account (1000 / Cash & Equivalents)
            SELECT id INTO v_parent_id
            FROM accounts
            WHERE account_code = '1000'
            ORDER BY (company_id = v_real_company_id) DESC, id ASC
            LIMIT 1;

            v_code := '1115' || LPAD(p_treasury_id::TEXT, 2, '0');

            INSERT INTO accounts (
                account_code, name, account_name, account_type, sort_order,
                company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
            )
            VALUES (
                v_code,
                'Custody - ' || COALESCE(v_treasury_name, 'Employee'),
                'عهدة - ' || COALESCE(v_treasury_name, 'موظف'),
                'asset', 1115,
                v_real_company_id,
                v_parent_id,
                5, true, true, false, true
            )
            ON CONFLICT (account_code) DO UPDATE SET
                account_name = 'عهدة - ' || COALESCE(v_treasury_name, 'موظف'),
                name = 'Custody - ' || COALESCE(v_treasury_name, 'Employee')
            RETURNING id INTO v_account_id;

            IF v_account_id IS NULL THEN
                SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
            END IF;
        END IF;

        IF v_account_id IS NOT NULL THEN
            UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id;
            RETURN v_account_id;
        END IF;
    END IF;

    -- 4) Main Treasury currency-based GL accounts (11101..11104)
    v_code := CASE p_currency
        WHEN 'EGP' THEN '11101'
        WHEN 'USD' THEN '11102'
        WHEN 'EUR' THEN '11103'
        WHEN 'GBP' THEN '11104'
        ELSE '11101'
    END;
    
    SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code AND company_id = v_real_company_id LIMIT 1;
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
    END IF;

    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 5) Fallback to any 111% or 11% or asset account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '111%' AND is_active = true
    ORDER BY (company_id = v_real_company_id) DESC, account_code LIMIT 1;

    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_type = 'asset' AND is_leaf = true AND is_active = true
    ORDER BY (company_id = v_real_company_id) DESC, account_code LIMIT 1;

    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    RAISE EXCEPTION 'Could not resolve any treasury GL account for treasury % currency %', p_treasury_id, p_currency;
END;
$$;


-- 3. disburse_custody: Main Treasury -> Employee Custody
DROP FUNCTION IF EXISTS public.disburse_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT);
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
    v_from_name    TEXT;
    v_to_name      TEXT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL AND CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Lock source balance
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

    -- Lock destination balance
    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT name, company_id INTO v_from_name, v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_to_treasury_id;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف عهدة إلى ' || COALESCE(v_to_name, 'موظف'));

    -- Resolve GL Accounts: Debit To (Employee Custody), Credit From (Main Treasury)
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    -- Update balances
    UPDATE treasury_balances SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
        VALUES (p_to_treasury_id, p_currency, p_amount, v_to_acct, NOW());
        v_to_balance := 0;
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount, updated_at = NOW()
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    -- Create GL Journal Entry
    v_je_id := public.post_journal_entry(
        'treasury_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام عهدة)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (صرف عهدة)')
        )
    );

    -- Record transactions WITH journal_entry_id
    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id)
    VALUES (p_from_treasury_id, 'disbursement_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id)
    VALUES (p_to_treasury_id, 'disbursement', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$$;


-- 4. transfer_custody: Custody -> Custody
DROP FUNCTION IF EXISTS public.transfer_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT);
CREATE OR REPLACE FUNCTION public.transfer_custody(
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
    v_from_name    TEXT;
    v_to_name      TEXT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL AND CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_from_balance;
    END IF;

    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT name, company_id INTO v_from_name, v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_to_treasury_id;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل عهدة من ' || COALESCE(v_from_name, '') || ' إلى ' || COALESCE(v_to_name, ''));

    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    UPDATE treasury_balances SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
        VALUES (p_to_treasury_id, p_currency, p_amount, v_to_acct, NOW());
        v_to_balance := 0;
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount, updated_at = NOW()
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    v_je_id := public.post_journal_entry(
        'treasury_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام تحويل)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال تحويل)')
        )
    );

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id)
    VALUES (p_from_treasury_id, 'transfer_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id)
    VALUES (p_to_treasury_id, 'transfer_in', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$$;


-- 5. return_custody: Employee Custody -> Main Treasury
DROP FUNCTION IF EXISTS public.return_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT);
CREATE OR REPLACE FUNCTION public.return_custody(
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
    v_from_name    TEXT;
    v_to_name      TEXT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL AND CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_from_balance;
    END IF;

    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT name, company_id INTO v_from_name, v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_to_treasury_id;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'إرجاع عهدة من ' || COALESCE(v_from_name, 'موظف'));

    -- Debit: Destination (Main Treasury), Credit: Source (Employee Custody)
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    UPDATE treasury_balances SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
        VALUES (p_to_treasury_id, p_currency, p_amount, v_to_acct, NOW());
        v_to_balance := 0;
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount, updated_at = NOW()
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    v_je_id := public.post_journal_entry(
        'treasury_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام مرتجع عهدة)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرجاع عهدة)')
        )
    );

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id)
    VALUES (p_from_treasury_id, 'return_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, v_user_id, v_je_id);

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by, journal_entry_id)
    VALUES (p_to_treasury_id, 'return_in', p_currency, p_amount,
        v_to_balance, v_to_balance + p_amount, v_desc, p_from_treasury_id, v_user_id, v_je_id);

    RETURN jsonb_build_object('journal_entry_id', v_je_id, 'success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.disburse_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.transfer_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.return_custody(INTEGER, INTEGER, TEXT, NUMERIC, TEXT) TO authenticated, anon, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
