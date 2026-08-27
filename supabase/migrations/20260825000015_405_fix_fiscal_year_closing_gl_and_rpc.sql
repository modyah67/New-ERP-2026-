-- ============================================================================
-- Migration 405: Fix Fiscal Year Closing GL Queries and Provide Atomic Closing RPC
-- ============================================================================

BEGIN;

-- 0. Ensure sys_document_types has fiscal_year_closing and fiscal_year_reopening
INSERT INTO public.sys_document_types (code, name, prefix, is_active, created_at, updated_at)
VALUES 
    ('fiscal_year_closing', 'Fiscal Year Closing / إقفال سنة مالية', 'FYC', true, NOW(), NOW()),
    ('fiscal_year_reopening', 'Fiscal Year Reopening / إعادة فتح سنة مالية', 'FYR', true, NOW(), NOW())
ON CONFLICT (code) DO UPDATE SET 
    name = EXCLUDED.name,
    prefix = EXCLUDED.prefix,
    is_active = true,
    updated_at = NOW();

-- 1. Fix get_account_totals to read from account_ledger_entries using amount_in_base_currency / debit / credit
CREATE OR REPLACE FUNCTION public.get_account_totals(
    p_account_code text,
    p_fiscal_year_id bigint
) 
RETURNS TABLE(total_debit numeric, total_credit numeric)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0)::numeric AS total_debit,
    COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0)::numeric AS total_credit
  FROM public.account_ledger_entries ale
  JOIN public.accounts a ON ale.account_id = a.id
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE a.account_code = p_account_code
    AND ale.deleted_at IS NULL
    AND ale.created_at::date BETWEEN fy.start_date AND fy.end_date;
$$;

GRANT EXECUTE ON FUNCTION public.get_account_totals(text, bigint) TO authenticated;

-- 2. Fix get_account_totals_for_fy
CREATE OR REPLACE FUNCTION public.get_account_totals_for_fy(
    p_account_code text,
    p_fiscal_year_id bigint
) 
RETURNS TABLE(total_debit numeric, total_credit numeric)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0)::numeric AS total_debit,
    COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0)::numeric AS total_credit
  FROM public.account_ledger_entries ale
  JOIN public.accounts a ON ale.account_id = a.id
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE a.account_code = p_account_code
    AND ale.deleted_at IS NULL
    AND ale.created_at::date BETWEEN fy.start_date AND fy.end_date;
$$;

GRANT EXECUTE ON FUNCTION public.get_account_totals_for_fy(text, bigint) TO authenticated;

-- 3. Fix validate_trial_balance to read from account_ledger_entries
CREATE OR REPLACE FUNCTION public.validate_trial_balance(
    p_fiscal_year_id bigint
) 
RETURNS boolean
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) =
         COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0)
  FROM public.account_ledger_entries ale
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE ale.deleted_at IS NULL
    AND ale.created_at::date BETWEEN fy.start_date AND fy.end_date;
$$;

GRANT EXECUTE ON FUNCTION public.validate_trial_balance(bigint) TO authenticated;

-- 4. Atomic Stored Procedure to Execute Fiscal Year Closing
CREATE OR REPLACE FUNCTION public.rpc_close_fiscal_year(
    p_fiscal_year_id bigint,
    p_user_id uuid,
    p_reason text DEFAULT NULL,
    p_create_next_year boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fy RECORD;
    v_company_id UUID;
    v_retained_acct_id BIGINT;
    v_je_lines JSONB := '[]'::jsonb;
    v_desc TEXT;
    v_je_id BIGINT;
    v_total_revenue NUMERIC := 0;
    v_total_expense NUMERIC := 0;
    v_net_income NUMERIC := 0;
    v_rec RECORD;
    v_balance NUMERIC;
    v_closing_count INT := 0;
    v_next_year INT;
    v_next_fy_id INT;
BEGIN
    -- 1. Fetch Fiscal Year
    SELECT * INTO v_fy FROM public.fiscal_years WHERE id = p_fiscal_year_id;
    IF v_fy IS NULL THEN
        RAISE EXCEPTION 'السنة المالية رقم % غير موجودة', p_fiscal_year_id;
    END IF;

    IF v_fy.is_closed = true THEN
        RAISE EXCEPTION 'السنة المالية % مغلقة بالفعل', v_fy.year;
    END IF;

    v_company_id := v_fy.company_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL LIMIT 1;
    END IF;

    -- 2. Fetch Retained Earnings Account 3100
    SELECT id INTO v_retained_acct_id FROM public.accounts WHERE account_code = '3100' LIMIT 1;
    IF v_retained_acct_id IS NULL THEN
        RAISE EXCEPTION 'حساب الأرباح المحتجزة (3100) غير موجود في الدليل المحاسبي';
    END IF;

    v_desc := 'قيد إقفال السنة المالية ' || v_fy.year;

    -- 3. Close Revenue Accounts (Zero them out by DEBITING their credit balance)
    FOR v_rec IN 
        SELECT 
            a.id AS account_id,
            a.account_code,
            a.name AS account_name,
            COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0) - 
            COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) AS net_credit
        FROM public.accounts a
        JOIN public.account_ledger_entries ale ON ale.account_id = a.id
        WHERE a.account_type = 'revenue'
          AND a.is_active = true
          AND ale.deleted_at IS NULL
          AND ale.created_at::date BETWEEN v_fy.start_date AND v_fy.end_date
        GROUP BY a.id, a.account_code, a.name
        HAVING (COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0) - 
                COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0)) != 0
    LOOP
        v_balance := v_rec.net_credit;
        IF v_balance > 0 THEN
            -- Normal credit balance: Debit account to zero out
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', v_balance,
                'base_debit', v_balance,
                'credit', 0,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'إقفال حساب الإيرادات ' || v_rec.account_name
            );
            v_total_revenue := v_total_revenue + v_balance;
            v_closing_count := v_closing_count + 1;
        ELSIF v_balance < 0 THEN
            -- Abnormal debit balance in revenue
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', 0,
                'base_debit', 0,
                'credit', ABS(v_balance),
                'base_credit', ABS(v_balance),
                'currency', 'EGP',
                'description', 'إقفال حساب الإيرادات ' || v_rec.account_name
            );
            v_total_revenue := v_total_revenue + v_balance;
            v_closing_count := v_closing_count + 1;
        END IF;

        -- Record in tracking table with entry_type
        INSERT INTO public.fiscal_year_closing_entries (
            fiscal_year_id, entry_type, account_code, account_name, account_type,
            debit, credit, description, created_at
        ) VALUES (
            p_fiscal_year_id, 'CLOSE_REVENUE', v_rec.account_code, v_rec.account_name, 'revenue',
            CASE WHEN v_balance > 0 THEN v_balance ELSE 0 END,
            CASE WHEN v_balance < 0 THEN ABS(v_balance) ELSE 0 END,
            'إقفال حساب الإيرادات ' || v_rec.account_name,
            NOW()
        );
    END LOOP;

    -- 4. Close Expense Accounts (Zero them out by CREDITING their debit balance)
    FOR v_rec IN 
        SELECT 
            a.id AS account_id,
            a.account_code,
            a.name AS account_name,
            COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) - 
            COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0) AS net_debit
        FROM public.accounts a
        JOIN public.account_ledger_entries ale ON ale.account_id = a.id
        WHERE a.account_type = 'expense'
          AND a.is_active = true
          AND ale.deleted_at IS NULL
          AND ale.created_at::date BETWEEN v_fy.start_date AND v_fy.end_date
        GROUP BY a.id, a.account_code, a.name
        HAVING (COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) - 
                COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0)) != 0
    LOOP
        v_balance := v_rec.net_debit;
        IF v_balance > 0 THEN
            -- Normal debit balance: Credit account to zero out
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', 0,
                'base_debit', 0,
                'credit', v_balance,
                'base_credit', v_balance,
                'currency', 'EGP',
                'description', 'إقفال حساب المصروفات ' || v_rec.account_name
            );
            v_total_expense := v_total_expense + v_balance;
            v_closing_count := v_closing_count + 1;
        ELSIF v_balance < 0 THEN
            -- Abnormal credit balance in expense
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', ABS(v_balance),
                'base_debit', ABS(v_balance),
                'credit', 0,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'إقفال حساب المصروفات ' || v_rec.account_name
            );
            v_total_expense := v_total_expense + v_balance;
            v_closing_count := v_closing_count + 1;
        END IF;

        -- Record in tracking table with entry_type
        INSERT INTO public.fiscal_year_closing_entries (
            fiscal_year_id, entry_type, account_code, account_name, account_type,
            debit, credit, description, created_at
        ) VALUES (
            p_fiscal_year_id, 'CLOSE_EXPENSE', v_rec.account_code, v_rec.account_name, 'expense',
            CASE WHEN v_balance < 0 THEN ABS(v_balance) ELSE 0 END,
            CASE WHEN v_balance > 0 THEN v_balance ELSE 0 END,
            'إقفال حساب المصروفات ' || v_rec.account_name,
            NOW()
        );
    END LOOP;

    -- 5. Calculate Net Income and Transfer to Retained Earnings 3100
    v_net_income := v_total_revenue - v_total_expense;

    IF v_net_income != 0 THEN
        IF v_net_income > 0 THEN
            -- Profit: Credit 3100 Retained Earnings
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_retained_acct_id,
                'debit', 0,
                'base_debit', 0,
                'credit', v_net_income,
                'base_credit', v_net_income,
                'currency', 'EGP',
                'description', 'ترحيل صافي أرباح العام إلى الأرباح المحتجزة'
            );
        ELSE
            -- Loss: Debit 3100 Retained Earnings
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_retained_acct_id,
                'debit', ABS(v_net_income),
                'base_debit', ABS(v_net_income),
                'credit', 0,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'ترحيل صافي خسائر العام إلى الأرباح المحتجزة'
            );
        END IF;

        INSERT INTO public.fiscal_year_closing_entries (
            fiscal_year_id, entry_type, account_code, account_name, account_type,
            debit, credit, description, created_at
        ) VALUES (
            p_fiscal_year_id, 'TRANSFER_RETAINED', '3100', 'الأرباح المحتجزة', 'equity',
            CASE WHEN v_net_income < 0 THEN ABS(v_net_income) ELSE 0 END,
            CASE WHEN v_net_income > 0 THEN v_net_income ELSE 0 END,
            'تحويل صافي الدخل إلى الأرباح المحتجزة',
            NOW()
        );
    END IF;

    -- 6. Post the Journal Entry if there are closing lines
    IF jsonb_array_length(v_je_lines) > 0 THEN
        v_je_id := public.post_journal_entry(
            'fiscal_year_closing',
            v_desc,
            v_fy.end_date,
            v_company_id,
            p_user_id,
            v_je_lines,
            p_fiscal_year_id::TEXT
        );
    END IF;

    -- 7. Update Fiscal Year Status to CLOSED
    UPDATE public.fiscal_years SET
        status = 'CLOSED',
        is_closed = true,
        closed_at = NOW(),
        closed_by = p_user_id,
        is_current = false,
        updated_at = NOW()
    WHERE id = p_fiscal_year_id;

    -- 8. Auto-create Next Fiscal Year if requested
    IF p_create_next_year THEN
        v_next_year := v_fy.year + 1;
        IF NOT EXISTS (SELECT 1 FROM public.fiscal_years WHERE year = v_next_year) THEN
            INSERT INTO public.fiscal_years (
                year, name, start_date, end_date, status, is_current, is_closed, company_id, created_at, updated_at
            ) VALUES (
                v_next_year,
                'FY ' || v_next_year,
                (v_next_year || '-01-01')::DATE,
                (v_next_year || '-12-31')::DATE,
                'ACTIVE',
                true,
                false,
                v_company_id,
                NOW(),
                NOW()
            ) RETURNING id INTO v_next_fy_id;
        ELSE
            UPDATE public.fiscal_years SET is_current = true WHERE year = v_next_year;
        END IF;
    END IF;

    -- 9. Audit Log
    INSERT INTO public.fiscal_year_audit_log (
        fiscal_year_id, action, performed_by, performed_at,
        old_status, new_status, reason, details
    ) VALUES (
        p_fiscal_year_id,
        'CLOSE',
        p_user_id,
        NOW(),
        jsonb_build_object('status', 'ACTIVE', 'is_closed', false),
        jsonb_build_object('status', 'CLOSED', 'is_closed', true),
        p_reason,
        jsonb_build_object(
            'closing_entries_count', v_closing_count,
            'total_revenue', v_total_revenue,
            'total_expense', v_total_expense,
            'net_income', v_net_income,
            'journal_entry_id', v_je_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'closing_entries_count', v_closing_count,
        'total_revenue', v_total_revenue,
        'total_expense', v_total_expense,
        'net_income', v_net_income
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_close_fiscal_year(bigint, uuid, text, boolean) TO authenticated;

-- 5. Stored Procedure to Reopen Fiscal Year
CREATE OR REPLACE FUNCTION public.rpc_reopen_fiscal_year(
    p_fiscal_year_id bigint,
    p_user_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fy RECORD;
    v_je RECORD;
BEGIN
    SELECT * INTO v_fy FROM public.fiscal_years WHERE id = p_fiscal_year_id;
    IF v_fy IS NULL THEN
        RAISE EXCEPTION 'السنة المالية غير موجودة';
    END IF;

    -- Reverse closing journal entries if any
    FOR v_je IN 
        SELECT id FROM public.journal_entries 
        WHERE source_type = 'fiscal_year_closing' 
          AND (source_id = p_fiscal_year_id::TEXT OR entry_date BETWEEN v_fy.start_date AND v_fy.end_date)
          AND is_reversed = false
    LOOP
        PERFORM public.reverse_journal_entry(v_je.id, 'إلغاء قيد إقفال السنة المالية ' || v_fy.year);
    END LOOP;

    DELETE FROM public.fiscal_year_closing_entries WHERE fiscal_year_id = p_fiscal_year_id;

    UPDATE public.fiscal_years SET
        status = 'ACTIVE',
        is_closed = false,
        closed_at = NULL,
        closed_by = NULL,
        is_current = true,
        updated_at = NOW()
    WHERE id = p_fiscal_year_id;

    UPDATE public.fiscal_years SET is_current = false WHERE id != p_fiscal_year_id;

    INSERT INTO public.fiscal_year_audit_log (
        fiscal_year_id, action, performed_by, performed_at,
        old_status, new_status, reason
    ) VALUES (
        p_fiscal_year_id,
        'REOPEN',
        p_user_id,
        NOW(),
        jsonb_build_object('status', 'CLOSED', 'is_closed', true),
        jsonb_build_object('status', 'ACTIVE', 'is_closed', false),
        p_reason
    );

    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_reopen_fiscal_year(bigint, uuid, text) TO authenticated;

COMMIT;
