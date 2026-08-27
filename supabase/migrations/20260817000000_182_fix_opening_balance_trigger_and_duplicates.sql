-- Migration 182: Fix Opening Balance Duplicates and Equity Account Lookup
-- 1. Deletes the manual Treasury 'opening' duplicate journal entries.
-- 2. Modifies sync_entity_opening_balance_gl to lookup Equity accounts (3001-3004) instead of 3000.
-- 3. Forces re-generation of existing opening balances.

BEGIN;

-- 1. Wipe out any existing garbage opening balance journal entries
DELETE FROM account_ledger_entries WHERE journal_entry_id IN (
    SELECT id FROM journal_entries WHERE source_type = 'opening_balance'
);
DELETE FROM journal_entries WHERE source_type = 'opening_balance';

-- 2. Wipe out the duplicate treasury transactions that the user made manually (which had "استلام % من opening")
DELETE FROM account_ledger_entries WHERE journal_entry_id IN (
    SELECT id FROM journal_entries WHERE source_type = 'treasury' AND source_id IN (
        SELECT id::text FROM treasury_transactions WHERE description LIKE 'استلام % من opening'
    )
);
DELETE FROM journal_entries WHERE source_type = 'treasury' AND source_id IN (
    SELECT id::text FROM treasury_transactions WHERE description LIKE 'استلام % من opening'
);
DELETE FROM treasury_transactions WHERE description LIKE 'استلام % من opening';

-- 2. Rewrite sync_entity_opening_balance_gl to use currency-specific Owner Equity accounts
CREATE OR REPLACE FUNCTION public.sync_entity_opening_balance_gl()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_equity_account_egp BIGINT;
    v_equity_account_usd BIGINT;
    v_equity_account_eur BIGINT;
    v_equity_account_gbp BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_new_balance NUMERIC;
    v_direction TEXT;
    v_currency TEXT;
    v_equity_account_code TEXT;
BEGIN
    -- Only trigger if initial_balance or direction changed
    IF TG_OP = 'UPDATE' THEN
        IF TG_TABLE_NAME = 'shareholders' THEN
            IF NEW.initial_balance_egp IS NOT DISTINCT FROM OLD.initial_balance_egp 
               AND NEW.initial_balance_usd IS NOT DISTINCT FROM OLD.initial_balance_usd 
               AND NEW.initial_balance_eur IS NOT DISTINCT FROM OLD.initial_balance_eur 
               AND NEW.initial_balance_gbp IS NOT DISTINCT FROM OLD.initial_balance_gbp 
               AND NEW.initial_balance_direction_egp IS NOT DISTINCT FROM OLD.initial_balance_direction_egp
               AND NEW.initial_balance_direction_usd IS NOT DISTINCT FROM OLD.initial_balance_direction_usd
               AND NEW.initial_balance_direction_eur IS NOT DISTINCT FROM OLD.initial_balance_direction_eur
               AND NEW.initial_balance_direction_gbp IS NOT DISTINCT FROM OLD.initial_balance_direction_gbp
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

    v_account_id := NEW.account_id;
    v_company_id := NEW.company_id;

    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Lookup all 4 possible Equity Accounts dynamically
    -- EGP
    SELECT id INTO v_equity_account_egp FROM accounts WHERE account_code::text = '3001' AND company_id = v_company_id LIMIT 1;
    IF v_equity_account_egp IS NULL THEN
        SELECT id INTO v_equity_account_egp FROM accounts WHERE account_code::text = '3001' LIMIT 1;
    END IF;

    -- USD
    SELECT id INTO v_equity_account_usd FROM accounts WHERE account_code::text = '3002' AND company_id = v_company_id LIMIT 1;
    IF v_equity_account_usd IS NULL THEN
        SELECT id INTO v_equity_account_usd FROM accounts WHERE account_code::text = '3002' LIMIT 1;
    END IF;

    -- EUR
    SELECT id INTO v_equity_account_eur FROM accounts WHERE account_code::text = '3003' AND company_id = v_company_id LIMIT 1;
    IF v_equity_account_eur IS NULL THEN
        SELECT id INTO v_equity_account_eur FROM accounts WHERE account_code::text = '3003' LIMIT 1;
    END IF;

    -- GBP
    SELECT id INTO v_equity_account_gbp FROM accounts WHERE account_code::text = '3004' AND company_id = v_company_id LIMIT 1;
    IF v_equity_account_gbp IS NULL THEN
        SELECT id INTO v_equity_account_gbp FROM accounts WHERE account_code::text = '3004' LIMIT 1;
    END IF;

    -- Pre-fetch the existing JE id if there is one
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type::text = 'opening_balance' AND source_id::text = NEW.id::text
    LIMIT 1;

    -- Clear existing ledger entries
    IF v_je_id IS NOT NULL THEN
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
    END IF;

    -- Check if we need a JE (is any balance != 0)
    IF TG_TABLE_NAME = 'shareholders' THEN
        IF COALESCE(NEW.initial_balance_egp, 0) = 0 AND 
           COALESCE(NEW.initial_balance_usd, 0) = 0 AND 
           COALESCE(NEW.initial_balance_eur, 0) = 0 AND 
           COALESCE(NEW.initial_balance_gbp, 0) = 0 THEN
            
            IF v_je_id IS NOT NULL THEN
                DELETE FROM journal_entries WHERE id = v_je_id;
            END IF;
            RETURN NEW;
        END IF;
    ELSE
        IF COALESCE(NEW.initial_balance, 0) = 0 THEN
            IF v_je_id IS NOT NULL THEN
                DELETE FROM journal_entries WHERE id = v_je_id;
            END IF;
            RETURN NEW;
        END IF;
    END IF;

    -- Create Journal Entry if not exists
    IF v_je_id IS NULL THEN
        INSERT INTO journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number
        ) VALUES (
            'opening_balance', NEW.id::text, CURRENT_DATE, 'رصيد افتتاحي - ' || COALESCE(NEW.name, ''), auth.uid(), v_company_id, public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL)
        ) RETURNING id INTO v_je_id;
    END IF;

    -- Now insert the lines
    IF TG_TABLE_NAME = 'shareholders' THEN
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');

        -- EGP
        IF COALESCE(NEW.initial_balance_egp, 0) != 0 AND v_equity_account_egp IS NOT NULL THEN
            v_new_balance := COALESCE(NEW.initial_balance_egp, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_egp, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_egp, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_egp, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

        -- USD
        IF COALESCE(NEW.initial_balance_usd, 0) != 0 AND v_equity_account_usd IS NOT NULL THEN
            v_new_balance := COALESCE(NEW.initial_balance_usd, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_usd, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'USD', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_usd, 0, v_new_balance, 'USD', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'USD', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_usd, v_new_balance, 0, 'USD', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

        -- EUR
        IF COALESCE(NEW.initial_balance_eur, 0) != 0 AND v_equity_account_eur IS NOT NULL THEN
            v_new_balance := COALESCE(NEW.initial_balance_eur, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_eur, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'EUR', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_eur, 0, v_new_balance, 'EUR', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'EUR', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_eur, v_new_balance, 0, 'EUR', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

        -- GBP
        IF COALESCE(NEW.initial_balance_gbp, 0) != 0 AND v_equity_account_gbp IS NOT NULL THEN
            v_new_balance := COALESCE(NEW.initial_balance_gbp, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_gbp, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'GBP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_gbp, 0, v_new_balance, 'GBP', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'GBP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_gbp, v_new_balance, 0, 'GBP', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

    ELSE
        -- Other entities (suppliers, customers, etc.)
        v_direction := NEW.initial_balance_direction;
        v_currency := COALESCE(row_to_json(NEW)->>'currency', 'EGP');
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');

        -- Pick the right equity account based on currency
        v_equity_account_id := CASE v_currency
            WHEN 'EGP' THEN v_equity_account_egp
            WHEN 'USD' THEN v_equity_account_usd
            WHEN 'EUR' THEN v_equity_account_eur
            WHEN 'GBP' THEN v_equity_account_gbp
            ELSE v_equity_account_egp
        END;
        
        IF v_equity_account_id IS NULL THEN
            RETURN NEW;
        END IF;
        
        IF v_direction = 'DEBIT' THEN
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, v_new_balance, 0, v_currency, v_new_balance, v_desc, v_company_id);
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, v_currency, v_new_balance, v_desc, v_company_id);
        ELSE
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_account_id, 0, v_new_balance, v_currency, v_new_balance, v_desc, v_company_id);
            INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
            VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, v_currency, v_new_balance, v_desc, v_company_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Force re-fire for all entities with opening balances to correct the missing GL lines
UPDATE public.shareholders SET initial_balance_egp = initial_balance_egp 
WHERE COALESCE(initial_balance_egp, 0) != 0 
   OR COALESCE(initial_balance_usd, 0) != 0 
   OR COALESCE(initial_balance_eur, 0) != 0 
   OR COALESCE(initial_balance_gbp, 0) != 0;

UPDATE public.suppliers SET initial_balance = initial_balance WHERE COALESCE(initial_balance, 0) != 0;
UPDATE public.customers SET initial_balance = initial_balance WHERE COALESCE(initial_balance, 0) != 0;

COMMIT;
