-- ============================================================================
-- Migration 056: Fix Currency-Specific Equity Posting & Parent Account Protection
-- ============================================================================
-- ROOT CAUSE:
--   receive_payment and update_bank_account_transaction hardcode '3000' (Owner Equity)
--   for shareholder, opening_balance, and bank deposit paths.
--   Account 3000 is marked is_leaf=true despite having children 3001-3004,
--   so the existing fn_reject_non_leaf_account_posting trigger doesn't block it.
--
-- FIXES:
--   1. Create resolve_equity_account() helper to centralize currency->equity mapping
--   2. Fix receive_payment: shareholder + opening_balance use currency-specific equity
--   3. Fix update_bank_account_transaction: bank deposit uses currency-specific equity
--   4. Set account 3000 is_leaf=false so trigger blocks future direct postings
--   5. Migrate existing incorrect journal entries (3000 -> 3001/3002)
--   6. Recalculate all account balances after migration
-- ============================================================================

-- ============================================================================
-- 1. HELPER: Resolve currency-specific equity account
-- ============================================================================
CREATE OR REPLACE FUNCTION public.resolve_equity_account(
    p_currency   TEXT,
    p_company_id UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_acct BIGINT;
BEGIN
    v_acct := public.resolve_gl_account(
        CASE p_currency
            WHEN 'EGP' THEN '3001'
            WHEN 'USD' THEN '3002'
            WHEN 'EUR' THEN '3003'
            WHEN 'GBP' THEN '3004'
            ELSE '3000'  -- unknown currency fallback
        END,
        p_company_id
    );
    RETURN v_acct;
END;
$$;

-- ============================================================================
-- 2. FIX receive_payment: shareholder + opening_balance paths
-- ============================================================================
DROP FUNCTION IF EXISTS public.receive_payment(VARCHAR, NUMERIC, VARCHAR, VARCHAR, BIGINT, UUID, UUID, TEXT, TEXT, BIGINT);

CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type       VARCHAR,
    p_amount             NUMERIC,
    p_currency           VARCHAR,
    p_counterparty_type  VARCHAR   DEFAULT NULL,
    p_counterparty_id    BIGINT    DEFAULT NULL,
    p_supplier_id        UUID      DEFAULT NULL,
    p_shareholder_id     UUID      DEFAULT NULL,
    p_description        TEXT      DEFAULT NULL,
    p_notes              TEXT      DEFAULT NULL,
    p_treasury_id        BIGINT    DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_treasury_id   BIGINT;
    v_balance       NUMERIC;
    v_tx_id         BIGINT;
    v_company_id    UUID;
    v_treasury_acct BIGINT;
    v_ar_acct       BIGINT;
    v_je_id         BIGINT;
    v_desc          TEXT;
    v_source_type   TEXT;
    v_treasury_name TEXT;
    v_je_source     TEXT;
    v_credit_acct   BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_treasury_id IS NOT NULL THEN
        v_treasury_id := p_treasury_id;
    ELSE
        SELECT id INTO v_treasury_id
        FROM public.treasuries
        WHERE type = 'main' AND user_id = auth.uid()
        LIMIT 1;
        IF v_treasury_id IS NULL THEN
            SELECT id INTO v_treasury_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        END IF;
        IF v_treasury_id IS NULL THEN
            RAISE EXCEPTION 'لم يتم العثور على الخزينة الرئيسية.';
        END IF;
    END IF;

    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = v_treasury_id;

    IF p_counterparty_type IS NULL THEN
        v_source_type := 'opening_balance';
        SELECT name INTO v_treasury_name FROM public.treasuries WHERE id = v_treasury_id;
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
        );
    ELSE
        v_source_type := p_counterparty_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'استلام ' || p_receipt_type);
    END IF;

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    -- FIXED: Use currency-specific equity accounts instead of hardcoded '3000'
    IF p_counterparty_type = 'customer' THEN
        v_credit_acct := public.resolve_gl_account('1020', v_company_id);
    ELSIF p_counterparty_type = 'supplier' THEN
        v_credit_acct := public.resolve_gl_account('2000', v_company_id);
    ELSIF p_counterparty_type = 'clearing_agent' THEN
        v_credit_acct := public.resolve_gl_account('41001', v_company_id);
    ELSIF p_counterparty_type = 'shipping_company' THEN
        v_credit_acct := public.resolve_gl_account('41001', v_company_id);
    ELSIF p_counterparty_type = 'shareholder' THEN
        v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
    ELSE
        v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, source_type,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        created_by, revenue_account_id
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc, v_source_type,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        auth.uid(),
        v_credit_acct
    ) RETURNING id INTO v_tx_id;

    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := public.resolve_gl_account('1020', v_company_id);
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id = p_supplier_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := public.resolve_gl_account('2000', v_company_id);
        v_je_id := public.post_journal_entry(
            'supplier_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := public.resolve_gl_account('41001', v_company_id);
        v_je_id := public.post_journal_entry(
            'clearing_agent_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := public.resolve_gl_account('41001', v_company_id);
        v_je_id := public.post_journal_entry(
            'shipping_company_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shareholder' AND p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_shareholder_id;
        END IF;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        -- FIXED: Use currency-specific equity account instead of hardcoded '3000'
        v_ar_acct := public.resolve_equity_account(p_currency, v_company_id);
        v_je_id := public.post_journal_entry(
            'shareholder_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSE
        -- FIXED: Use currency-specific equity account instead of hardcoded '3000'
        v_je_source := 'opening_balance';
        v_je_id := public.post_journal_entry(
            v_je_source, v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', public.resolve_equity_account(p_currency, v_company_id), 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    -- Sync treasury_balances
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (v_treasury_id, p_currency, p_amount, v_treasury_acct)
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = public.treasury_balances.balance + p_amount;

    RETURN jsonb_build_object('success', true, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.receive_payment(VARCHAR, NUMERIC, VARCHAR, VARCHAR, BIGINT, UUID, UUID, TEXT, TEXT, BIGINT) TO authenticated;

-- ============================================================================
-- 3. FIX update_bank_account_transaction: bank deposit uses currency-specific equity
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
    v_currency      TEXT;
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

        -- Get currency from bank account
        SELECT currency INTO v_currency FROM bank_accounts WHERE id = v_tx.bank_account_id;

        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_tx.journal_entry_id;
        DELETE FROM public.journal_entries WHERE id = v_tx.journal_entry_id;

        IF v_tx.type = 'deposit' THEN
            -- FIXED: Use currency-specific equity account instead of hardcoded '3000'
            v_je_id := public.post_journal_entry(
                'bank_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_bank_acct, 'debit', p_new_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', public.resolve_equity_account(v_currency, v_company_id), 'debit', 0, 'credit', p_new_amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        ELSE
            v_je_id := public.post_journal_entry(
                'bank_withdraw', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
                jsonb_build_array(
                    jsonb_build_object('account_id', public.resolve_gl_account('51101', v_company_id), 'debit', p_new_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_new_amount, 'currency', v_currency, 'description', v_desc)
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
-- 4. PARENT ACCOUNT PROTECTION: Set account 3000 is_leaf=false
-- ============================================================================
-- Account 3000 has children (3001, 3002, 3003, 3004) so it must NOT be a leaf.
-- The existing fn_reject_non_leaf_account_posting trigger will then block
-- any future direct postings to 3000.
UPDATE accounts SET is_leaf = false WHERE account_code = '3000';

-- ============================================================================
-- 5. DATA MIGRATION: Fix existing incorrect journal entries posting to 3000
-- ============================================================================
-- Strategy: Delete incorrect JE lines pointing to 3000, recreate them pointing
-- to the correct currency-specific equity account. We use the journal entry's
-- currency metadata to determine the correct account.

DO $$
DECLARE
    v_je                RECORD;
    v_correct_acct      BIGINT;
    v_line              RECORD;
    v_new_lines         JSONB := '[]'::jsonb;
    v_old_debit         NUMERIC;
    v_old_credit        NUMERIC;
    v_line_currency     TEXT;
BEGIN
    -- Find all journal entries that have a line posting to account 3000
    FOR v_je IN
        SELECT DISTINCT je.id AS je_id, je.source_type, je.entry_date, je.description, je.company_id
        FROM journal_entries je
        JOIN account_ledger_entries ale ON ale.journal_entry_id = je.id
        JOIN accounts a ON a.id = ale.account_id
        WHERE a.account_code = '3000'
    LOOP
        -- For each JE, find the line that posts to 3000
        FOR v_line IN
            SELECT ale.id AS ale_id, ale.account_id, ale.debit, ale.credit, ale.currency, ale.description AS line_desc
            FROM account_ledger_entries ale
            WHERE ale.journal_entry_id = v_je.je_id
        LOOP
            SELECT a.account_code INTO v_line.account_id
            FROM accounts a WHERE a.id = v_line.account_id;

            -- If this line points to account 3000, fix it
            IF v_line.account_id = '3000' THEN
                -- Use the currency from the line (or fallback to EGP)
                v_line_currency := COALESCE(v_line.currency, 'EGP');

                -- Resolve the correct currency-specific equity account
                v_correct_acct := public.resolve_equity_account(v_line_currency, v_je.company_id);

                -- Update the account_ledger_entries to point to the correct account
                UPDATE account_ledger_entries
                SET account_id = v_correct_acct
                WHERE id = v_line.ale_id;

                RAISE NOTICE 'Fixed JE % line %: account 3000 -> % (currency %)',
                    v_je.je_id, v_line.ale_id, v_correct_acct, v_line_currency;
            END IF;
        END LOOP;

        -- Update accounts.balance: subtract from 3000, add to correct account
        -- The trg_sync_account_balance trigger handles this automatically
    END LOOP;
END;
$$;

-- ============================================================================
-- 6. RECALCULATE all account balances from ledger entries
-- ============================================================================
-- Reset all balances to 0, then recalculate from account_ledger_entries
UPDATE accounts SET balance = 0;

UPDATE accounts SET balance = sub.total
FROM (
    SELECT account_id, SUM(debit) - SUM(credit) AS total
    FROM account_ledger_entries
    GROUP BY account_id
) sub
WHERE accounts.id = sub.account_id;

-- ============================================================================
-- 7. Verify: No remaining postings to account 3000
-- ============================================================================
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM account_ledger_entries ale
    JOIN accounts a ON a.id = ale.account_id
    WHERE a.account_code = '3000';

    IF v_count > 0 THEN
        RAISE WARNING 'WARNING: % ledger entries still reference account 3000 after migration', v_count;
    ELSE
        RAISE NOTICE 'SUCCESS: No ledger entries reference account 3000';
    END IF;
END;
$$;
