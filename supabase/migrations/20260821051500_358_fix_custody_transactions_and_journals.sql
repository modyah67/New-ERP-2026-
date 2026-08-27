-- Migration 358: Fix Custody Transactions and Journal Entries
-- Resolves missing journal entries and receiving-side transactions for custody operations.
-- Replaces single-record insert with dual-record inserts (outflow/inflow) and fixes journal entry document prefixes.

BEGIN;

-- 1. disburse_custody
DROP FUNCTION IF EXISTS public.disburse_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.disburse_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.disburse_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_to_name      TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف في الخزينة المصدرة';
    END IF;

    -- IAS 21 Outbound from Source Treasury
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    -- Update Source Treasury
    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    -- Update/Upsert Destination Treasury
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    -- IAS 21 Inbound to Destination Treasury
    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;
    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف عهدة إلى ' || COALESCE(v_to_name, 'موظف'));

    -- GL Posting
    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_disbursement', v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام عهدة)', 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (صرف عهدة)', 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    -- Transaction Record (Sender)
    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_from_treasury_id, 'disbursement_out', p_amount, p_currency, v_desc,
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    ) RETURNING id INTO v_tx_id;

    -- Transaction Record (Receiver)
    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_to_treasury_id, 'disbursement', p_amount, p_currency, v_desc,
        v_to_balance, v_to_balance + p_amount,
        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    );

    RETURN v_tx_id;
END;
$function$;

-- 2. transfer_custody
DROP FUNCTION IF EXISTS public.transfer_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.transfer_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.transfer_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_from_name    TEXT;
    v_to_name      TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف للتحويل';
    END IF;

    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    SELECT name INTO v_from_name FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;
    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل عهدة من ' || COALESCE(v_from_name, '') || ' إلى ' || COALESCE(v_to_name, ''));

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_transfer', v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام تحويل)', 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال تحويل)', 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_from_treasury_id, 'transfer_out', p_amount, p_currency, v_desc,
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_to_treasury_id, 'transfer_in', p_amount, p_currency, v_desc,
        v_to_balance, v_to_balance + p_amount,
        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    );

    RETURN v_tx_id;
END;
$function$;

-- 3. return_custody
DROP FUNCTION IF EXISTS public.return_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.return_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.return_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_from_name    TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف لرد العهدة';
    END IF;

    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    SELECT name INTO v_from_name FROM treasuries WHERE id = p_from_treasury_id;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إرجاع عهدة من ' || COALESCE(v_from_name, 'موظف'));

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'return_custody', v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام مرتجع عهدة)', 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرجاع عهدة)', 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_from_treasury_id, 'return_out', p_amount, p_currency, v_desc,
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_to_treasury_id, 'return_in', p_amount, p_currency, v_desc,
        v_to_balance, v_to_balance + p_amount,
        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    );

    RETURN v_tx_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.disburse_custody(integer, integer, text, numeric, text, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.transfer_custody(integer, integer, text, numeric, text, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.return_custody(integer, integer, text, numeric, text, text) TO authenticated, anon, service_role;


-- 4. Auto-repair Historical Transactions that were inserted since migration 356
DO $$
DECLARE
    rec RECORD;
    v_to_treasury_id BIGINT;
    v_je_id BIGINT;
BEGIN
    -- Repair custody_disbursement
    FOR rec IN 
        SELECT id, treasury_id, amount, currency, description, reference_id, created_by, journal_entry_id, notes, created_at 
        FROM treasury_transactions 
        WHERE type = 'custody_disbursement'
    LOOP
        v_to_treasury_id := NULLIF(rec.reference_id, '')::BIGINT;
        IF v_to_treasury_id IS NOT NULL THEN
            -- Fix existing OUT record
            UPDATE treasury_transactions SET type = 'disbursement_out' WHERE id = rec.id;
            
            -- Re-parent journal entry source type if needed
            UPDATE journal_entries SET source_type = 'custody_disbursement' WHERE id = rec.journal_entry_id AND source_type = 'custody_transfer';

            -- Generate missing IN record if it does not exist
            IF NOT EXISTS (SELECT 1 FROM treasury_transactions WHERE treasury_id = v_to_treasury_id AND type = 'disbursement' AND journal_entry_id = rec.journal_entry_id) THEN
                INSERT INTO treasury_transactions (
                    treasury_id, type, amount, currency, description,
                    reference_type, reference_id, notes, created_by, journal_entry_id, created_at,
                    balance_before, balance_after
                ) VALUES (
                    v_to_treasury_id, 'disbursement', rec.amount, rec.currency, rec.description,
                    'treasury', rec.treasury_id::TEXT, rec.notes, rec.created_by, rec.journal_entry_id, rec.created_at,
                    0, 0 -- Historical balances can be 0 or extrapolated, 0 is safer for repair scripts
                );
            END IF;
        END IF;
    END LOOP;

    -- Repair custody_transfer
    FOR rec IN 
        SELECT id, treasury_id, amount, currency, description, reference_id, created_by, journal_entry_id, notes, created_at 
        FROM treasury_transactions 
        WHERE type = 'custody_transfer'
    LOOP
        v_to_treasury_id := NULLIF(rec.reference_id, '')::BIGINT;
        IF v_to_treasury_id IS NOT NULL THEN
            UPDATE treasury_transactions SET type = 'transfer_out' WHERE id = rec.id;
            IF NOT EXISTS (SELECT 1 FROM treasury_transactions WHERE treasury_id = v_to_treasury_id AND type = 'transfer_in' AND journal_entry_id = rec.journal_entry_id) THEN
                INSERT INTO treasury_transactions (
                    treasury_id, type, amount, currency, description,
                    reference_type, reference_id, notes, created_by, journal_entry_id, created_at,
                    balance_before, balance_after
                ) VALUES (
                    v_to_treasury_id, 'transfer_in', rec.amount, rec.currency, rec.description,
                    'treasury', rec.treasury_id::TEXT, rec.notes, rec.created_by, rec.journal_entry_id, rec.created_at,
                    0, 0
                );
            END IF;
        END IF;
    END LOOP;

    -- Repair custody_return
    FOR rec IN 
        SELECT id, treasury_id, amount, currency, description, reference_id, created_by, journal_entry_id, notes, created_at 
        FROM treasury_transactions 
        WHERE type = 'custody_return'
    LOOP
        v_to_treasury_id := NULLIF(rec.reference_id, '')::BIGINT;
        IF v_to_treasury_id IS NOT NULL THEN
            UPDATE treasury_transactions SET type = 'return_out' WHERE id = rec.id;
            
            -- Fix source_type in JE
            UPDATE journal_entries SET source_type = 'return_custody' WHERE id = rec.journal_entry_id AND source_type = 'custody_return';
            
            IF NOT EXISTS (SELECT 1 FROM treasury_transactions WHERE treasury_id = v_to_treasury_id AND type = 'return_in' AND journal_entry_id = rec.journal_entry_id) THEN
                INSERT INTO treasury_transactions (
                    treasury_id, type, amount, currency, description,
                    reference_type, reference_id, notes, created_by, journal_entry_id, created_at,
                    balance_before, balance_after
                ) VALUES (
                    v_to_treasury_id, 'return_in', rec.amount, rec.currency, rec.description,
                    'treasury', rec.treasury_id::TEXT, rec.notes, rec.created_by, rec.journal_entry_id, rec.created_at,
                    0, 0
                );
            END IF;
        END IF;
    END LOOP;

END;
$$;

COMMIT;
NOTIFY pgrst, 'reload schema';
