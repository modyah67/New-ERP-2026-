-- 161_fix_sorting_sale_gl.sql
-- Fixes the GL logic for selling a "فرزة" (Sorting product) by introducing a dedicated RPC
-- that posts the correct Journal Entry (Dr. Treasury, Cr. Sales Revenue) and updates the Treasury appropriately.
-- It also softens the trigger on treasury_transactions so it automatically assigns 4100 to deposits if missing.

BEGIN;

-- 1. Modify the strict trigger to automatically assign Sales Revenue (4100) if missing for a deposit
CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_company_id UUID;
    v_sales_acct BIGINT;
BEGIN
    IF NEW.type = 'deposit' AND NEW.revenue_account_id IS NULL THEN
        -- Resolve company ID from the treasury
        SELECT company_id INTO v_company_id FROM treasuries WHERE id = NEW.treasury_id;
        
        -- Default to Sales Revenue (4100)
        SELECT id INTO v_sales_acct FROM accounts WHERE account_code = '4100' AND company_id = v_company_id LIMIT 1;
        
        -- If 4100 doesn't exist, fallback to Owner Equity (3000) so we don't block operations
        IF v_sales_acct IS NULL THEN
            SELECT id INTO v_sales_acct FROM accounts WHERE account_code = '3000' AND company_id = v_company_id LIMIT 1;
        END IF;

        NEW.revenue_account_id := v_sales_acct;
    END IF;
    RETURN NEW;
END;
$$;

-- 2. Create the dedicated RPC for selling sorting
CREATE OR REPLACE FUNCTION public.rpc_sell_sorting(
    p_sorting_id INT,
    p_qty NUMERIC,
    p_price NUMERIC,
    p_treasury_id BIGINT,
    p_treasury_name TEXT,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_amount NUMERIC;
    v_sorting RECORD;
    v_new_remaining NUMERIC;
    v_new_sale_total NUMERIC;
    v_new_status TEXT;
    v_updated_treasury_names TEXT;
    
    v_company_id UUID;
    v_currency TEXT := 'EGP';
    
    v_current_balance NUMERIC;
    v_new_balance NUMERIC;
    v_treasury_balance_id INTEGER;
    v_treasury_acct BIGINT;
    v_sales_acct BIGINT;
    
    v_je_id BIGINT;
    v_tx_id INTEGER;
    v_desc TEXT;
BEGIN
    v_amount := p_qty * p_price;
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Lock the sorting row
    SELECT * INTO v_sorting FROM packing_order_sortings WHERE id = p_sorting_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'سجل الفرز غير موجود';
    END IF;

    IF p_qty > v_sorting.remaining_weight_kg THEN
        RAISE EXCEPTION 'الكمية المباعة أكبر من المتبقي (% كجم)', v_sorting.remaining_weight_kg;
    END IF;

    v_new_remaining := v_sorting.remaining_weight_kg - p_qty;
    v_new_sale_total := COALESCE(v_sorting.total_sale_amount, 0) + v_amount;
    
    IF v_new_remaining <= 0 THEN
        v_new_status := 'sold';
    ELSE
        v_new_status := 'pending';
    END IF;

    v_updated_treasury_names := v_sorting.treasury_names;
    IF p_treasury_name IS NOT NULL THEN
        IF v_updated_treasury_names IS NULL OR v_updated_treasury_names = '' THEN
            v_updated_treasury_names := p_treasury_name;
        ELSIF v_updated_treasury_names NOT LIKE '%' || p_treasury_name || '%' THEN
            v_updated_treasury_names := v_updated_treasury_names || '، ' || p_treasury_name;
        END IF;
    END IF;

    -- Update sorting row
    UPDATE packing_order_sortings SET
        remaining_weight_kg = GREATEST(0, v_new_remaining),
        total_sale_amount = v_new_sale_total,
        status = v_new_status,
        sold_at = CASE WHEN v_new_status = 'sold' THEN now() ELSE sold_at END,
        treasury_names = v_updated_treasury_names
    WHERE id = p_sorting_id;

    -- Resolve Treasury and Company
    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'الخزنة غير موجودة';
    END IF;

    -- Treasury Balance
    SELECT id, COALESCE(balance, 0) INTO v_treasury_balance_id, v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = v_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + v_amount;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, v_currency, v_company_id);
    IF v_treasury_balance_id IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
        VALUES (p_treasury_id, v_currency, v_new_balance, v_treasury_acct)
        RETURNING id INTO v_treasury_balance_id;
    ELSE
        UPDATE treasury_balances SET balance = v_new_balance WHERE id = v_treasury_balance_id;
    END IF;

    -- GL Accounts
    SELECT id INTO v_sales_acct FROM accounts WHERE account_code = '4100' AND company_id = v_company_id LIMIT 1;
    IF v_sales_acct IS NULL THEN
        v_sales_acct := public.resolve_gl_account('3000', v_company_id);
    END IF;

    v_desc := 'بيع فرز - ' || COALESCE(v_sorting.product_name, '') || ' - ' || trim(to_char(p_qty, '9999990.9')) || ' كجم';

    -- Journal Entry: Dr. Treasury / Cr. Sales Revenue
    v_je_id := public.post_journal_entry(
        'sale_sorting',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', v_amount, 'base_debit', v_amount, 'credit', 0, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_sales_acct, 'debit', 0, 'base_debit', 0, 'credit', v_amount, 'base_credit', v_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    -- Treasury Transaction
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after,
        description, source_type, journal_entry_id, revenue_account_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', v_currency, v_amount, v_current_balance, v_new_balance,
        v_desc, 'sale_sorting', v_je_id, v_sales_acct, p_user_id
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object('success', true, 'journal_entry_id', v_je_id, 'treasury_tx_id', v_tx_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.rpc_sell_sorting(INT, NUMERIC, NUMERIC, BIGINT, TEXT, UUID) TO authenticated;

COMMIT;
