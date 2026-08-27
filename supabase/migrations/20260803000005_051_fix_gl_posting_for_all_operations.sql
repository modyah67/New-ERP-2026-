-- ============================================================================
-- Migration 051: Fix GL Posting for transfer_custody, return_custody,
--                 exchange_currency, exchange_bank_currency,
--                 update_bank_account_transaction, delete_bank_account_transaction
-- ============================================================================

-- ============================================================================
-- 1. transfer_custody — add GL posting (mirror of disburse_custody)
-- ============================================================================
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
    v_je_id        BIGINT;
    v_desc         TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
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

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_from_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل بين الخزائن');

    v_from_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );
    v_to_acct := v_from_acct;

    UPDATE treasury_balances SET balance = balance - p_amount
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance)
        VALUES (p_to_treasury_id, p_currency, p_amount);
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    v_je_id := public.post_journal_entry(
        'treasury_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (وصول)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال)')
        )
    );

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_from_treasury_id, 'transfer_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, auth.uid());

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_to_treasury_id, 'transfer_in', p_currency, p_amount,
        COALESCE(v_to_balance, 0), COALESCE(v_to_balance, 0) + p_amount, v_desc,
        p_from_treasury_id, auth.uid());

    RETURN jsonb_build_object('journal_entry_id', v_je_id);
END;
$$;

-- ============================================================================
-- 2. return_custody — add GL posting (reverse direction of transfer)
-- ============================================================================
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
    v_je_id        BIGINT;
    v_desc         TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
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

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_from_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'إرجاع عهدة');

    v_from_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );
    v_to_acct := v_from_acct;

    UPDATE treasury_balances SET balance = balance - p_amount
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance)
        VALUES (p_to_treasury_id, p_currency, p_amount);
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    v_je_id := public.post_journal_entry(
        'treasury_transfer',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (وصول)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال)')
        )
    );

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_from_treasury_id, 'return_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, v_desc, p_to_treasury_id, auth.uid());

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_to_treasury_id, 'return_in', p_currency, p_amount,
        COALESCE(v_to_balance, 0), COALESCE(v_to_balance, 0) + p_amount, v_desc,
        p_from_treasury_id, auth.uid());

    RETURN jsonb_build_object('journal_entry_id', v_je_id);
END;
$$;

-- ============================================================================
-- 3. exchange_currency — add GL posting (Dr.To-Currency Acct / Cr.From-Currency Acct)
-- ============================================================================
DROP FUNCTION IF EXISTS public.exchange_currency(BIGINT, VARCHAR, VARCHAR, NUMERIC, NUMERIC, NUMERIC, UUID);
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id    BIGINT,
    p_from_currency  VARCHAR,
    p_to_currency    VARCHAR,
    p_amount_from    NUMERIC,
    p_amount_to      NUMERIC,
    p_exchange_rate  NUMERIC,
    p_user_id        UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance_before_from DECIMAL(15,2);
    v_balance_after_from  DECIMAL(15,2);
    v_balance_before_to   DECIMAL(15,2);
    v_balance_after_to    DECIMAL(15,2);
    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    SELECT balance INTO v_balance_before_from
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    INSERT INTO treasury_balances (treasury_id, currency, balance)
    VALUES (p_treasury_id, p_to_currency, 0.00)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance INTO v_balance_before_to
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := 'تحويل عملة من ' || p_from_currency || ' إلى ' || p_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE p_from_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE p_to_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    UPDATE treasury_balances
    SET balance = v_balance_after_from
    WHERE treasury_id = p_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to
    WHERE treasury_id = p_treasury_id AND currency = p_to_currency;

    v_je_id := public.post_journal_entry(
        'currency_exchange',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'currency', p_to_currency, 'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'currency', p_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, balance_before, balance_after, description, created_by
    ) VALUES (
        p_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency,
        v_balance_before_from, v_balance_after_from, v_desc, p_user_id
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, balance_before, balance_after, description, created_by
    ) VALUES (
        p_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency,
        v_balance_before_to, v_balance_after_to, v_desc, p_user_id
    );

    RETURN jsonb_build_object('journal_entry_id', v_je_id);
END;
$$;

-- ============================================================================
-- 4. exchange_bank_currency — add GL posting
-- ============================================================================
DROP FUNCTION IF EXISTS public.exchange_bank_currency(INTEGER, INTEGER, NUMERIC, NUMERIC, NUMERIC);
CREATE OR REPLACE FUNCTION public.exchange_bank_currency(
    p_from_account_id INTEGER,
    p_to_account_id   INTEGER,
    p_amount_from     NUMERIC,
    p_amount_to       NUMERIC,
    p_exchange_rate   NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance_before_from NUMERIC(18,2);
    v_balance_after_from  NUMERIC(18,2);
    v_balance_before_to   NUMERIC(18,2);
    v_balance_after_to    NUMERIC(18,2);
    v_from_currency       TEXT;
    v_to_currency         TEXT;
    v_user_id             UUID := auth.uid();
    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس الحساب';
    END IF;

    SELECT balance, currency INTO v_balance_before_from, v_from_currency
    FROM bank_accounts
    WHERE id = p_from_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'حساب المصدر غير موجود';
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في حساب المصدر (المتوفر: %)', v_balance_before_from;
    END IF;

    SELECT balance, currency INTO v_balance_before_to, v_to_currency
    FROM bank_accounts
    WHERE id = p_to_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب الهدف غير موجود';
    END IF;

    IF v_from_currency = v_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل بين حسابات بنفس العملة (يجب أن تكون العملات مختلفة)';
    END IF;

    v_company_id := (SELECT company_id FROM bank_accounts WHERE id = p_from_account_id);

    v_desc := 'تحويل عملة بنكي من ' || v_from_currency || ' إلى ' || v_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account('11201', v_company_id);
    v_to_acct   := public.resolve_gl_account('11201', v_company_id);

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to   := v_balance_before_to + p_amount_to;

    UPDATE bank_accounts
    SET balance = v_balance_after_from, updated_at = now()
    WHERE id = p_from_account_id;

    UPDATE bank_accounts
    SET balance = v_balance_after_to, updated_at = now()
    WHERE id = p_to_account_id;

    v_je_id := public.post_journal_entry(
        'bank_currency_exchange',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
        )
    );

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after, description, created_by
    ) VALUES (
        p_from_account_id, 'currency_exchange_out', p_amount_from,
        v_balance_before_from, v_balance_after_from, v_desc, v_user_id
    );

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after, description, created_by
    ) VALUES (
        p_to_account_id, 'currency_exchange_in', p_amount_to,
        v_balance_before_to, v_balance_after_to, v_desc, v_user_id
    );

    RETURN jsonb_build_object('journal_entry_id', v_je_id);
END;
$$;

-- ============================================================================
-- 5. update_bank_account_transaction — add GL reversal + recreation
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_bank_account_transaction(
    p_transaction_id INTEGER,
    p_new_amount     NUMERIC,
    p_new_description TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tx            RECORD;
    v_balance_diff  NUMERIC;
    v_new_balance   NUMERIC;
    v_company_id    UUID;
    v_bank_acct     BIGINT;
    v_old_je_id     BIGINT;
    v_je_id         BIGINT;
    v_desc          TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
    END IF;

    IF p_new_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT id, bank_account_id, type, amount, balance_before, balance_after,
           journal_entry_id, description
    INTO v_tx
    FROM public.bank_account_transactions
    WHERE id = p_transaction_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    v_balance_diff := p_new_amount - v_tx.amount;

    IF v_tx.type = 'deposit' THEN
        v_new_balance := v_tx.balance_after + v_balance_diff;
    ELSE
        v_new_balance := v_tx.balance_after - v_balance_diff;
    END IF;

    IF v_new_balance < 0 THEN
        RAISE EXCEPTION 'الرصيد لا يمكن أن يصبح سالباً (المتوفر: %)', v_tx.balance_after;
    END IF;

    UPDATE public.bank_accounts
    SET balance = v_new_balance
    WHERE id = v_tx.bank_account_id;

    UPDATE public.bank_account_transactions
    SET amount = p_new_amount,
        balance_after = v_new_balance,
        description = COALESCE(p_new_description, description)
    WHERE id = p_transaction_id;

    IF v_tx.type = 'deposit' THEN
        UPDATE public.bank_account_transactions
        SET balance_before = balance_before + v_balance_diff,
            balance_after  = balance_after + v_balance_diff
        WHERE bank_account_id = v_tx.bank_account_id
          AND id > p_transaction_id;
    ELSE
        UPDATE public.bank_account_transactions
        SET balance_before = balance_before - v_balance_diff,
            balance_after  = balance_after - v_balance_diff
        WHERE bank_account_id = v_tx.bank_account_id
          AND id > p_transaction_id;
    END IF;

    IF v_tx.journal_entry_id IS NOT NULL THEN
        v_company_id := (SELECT company_id FROM bank_accounts WHERE id = v_tx.bank_account_id);
        v_bank_acct  := public.resolve_gl_account('11201', v_company_id);
        v_desc       := COALESCE(p_new_description, v_tx.description);

        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_tx.journal_entry_id;
        DELETE FROM public.journal_entries WHERE id = v_tx.journal_entry_id;

        IF v_tx.type = 'deposit' THEN
            v_je_id := public.post_journal_entry(
                'bank_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_bank_acct, 'debit', p_new_amount, 'credit', 0, 'currency', 'EGP', 'description', v_desc),
                    jsonb_build_object('account_id', public.resolve_gl_account('3000', v_company_id), 'debit', 0, 'credit', p_new_amount, 'currency', 'EGP', 'description', v_desc)
                )
            );
        ELSE
            v_je_id := public.post_journal_entry(
                'bank_withdraw', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', public.resolve_gl_account('51101', v_company_id), 'debit', p_new_amount, 'credit', 0, 'currency', 'EGP', 'description', v_desc),
                    jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_new_amount, 'currency', 'EGP', 'description', v_desc)
                )
            );
        END IF;

        UPDATE public.bank_account_transactions
        SET journal_entry_id = v_je_id
        WHERE id = p_transaction_id;
    END IF;

    RETURN json_build_object('id', v_tx.bank_account_id, 'balance', v_new_balance);
END;
$$;

-- ============================================================================
-- 6. delete_bank_account_transaction — add GL reversal
-- ============================================================================
CREATE OR REPLACE FUNCTION public.delete_bank_account_transaction(
    p_transaction_id INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tx            RECORD;
    v_balance_diff  NUMERIC;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
    END IF;

    SELECT id, bank_account_id, type, amount, balance_before, balance_after,
           entity_type, entity_id, counterparty_name, description, journal_entry_id
    INTO v_tx
    FROM public.bank_account_transactions
    WHERE id = p_transaction_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.type = 'deposit' THEN
        v_balance_diff := -v_tx.amount;
    ELSE
        v_balance_diff := v_tx.amount;
    END IF;

    DECLARE
        v_current_balance NUMERIC;
    BEGIN
        SELECT balance INTO v_current_balance FROM public.bank_accounts WHERE id = v_tx.bank_account_id;
        IF v_current_balance + v_balance_diff < 0 THEN
            RAISE EXCEPTION 'لا يمكن حذف هذه الحركة لأن الرصيد سينخفض عن الصفر';
        END IF;
    END;

    IF v_tx.entity_type IS NOT NULL AND v_tx.entity_id IS NOT NULL THEN
        IF v_tx.entity_type = 'customer' THEN
            UPDATE public.customers
            SET balance = CASE
                WHEN v_tx.type = 'deposit' THEN balance + v_tx.amount
                ELSE balance - v_tx.amount
            END
            WHERE id = v_tx.entity_id::INTEGER;
        ELSIF v_tx.entity_type = 'supplier' THEN
            UPDATE public.suppliers
            SET outstanding_balance = CASE
                WHEN v_tx.type = 'deposit' THEN outstanding_balance - v_tx.amount
                ELSE outstanding_balance + v_tx.amount
            END
            WHERE id = v_tx.entity_id::UUID;
        ELSIF v_tx.entity_type = 'clearing_agent' THEN
            UPDATE public.clearing_agents
            SET manual_adjustment = CASE
                WHEN v_tx.type = 'deposit' THEN manual_adjustment - v_tx.amount
                ELSE manual_adjustment + v_tx.amount
            END,
            balance = CASE
                WHEN v_tx.type = 'deposit' THEN balance - v_tx.amount
                ELSE balance + v_tx.amount
            END
            WHERE id = v_tx.entity_id::INTEGER;
        ELSIF v_tx.entity_type = 'shipping_company' THEN
            UPDATE public.shipping_companies
            SET manual_adjustment = CASE
                WHEN v_tx.type = 'deposit' THEN manual_adjustment - v_tx.amount
                ELSE manual_adjustment + v_tx.amount
            END,
            balance = CASE
                WHEN v_tx.type = 'deposit' THEN balance - v_tx.amount
                ELSE balance + v_tx.amount
            END
            WHERE id = v_tx.entity_id::INTEGER;
        END IF;

        DELETE FROM public.ledger_entries
        WHERE id = (
            SELECT id FROM public.ledger_entries
            WHERE entity_type = v_tx.entity_type
              AND entity_id = v_tx.entity_id
              AND reference_type = 'bank_transfer'
              AND amount = v_tx.amount
              AND (
                (v_tx.type = 'deposit'   AND entry_type = 'credit')
                OR
                (v_tx.type = 'withdraw' AND entry_type = 'debit')
              )
            LIMIT 1
        );
    END IF;

    IF v_tx.journal_entry_id IS NOT NULL THEN
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_tx.journal_entry_id;
        DELETE FROM public.journal_entries WHERE id = v_tx.journal_entry_id;
    END IF;

    UPDATE public.bank_accounts
    SET balance = balance + v_balance_diff
    WHERE id = v_tx.bank_account_id;

    DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

    IF v_tx.type = 'deposit' THEN
        UPDATE public.bank_account_transactions
        SET balance_before = balance_before - v_tx.amount,
            balance_after  = balance_after - v_tx.amount
        WHERE bank_account_id = v_tx.bank_account_id
          AND id > p_transaction_id;
    ELSE
        UPDATE public.bank_account_transactions
        SET balance_before = balance_before + v_tx.amount,
            balance_after  = balance_after + v_tx.amount
        WHERE bank_account_id = v_tx.bank_account_id
          AND id > p_transaction_id;
    END IF;

    RETURN json_build_object(
        'id', v_tx.bank_account_id,
        'balance', (SELECT balance FROM public.bank_accounts WHERE id = v_tx.bank_account_id)
    );
END;
$$;
