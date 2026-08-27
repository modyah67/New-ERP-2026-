BEGIN;

CREATE OR REPLACE FUNCTION public.sync_entity_opening_balance_gl()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_je_id BIGINT;
    v_diff NUMERIC;
    v_is_liability BOOLEAN := FALSE;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_entity_name TEXT;
    v_new_balance NUMERIC;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.initial_balance IS NOT DISTINCT FROM OLD.initial_balance THEN
            RETURN NEW;
        END IF;
    END IF;

    v_new_balance := COALESCE(NEW.initial_balance, 0);
    v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');

    v_account_id := NEW.account_id;
    v_company_id := NEW.company_id;

    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME IN ('suppliers', 'clearing_agents', 'shipping_companies') THEN
        v_is_liability := TRUE;
    END IF;

    SELECT id INTO v_equity_account_id
    FROM accounts
    WHERE account_code = '3000' AND company_id = v_company_id
    LIMIT 1;

    IF v_equity_account_id IS NULL THEN
        RAISE EXCEPTION 'Owner Equity account (3000) not found for company %', v_company_id;
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

    IF v_is_liability THEN
        IF v_new_balance > 0 THEN
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
        ELSE
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, ABS(v_new_balance), 0, 'EGP', ABS(v_new_balance), v_desc, v_company_id);
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, 0, ABS(v_new_balance), 'EGP', ABS(v_new_balance), v_desc, v_company_id);
        END IF;
    ELSE
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
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_shareholder_opening_balance_gl()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_je_id BIGINT;
    v_diff NUMERIC;
    v_is_liability BOOLEAN := FALSE;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_entity_name TEXT;
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

    SELECT id INTO v_equity_account_id
    FROM accounts
    WHERE account_code = '3000' AND company_id = v_company_id
    LIMIT 1;

    IF v_equity_account_id IS NULL THEN
        RAISE EXCEPTION 'Owner Equity account (3000) not found for company %', v_company_id;
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
$$;

DROP TRIGGER IF EXISTS trg_customer_opening_balance_gl ON public.customers;
DROP TRIGGER IF EXISTS trg_supplier_opening_balance_gl ON public.suppliers;
DROP TRIGGER IF EXISTS trg_shipping_company_opening_balance_gl ON public.shipping_companies;
DROP TRIGGER IF EXISTS trg_clearing_agent_opening_balance_gl ON public.clearing_agents;
DROP TRIGGER IF EXISTS trg_shareholder_opening_balance_gl ON public.shareholders;

CREATE TRIGGER trg_customer_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance ON public.customers FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();
CREATE TRIGGER trg_supplier_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();
CREATE TRIGGER trg_shipping_company_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance ON public.shipping_companies FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();
CREATE TRIGGER trg_clearing_agent_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance ON public.clearing_agents FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();
CREATE TRIGGER trg_shareholder_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance_egp ON public.shareholders FOR EACH ROW EXECUTE FUNCTION public.sync_shareholder_opening_balance_gl();

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM public.customers WHERE COALESCE(initial_balance, 0) != 0 AND account_id IS NOT NULL
    LOOP
        UPDATE public.customers SET initial_balance = initial_balance WHERE id = rec.id;
    END LOOP;

    FOR rec IN SELECT * FROM public.suppliers WHERE COALESCE(initial_balance, 0) != 0 AND account_id IS NOT NULL
    LOOP
        UPDATE public.suppliers SET initial_balance = initial_balance WHERE id = rec.id;
    END LOOP;

    FOR rec IN SELECT * FROM public.shipping_companies WHERE COALESCE(initial_balance, 0) != 0 AND account_id IS NOT NULL
    LOOP
        UPDATE public.shipping_companies SET initial_balance = initial_balance WHERE id = rec.id;
    END LOOP;

    FOR rec IN SELECT * FROM public.clearing_agents WHERE COALESCE(initial_balance, 0) != 0 AND account_id IS NOT NULL
    LOOP
        UPDATE public.clearing_agents SET initial_balance = initial_balance WHERE id = rec.id;
    END LOOP;

    FOR rec IN SELECT * FROM public.shareholders WHERE COALESCE(initial_balance_egp, 0) != 0 AND account_id IS NOT NULL
    LOOP
        UPDATE public.shareholders SET initial_balance_egp = initial_balance_egp WHERE id = rec.id;
    END LOOP;
END;
$$;

COMMIT;
