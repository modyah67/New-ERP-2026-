-- ============================================================================
-- 040c_fix_existing_broken_transactions.sql
--
-- Fixes treasury_transactions and bank_account_transactions that were created
-- during the error period (before document types existed) where the Dart
-- fallback created transactions without journal_entry_id or source_type.
--
-- Creates proper journal entries for these orphaned transactions and links them.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Fix treasury_transactions without journal_entry_id (non-transfer, non-expense)
-- ============================================================================

-- For treasury 'deposit' transactions without journal_entry_id:
-- These are opening balance deposits that were created by the Dart fallback
DO $$
DECLARE
    v_tx RECORD;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_equity_acct BIGINT;
    v_je_id BIGINT;
    v_entry_number TEXT;
    v_desc TEXT;
    v_treasury_name TEXT;
BEGIN
    FOR v_tx IN
        SELECT tt.id, tt.treasury_id, tt.currency, tt.amount,
               tt.balance_before, tt.balance_after, tt.created_by, tt.created_at
        FROM treasury_transactions tt
        WHERE tt.journal_entry_id IS NULL
          AND tt.type = 'deposit'
    LOOP
        -- Resolve company
        SELECT t.company_id INTO v_company_id
        FROM treasuries t WHERE t.id = v_tx.treasury_id;
        IF v_company_id IS NULL THEN CONTINUE; END IF;

        -- Resolve treasury name
        SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_tx.treasury_id;
        v_desc := 'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية');

        -- Resolve GL accounts
        v_treasury_acct := public.resolve_gl_account(
            CASE v_tx.currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        );
        v_equity_acct := public.resolve_gl_account('3000', v_company_id);

        -- Create journal entry
        v_je_id := public.post_journal_entry(
            'opening_balance',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            COALESCE(v_tx.created_by, auth.uid()),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', v_tx.amount, 'credit', 0, 'currency', v_tx.currency, 'description', v_desc),
                jsonb_build_object('account_id', v_equity_acct, 'debit', 0, 'credit', v_tx.amount, 'currency', v_tx.currency, 'description', v_desc)
            )
        );

        SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

        -- Link journal entry to the transaction
        UPDATE treasury_transactions
        SET journal_entry_id = v_je_id,
            source_type = 'opening_balance',
            description = COALESCE(NULLIF(description, ''), v_desc)
        WHERE id = v_tx.id;

        RAISE NOTICE 'Fixed treasury deposit tx %: linked to JE % (%)', v_tx.id, v_je_id, v_entry_number;
    END LOOP;
END;
$$;

-- For treasury 'withdrawal' transactions without journal_entry_id:
DO $$
DECLARE
    v_tx RECORD;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_equity_acct BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_treasury_name TEXT;
BEGIN
    FOR v_tx IN
        SELECT tt.id, tt.treasury_id, tt.currency, tt.amount,
               tt.balance_before, tt.balance_after, tt.created_by
        FROM treasury_transactions tt
        WHERE tt.journal_entry_id IS NULL
          AND tt.type = 'withdrawal'
    LOOP
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = v_tx.treasury_id;
        IF v_company_id IS NULL THEN CONTINUE; END IF;

        SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_tx.treasury_id;
        v_desc := 'سحب من ' || COALESCE(v_treasury_name, 'الخزينة الرئيسية');

        v_treasury_acct := public.resolve_gl_account(
            CASE v_tx.currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        );
        v_equity_acct := public.resolve_gl_account('3000', v_company_id);

        v_je_id := public.post_journal_entry(
            'opening_balance',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            COALESCE(v_tx.created_by, auth.uid()),
            jsonb_build_array(
                jsonb_build_object('account_id', v_equity_acct, 'debit', v_tx.amount, 'credit', 0, 'currency', v_tx.currency, 'description', v_desc),
                jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', v_tx.amount, 'currency', v_tx.currency, 'description', v_desc)
            )
        );

        UPDATE treasury_transactions
        SET journal_entry_id = v_je_id,
            source_type = 'opening_balance',
            description = COALESCE(NULLIF(description, ''), v_desc)
        WHERE id = v_tx.id;

        RAISE NOTICE 'Fixed treasury withdrawal tx %: linked to JE %', v_tx.id, v_je_id;
    END LOOP;
END;
$$;

-- For treasury 'expense' transactions without journal_entry_id:
DO $$
DECLARE
    v_tx RECORD;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_expense_acct BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
BEGIN
    FOR v_tx IN
        SELECT tt.id, tt.treasury_id, tt.currency, tt.amount,
               tt.description, tt.created_by
        FROM treasury_transactions tt
        WHERE tt.journal_entry_id IS NULL
          AND tt.type = 'expense'
    LOOP
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = v_tx.treasury_id;
        IF v_company_id IS NULL THEN CONTINUE; END IF;

        v_desc := COALESCE(NULLIF(v_tx.description, ''), 'مصروف خزينة');

        v_treasury_acct := public.resolve_gl_account(
            CASE v_tx.currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        );
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);

        v_je_id := public.post_journal_entry(
            'expense_payment',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            COALESCE(v_tx.created_by, auth.uid()),
            jsonb_build_array(
                jsonb_build_object('account_id', v_expense_acct, 'debit', v_tx.amount, 'credit', 0, 'currency', v_tx.currency, 'description', v_desc),
                jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', v_tx.amount, 'currency', v_tx.currency, 'description', v_desc)
            )
        );

        UPDATE treasury_transactions
        SET journal_entry_id = v_je_id
        WHERE id = v_tx.id;

        RAISE NOTICE 'Fixed treasury expense tx %: linked to JE %', v_tx.id, v_je_id;
    END LOOP;
END;
$$;

-- ============================================================================
-- 2. Fix bank_account_transactions without journal_entry_id
-- ============================================================================

DO $$
DECLARE
    v_tx RECORD;
    v_company_id UUID;
    v_bank_acct BIGINT;
    v_other_acct BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_currency TEXT;
BEGIN
    FOR v_tx IN
        SELECT bt.id, bt.bank_account_id, bt.type, bt.amount,
               bt.description, bt.created_by, ba.currency, ba.company_id
        FROM bank_account_transactions bt
        JOIN bank_accounts ba ON ba.id = bt.bank_account_id
        WHERE bt.journal_entry_id IS NULL
    LOOP
        v_company_id := v_tx.company_id;
        IF v_company_id IS NULL THEN CONTINUE; END IF;

        v_currency := v_tx.currency;
        v_bank_acct := public.resolve_gl_account('11201', v_company_id);

        IF v_tx.type = 'deposit' THEN
            v_desc := COALESCE(NULLIF(v_tx.description, ''), 'إيداع بنكي');
            v_other_acct := public.resolve_gl_account('41101', v_company_id);
            v_je_id := public.post_journal_entry(
                'bank_deposit', v_desc, CURRENT_DATE, v_company_id,
                COALESCE(v_tx.created_by, auth.uid()),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_bank_acct, 'debit', v_tx.amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_other_acct, 'debit', 0, 'credit', v_tx.amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        ELSE
            v_desc := COALESCE(NULLIF(v_tx.description, ''), 'سحب بنكي');
            v_other_acct := public.resolve_gl_account('51101', v_company_id);
            v_je_id := public.post_journal_entry(
                'bank_withdraw', v_desc, CURRENT_DATE, v_company_id,
                COALESCE(v_tx.created_by, auth.uid()),
                jsonb_build_array(
                    jsonb_build_object('account_id', v_other_acct, 'debit', v_tx.amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', v_tx.amount, 'currency', v_currency, 'description', v_desc)
                )
            );
        END IF;

        UPDATE bank_account_transactions
        SET journal_entry_id = v_je_id,
            source_type = COALESCE(source_type, 'opening_balance')
        WHERE id = v_tx.id;

        RAISE NOTICE 'Fixed bank tx % (%): linked to JE %', v_tx.id, v_tx.type, v_je_id;
    END LOOP;
END;
$$;

COMMIT;
