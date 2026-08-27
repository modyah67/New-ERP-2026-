-- Migration 036: Phase A — bank_account_dao + shipment_cost_item + shipment_payment + packing_order
-- Architecture: one business operation = one SQL transaction = one RPC call
-- 1. deposit_bank_account: now includes party balance + ledger_entries
-- 2. withdraw_bank_account: now includes party balance + ledger_entries
-- 3. rpc_sync_vendor_balances_and_ledger: atomic vendor balance recalc + ledger sync
-- 4. rpc_deposit_customer_treasury: treasury deposit + customer balance + ledger_entries
-- 5. rpc_withdraw_customer_treasury: treasury withdraw + customer balance + ledger_entries

BEGIN;

-- ============================================================
-- 1. deposit_bank_account: now handles party balance + ledger_entries
-- ============================================================
CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC := 0;
    v_tx_id BIGINT;
    v_bank_account_id_code BIGINT;
    v_revenue_account_id BIGINT;
    v_currency TEXT;
    v_company_id UUID;
    v_desc TEXT;
    v_le_created_by UUID;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    v_new_balance := v_current_balance + p_amount;
    v_le_created_by := auth.uid();
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي مباشر');

    SELECT id INTO v_bank_account_id_code FROM accounts WHERE account_code = '11201' AND company_id = v_company_id;
    SELECT id INTO v_revenue_account_id FROM accounts WHERE account_code = '41101' AND company_id = v_company_id;

    IF v_bank_account_id_code IS NULL OR v_revenue_account_id IS NULL THEN
        SELECT id INTO v_bank_account_id_code FROM accounts WHERE company_id = v_company_id LIMIT 1;
        SELECT id INTO v_revenue_account_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
    END IF;

    -- GL: debit bank, credit revenue
    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        'PENDING', CURRENT_DATE, v_desc, 'posted', true, 'bank_deposit', v_le_created_by, v_company_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_bank_account_id_code, p_amount, 0, v_currency, p_amount, v_desc, v_company_id);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_revenue_account_id, 0, p_amount, v_currency, p_amount, v_desc, v_company_id);

    -- Bank balance
    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, v_le_created_by, p_entity_type, p_entity_id, p_counterparty_name
    ) RETURNING id INTO v_tx_id;

    -- Party balance + subledger (party_subledger.ledger_entries)
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount
        WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id, 'credit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount
        WHERE id::text = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id, 'credit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = manual_adjustment + p_amount,
            balance = balance + p_amount
        WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'clearing_agent', p_entity_id, 'credit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = manual_adjustment + p_amount,
            balance = balance + p_amount
        WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'shipping_company', p_entity_id, 'credit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_entity_id::uuid;
        END IF;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'shareholder', p_entity_id, 'credit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'balance_after', v_new_balance
    );
END;
$$;

-- ============================================================
-- 2. withdraw_bank_account: now handles party balance + ledger_entries
-- ============================================================
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id integer,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC := 0;
    v_tx_id BIGINT;
    v_bank_account_id_code BIGINT;
    v_expense_account_id BIGINT;
    v_currency TEXT;
    v_company_id UUID;
    v_desc TEXT;
    v_le_created_by UUID;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية (الرصيد الحالي: %)', v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;
    v_le_created_by := auth.uid();
    v_desc := COALESCE(NULLIF(p_description, ''), 'سحب / مصروف بنكي مباشر');

    SELECT id INTO v_bank_account_id_code FROM accounts WHERE account_code = '11201' AND company_id = v_company_id;
    SELECT id INTO v_expense_account_id FROM accounts WHERE account_code = '51101' AND company_id = v_company_id;

    IF v_bank_account_id_code IS NULL OR v_expense_account_id IS NULL THEN
        SELECT id INTO v_bank_account_id_code FROM accounts WHERE company_id = v_company_id LIMIT 1;
        SELECT id INTO v_expense_account_id FROM accounts WHERE company_id = v_company_id LIMIT 1;
    END IF;

    -- GL: debit expense, credit bank
    INSERT INTO journal_entries (
        entry_number, entry_date, description, status, is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        'PENDING', CURRENT_DATE, v_desc, 'posted', true, 'bank_withdraw', v_le_created_by, v_company_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_expense_account_id, p_amount, 0, v_currency, p_amount, v_desc, v_company_id);

    INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
    VALUES (v_tx_id, v_bank_account_id_code, 0, p_amount, v_currency, p_amount, v_desc, v_company_id);

    -- Bank balance
    UPDATE bank_accounts SET balance = v_new_balance WHERE id = p_account_id;

    INSERT INTO bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name
    ) VALUES (
        p_account_id, 'withdrawal', p_amount, v_current_balance, v_new_balance,
        v_desc, v_le_created_by, p_entity_type, p_entity_id, p_counterparty_name
    ) RETURNING id INTO v_tx_id;

    -- Party balance + subledger (party_subledger.ledger_entries)
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount
        WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id, 'debit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount
        WHERE id::text = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id, 'debit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = manual_adjustment - p_amount,
            balance = balance - p_amount
        WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'clearing_agent', p_entity_id, 'debit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = manual_adjustment - p_amount,
            balance = balance - p_amount
        WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'shipping_company', p_entity_id, 'debit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );

    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'shareholder', p_entity_id, 'debit', p_amount, v_currency,
            'bank_transfer', p_counterparty_name, v_desc, v_le_created_by
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'balance_after', v_new_balance
    );
END;
$$;

-- ============================================================
-- 3. rpc_sync_vendor_balances_and_ledger: atomic vendor balance recalc + ledger sync
-- ============================================================
CREATE OR REPLACE FUNCTION public.rpc_sync_vendor_balances_and_ledger()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_total_cost NUMERIC;
    v_shipping_updated INT := 0;
    v_ca_updated INT := 0;
    v_le_upserted INT := 0;
    v_le_deleted INT := 0;
BEGIN
    -- Shipping companies: recalculate balance
    FOR r IN
        SELECT sci.vendor_id AS comp_id,
               COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost
        FROM public.shipment_cost_items sci
        WHERE sci.vendor_type = 'shipping_company' AND sci.vendor_id IS NOT NULL
        GROUP BY sci.vendor_id
    LOOP
        UPDATE public.shipping_companies
        SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)
        WHERE id = r.comp_id;
        v_shipping_updated := v_shipping_updated + 1;
    END LOOP;

    UPDATE public.shipping_companies sc
    SET balance = COALESCE(sc.initial_balance, 0) + COALESCE(sc.manual_adjustment, 0)
    WHERE sc.id NOT IN (
        SELECT DISTINCT vendor_id FROM public.shipment_cost_items
        WHERE vendor_type = 'shipping_company' AND vendor_id IS NOT NULL
    );

    -- Clearing agents: recalculate balance
    FOR r IN
        SELECT sci.vendor_id AS agent_id,
               COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost
        FROM public.shipment_cost_items sci
        WHERE sci.vendor_type = 'clearing_agent' AND sci.vendor_id IS NOT NULL
        GROUP BY sci.vendor_id
    LOOP
        UPDATE public.clearing_agents
        SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)
        WHERE id = r.agent_id;
        v_ca_updated := v_ca_updated + 1;
    END LOOP;

    UPDATE public.clearing_agents ca
    SET balance = COALESCE(ca.initial_balance, 0) + COALESCE(ca.manual_adjustment, 0)
    WHERE ca.id NOT IN (
        SELECT DISTINCT vendor_id FROM public.shipment_cost_items
        WHERE vendor_type = 'clearing_agent' AND vendor_id IS NOT NULL
    );

    -- Upsert ledger_entries for shipment_cost_items
    -- Delete orphaned entries
    DELETE FROM public.ledger_entries le
    WHERE le.reference_type = 'shipment_cost_item'
      AND le.reference_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM public.shipment_cost_items sci
          WHERE sci.id = le.reference_id::bigint
      );
    GET DIAGNOSTICS v_le_deleted = ROW_COUNT;

    -- Upsert entries for current items
    FOR r IN
        SELECT sci.id AS item_id,
               sci.vendor_type,
               sci.vendor_id,
               sci.supplier_id,
               sci.total_price,
               sci.exchange_rate,
               sci.original_currency,
               sci.description
        FROM public.shipment_cost_items sci
        WHERE sci.total_price > 0
    LOOP
        DECLARE
            v_entity_type TEXT;
            v_entity_id   TEXT;
            v_ledger_amount NUMERIC;
            v_ledger_currency TEXT;
            v_exists BIGINT;
        BEGIN
            IF r.vendor_type = 'shipping_company' AND r.vendor_id IS NOT NULL THEN
                v_entity_type := 'shipping_company';
                v_entity_id := r.vendor_id::text;
            ELSIF r.vendor_type = 'clearing_agent' AND r.vendor_id IS NOT NULL THEN
                v_entity_type := 'clearing_agent';
                v_entity_id := r.vendor_id::text;
            ELSIF r.supplier_id IS NOT NULL AND r.supplier_id != '' THEN
                v_entity_type := 'supplier';
                v_entity_id := r.supplier_id;
            ELSE
                CONTINUE;
            END IF;

            v_ledger_currency := COALESCE(NULLIF(r.original_currency, ''), 'EGP');
            IF v_ledger_currency != 'EGP' AND r.exchange_rate > 0 THEN
                v_ledger_amount := r.total_price / r.exchange_rate;
            ELSE
                v_ledger_amount := r.total_price;
            END IF;

            SELECT COUNT(*) INTO v_exists FROM public.ledger_entries
            WHERE reference_type = 'shipment_cost_item' AND reference_id = r.item_id;

            IF v_exists > 0 THEN
                UPDATE public.ledger_entries
                SET entity_type = v_entity_type,
                    entity_id = v_entity_id,
                    amount = v_ledger_amount,
                    currency = v_ledger_currency,
                    description = 'بند تكلفة شحنة: ' || COALESCE(r.description, '')
                WHERE reference_type = 'shipment_cost_item' AND reference_id = r.item_id;
            ELSE
                INSERT INTO public.ledger_entries (
                    entity_type, entity_id, entry_type, amount, currency,
                    reference_type, reference_id, description, created_by
                ) VALUES (
                    v_entity_type, v_entity_id, 'credit', v_ledger_amount, v_ledger_currency,
                    'shipment_cost_item', r.item_id,
                    'بند تكلفة شحنة: ' || COALESCE(r.description, ''),
                    auth.uid()
                );
            END IF;
            v_le_upserted := v_le_upserted + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'shipping_updated', v_shipping_updated,
        'ca_updated', v_ca_updated,
        'ledger_upserted', v_le_upserted,
        'ledger_deleted', v_le_deleted
    );
END;
$$;

-- ============================================================
-- 4. rpc_deposit_customer_treasury: treasury deposit + customer balance + ledger_entries
-- ============================================================
CREATE OR REPLACE FUNCTION public.rpc_deposit_customer_treasury(
    p_treasury_id bigint,
    p_currency varchar,
    p_amount numeric,
    p_description text,
    p_customer_id bigint
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance numeric;
    v_tx_id bigint;
BEGIN
    -- Treasury balance check
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL THEN
        RAISE EXCEPTION 'الخزينة غير موجودة';
    END IF;

    -- Credit treasury
    UPDATE public.treasury_balances
    SET balance = balance + p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Create treasury transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_amount, p_currency, p_description,
        p_customer_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Customer balance: decrease (money received reduces what they owe)
    UPDATE public.customers SET balance = balance - p_amount
    WHERE id = p_customer_id;

    -- Subledger entry
    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        'customer', p_customer_id::text, 'credit', p_amount, p_currency,
        'treasury_deposit', v_tx_id, p_description, auth.uid()
    );

    RETURN v_tx_id;
END;
$$;

-- ============================================================
-- 5. rpc_withdraw_customer_treasury: treasury withdraw + customer balance + ledger_entries
-- ============================================================
CREATE OR REPLACE FUNCTION public.rpc_withdraw_customer_treasury(
    p_treasury_id bigint,
    p_currency varchar,
    p_amount numeric,
    p_description text,
    p_customer_id bigint
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_balance numeric;
    v_tx_id bigint;
BEGIN
    -- Treasury balance check
    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    -- Debit treasury
    UPDATE public.treasury_balances
    SET balance = balance - p_amount, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Create treasury transaction
    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        customer_id, created_by
    ) VALUES (
        p_treasury_id, 'expense', p_amount, p_currency, p_description,
        p_customer_id, auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Customer balance: increase (money returned increases what they owe)
    UPDATE public.customers SET balance = balance + p_amount
    WHERE id = p_customer_id;

    -- Subledger entry
    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_id, description, created_by
    ) VALUES (
        'customer', p_customer_id::text, 'debit', p_amount, p_currency,
        'treasury_deposit', v_tx_id, p_description, auth.uid()
    );

    RETURN v_tx_id;
END;
$$;

COMMIT;
