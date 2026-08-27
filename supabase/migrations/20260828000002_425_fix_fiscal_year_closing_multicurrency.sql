-- ============================================================================
-- Migration 425: Multi-Currency Fiscal Year Closing Fix
-- Description:
--   Ensures rpc_close_fiscal_year generates closing entries per currency
--   (e.g., USD, EUR, EGP) so both base currency and foreign currency balances
--   are zeroed out cleanly on revenue and expense accounts.
-- ============================================================================

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
    v_base_balance NUMERIC;
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

    -- 3. Close Revenue Accounts by Currency (Zero them out in their respective currencies)
    FOR v_rec IN 
        SELECT 
            a.id AS account_id,
            a.account_code,
            a.name AS account_name,
            COALESCE(ale.currency, 'EGP') AS currency,
            COALESCE(SUM(ale.credit), 0) - COALESCE(SUM(ale.debit), 0) AS net_credit,
            COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0) - 
            COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) AS net_base_credit
        FROM public.accounts a
        JOIN public.account_ledger_entries ale ON ale.account_id = a.id
        LEFT JOIN public.journal_entries je ON je.id = ale.journal_entry_id
        WHERE a.account_type = 'revenue'
          AND a.is_active = true
          AND ale.deleted_at IS NULL
          AND (je.source_type IS NULL OR je.source_type != 'fiscal_year_closing')
          AND ale.created_at::date BETWEEN v_fy.start_date AND v_fy.end_date
        GROUP BY a.id, a.account_code, a.name, ale.currency
        HAVING (COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0) - 
                COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0)) != 0
            OR (COALESCE(SUM(ale.credit), 0) - COALESCE(SUM(ale.debit), 0)) != 0
    LOOP
        v_balance := v_rec.net_credit;
        v_base_balance := v_rec.net_base_credit;
        
        IF v_base_balance > 0 OR v_balance > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', v_balance,
                'base_debit', v_base_balance,
                'credit', 0,
                'base_credit', 0,
                'currency', v_rec.currency,
                'description', 'إقفال حساب الإيرادات ' || v_rec.account_name
            );
            v_total_revenue := v_total_revenue + v_base_balance;
            v_closing_count := v_closing_count + 1;
        ELSIF v_base_balance < 0 OR v_balance < 0 THEN
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', 0,
                'base_debit', 0,
                'credit', ABS(v_balance),
                'base_credit', ABS(v_base_balance),
                'currency', v_rec.currency,
                'description', 'إقفال حساب الإيرادات ' || v_rec.account_name
            );
            v_total_revenue := v_total_revenue + v_base_balance;
            v_closing_count := v_closing_count + 1;
        END IF;

        INSERT INTO public.fiscal_year_closing_entries (
            fiscal_year_id, entry_type, account_code, account_name, account_type,
            debit, credit, description, created_at
        ) VALUES (
            p_fiscal_year_id, 'CLOSE_REVENUE', v_rec.account_code, v_rec.account_name, 'revenue',
            CASE WHEN v_base_balance > 0 THEN v_base_balance ELSE 0 END,
            CASE WHEN v_base_balance < 0 THEN ABS(v_base_balance) ELSE 0 END,
            'إقفال حساب الإيرادات ' || v_rec.account_name || ' (' || v_rec.currency || ')',
            NOW()
        );
    END LOOP;

    -- 4. Close Expense Accounts by Currency (Zero them out in their respective currencies)
    FOR v_rec IN 
        SELECT 
            a.id AS account_id,
            a.account_code,
            a.name AS account_name,
            COALESCE(ale.currency, 'EGP') AS currency,
            COALESCE(SUM(ale.debit), 0) - COALESCE(SUM(ale.credit), 0) AS net_debit,
            COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) - 
            COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0) AS net_base_debit
        FROM public.accounts a
        JOIN public.account_ledger_entries ale ON ale.account_id = a.id
        LEFT JOIN public.journal_entries je ON je.id = ale.journal_entry_id
        WHERE a.account_type = 'expense'
          AND a.is_active = true
          AND ale.deleted_at IS NULL
          AND (je.source_type IS NULL OR je.source_type != 'fiscal_year_closing')
          AND ale.created_at::date BETWEEN v_fy.start_date AND v_fy.end_date
        GROUP BY a.id, a.account_code, a.name, ale.currency
        HAVING (COALESCE(SUM(CASE WHEN ale.debit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.debit) ELSE 0 END), 0) - 
                COALESCE(SUM(CASE WHEN ale.credit > 0 THEN COALESCE(ale.amount_in_base_currency, ale.credit) ELSE 0 END), 0)) != 0
            OR (COALESCE(SUM(ale.debit), 0) - COALESCE(SUM(ale.credit), 0)) != 0
    LOOP
        v_balance := v_rec.net_debit;
        v_base_balance := v_rec.net_base_debit;
        
        IF v_base_balance > 0 OR v_balance > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', 0,
                'base_debit', 0,
                'credit', v_balance,
                'base_credit', v_base_balance,
                'currency', v_rec.currency,
                'description', 'إقفال حساب المصروفات ' || v_rec.account_name
            );
            v_total_expense := v_total_expense + v_base_balance;
            v_closing_count := v_closing_count + 1;
        ELSIF v_base_balance < 0 OR v_balance < 0 THEN
            v_je_lines := v_je_lines || jsonb_build_object(
                'account_id', v_rec.account_id,
                'debit', ABS(v_balance),
                'base_debit', ABS(v_base_balance),
                'credit', 0,
                'base_credit', 0,
                'currency', v_rec.currency,
                'description', 'إقفال حساب المصروفات ' || v_rec.account_name
            );
            v_total_expense := v_total_expense + v_base_balance;
            v_closing_count := v_closing_count + 1;
        END IF;

        INSERT INTO public.fiscal_year_closing_entries (
            fiscal_year_id, entry_type, account_code, account_name, account_type,
            debit, credit, description, created_at
        ) VALUES (
            p_fiscal_year_id, 'CLOSE_EXPENSE', v_rec.account_code, v_rec.account_name, 'expense',
            CASE WHEN v_base_balance < 0 THEN ABS(v_base_balance) ELSE 0 END,
            CASE WHEN v_base_balance > 0 THEN v_base_balance ELSE 0 END,
            'إقفال حساب المصروفات ' || v_rec.account_name || ' (' || v_rec.currency || ')',
            NOW()
        );
    END LOOP;

    -- 5. Calculate Net Income in Base Currency and Transfer to Retained Earnings 3100
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
