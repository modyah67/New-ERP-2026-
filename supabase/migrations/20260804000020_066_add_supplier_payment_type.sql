-- Migration 066: Add supplier_payment type + audit treasury type system
-- ============================================================================
-- ROOT CAUSE: spend_custody (migration 065) inserts type='supplier_payment'
-- but the CHECK constraint does not allow it.
--
-- ACTIONS:
--   1. Drop old constraint, recreate with supplier_payment
--   2. Update get_treasury_stats to count supplier_payment as expense
--   3. Ensure fn_require_expense_account_treasury handles supplier_payment
--   4. GRANT and NOTIFY

BEGIN;

-- ============================================================================
-- 1. Fix CHECK constraint
-- ============================================================================

ALTER TABLE public.treasury_transactions
    DROP CONSTRAINT IF EXISTS treasury_transactions_type_check;

ALTER TABLE public.treasury_transactions
    ADD CONSTRAINT treasury_transactions_type_check
    CHECK (type = ANY (ARRAY[
        'deposit',
        'expense',
        'withdrawal',
        'disbursement',
        'disbursement_out',
        'transfer_in',
        'transfer_out',
        'return_in',
        'return_out',
        'currency_exchange_out',
        'currency_exchange_in',
        'supplier_payment'
    ]));

-- ============================================================================
-- 2. Update fn_require_expense_account_treasury (migration 061 version)
--    supplier_payment does NOT require expense_account_id
--    (the GL account is auto-resolved from suppliers.account_id in SQL)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_require_expense_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Require expense_account_id for 'expense' and 'withdrawal' only
    -- 'supplier_payment' does NOT require it (auto-resolved from supplier)
    IF NEW.type IN ('expense', 'withdrawal') AND NEW.expense_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. Update get_treasury_stats — include supplier_payment in expense sums
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_treasury_stats(p_treasury_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_result JSON;
    v_total_balance NUMERIC := 0;
    v_expenses NUMERIC := 0;
    v_disbursements NUMERIC := 0;
    v_returns NUMERIC := 0;
    v_transfers NUMERIC := 0;
    v_deposits NUMERIC := 0;
    v_expense_breakdown JSONB := '[]'::jsonb;
BEGIN
    -- Total balance from treasury_balances (single source of truth)
    SELECT COALESCE(SUM(balance), 0) INTO v_total_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id;

    -- Expense total: expense + withdrawal + supplier_payment
    SELECT COALESCE(SUM(CASE WHEN type IN ('expense', 'withdrawal', 'supplier_payment') THEN amount ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN type IN ('disbursement', 'disbursement_out') THEN amount ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN type IN ('return_in', 'return_out') THEN amount ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN type IN ('transfer_in', 'transfer_out') THEN amount ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END), 0)
    INTO v_expenses, v_disbursements, v_returns, v_transfers, v_deposits
    FROM treasury_transactions
    WHERE treasury_id = p_treasury_id;

    -- Expense breakdown by category (includes supplier_payment)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'category_id', category_id,
                'category_name', COALESCE(
                    (SELECT name FROM expense_categories WHERE id = category_id),
                    'غير مصنف'
                ),
                'total', total
            )
        ),
        '[]'::jsonb
    ) INTO v_expense_breakdown
    FROM (
        SELECT category_id, SUM(amount) as total
        FROM treasury_transactions
        WHERE treasury_id = p_treasury_id
          AND type IN ('expense', 'withdrawal', 'supplier_payment')
        GROUP BY category_id
        ORDER BY total DESC
    ) sub;

    SELECT jsonb_build_object(
        'total_balance', v_total_balance,
        'expenses', v_expenses,
        'disbursements', v_disbursements,
        'returns', v_returns,
        'transfers', v_transfers,
        'deposits', v_deposits,
        'expense_breakdown', v_expense_breakdown
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 4. Update get_treasury_detailed_stats — include supplier_payment
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_treasury_detailed_stats(p_company_id UUID DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_result JSON;
    v_total_treasury_balance NUMERIC := 0;
    v_total_bank_balance NUMERIC := 0;
    v_expenses NUMERIC := 0;
    v_disbursements NUMERIC := 0;
    v_returns NUMERIC := 0;
    v_transfers NUMERIC := 0;
    v_deposits NUMERIC := 0;
    v_bank_deposits NUMERIC := 0;
    v_bank_withdrawals NUMERIC := 0;
    v_per_treasury JSONB := '[]'::jsonb;
    v_bank_stats JSONB := '[]'::jsonb;
BEGIN
    -- Total treasury balance
    SELECT COALESCE(SUM(balance), 0) INTO v_total_treasury_balance
    FROM treasury_balances tb
    JOIN treasuries t ON t.id = tb.treasury_id
    WHERE (p_company_id IS NULL OR t.company_id = p_company_id);

    -- Total bank balance
    SELECT COALESCE(SUM(balance), 0) INTO v_total_bank_balance
    FROM bank_accounts ba
    WHERE (p_company_id IS NULL OR ba.company_id = p_company_id);

    -- Treasury expenses (including supplier_payment)
    SELECT
        COALESCE(SUM(CASE WHEN type IN ('expense', 'withdrawal', 'supplier_payment') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type IN ('disbursement', 'disbursement_out') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type IN ('return_in', 'return_out') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type IN ('transfer_in', 'transfer_out') THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END), 0)
    INTO v_expenses, v_disbursements, v_returns, v_transfers, v_deposits
    FROM treasury_transactions tt
    JOIN treasuries t ON t.id = tt.treasury_id
    WHERE (p_company_id IS NULL OR t.company_id = p_company_id);

    -- Per-treasury stats
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'treasury_id', t.id,
                'treasury_name', t.name,
                'total_balance', COALESCE(tb.total_balance, 0),
                'expenses', COALESCE(ts.expenses, 0),
                'deposits', COALESCE(ts.deposits, 0),
                'disbursements', COALESCE(ts.disbursements, 0),
                'returns', COALESCE(ts.returns, 0),
                'transfers', COALESCE(ts.transfers, 0)
            )
        ),
        '[]'::jsonb
    ) INTO v_per_treasury
    FROM treasuries t
    LEFT JOIN (
        SELECT treasury_id, SUM(balance) as total_balance
        FROM treasury_balances
        GROUP BY treasury_id
    ) tb ON tb.treasury_id = t.id
    LEFT JOIN (
        SELECT
            treasury_id,
            SUM(CASE WHEN type IN ('expense', 'withdrawal', 'supplier_payment') THEN amount ELSE 0 END) AS expenses,
            SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END) AS deposits,
            SUM(CASE WHEN type IN ('disbursement', 'disbursement_out') THEN amount ELSE 0 END) AS disbursements,
            SUM(CASE WHEN type IN ('return_in', 'return_out') THEN amount ELSE 0 END) AS returns,
            SUM(CASE WHEN type IN ('transfer_in', 'transfer_out') THEN amount ELSE 0 END) AS transfers
        FROM treasury_transactions
        GROUP BY treasury_id
    ) ts ON ts.treasury_id = t.id
    WHERE (p_company_id IS NULL OR t.company_id = p_company_id)
    ORDER BY t.name;

    -- Bank stats
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'bank_account_id', ba.id,
                'bank_name', ba.bank_name,
                'account_number', ba.account_number,
                'balance', ba.balance,
                'currency', ba.currency,
                'expenses', COALESCE(bs.withdrawals, 0),
                'deposits', COALESCE(bs.deposits, 0)
            )
        ),
        '[]'::jsonb
    ) INTO v_bank_stats
    FROM bank_accounts ba
    LEFT JOIN (
        SELECT
            bank_account_id,
            SUM(CASE WHEN type = 'withdrawal' THEN amount ELSE 0 END) AS withdrawals,
            SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END) AS deposits
        FROM bank_account_transactions
        GROUP BY bank_account_id
    ) bs ON bs.bank_account_id = ba.id
    WHERE (p_company_id IS NULL OR ba.company_id = p_company_id)
    ORDER BY ba.bank_name;

    SELECT jsonb_build_object(
        'total_treasury_balance', v_total_treasury_balance,
        'total_bank_balance', v_total_bank_balance,
        'total_expenses', v_expenses,
        'total_disbursements', v_disbursements,
        'total_returns', v_returns,
        'total_transfers', v_transfers,
        'total_deposits', v_deposits,
        'per_treasury', v_per_treasury,
        'bank_stats', v_bank_stats
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 5. Update get_expense_breakdown — include supplier_payment
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_expense_breakdown(
    p_treasury_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'category_id', category_id,
                'category_name', COALESCE(
                    (SELECT name FROM expense_categories WHERE id = category_id),
                    'غير مصنف'
                ),
                'total', total,
                'count', cnt
            )
        ),
        '[]'::jsonb
    ) INTO v_result
    FROM (
        SELECT
            category_id,
            SUM(amount) as total,
            COUNT(*) as cnt
        FROM treasury_transactions
        WHERE treasury_id = p_treasury_id
          AND type IN ('expense', 'withdrawal', 'supplier_payment')
          AND (p_start_date IS NULL OR created_at >= p_start_date)
          AND (p_end_date IS NULL OR created_at < p_end_date + INTERVAL '1 day')
        GROUP BY category_id
        ORDER BY total DESC
    ) sub;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 6. Ensure supplier_payment is in type labels (for UI consistency)
-- ============================================================================

-- No SQL change needed — labels are in Dart code.

-- ============================================================================
-- 7. GRANT
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.get_treasury_stats(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_treasury_detailed_stats(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_expense_breakdown(BIGINT, DATE, DATE) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
