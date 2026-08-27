-- Migration 313: Fix and sync opening balance journal entries for all entities
-- Entities: customers, clearing_agents, shipping_companies, suppliers, shareholders
-- Ensures OB journal entries appear in Journal, GL, Trial Balance, and COA Account Dialogs

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_entity_opening_balance_gl()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_equity_code TEXT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_new_balance NUMERIC;
    v_direction TEXT;
    v_currency TEXT;
    v_source_id TEXT;
    v_entry_number TEXT;
BEGIN
    -- Check if initial_balance or direction changed on UPDATE
    IF TG_OP = 'UPDATE' THEN
        IF TG_TABLE_NAME = 'shareholders' THEN
            IF NEW.initial_balance_egp IS NOT DISTINCT FROM OLD.initial_balance_egp 
               AND NEW.initial_balance_direction IS NOT DISTINCT FROM OLD.initial_balance_direction
               AND NEW.account_id IS NOT DISTINCT FROM OLD.account_id THEN
                RETURN NEW;
            END IF;
        ELSE
            IF NEW.initial_balance IS NOT DISTINCT FROM OLD.initial_balance 
               AND NEW.initial_balance_direction IS NOT DISTINCT FROM OLD.initial_balance_direction
               AND NEW.account_id IS NOT DISTINCT FROM OLD.account_id THEN
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    -- Extract balance & description
    IF TG_TABLE_NAME = 'shareholders' THEN
        v_new_balance := COALESCE(NEW.initial_balance_egp, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    ELSIF TG_TABLE_NAME = 'customers' THEN
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    ELSIF TG_TABLE_NAME = 'clearing_agents' THEN
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    ELSIF TG_TABLE_NAME = 'shipping_companies' THEN
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    ELSE
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    END IF;

    v_account_id := NEW.account_id;
    v_company_id := NEW.company_id;
    
    -- Direction default
    IF TG_TABLE_NAME = 'customers' THEN
        v_direction := COALESCE(NEW.initial_balance_direction, 'DEBIT');
    ELSE
        v_direction := COALESCE(NEW.initial_balance_direction, 'CREDIT');
    END IF;
    
    -- Extract currency
    v_currency := UPPER(COALESCE(row_to_json(NEW)->>'currency', 'EGP'));
    IF v_currency = '' THEN
        v_currency := 'EGP';
    END IF;

    -- If account_id is missing, try to resolve from accounts table
    IF v_account_id IS NULL THEN
        IF TG_TABLE_NAME = 'customers' THEN
            SELECT id INTO v_account_id FROM accounts WHERE account_code = '1020' || LPAD(NEW.code, 2, '0') AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        ELSIF TG_TABLE_NAME = 'suppliers' THEN
            SELECT id INTO v_account_id FROM accounts WHERE account_code = '2000' || LPAD(NEW.code, 2, '0') AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        ELSIF TG_TABLE_NAME = 'clearing_agents' THEN
            SELECT id INTO v_account_id FROM accounts WHERE account_code = '2104' || LPAD(NEW.code, 2, '0') AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        ELSIF TG_TABLE_NAME = 'shipping_companies' THEN
            SELECT id INTO v_account_id FROM accounts WHERE account_code = '2103' || LPAD(NEW.code, 2, '0') AND (company_id = v_company_id OR company_id IS NULL) LIMIT 1;
        END IF;
    END IF;

    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Resolve Equity Account matching currency
    CASE v_currency
        WHEN 'USD' THEN v_equity_code := '3002';
        WHEN 'EUR' THEN v_equity_code := '3003';
        WHEN 'GBP' THEN v_equity_code := '3004';
        ELSE v_equity_code := '3001'; -- EGP
    END CASE;

    SELECT id INTO v_equity_account_id
    FROM accounts
    WHERE account_code::text = v_equity_code
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY (company_id = v_company_id) DESC, id ASC
    LIMIT 1;

    -- Fallback to 3001 or 3000 if not found
    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id
        FROM accounts
        WHERE account_code::text IN ('3001', '3000', '3300')
          AND (company_id = v_company_id OR company_id IS NULL)
        ORDER BY (company_id = v_company_id) DESC, id ASC
        LIMIT 1;
    END IF;
    
    IF v_equity_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Unique source_id per table to prevent entity collision
    v_source_id := TG_TABLE_NAME || '_' || NEW.id::text;

    -- Check for existing journal entry for this entity
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type::text = 'opening_balance' 
      AND (source_id::text = v_source_id OR source_id::text = NEW.id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        -- Delete existing lines
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
        
        IF v_new_balance = 0 THEN
            DELETE FROM journal_entries WHERE id = v_je_id;
            RETURN NEW;
        END IF;

        -- Update header description and source_id
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

    -- Create double-entry lines based strictly on chosen direction
    IF v_direction = 'DEBIT' THEN
        -- Debit Entity Account, Credit Equity Account
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_new_balance, 0, v_currency, v_new_balance, v_desc, v_company_id
        );
        
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_equity_account_id, 0, v_new_balance, v_currency, v_new_balance, v_desc, v_company_id
        );
    ELSE
        -- Credit Entity Account, Debit Equity Account
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, 0, v_new_balance, v_currency, v_new_balance, v_desc, v_company_id
        );
        
        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_equity_account_id, v_new_balance, 0, v_currency, v_new_balance, v_desc, v_company_id
        );
    END IF;

    RETURN NEW;
END;
$$;

-- Drop and re-attach triggers
DROP TRIGGER IF EXISTS trg_customer_opening_balance_gl ON public.customers;
CREATE TRIGGER trg_customer_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.customers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_supplier_opening_balance_gl ON public.suppliers;
CREATE TRIGGER trg_supplier_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.suppliers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_clearing_agent_opening_balance_gl ON public.clearing_agents;
CREATE TRIGGER trg_clearing_agent_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.clearing_agents
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_shipping_company_opening_balance_gl ON public.shipping_companies;
CREATE TRIGGER trg_shipping_company_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.shipping_companies
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

-- Backfill / Re-sync all existing entities with initial_balance != 0
UPDATE public.customers SET initial_balance = initial_balance WHERE initial_balance != 0;
UPDATE public.clearing_agents SET initial_balance = initial_balance WHERE initial_balance != 0;
UPDATE public.shipping_companies SET initial_balance = initial_balance WHERE initial_balance != 0;
UPDATE public.suppliers SET initial_balance = initial_balance WHERE initial_balance != 0;

COMMIT;
