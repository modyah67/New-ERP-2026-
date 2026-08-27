-- Migration 130: Fix entity opening balance sync triggers & typing

BEGIN;

-- 1. Safely handle type casting in get_next_entity_account_code
DROP FUNCTION IF EXISTS public.get_next_entity_account_code(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.get_next_entity_account_code(
  p_entity_type TEXT,
  p_company_id UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pattern TEXT;
  v_start INT;
  v_next INT;
  v_code TEXT;
BEGIN
  CASE p_entity_type
    WHEN 'customer'         THEN v_pattern := '^11[0-9]{3}$'; v_start := 11000;
    WHEN 'supplier'         THEN v_pattern := '^21[0-9]{3}$'; v_start := 21000;
    WHEN 'shipping_company' THEN v_pattern := '^200[0-9]{2}$'; v_start := 20000;
    WHEN 'clearing_agent'   THEN v_pattern := '^201[0-9]{2}$'; v_start := 20100;
    WHEN 'shareholder'      THEN v_pattern := '^300[0-9]{2}$'; v_start := 30000;
    ELSE RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
  END CASE;

  LOOP
    SELECT COALESCE(MAX(NULLIF(regexp_replace(account_code::text, '\D', '', 'g'), '')::int), v_start) + 1 INTO v_next
    FROM accounts
    WHERE account_code::text ~ v_pattern;

    IF v_next <= v_start THEN
      v_next := v_start + 1;
    END IF;

    v_code := LPAD(v_next::TEXT, 5, '0');

    -- Ensure code is available in both accounts and deleted_account_codes
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM accounts WHERE account_code::text = v_code
    ) AND NOT EXISTS (
      SELECT 1 FROM deleted_account_codes WHERE account_code::text = v_code
    );

    v_start := v_next;
  END LOOP;

  RETURN v_code;
END;
$$;


-- 2. Ensure type-safe comparison in sync_entity_opening_balance_gl
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
    -- Only trigger if initial_balance changed
    IF TG_OP = 'UPDATE' THEN
        IF TG_TABLE_NAME = 'shareholders' THEN
            IF NEW.initial_balance_egp IS NOT DISTINCT FROM OLD.initial_balance_egp THEN
                RETURN NEW;
            END IF;
        ELSE
            IF NEW.initial_balance IS NOT DISTINCT FROM OLD.initial_balance AND NEW.account_id IS NOT DISTINCT FROM OLD.account_id THEN
                -- If neither initial_balance nor account_id changed, skip.
                -- We want to fire if account_id just got assigned so we can create the GL entry.
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    -- Different tables have different column names for balance and name
    IF TG_TABLE_NAME = 'shareholders' THEN
        v_new_balance := COALESCE(NEW.initial_balance_egp, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    ELSE
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
    END IF;

    v_account_id := NEW.account_id;
    v_company_id := NEW.company_id;

    -- Only proceed if the entity has an account_id
    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Determine if it's a liability or asset based on table name
    IF TG_TABLE_NAME IN ('suppliers', 'clearing_agents', 'shipping_companies') THEN
        v_is_liability := TRUE;
    END IF;

    -- Get Owner Equity account (3000)
    SELECT id INTO v_equity_account_id
    FROM accounts
    WHERE account_code::text = '3000' AND company_id = v_company_id
    LIMIT 1;

    -- Fallback to any 3000 if company specific not found
    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id
        FROM accounts
        WHERE account_code::text = '3000'
        LIMIT 1;
    END IF;
    
    IF v_equity_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Find existing journal entry safely with type casts
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type::text = 'opening_balance' AND source_id::text = NEW.id::text
    LIMIT 1;

    IF v_je_id IS NOT NULL THEN
        -- Clear old ledger entries
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
        
        -- If new balance is 0, delete JE and exit
        IF v_new_balance = 0 THEN
            DELETE FROM journal_entries WHERE id = v_je_id;
            RETURN NEW;
        END IF;
    ELSE
        IF v_new_balance = 0 THEN
            RETURN NEW;
        END IF;
        
        -- Create new JE
        INSERT INTO journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number
        ) VALUES (
            'opening_balance', NEW.id::text, CURRENT_DATE, v_desc, auth.uid(), v_company_id, public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL)
        ) RETURNING id INTO v_je_id;
    END IF;

    -- Create lines based on liability or asset
    IF v_is_liability THEN
        IF v_new_balance > 0 THEN
            -- Credit Liability, Debit Equity
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
            
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
        ELSE
            -- Debit Liability, Credit Equity
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, ABS(v_new_balance), 0, 'EGP', ABS(v_new_balance), v_desc, v_company_id);
            
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, 0, ABS(v_new_balance), 'EGP', ABS(v_new_balance), v_desc, v_company_id);
        END IF;
    ELSE
        -- Asset
        IF v_new_balance > 0 THEN
            -- Debit Asset, Credit Equity
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
            
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
        ELSE
            -- Credit Asset, Debit Equity
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, 0, ABS(v_new_balance), 'EGP', ABS(v_new_balance), v_desc, v_company_id);
            
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, ABS(v_new_balance), 0, 'EGP', ABS(v_new_balance), v_desc, v_company_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Update triggers to ALSO trigger on account_id changes 
-- so that new entities get their GL entries synced when account_id is generated by other triggers.

DROP TRIGGER IF EXISTS trg_customer_opening_balance_gl ON public.customers;
CREATE TRIGGER trg_customer_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, account_id ON public.customers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_supplier_opening_balance_gl ON public.suppliers;
CREATE TRIGGER trg_supplier_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, account_id ON public.suppliers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_clearing_agent_opening_balance_gl ON public.clearing_agents;
CREATE TRIGGER trg_clearing_agent_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, account_id ON public.clearing_agents
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_shipping_company_opening_balance_gl ON public.shipping_companies;
CREATE TRIGGER trg_shipping_company_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, account_id ON public.shipping_companies
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_shareholder_opening_balance_gl ON public.shareholders;
CREATE TRIGGER trg_shareholder_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance_egp, account_id ON public.shareholders
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

COMMIT;
