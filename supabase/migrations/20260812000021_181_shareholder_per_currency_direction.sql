-- Migration 181: Per-Currency Initial Balance Direction for Shareholders
-- Adds individual direction columns for each currency (EGP, USD, EUR, GBP)
-- and updates the sync_entity_opening_balance_gl function accordingly.

BEGIN;

-- 1. Add per-currency direction columns
ALTER TABLE public.shareholders ADD COLUMN IF NOT EXISTS initial_balance_direction_egp TEXT DEFAULT 'CREDIT' CHECK (initial_balance_direction_egp IN ('DEBIT', 'CREDIT'));
ALTER TABLE public.shareholders ADD COLUMN IF NOT EXISTS initial_balance_direction_usd TEXT DEFAULT 'CREDIT' CHECK (initial_balance_direction_usd IN ('DEBIT', 'CREDIT'));
ALTER TABLE public.shareholders ADD COLUMN IF NOT EXISTS initial_balance_direction_eur TEXT DEFAULT 'CREDIT' CHECK (initial_balance_direction_eur IN ('DEBIT', 'CREDIT'));
ALTER TABLE public.shareholders ADD COLUMN IF NOT EXISTS initial_balance_direction_gbp TEXT DEFAULT 'CREDIT' CHECK (initial_balance_direction_gbp IN ('DEBIT', 'CREDIT'));

-- 2. Backfill: Copy old single direction to all 4 new columns
UPDATE public.shareholders SET
  initial_balance_direction_egp = COALESCE(initial_balance_direction, 'CREDIT'),
  initial_balance_direction_usd = COALESCE(initial_balance_direction, 'CREDIT'),
  initial_balance_direction_eur = COALESCE(initial_balance_direction, 'CREDIT'),
  initial_balance_direction_gbp = COALESCE(initial_balance_direction, 'CREDIT');

-- 3. Rewrite sync_entity_opening_balance_gl to use per-currency directions for shareholders
CREATE OR REPLACE FUNCTION public.sync_entity_opening_balance_gl()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_new_balance NUMERIC;
    v_direction TEXT;
    v_currency TEXT;
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

    SELECT id INTO v_equity_account_id
    FROM accounts
    WHERE account_code::text = '3000' AND company_id = v_company_id
    LIMIT 1;

    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id
        FROM accounts
        WHERE account_code::text = '3000'
        LIMIT 1;
    END IF;
    
    IF v_equity_account_id IS NULL THEN
        RETURN NEW;
    END IF;

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

        -- EGP (uses its own direction)
        IF COALESCE(NEW.initial_balance_egp, 0) != 0 THEN
            v_new_balance := COALESCE(NEW.initial_balance_egp, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_egp, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'EGP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, 'EGP', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

        -- USD (uses its own direction)
        IF COALESCE(NEW.initial_balance_usd, 0) != 0 THEN
            v_new_balance := COALESCE(NEW.initial_balance_usd, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_usd, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'USD', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, 'USD', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'USD', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, 'USD', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

        -- EUR (uses its own direction)
        IF COALESCE(NEW.initial_balance_eur, 0) != 0 THEN
            v_new_balance := COALESCE(NEW.initial_balance_eur, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_eur, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'EUR', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, 'EUR', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'EUR', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, 'EUR', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

        -- GBP (uses its own direction)
        IF COALESCE(NEW.initial_balance_gbp, 0) != 0 THEN
            v_new_balance := COALESCE(NEW.initial_balance_gbp, 0);
            v_direction := COALESCE(NEW.initial_balance_direction_gbp, 'CREDIT');
            IF v_direction = 'DEBIT' THEN
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, v_new_balance, 0, 'GBP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, 0, v_new_balance, 'GBP', v_new_balance, v_desc, v_company_id);
            ELSE
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_account_id, 0, v_new_balance, 'GBP', v_new_balance, v_desc, v_company_id);
                INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                VALUES (v_je_id, v_equity_account_id, v_new_balance, 0, 'GBP', v_new_balance, v_desc, v_company_id);
            END IF;
        END IF;

    ELSE
        -- Other entities (suppliers, customers, etc.) — unchanged
        v_direction := NEW.initial_balance_direction;
        v_currency := COALESCE(row_to_json(NEW)->>'currency', 'EGP');
        v_new_balance := COALESCE(NEW.initial_balance, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(NEW.name, '');
        
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

-- 4. Recreate trigger to include per-currency direction columns
DROP TRIGGER IF EXISTS trg_shareholder_opening_balance_gl ON public.shareholders;
CREATE TRIGGER trg_shareholder_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance_egp, initial_balance_usd, initial_balance_eur, initial_balance_gbp, initial_balance_direction_egp, initial_balance_direction_usd, initial_balance_direction_eur, initial_balance_direction_gbp, account_id
ON public.shareholders
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

-- 5. Force re-fire for existing shareholders with non-zero balances
UPDATE public.shareholders SET initial_balance_egp = initial_balance_egp 
WHERE COALESCE(initial_balance_egp, 0) != 0 
   OR COALESCE(initial_balance_usd, 0) != 0 
   OR COALESCE(initial_balance_eur, 0) != 0 
   OR COALESCE(initial_balance_gbp, 0) != 0;

COMMIT;
