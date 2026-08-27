-- Migration 305: Distinct Journal Entry Prefixes for Custody Operations
-- Assigns unique, non-conflicting document types and prefixes:
-- 1. صرف عهدة (Disburse Custody)  -> code: 'custody_disbursement', prefix: 'CDIS'
-- 2. تحويل عهدة (Transfer Custody) -> code: 'custody_transfer',     prefix: 'CTRF'
-- 3. إرجاع عهدة (Return Custody)   -> code: 'return_custody',       prefix: 'CRET'

BEGIN;

-- 1. Register distinct document types and prefixes in sys_document_types
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES 
  ('custody_disbursement', 'Custody Disbursement / صرف عهدة', 'CDIS', true),
  ('custody_transfer',     'Custody Transfer / تحويل عهدة',     'CTRF', true),
  ('return_custody',       'Return Custody / إرجاع عهدة',       'CRET', true)
ON CONFLICT (code) DO UPDATE SET
  prefix = EXCLUDED.prefix,
  name = EXCLUDED.name,
  is_active = true;

UPDATE public.sys_document_types SET prefix = 'CTRF', name = 'Custody Transfer / تحويل عهدة', is_active = true WHERE code = 'custody_transfer';
UPDATE public.sys_document_types SET prefix = 'CRET', name = 'Return Custody / إرجاع عهدة', is_active = true WHERE code = 'return_custody';


-- 2. Update disburse_custody: passes 'custody_disbursement' (Prefix: CDIS)
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

    -- Create GL Journal Entry with unique document_type 'custody_disbursement' (CDIS)
    v_je_id := public.post_journal_entry(
        'custody_disbursement',
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


-- 3. Update transfer_custody: passes 'custody_transfer' (Prefix: CTRF)
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

    -- Create GL Journal Entry with unique document_type 'custody_transfer' (CTRF)
    v_je_id := public.post_journal_entry(
        'custody_transfer',
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


-- 4. Update return_custody: passes 'return_custody' (Prefix: CRET)
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

    -- Create GL Journal Entry with unique document_type 'return_custody' (CRET)
    v_je_id := public.post_journal_entry(
        'return_custody',
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
