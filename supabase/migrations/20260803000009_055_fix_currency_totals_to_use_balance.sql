-- Phase 055: Fix currency_totals to read from treasury_balances instead of expense aggregates
-- The dashboard cards labeled "الخزينة (ج.م)" should show the actual treasury balance,
-- not the sum of expenses per currency.

DROP FUNCTION IF EXISTS public.get_treasury_stats(text, boolean, text, text);

CREATE OR REPLACE FUNCTION public.get_treasury_stats(
    p_main_treasury_id text DEFAULT NULL,
    p_all_treasuries   boolean DEFAULT false,
    p_start_date       text DEFAULT NULL,
    p_end_date         text DEFAULT NULL
) RETURNS jsonb
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
    v_revenue_breakdown JSONB;
    v_currency_totals JSONB;
    v_employee_custody NUMERIC := 0;
    v_employee_custody_breakdown JSONB;
BEGIN
    -- Treasury-only aggregates
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
        'id', a.id,
        'name', a.account_name,
        'code', a.account_code,
        'color', '#E65100',
        'total', COALESCE(totals.total, 0)
    ) ORDER BY COALESCE(totals.total, 0) DESC), '[]'::jsonb)
    INTO v_category_breakdown
    FROM accounts a
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(sub.amount), 0) AS total
        FROM (
            SELECT td.amount
            FROM treasury_transactions td
            WHERE td.expense_account_id = a.id
              AND td.type IN ('expense', 'withdrawal')
              AND (p_start_date IS NULL OR td.created_at >= p_start_date::timestamptz)
              AND (p_end_date IS NULL OR td.created_at <= (p_end_date::timestamptz + interval '1 day'))
              AND (
                p_all_treasuries = TRUE
                OR td.treasury_id::TEXT = p_main_treasury_id
                OR (p_main_treasury_id IS NULL AND td.treasury_id IN (
                    SELECT id FROM treasuries WHERE type = 'main' LIMIT 1
                ))
              )

            UNION ALL

            SELECT bat.amount
            FROM bank_account_transactions bat
            WHERE bat.expense_account_id = a.id
              AND bat.type = 'withdrawal'
              AND (p_start_date IS NULL OR bat.created_at >= p_start_date::timestamptz)
              AND (p_end_date IS NULL OR bat.created_at <= (p_end_date::timestamptz + interval '1 day'))
        ) sub
    ) totals ON TRUE
    WHERE a.account_type = 'expense'
      AND a.is_leaf = true
      AND a.is_active = true;

    -- Revenue account breakdown
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', a.id,
        'name', a.account_name,
        'code', a.account_code,
        'color', '#2E7D32',
        'total', COALESCE(totals.total, 0)
    ) ORDER BY COALESCE(totals.total, 0) DESC), '[]'::jsonb)
    INTO v_revenue_breakdown
    FROM accounts a
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(sub.amount), 0) AS total
        FROM (
            SELECT td.amount
            FROM treasury_transactions td
            WHERE td.revenue_account_id = a.id
              AND td.type = 'deposit'
              AND (p_start_date IS NULL OR td.created_at >= p_start_date::timestamptz)
              AND (p_end_date IS NULL OR td.created_at <= (p_end_date::timestamptz + interval '1 day'))
              AND (
                p_all_treasuries = TRUE
                OR td.treasury_id::TEXT = p_main_treasury_id
                OR (p_main_treasury_id IS NULL AND td.treasury_id IN (
                    SELECT id FROM treasuries WHERE type = 'main' LIMIT 1
                ))
              )

            UNION ALL

            SELECT bat.amount
            FROM bank_account_transactions bat
            WHERE bat.revenue_account_id = a.id
              AND bat.type = 'deposit'
              AND (p_start_date IS NULL OR bat.created_at >= p_start_date::timestamptz)
              AND (p_end_date IS NULL OR bat.created_at <= (p_end_date::timestamptz + interval '1 day'))
        ) sub
    ) totals ON TRUE
    WHERE a.account_type = 'revenue'
      AND a.is_leaf = true
      AND a.is_active = true;

    -- Currency totals: READ FROM treasury_balances (actual balance, not expense aggregates)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'currency', tb.currency,
        'total', tb.balance,
        'balance', tb.balance
    )), '[]'::jsonb)
    INTO v_currency_totals
    FROM treasury_balances tb
    JOIN treasuries t ON t.id = tb.treasury_id
    WHERE tb.balance > 0
      AND (
        p_all_treasuries = TRUE
        OR t.id::TEXT = p_main_treasury_id
        OR (p_main_treasury_id IS NULL AND t.type = 'main')
      );

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
        'revenue_breakdown', v_revenue_breakdown,
        'currency_totals', v_currency_totals,
        'total_employee_custody', v_employee_custody,
        'employee_custody_breakdown', v_employee_custody_breakdown
    );

    RETURN v_result;
END;
$$;
