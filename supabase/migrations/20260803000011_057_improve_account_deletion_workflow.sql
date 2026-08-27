-- Migration 057: Improve account deletion workflow
-- 1. Create fn_validate_account_deletion RPC for defense in depth
-- 2. Update DAO to call validation before delete

CREATE OR REPLACE FUNCTION public.fn_validate_account_deletion(
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_account       RECORD;
    v_has_children  BOOLEAN;
    v_has_entries   BOOLEAN;
    v_has_treasury  BOOLEAN;
    v_has_bank      BOOLEAN;
    v_has_balances  BOOLEAN;
    v_reasons       TEXT[] := '{}';
BEGIN
    -- 1. Check account exists
    SELECT id, account_code, account_name, is_system, is_leaf, is_locked, balance, parent_id
    INTO v_account
    FROM accounts WHERE id = p_account_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'الحساب غير موجود');
    END IF;

    -- 2. System account check
    IF v_account.is_system = true THEN
        v_reasons := array_append(v_reasons, 'حساب نظامي');
    END IF;

    -- 3. Has children check
    SELECT EXISTS(SELECT 1 FROM accounts WHERE parent_id = p_account_id) INTO v_has_children;
    IF v_has_children THEN
        v_reasons := array_append(v_reasons, 'يحتوي على حسابات فرعية');
    END IF;

    -- 4. Non-zero balance check
    IF v_account.balance != 0 THEN
        v_reasons := array_append(v_reasons, 'رصيد الحساب غير صفر (' || v_account.balance || ')');
    END IF;

    -- 5. Ledger entries check
    SELECT EXISTS(SELECT 1 FROM account_ledger_entries WHERE account_id = p_account_id) INTO v_has_entries;
    IF v_has_entries THEN
        v_reasons := array_append(v_reasons, 'يحتوي على قيود محاسبية');
    END IF;

    -- 6. Treasury transactions reference check
    SELECT EXISTS(
        SELECT 1 FROM treasury_transactions
        WHERE expense_account_id = p_account_id OR revenue_account_id = p_account_id
    ) INTO v_has_treasury;
    IF v_has_treasury THEN
        v_reasons := array_append(v_reasons, 'مستخدم في معاملات خزينة');
    END IF;

    -- 7. Bank transactions reference check
    SELECT EXISTS(
        SELECT 1 FROM bank_account_transactions
        WHERE expense_account_id = p_account_id OR revenue_account_id = p_account_id
    ) INTO v_has_bank;
    IF v_has_bank THEN
        v_reasons := array_append(v_reasons, 'مستخدم في معاملات بنكية');
    END IF;

    -- 8. Treasury balances reference check
    SELECT EXISTS(
        SELECT 1 FROM treasury_balances WHERE account_id = p_account_id
    ) INTO v_has_balances;
    IF v_has_balances THEN
        v_reasons := array_append(v_reasons, 'مرتبط برصيد خزينة');
    END IF;

    -- 9. Return result
    IF array_length(v_reasons, 1) > 0 THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', array_to_string(v_reasons, ' — ')
        );
    END IF;

    RETURN jsonb_build_object('allowed', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_validate_account_deletion(BIGINT) TO authenticated;
