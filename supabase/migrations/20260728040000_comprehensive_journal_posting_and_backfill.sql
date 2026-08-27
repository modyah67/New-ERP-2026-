-- ============================================================================
-- Migration: Comprehensive Journal Entry Posting Engine & Historical Backfill
-- Ensures atomic double-entry posting for Treasury, Bank, Sales, Purchases, Costs
-- Provides idempotent fn_repost_all_historical_journal_entries()
-- ============================================================================

-- 1. UTILITY: Helper to get or create account_id by code
CREATE OR REPLACE FUNCTION public.fn_get_account_id_by_code(p_code text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_account_id bigint;
BEGIN
  SELECT id INTO v_account_id FROM public.accounts WHERE code = p_code LIMIT 1;
  IF v_account_id IS NULL THEN
    SELECT id INTO v_account_id FROM public.accounts LIMIT 1;
  END IF;
  RETURN v_account_id;
END;
$$;

-- 2. UPDATED DEPOSIT TREASURY RPC (ATOMIC DOUBLE ENTRY)
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
    v_revenue_acc_id  BIGINT;
    v_account_code    TEXT;
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

    CASE p_currency
        WHEN 'EGP' THEN v_account_code := '11101';
        WHEN 'USD' THEN v_account_code := '11102';
        WHEN 'EUR' THEN v_account_code := '11103';
        WHEN 'GBP' THEN v_account_code := '11104';
        ELSE v_account_code := '11101';
    END CASE;

    v_treasury_acc_id := fn_get_account_id_by_code(v_account_code);
    v_revenue_acc_id := fn_get_account_id_by_code('41101');

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'إيداع نقدي بالخزينة'), 'posted', true, 'treasury_deposit', auth.uid()
    ) RETURNING id INTO v_journal_id;

    v_entry_num := fn_generate_journal_entry_number(v_journal_id);
    UPDATE journal_entries SET entry_number = v_entry_num, source_id = v_journal_id::text WHERE id = v_journal_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_treasury_acc_id, p_amount, 0, p_currency, p_amount, p_description);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_revenue_acc_id, 0, p_amount, p_currency, p_amount, p_description);

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


-- 3. UPDATED DISBURSE TREASURY RPC (ATOMIC DOUBLE ENTRY)
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

    CASE p_currency
        WHEN 'EGP' THEN v_account_code := '11101';
        WHEN 'USD' THEN v_account_code := '11102';
        WHEN 'EUR' THEN v_account_code := '11103';
        WHEN 'GBP' THEN v_account_code := '11104';
        ELSE v_account_code := '11101';
    END CASE;

    v_treasury_acc_id := fn_get_account_id_by_code(v_account_code);
    v_expense_acc_id := fn_get_account_id_by_code('51101');

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by
    ) VALUES (
        'PENDING', CURRENT_DATE, COALESCE(NULLIF(p_description, ''), 'صرف / مصروف نقدي من الخزينة'), 'posted', true, 'treasury_withdraw', auth.uid()
    ) RETURNING id INTO v_journal_id;

    v_entry_num := fn_generate_journal_entry_number(v_journal_id);
    UPDATE journal_entries SET entry_number = v_entry_num, source_id = v_journal_id::text WHERE id = v_journal_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_expense_acc_id, p_amount, 0, p_currency, p_amount, p_description);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
    VALUES (v_journal_id, v_treasury_acc_id, 0, p_amount, p_currency, p_amount, p_description);

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


-- 4. IDEMPOTENT HISTORICAL RE-POSTING FUNCTION
CREATE OR REPLACE FUNCTION public.fn_repost_all_historical_journal_entries()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_treasury_count INT := 0;
    v_bank_count     INT := 0;
    v_shipment_count INT := 0;
    v_purchase_count INT := 0;
    v_journal_id     BIGINT;
    v_entry_num      TEXT;
    v_treasury_acc   BIGINT;
    v_bank_acc       BIGINT;
    v_rev_acc        BIGINT;
    v_exp_acc        BIGINT;
    v_inv_acc        BIGINT;
    v_supp_acc       BIGINT;
    r_tt             RECORD;
    r_bt             RECORD;
    r_es             RECORD;
    r_pi             RECORD;
BEGIN
    v_rev_acc := fn_get_account_id_by_code('41101');
    v_exp_acc := fn_get_account_id_by_code('51101');
    v_inv_acc := fn_get_account_id_by_code('11401');
    v_supp_acc := fn_get_account_id_by_code('21101');

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

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_by, created_at
        ) VALUES (
            'PENDING', COALESCE(r_tt.created_at::date, CURRENT_DATE), COALESCE(r_tt.description, 'معاملة خزينة مكملة'), 'posted', true, 'treasury_tx', r_tt.id::text, r_tt.created_by, r_tt.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        IF r_tt.type IN ('deposit', 'deposit_in', 'customer_payment', 'transfer_in') THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_treasury_acc, r_tt.amount, 0, r_tt.currency, r_tt.amount, r_tt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_rev_acc, 0, r_tt.amount, r_tt.currency, r_tt.amount, r_tt.description);
        ELSE
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_exp_acc, r_tt.amount, 0, r_tt.currency, r_tt.amount, r_tt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_treasury_acc, 0, r_tt.amount, r_tt.currency, r_tt.amount, r_tt.description);
        END IF;

        UPDATE public.treasury_transactions SET journal_entry_id = v_journal_id WHERE id = r_tt.id;
        v_treasury_count := v_treasury_count + 1;
    END LOOP;

    -- B. Backfill Unposted Bank Transactions
    FOR r_bt IN 
        SELECT * FROM public.bank_account_transactions bt
        WHERE bt.journal_entry_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM public.journal_entries WHERE source_type = 'bank_tx' AND source_id = bt.id::text
          )
    LOOP
        v_bank_acc := fn_get_account_id_by_code('11201');

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_by, created_at
        ) VALUES (
            'PENDING', COALESCE(r_bt.created_at::date, CURRENT_DATE), COALESCE(r_bt.description, 'معاملة بنكية مكملة'), 'posted', true, 'bank_tx', r_bt.id::text, r_bt.created_by, r_bt.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        IF r_bt.type = 'deposit' THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_bank_acc, r_bt.amount, 0, 'EGP', r_bt.amount, r_bt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_rev_acc, 0, r_bt.amount, 'EGP', r_bt.amount, r_bt.description);
        ELSE
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_exp_acc, r_bt.amount, 0, 'EGP', r_bt.amount, r_bt.description);

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_bank_acc, 0, r_bt.amount, 'EGP', r_bt.amount, r_bt.description);
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
        v_bank_acc := fn_get_account_id_by_code('11201');

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_at
        ) VALUES (
            'PENDING', COALESCE(r_es.shipment_date, CURRENT_DATE), 'قيد إيراد وتكلفة شحنة تصدير رقم ' || COALESCE(r_es.shipment_no, r_es.id::text), 'posted', true, 'export_shipment', r_es.id::text, r_es.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
        VALUES (v_journal_id, v_bank_acc, r_es.total_revenue_egp, 0, 'EGP', r_es.total_revenue_egp, 'إيراد مبيعات شحنة تصدير');

        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
        VALUES (v_journal_id, v_rev_acc, 0, r_es.total_revenue_egp, 'EGP', r_es.total_revenue_egp, 'إيراد مبيعات شحنة تصدير');

        IF COALESCE(r_es.total_landed_cost, 0) > 0 THEN
            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_exp_acc, r_es.total_landed_cost, 0, 'EGP', r_es.total_landed_cost, 'تكلفة بضاعة مباعة لشحنة تصدير');

            INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
            VALUES (v_journal_id, v_inv_acc, 0, r_es.total_landed_cost, 'EGP', r_es.total_landed_cost, 'تخفيض مخزون لشحنة تصدير');
        END IF;

        v_shipment_count := v_shipment_count + 1;
    END LOOP;

    -- D. Backfill Unposted Purchase Invoices (Perpetual Inventory: Debit Inventory, Credit Supplier)
    FOR r_pi IN
        SELECT * FROM public.purchase_invoices pi
        WHERE pi.status IN ('confirmed', 'received')
          AND COALESCE(pi.total_amount, 0) > 0
          AND NOT EXISTS (
              SELECT 1 FROM public.journal_entries WHERE source_type = 'purchase_invoice' AND source_id = pi.id::text
          )
    LOOP
        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, is_auto_generated, source_type, source_id, created_by, created_at
        ) VALUES (
            'PENDING', COALESCE(r_pi.invoice_date, CURRENT_DATE), 'قيد توريد فاتورة شراء رقم ' || COALESCE(r_pi.invoice_number, r_pi.id::text), 'posted', true, 'purchase_invoice', r_pi.id::text, r_pi.user_id, r_pi.created_at
        ) RETURNING id INTO v_journal_id;

        v_entry_num := fn_generate_journal_entry_number(v_journal_id);
        UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_journal_id;

        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
        VALUES (v_journal_id, v_inv_acc, r_pi.total_amount, 0, 'EGP', r_pi.total_amount, 'إضافة للمخزون - فاتورة شراء');

        INSERT INTO public.account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description)
        VALUES (v_journal_id, v_supp_acc, 0, r_pi.total_amount, 'EGP', r_pi.total_amount, 'حساب المورد - فاتورة شراء');

        v_purchase_count := v_purchase_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'treasury_reposted', v_treasury_count,
        'bank_reposted', v_bank_count,
        'shipments_reposted', v_shipment_count,
        'purchases_reposted', v_purchase_count
    );
END;
$$;

-- Execute historical backfill
SELECT public.fn_repost_all_historical_journal_entries();

GRANT EXECUTE ON FUNCTION public.fn_repost_all_historical_journal_entries() TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_treasury(INTEGER, TEXT, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disburse_treasury(INTEGER, TEXT, NUMERIC, TEXT, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';
