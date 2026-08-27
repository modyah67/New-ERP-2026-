-- ============================================================================
-- Migration 343: Opening Balance Equity Structure & Raw Materials GL Sync
-- ============================================================================

-- 1. Create Opening Balance Equity Parent (3900) and Currency Sub-Accounts (3901-3904)
DO $$
DECLARE
    v_parent_id BIGINT;
    v_3900_id BIGINT;
BEGIN
    -- Find Root Equity Account (Code '3' or '3000' parent)
    SELECT id INTO v_parent_id FROM accounts WHERE account_code = '3' LIMIT 1;
    IF v_parent_id IS NULL THEN
        SELECT parent_id INTO v_parent_id FROM accounts WHERE account_code = '3000' LIMIT 1;
    END IF;

    -- Insert 3900 (Parent: Opening Balance Equity)
    INSERT INTO accounts (account_code, name, account_name, account_type, is_leaf, allow_posting, is_active, parent_id)
    VALUES ('3900', 'الأرصدة الافتتاحية', 'Opening Balance Equity', 'equity', false, false, true, v_parent_id)
    ON CONFLICT (account_code) DO UPDATE
    SET name = 'الأرصدة الافتتاحية', account_name = 'Opening Balance Equity', account_type = 'equity'
    RETURNING id INTO v_3900_id;

    IF v_3900_id IS NULL THEN
        SELECT id INTO v_3900_id FROM accounts WHERE account_code = '3900' LIMIT 1;
    END IF;

    -- Insert 3901 (EGP)
    INSERT INTO accounts (account_code, name, account_name, account_type, is_leaf, allow_posting, is_active, parent_id)
    VALUES ('3901', 'الأرصدة الافتتاحية - ج.م', 'Opening Balance Equity - EGP', 'equity', true, true, true, v_3900_id)
    ON CONFLICT (account_code) DO UPDATE
    SET name = 'الأرصدة الافتتاحية - ج.م', account_name = 'Opening Balance Equity - EGP', is_leaf = true, allow_posting = true;

    -- Insert 3902 (USD)
    INSERT INTO accounts (account_code, name, account_name, account_type, is_leaf, allow_posting, is_active, parent_id)
    VALUES ('3902', 'الأرصدة الافتتاحية - دولار', 'Opening Balance Equity - USD', 'equity', true, true, true, v_3900_id)
    ON CONFLICT (account_code) DO UPDATE
    SET name = 'الأرصدة الافتتاحية - دولار', account_name = 'Opening Balance Equity - USD', is_leaf = true, allow_posting = true;

    -- Insert 3903 (EUR)
    INSERT INTO accounts (account_code, name, account_name, account_type, is_leaf, allow_posting, is_active, parent_id)
    VALUES ('3903', 'الأرصدة الافتتاحية - يورو', 'Opening Balance Equity - EUR', 'equity', true, true, true, v_3900_id)
    ON CONFLICT (account_code) DO UPDATE
    SET name = 'الأرصدة الافتتاحية - يورو', account_name = 'Opening Balance Equity - EUR', is_leaf = true, allow_posting = true;

    -- Insert 3904 (GBP)
    INSERT INTO accounts (account_code, name, account_name, account_type, is_leaf, allow_posting, is_active, parent_id)
    VALUES ('3904', 'الأرصدة الافتتاحية - إسترليني', 'Opening Balance Equity - GBP', 'equity', true, true, true, v_3900_id)
    ON CONFLICT (account_code) DO UPDATE
    SET name = 'الأرصدة الافتتاحية - إسترليني', account_name = 'Opening Balance Equity - GBP', is_leaf = true, allow_posting = true;
END $$;

-- 2. Central Resolver Function: resolve_opening_balance_equity_account
CREATE OR REPLACE FUNCTION public.resolve_opening_balance_equity_account(
    p_currency TEXT,
    p_company_id UUID DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_code TEXT;
    v_acct BIGINT;
BEGIN
    v_code := CASE UPPER(COALESCE(p_currency, 'EGP'))
        WHEN 'USD' THEN '3902'
        WHEN 'EUR' THEN '3903'
        WHEN 'GBP' THEN '3904'
        ELSE '3901'
    END;

    v_acct := public.resolve_gl_account(v_code, p_company_id);

    IF v_acct IS NULL THEN
        v_acct := public.resolve_gl_account('3901', p_company_id);
    END IF;
    IF v_acct IS NULL THEN
        v_acct := public.resolve_gl_account('3900', p_company_id);
    END IF;
    IF v_acct IS NULL THEN
        v_acct := public.resolve_gl_account('3000', p_company_id);
    END IF;

    RETURN v_acct;
END;
$$;

-- 3. Update deposit_treasury (4-arguments opening balance overload & 5-arguments overload)
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id INTEGER,
    p_currency TEXT,
    p_amount NUMERIC,
    p_description TEXT DEFAULT ''::text
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
    );

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    -- Current balance
    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    -- Upsert treasury balance
    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id, updated_at)
    VALUES (p_treasury_id, p_currency, v_new_balance,
        public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        ),
        NOW()
    )
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance, updated_at = NOW();

    -- GL accounts
    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);
    v_equity_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);

    -- Journal entry: Dr.Treasury / Cr.Opening Balance Equity
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_equity_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type,
        journal_entry_id, created_by, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance',
        v_je_id, auth.uid(), v_rate, v_base_amount, v_snapshot
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object(
        'success', true,
        'treasury_tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_number,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount
    );
END;
$$;

DROP FUNCTION IF EXISTS public.deposit_treasury(integer, text, numeric, text, integer);

CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text,
    p_revenue_account_id integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_revenue_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_source_type     TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_rate := public.fn_get_exchange_rate(p_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'إيداع نقدي ' || p_currency || ' في ' || COALESCE(v_treasury_name, 'الخزينة')
    );

    SELECT COALESCE(balance, 0) INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (p_treasury_id, p_currency, v_new_balance,
        public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        )
    )
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_source_type := 'treasury_deposit';
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'إيداع نقدي ' || p_currency || ' في ' || COALESCE(v_treasury_name, 'الخزينة')
        );
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_source_type := 'opening_balance';
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
        );
        v_revenue_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        v_source_type,
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_source_type, v_je_id, auth.uid(),
        CASE WHEN p_revenue_account_id IS NOT NULL THEN p_revenue_account_id ELSE NULL END,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance
    );
END;
$$;

-- 4. Update deposit_bank_account to route opening balances to 3901-3904
DROP FUNCTION IF EXISTS public.deposit_bank_account(integer, numeric, text, text, text, text, integer, text);
DROP FUNCTION IF EXISTS public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id BIGINT,
    p_amount NUMERIC,
    p_description TEXT DEFAULT NULL,
    p_revenue_account_id BIGINT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_source_type TEXT DEFAULT 'deposit',
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_credit_acct     BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id
      INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(p_amount * v_rate, 2);

    v_new_balance := v_current_balance + p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'رصيد افتتاحي');
    ELSIF p_entity_type = 'revenue' THEN
        v_source_type := 'revenue';
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيراد');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_credit_acct := NULL;

    IF p_entity_type IS NULL OR p_entity_type = 'opening_balance' THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    ELSIF p_entity_type = 'revenue' THEN
        IF p_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب الإيرادات';
        END IF;
        v_credit_acct := p_revenue_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_credit_acct FROM customers WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_credit_acct FROM suppliers WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM shareholders WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_credit_acct FROM clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_credit_acct FROM shipping_companies WHERE id = p_entity_id::bigint;
    ELSE
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    IF v_credit_acct IS NULL THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct,  'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END,
        p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'new_balance', v_new_balance,
        'journal_entry_id', v_je_id
    );
END;
$$;

-- 5. Update sync_entity_opening_balance_gl Trigger Function
CREATE OR REPLACE FUNCTION public.sync_entity_opening_balance_gl()
RETURNS TRIGGER AS $$
DECLARE
    v_je_id BIGINT;
    v_account_id BIGINT;
    v_equity_account_id BIGINT;
    v_company_id UUID;
    v_new_balance NUMERIC;
    v_direction TEXT;
    v_currency TEXT;
    v_rate NUMERIC := 1.0;
    v_base_balance NUMERIC;
    v_desc TEXT;
    v_entity_name TEXT;
    v_source_id TEXT;
    v_entry_number TEXT;
BEGIN
    v_company_id := NEW.company_id;

    v_new_balance := COALESCE(NEW.initial_balance, 0);
    v_direction := COALESCE(NEW.initial_balance_direction, 'DEBIT');
    v_currency := COALESCE(NEW.currency, 'EGP');
    v_entity_name := COALESCE(NEW.name, '');
    v_desc := 'رصيد افتتاحي - ' || v_entity_name;

    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_balance := ROUND(v_new_balance * v_rate, 2);

    v_account_id := NEW.account_id;
    IF v_account_id IS NULL THEN
        IF TG_TABLE_NAME = 'customers' THEN
            SELECT id INTO v_account_id FROM accounts WHERE (account_code = '1020' || LPAD(NEW.code, 2, '0') OR account_code = '1020' || NEW.code::text) AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        ELSIF TG_TABLE_NAME = 'suppliers' THEN
            SELECT id INTO v_account_id FROM accounts WHERE (account_code = '2000' || LPAD(NEW.code, 2, '0') OR account_code = '2000' || NEW.code::text) AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        ELSIF TG_TABLE_NAME = 'clearing_agents' THEN
            SELECT id INTO v_account_id FROM accounts WHERE (account_code = '2104' || LPAD(NEW.code, 2, '0') OR account_code = '2104' || NEW.code::text) AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        ELSIF TG_TABLE_NAME = 'shipping_companies' THEN
            SELECT id INTO v_account_id FROM accounts WHERE (account_code = '2103' || LPAD(NEW.code, 2, '0') OR account_code = '2103' || NEW.code::text) AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        END IF;
    END IF;

    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Resolve Opening Balance Equity Account (3901-3904)
    v_equity_account_id := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    
    IF v_equity_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_source_id := TG_TABLE_NAME || '_' || NEW.id::text;

    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type::text = 'opening_balance' 
      AND (source_id::text = v_source_id OR source_id::text = NEW.id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
        
        IF v_new_balance = 0 THEN
            DELETE FROM journal_entries WHERE id = v_je_id;
            RETURN NEW;
        END IF;

        UPDATE journal_entries 
        SET description = v_desc,
            source_id = v_source_id,
            entry_date = CURRENT_DATE,
            status = 'posted'
        WHERE id = v_je_id;
    ELSE
        IF v_new_balance = 0 THEN
            RETURN NEW;
        END IF;
        
        v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);
        IF v_entry_number IS NULL OR v_entry_number = '' THEN
            v_entry_number := 'OB-' || LPAD((COALESCE((SELECT MAX(id) FROM journal_entries), 0) + 1)::text, 5, '0');
        END IF;

        INSERT INTO journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
        ) VALUES (
            'opening_balance', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
        ) RETURNING id INTO v_je_id;
    END IF;

    IF v_direction = 'DEBIT' THEN
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_new_balance, 0, v_currency, v_base_balance, v_desc, v_company_id
        );
        
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_equity_account_id, 0, v_new_balance, v_currency, v_base_balance, v_desc, v_company_id
        );
    ELSE
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, 0, v_new_balance, v_currency, v_base_balance, v_desc, v_company_id
        );
        
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_equity_account_id, v_new_balance, 0, v_currency, v_base_balance, v_desc, v_company_id
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Update sync_shareholder_opening_balance_gl Trigger Function
CREATE OR REPLACE FUNCTION public.sync_shareholder_opening_balance_gl()
RETURNS TRIGGER AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_new_balance NUMERIC;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.initial_balance_egp IS NOT DISTINCT FROM OLD.initial_balance_egp THEN
            RETURN NEW;
        END IF;
    END IF;

    v_new_balance := COALESCE(NEW.initial_balance_egp, 0);
    v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');

    v_account_id := NEW.account_id;
    v_company_id := NEW.company_id;

    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_equity_account_id := public.resolve_opening_balance_equity_account('EGP', v_company_id);

    IF v_equity_account_id IS NULL THEN
        RAISE EXCEPTION 'Opening Balance Equity account (3901) not found for company %', v_company_id;
    END IF;

    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type = 'opening_balance' AND source_id = TG_TABLE_NAME || '_' || NEW.id::TEXT
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
    ELSE
        INSERT INTO journal_entries (
            entry_number, entry_date, description, status,
            is_auto_generated, source_type, source_id, created_by, company_id
        ) VALUES (
            public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL),
            CURRENT_DATE, v_desc, 'posted',
            true, 'opening_balance', TG_TABLE_NAME || '_' || NEW.id::TEXT, NULL, v_company_id
        ) RETURNING id INTO v_je_id;
    END IF;

    IF v_new_balance > 0 THEN
        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
        VALUES (v_je_id, v_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
        VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
    ELSE
        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
        VALUES (v_je_id, v_account_id, 0, ABS(v_new_balance), 'EGP', ABS(v_new_balance), v_desc, v_company_id);
        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
        VALUES (v_je_id, v_equity_account_id, ABS(v_new_balance), 0, 'EGP', ABS(v_new_balance), v_desc, v_company_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. New RPC: rpc_record_raw_material_opening_gl with Atomic Idempotency
CREATE OR REPLACE FUNCTION public.rpc_record_raw_material_opening_gl(
    p_raw_material_id UUID,
    p_quantity NUMERIC,
    p_unit_price NUMERIC,
    p_currency TEXT,
    p_company_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id UUID;
    v_rate NUMERIC;
    v_total_foreign NUMERIC;
    v_total_base NUMERIC;
    v_inv_acct BIGINT;
    v_equity_acct BIGINT;
    v_je_id BIGINT;
    v_material_name TEXT;
    v_desc TEXT;
    v_source_id TEXT;
    v_entry_number TEXT;
BEGIN
    IF p_quantity <= 0 OR p_unit_price <= 0 THEN
        RETURN jsonb_build_object('success', false, 'reason', 'Zero quantity or price');
    END IF;

    -- Resolve company_id with robust multi-level fallback
    v_company_id := p_company_id;
    IF v_company_id IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT tenant_id INTO v_company_id FROM tenant_users WHERE user_id = auth.uid() LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM treasuries WHERE type = 'main' AND company_id IS NOT NULL LIMIT 1;
    END IF;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    SELECT name INTO v_material_name FROM raw_materials WHERE id = p_raw_material_id;
    v_desc := 'رصيد افتتاحي مخزون مادة تعبئة - ' || COALESCE(v_material_name, '');

    -- Get exchange rate & compute base value
    v_rate := public.fn_get_exchange_rate(p_currency);
    v_total_foreign := ROUND(p_quantity * p_unit_price, 2);
    v_total_base := ROUND(v_total_foreign * v_rate, 2);

    -- Resolve GL accounts (Debit 1040 / Credit 390x)
    v_inv_acct := public.resolve_gl_account('1040', v_company_id);
    IF v_inv_acct IS NULL THEN
        RAISE EXCEPTION 'Packing Materials Inventory account (1040) not found in chart of accounts';
    END IF;

    v_equity_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    IF v_equity_acct IS NULL THEN
        RAISE EXCEPTION 'Opening Balance Equity account (390x) not found for currency %', p_currency;
    END IF;

    v_source_id := 'raw_material_' || p_raw_material_id::text;

    -- Idempotency check: check if a journal entry already exists for this raw material
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type = 'raw_material_opening'
      AND (source_id = v_source_id OR source_id = p_raw_material_id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        -- Atomically wipe old lines within this transaction and update header
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;

        UPDATE journal_entries
        SET description = v_desc,
            entry_date = CURRENT_DATE,
            status = 'posted'
        WHERE id = v_je_id;
    ELSE
        v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);
        IF v_entry_number IS NULL OR v_entry_number = '' THEN
            v_entry_number := 'OB-RM-' || LPAD((COALESCE((SELECT MAX(id) FROM journal_entries), 0) + 1)::text, 5, '0');
        END IF;

        INSERT INTO journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
        ) VALUES (
            'raw_material_opening', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
        ) RETURNING id INTO v_je_id;
    END IF;

    -- Double entry lines
    -- Debit: 1040 (Packing Materials Inventory)
    INSERT INTO account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_inv_acct, v_total_foreign, 0, p_currency, v_total_base, v_desc, v_company_id
    );

    -- Credit: 390x (Opening Balance Equity)
    INSERT INTO account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_equity_acct, 0, v_total_foreign, p_currency, v_total_base, v_desc, v_company_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'amount_foreign', v_total_foreign,
        'amount_base', v_total_base,
        'currency', p_currency,
        'exchange_rate', v_rate
    );
END;
$$;
