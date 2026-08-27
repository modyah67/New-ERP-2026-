-- ============================================================================
-- Migration: Complete Fix, Rollback Bad Entries & Re-post Journal Entries
-- Corrects Bank Account Join Currency Resolution (10101..10104) and Removes Duplicate Purchase Reposting
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: ROLLBACK ALL BAD AUTO-GENERATED ENTRIES & RESET SOURCE LINKS
-- ----------------------------------------------------------------------------

-- 1.1 Delete ledger entries of auto-generated journal entries
DELETE FROM public.account_ledger_entries 
WHERE journal_entry_id IN (
    SELECT id FROM public.journal_entries WHERE is_auto_generated = true
);

-- 1.2 Delete auto-generated journal entries
DELETE FROM public.journal_entries WHERE is_auto_generated = true;

-- 1.3 Reset source links in treasury and bank tables
UPDATE public.treasury_transactions SET journal_entry_id = NULL WHERE journal_entry_id IS NOT NULL;
UPDATE public.bank_account_transactions SET journal_entry_id = NULL WHERE journal_entry_id IS NOT NULL;


-- ----------------------------------------------------------------------------
-- STEP 2: ENSURE SUB-BANK ACCOUNTS (10101..10104) & SUSPENSE ACCOUNT (9000)
-- ----------------------------------------------------------------------------

-- Fix any existing invalid account types in public.accounts
UPDATE public.accounts SET account_type = 'equity' WHERE LOWER(account_type) = 'suspense';

-- Insert Bank Sub-Accounts under parent account 1010
INSERT INTO public.accounts (account_code, name, account_name, account_type, parent_id)
SELECT '10101', 'Bank - EGP', 'البنك - جنيه', 'asset', (SELECT id FROM public.accounts WHERE account_code = '1010' OR code = '1010' LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '10101' OR code = '10101');

INSERT INTO public.accounts (account_code, name, account_name, account_type, parent_id)
SELECT '10102', 'Bank - USD', 'البنك - دولار', 'asset', (SELECT id FROM public.accounts WHERE account_code = '1010' OR code = '1010' LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '10102' OR code = '10102');

INSERT INTO public.accounts (account_code, name, account_name, account_type, parent_id)
SELECT '10103', 'Bank - EUR', 'البنك - يورو', 'asset', (SELECT id FROM public.accounts WHERE account_code = '1010' OR code = '1010' LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '10103' OR code = '10103');

INSERT INTO public.accounts (account_code, name, account_name, account_type, parent_id)
SELECT '10104', 'Bank - GBP', 'البنك - استرليني', 'asset', (SELECT id FROM public.accounts WHERE account_code = '1010' OR code = '1010' LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '10104' OR code = '10104');

-- Ensure Suspense Account (9000) exists with valid account_type 'equity'
INSERT INTO public.accounts (account_code, name, account_name, account_type)
SELECT '9000', 'Suspense Account', 'حركات غير مصنفة', 'equity'
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '9000' OR code = '9000');


-- Smart Account Lookup Function
CREATE OR REPLACE FUNCTION public.fn_get_account_id_by_code(p_code text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_account_id bigint;
BEGIN
  -- 1. Exact match by code or account_code
  SELECT id INTO v_account_id 
  FROM public.accounts 
  WHERE TRIM(account_code) = TRIM(p_code) OR TRIM(code) = TRIM(p_code) 
  LIMIT 1;

  -- 2. Smart fallback search by type or name
  IF v_account_id IS NULL THEN
    IF p_code LIKE '1010%' OR p_code = '1010' THEN
      SELECT id INTO v_account_id FROM public.accounts 
      WHERE account_code = '1010' OR code = '1010' OR account_type = 'bank' OR name LIKE '%بنك%' OR account_name LIKE '%بنك%'
      LIMIT 1;
    ELSIF p_code = '4000' THEN
      SELECT id INTO v_account_id FROM public.accounts 
      WHERE account_type = 'revenue' OR name LIKE '%إيراد%' OR account_name LIKE '%إيراد%' OR account_code LIKE '4%' OR code LIKE '4%'
      LIMIT 1;
    ELSIF p_code = '5000' THEN
      SELECT id INTO v_account_id FROM public.accounts 
      WHERE account_type IN ('cogs', 'expense') OR name LIKE '%تكلفة%' OR account_name LIKE '%تكلفة%' OR account_code LIKE '5%' OR code LIKE '5%'
      LIMIT 1;
    ELSIF p_code = '6000' THEN
      SELECT id INTO v_account_id FROM public.accounts 
      WHERE account_type = 'expense' OR name LIKE '%مصروف%' OR account_name LIKE '%مصروف%' OR account_code LIKE '6%' OR code LIKE '6%'
      LIMIT 1;
    ELSIF p_code = '1030' THEN
      SELECT id INTO v_account_id FROM public.accounts 
      WHERE account_type = 'asset' OR name LIKE '%مخزون%' OR account_name LIKE '%مخزون%' OR account_code LIKE '10%' OR code LIKE '10%'
      LIMIT 1;
    ELSIF p_code = '2000' THEN
      SELECT id INTO v_account_id FROM public.accounts 
      WHERE account_type = 'liability' OR name LIKE '%مورد%' OR account_name LIKE '%مورد%' OR account_code LIKE '2%' OR code LIKE '2%'
      LIMIT 1;
    END IF;
  END IF;

  -- 3. If still not found, create account automatically using standard account_type
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type)
    VALUES (
      p_code, 
      'حساب ' || p_code, 
      'حساب ' || p_code, 
      CASE 
        WHEN p_code LIKE '1%' THEN 'asset'
        WHEN p_code LIKE '2%' THEN 'liability'
        WHEN p_code LIKE '3%' THEN 'equity'
        WHEN p_code LIKE '4%' THEN 'revenue'
        WHEN p_code LIKE '5%' THEN 'expense'
        WHEN p_code LIKE '6%' THEN 'expense'
        ELSE 'equity'
      END
    )
    RETURNING id INTO v_account_id;
  END IF;

  RETURN v_account_id;
END;
$$;


-- ----------------------------------------------------------------------------
-- STEP 3: CORRECT RPCS WITH EXACT CHART OF ACCOUNTS CODES
-- ----------------------------------------------------------------------------

-- Updated deposit_treasury RPC
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id   INTEGER,
    p_currency      TEXT,
    p_amount        NUMERIC,
    p_description   TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_journal_id      BIGINT;
    v_entry_num       TEXT;
    v_treasury_acc_id BIGINT;
    v_offset_acc_id   BIGINT;
    v_account_code    TEXT;
    v_rate            NUMERIC := 1.0;
    v_amount_base     NUMERIC := 0;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    INSERT INTO treasury_balances (treasury_id, currency, balance)
    VALUES (p_treasury_id, p_currency, v_new_balance)
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance;

    -- Calculate base currency amount using currencies exchange rate
    IF p_currency != 'EGP' THEN
        SELECT COALESCE(exchange_rate, 1.0) INTO v_rate 
        FROM public.currencies 
        WHERE code = p_currency 
        ORDER BY created_at DESC LIMIT 1;
    END IF;
    v_rate := COALESCE(v_rate, 1.0);
    v_amount_base := p_amount * v_rate;

    CASE p_currency
        WHEN 'EGP' THEN v_account_code := '11101';
        WHEN 'USD' THEN v_account_code := '11102';
        WHEN 'EUR' THEN v_account_code := '11103';
        WHEN 'GBP' THEN v_account_code := '11104';
        ELSE v_account_code := '11101';
    END CASE;

    v_treasury_acc_id := fn_get_account_id_by_code(v_account_code);
    v_offset_acc_id := fn_get_account_id_by_code('9000');

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'إيداع نقدي بالخزينة'), 'posted', true, 'treasury_deposit', auth.uid()
    ) RETURNING id INTO v_journal_id;

    v_entry_num := fn_generate_journal_entry_number(v_journal_id);
    UPDATE journal_entries SET entry_number = v_entry_num, source_id = v_journal_id::text WHERE id = v_journal_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_treasury_acc_id, p_amount, 0, p_currency, v_amount_base, p_description);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_offset_acc_id, 0, p_amount, p_currency, v_amount_base, p_description);

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after, description, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount, COALESCE(v_current_balance, 0), v_new_balance, p_description, v_journal_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_journal_id,
        'entry_number', v_entry_num,
        'balance_after', v_new_balance
    );
END;
$$;


-- Updated disburse_treasury RPC
CREATE OR REPLACE FUNCTION public.disburse_treasury(
    p_treasury_id   INTEGER,
    p_currency      TEXT,
    p_amount        NUMERIC,
    p_description   TEXT DEFAULT '',
    p_category_id   INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_journal_id      BIGINT;
    v_entry_num       TEXT;
    v_treasury_acc_id BIGINT;
    v_expense_acc_id  BIGINT;
    v_account_code    TEXT;
    v_rate            NUMERIC := 1.0;
    v_amount_base     NUMERIC := 0;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة. المتوفر: % %', v_current_balance, p_currency;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE treasury_balances
    SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Calculate base currency amount using currencies exchange rate
    IF p_currency != 'EGP' THEN
        SELECT COALESCE(exchange_rate, 1.0) INTO v_rate 
        FROM public.currencies 
        WHERE code = p_currency 
        ORDER BY created_at DESC LIMIT 1;
    END IF;
    v_rate := COALESCE(v_rate, 1.0);
    v_amount_base := p_amount * v_rate;

    CASE p_currency
        WHEN 'EGP' THEN v_account_code := '11101';
        WHEN 'USD' THEN v_account_code := '11102';
        WHEN 'EUR' THEN v_account_code := '11103';
        WHEN 'GBP' THEN v_account_code := '11104';
        ELSE v_account_code := '11101';
    END CASE;

    v_treasury_acc_id := fn_get_account_id_by_code(v_account_code);
    v_expense_acc_id := fn_get_account_id_by_code('6000');

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'صرف / مصروف نقدي من الخزينة'), 'posted', true, 'treasury_withdraw', auth.uid()
    ) RETURNING id INTO v_journal_id;

    v_entry_num := fn_generate_journal_entry_number(v_journal_id);
    UPDATE journal_entries SET entry_number = v_entry_num, source_id = v_journal_id::text WHERE id = v_journal_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_expense_acc_id, p_amount, 0, p_currency, v_amount_base, p_description);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_treasury_acc_id, 0, p_amount, p_currency, v_amount_base, p_description);

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, balance_before, balance_after, description, category_id, journal_entry_id, created_by
    ) VALUES (
        p_treasury_id, 'expense', p_currency, p_amount, v_current_balance, v_new_balance, p_description, p_category_id, v_journal_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_journal_id,
        'entry_number', v_entry_num,
        'balance_after', v_new_balance
    );
END;
$$;


-- ----------------------------------------------------------------------------
-- STEP 4 & 5: REPOST HISTORICAL DATA WITH STRICT ACCURATE CODES & BASE CURRENCY
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_repost_all_historical_journal_entries()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_treasury_count INT := 0;
    v_bank_count     INT := 0;
    v_shipment_count INT := 0;
    v_journal_id     BIGINT;
    v_entry_num      TEXT;
    v_treasury_acc   BIGINT;
    v_bank_acc       BIGINT;
    v_rev_acc        BIGINT;
    v_cogs_acc       BIGINT;
    v_exp_acc        BIGINT;
    v_inv_acc        BIGINT;
    v_supp_acc       BIGINT;
    v_suspense_acc   BIGINT;
    v_offset_acc     BIGINT;
    v_bank_code      TEXT;
    v_rate           NUMERIC := 1.0;
    v_amount_base    NUMERIC := 0;
    r_tt             RECORD;
    r_bt             RECORD;
    r_es             RECORD;
BEGIN
    v_rev_acc      := fn_get_account_id_by_code('4000'); -- Sales Revenue
    v_cogs_acc     := fn_get_account_id_by_code('5000'); -- COGS
    v_exp_acc      := fn_get_account_id_by_code('6000'); -- Expenses
    v_inv_acc      := fn_get_account_id_by_code('1030'); -- Inventory
    v_supp_acc     := fn_get_account_id_by_code('2000'); -- Suppliers
    v_suspense_acc := fn_get_account_id_by_code('9000'); -- Suspense Account

    -- A. Backfill Unposted Treasury Transactions
    FOR r_tt IN 
        SELECT * FROM public.treasury_transactions tt
        WHERE tt.journal_entry_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM public.journal_entries WHERE source_type = 'treasury_tx' AND source_id = tt.id::text
          )
    LOOP
        v_treasury_acc := fn_get_account_id_by_code(
            CASE r_tt.currency
                WHEN 'EGP' THEN '11101'
                WHEN 'USD' THEN '11102'
                WHEN 'EUR' THEN '11103'
                WHEN 'GBP' THEN '11104'
                ELSE '11101'
            END
        );

        -- Calculate amount_in_base_currency with exchange_rate lookup
        v_rate := COALESCE((to_jsonb(r_tt) ->> 'exchange_rate')::numeric, NULL);
        IF v_rate IS NULL AND r_tt.currency != 'EGP' THEN
            SELECT COALESCE(exchange_rate, 1.0) INTO v_rate 
            FROM public.currencies 
            WHERE code = r_tt.currency 
            ORDER BY created_at DESC LIMIT 1;
        END IF;
        v_rate := COALESCE(v_rate, 1.0);
        v_amount_base := r_tt.amount * v_rate;

        -- Classification Logic: Category / Customer Payment / Supplier Payment vs Suspense 9000
        IF r_tt.category_id IS NOT NULL THEN
            v_offset_acc := v_exp_acc;
        ELSIF r_tt.type IN ('customer_payment') 
           OR (to_jsonb(r_tt) ->> 'reference_type') IN ('invoice', 'export_shipment', 'customer_payment') THEN
            v_offset_acc := v_rev_acc;
        ELSIF r_tt.type IN ('supplier_payment') 
           OR (to_jsonb(r_tt) ->> 'reference_type') IN ('purchase_invoice', 'supplier_payment') THEN
            v_offset_acc := v_supp_acc;
        ELSE
            -- Uncategorized deposits/withdrawals (opening balances, etc.) map to Suspense 9000
            v_offset_acc := v_suspense_acc;
        END IF;

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_by, created_at
        ) VALUES (
            'PENDING', COALESCE(r_tt.created_at::date, CURRENT_DATE), COALESCE(r_tt.description, 'معاملة خزينة مكملة'), 'posted', true, 'treasury_tx', r_tt.id::text, COALESCE((to_jsonb(r_tt) ->> 'created_by')::uuid, NULL), r_tt.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        IF r_tt.type IN ('deposit', 'deposit_in', 'customer_payment', 'transfer_in') THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_treasury_acc, r_tt.amount, 0, r_tt.currency, v_amount_base, r_tt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_offset_acc, 0, r_tt.amount, r_tt.currency, v_amount_base, r_tt.description);
        ELSE
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_offset_acc, r_tt.amount, 0, r_tt.currency, v_amount_base, r_tt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_treasury_acc, 0, r_tt.amount, r_tt.currency, v_amount_base, r_tt.description);
        END IF;

        UPDATE public.treasury_transactions SET journal_entry_id = v_journal_id WHERE id = r_tt.id;
        v_treasury_count := v_treasury_count + 1;
    END LOOP;

    -- B. Backfill Unposted Bank Transactions (Multi-currency Bank Accounts by joining bank_accounts: 10101..10104)
    FOR r_bt IN 
        SELECT bt.*, COALESCE(ba.currency, 'EGP') AS bank_currency
        FROM public.bank_account_transactions bt
        LEFT JOIN public.bank_accounts ba ON ba.id = bt.bank_account_id
        WHERE bt.journal_entry_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM public.journal_entries WHERE source_type = 'bank_tx' AND source_id = bt.id::text
          )
    LOOP
        CASE r_bt.bank_currency
            WHEN 'EGP' THEN v_bank_code := '10101';
            WHEN 'USD' THEN v_bank_code := '10102';
            WHEN 'EUR' THEN v_bank_code := '10103';
            WHEN 'GBP' THEN v_bank_code := '10104';
            ELSE v_bank_code := '10101';
        END CASE;

        v_bank_acc := fn_get_account_id_by_code(v_bank_code);
        
        -- Calculate amount_in_base_currency with exchange_rate lookup
        v_rate := COALESCE((to_jsonb(r_bt) ->> 'exchange_rate')::numeric, NULL);
        IF v_rate IS NULL AND r_bt.bank_currency != 'EGP' THEN
            SELECT COALESCE(exchange_rate, 1.0) INTO v_rate 
            FROM public.currencies 
            WHERE code = r_bt.bank_currency 
            ORDER BY created_at DESC LIMIT 1;
        END IF;
        v_rate := COALESCE(v_rate, 1.0);
        v_amount_base := r_bt.amount * v_rate;

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_by, created_at
        ) VALUES (
            'PENDING', COALESCE(r_bt.created_at::date, CURRENT_DATE), COALESCE(r_bt.description, 'معاملة بنكية مكملة'), 'posted', true, 'bank_tx', r_bt.id::text, COALESCE((to_jsonb(r_bt) ->> 'created_by')::uuid, NULL), r_bt.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        IF r_bt.type = 'deposit' THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_bank_acc, r_bt.amount, 0, r_bt.bank_currency, v_amount_base, r_bt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_suspense_acc, 0, r_bt.amount, r_bt.bank_currency, v_amount_base, r_bt.description);
        ELSE
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_exp_acc, r_bt.amount, 0, r_bt.bank_currency, v_amount_base, r_bt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_bank_acc, 0, r_bt.amount, r_bt.bank_currency, v_amount_base, r_bt.description);
        END IF;

        UPDATE public.bank_account_transactions SET journal_entry_id = v_journal_id WHERE id = r_bt.id;
        v_bank_count := v_bank_count + 1;
    END LOOP;

    -- C. Backfill Unposted Export Shipments
    FOR r_es IN 
        SELECT * FROM public.export_shipments es
        WHERE es.status != 'cancelled'
          AND COALESCE(es.total_revenue_egp, 0) > 0
          AND NOT EXISTS (
              SELECT 1 FROM public.journal_entries WHERE source_type = 'export_shipment' AND source_id = es.id::text
          )
    LOOP
        v_bank_acc := fn_get_account_id_by_code('10101'); -- Default EGP Bank Account

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_at
        ) VALUES (
            'PENDING', COALESCE(r_es.shipment_date, CURRENT_DATE), 'قيد إيراد وتكلفة شحنة تصدير رقم ' || COALESCE(r_es.shipment_no, r_es.id::text), 'posted', true, 'export_shipment', r_es.id::text, r_es.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        -- Debit Bank/Receivable (10101), Credit Sales Revenue (4000)
        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
        VALUES (v_journal_id, v_bank_acc, r_es.total_revenue_egp, 0, 'EGP', r_es.total_revenue_egp, 'إيراد مبيعات شحنة تصدير');

        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
        VALUES (v_journal_id, v_rev_acc, 0, r_es.total_revenue_egp, 'EGP', r_es.total_revenue_egp, 'إيراد مبيعات شحنة تصدير');

        -- Debit COGS (5000), Credit Inventory (1030)
        IF COALESCE(r_es.total_landed_cost, 0) > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_cogs_acc, r_es.total_landed_cost, 0, 'EGP', r_es.total_landed_cost, 'تكلفة بضاعة مباعة لشحنة تصدير');

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_inv_acc, 0, r_es.total_landed_cost, 'EGP', r_es.total_landed_cost, 'تخفيض مخزون لشحنة تصدير');
        END IF;

        v_shipment_count := v_shipment_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'treasury_reposted', v_treasury_count,
        'bank_reposted', v_bank_count,
        'shipments_reposted', v_shipment_count
    );
END;
$$;

-- Execute historical backfill
SELECT public.fn_repost_all_historical_journal_entries();

GRANT EXECUTE ON FUNCTION public.fn_repost_all_historical_journal_entries() TO authenticated;

NOTIFY pgrst, 'reload schema';
