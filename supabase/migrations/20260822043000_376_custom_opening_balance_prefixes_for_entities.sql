-- ============================================================================
-- Migration 376: Custom Opening Balance Prefixes for Specific Counterparties
-- ============================================================================
-- Prefixes:
--   Customers (العملاء)           → OB-CUS-
--   Suppliers (الموردون)          → OB-SUP-
--   Clearing Agents (المخلصون)   → OB-CLR-
--   Shipping Companies (شركات الشحن) → OB-SHP-
--   Shareholders (المساهمون)       → OB-SH-
-- ============================================================================

BEGIN;

-- 1. Update sync_entity_opening_balance_gl Trigger Function
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
    v_prefix TEXT;
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
        
        CASE TG_TABLE_NAME
            WHEN 'customers'          THEN v_prefix := 'OB-CUS-';
            WHEN 'suppliers'          THEN v_prefix := 'OB-SUP-';
            WHEN 'clearing_agents'    THEN v_prefix := 'OB-CLR-';
            WHEN 'shipping_companies' THEN v_prefix := 'OB-SHP-';
            ELSE v_prefix := 'OB-';
        END CASE;

        v_entry_number := v_prefix || LPAD((COALESCE((SELECT MAX(id) FROM journal_entries), 0) + 1)::text, 5, '0');

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

DROP TRIGGER IF EXISTS trg_customer_opening_balance_gl ON public.customers;
CREATE TRIGGER trg_customer_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, currency, account_id ON public.customers FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_supplier_opening_balance_gl ON public.suppliers;
CREATE TRIGGER trg_supplier_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, currency, account_id ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_clearing_agent_opening_balance_gl ON public.clearing_agents;
CREATE TRIGGER trg_clearing_agent_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, currency, account_id ON public.clearing_agents FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_shipping_company_opening_balance_gl ON public.shipping_companies;
CREATE TRIGGER trg_shipping_company_opening_balance_gl AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, currency, account_id ON public.shipping_companies FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

-- 2. Update rpc_update_shareholder_all_balances (Sets OB-SH- prefix)
CREATE OR REPLACE FUNCTION public.rpc_update_shareholder_all_balances(
    p_shareholder_id uuid,
    p_egp_bal numeric,
    p_egp_dir text,
    p_usd_bal numeric,
    p_usd_dir text,
    p_eur_bal numeric,
    p_eur_dir text,
    p_gbp_bal numeric,
    p_gbp_dir text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_sh RECORD;
    v_account_id BIGINT;
    v_company_id UUID;
    v_je_id BIGINT;
    v_source_id TEXT;
    v_desc TEXT;
    v_entry_number TEXT;
    
    -- Variables for looping/calculations
    v_currencies TEXT[] := ARRAY['EGP', 'USD', 'EUR', 'GBP'];
    v_new_balances NUMERIC[] := ARRAY[COALESCE(p_egp_bal, 0), COALESCE(p_usd_bal, 0), COALESCE(p_eur_bal, 0), COALESCE(p_gbp_bal, 0)];
    v_new_dirs TEXT[] := ARRAY[UPPER(COALESCE(p_egp_dir, 'CREDIT')), UPPER(COALESCE(p_usd_dir, 'CREDIT')), UPPER(COALESCE(p_eur_dir, 'CREDIT')), UPPER(COALESCE(p_gbp_dir, 'CREDIT'))];
    
    v_old_balances NUMERIC[];
    v_old_dirs TEXT[];
    
    v_old_signed NUMERIC;
    v_new_signed NUMERIC;
    v_delta NUMERIC;
    
    v_curr TEXT;
    v_new_bal NUMERIC;
    v_new_dir TEXT;
    
    v_equity_account_id BIGINT;
    v_base_amount NUMERIC;
    v_rate NUMERIC;
    
    v_i INT;
BEGIN
    -- 1. Validation
    IF p_shareholder_id IS NULL THEN
        RAISE EXCEPTION 'معرف المساهم مطلوب.';
    END IF;

    -- 2. Fetch shareholder record with row lock
    SELECT * INTO v_sh
    FROM public.shareholders
    WHERE id = p_shareholder_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'المساهم غير موجود.';
    END IF;

    v_account_id := v_sh.account_id;
    v_company_id := v_sh.company_id;
    
    v_old_balances := ARRAY[COALESCE(v_sh.initial_balance_egp, 0), COALESCE(v_sh.initial_balance_usd, 0), COALESCE(v_sh.initial_balance_eur, 0), COALESCE(v_sh.initial_balance_gbp, 0)];
    v_old_dirs := ARRAY[UPPER(COALESCE(v_sh.initial_balance_direction_egp, 'CREDIT')), UPPER(COALESCE(v_sh.initial_balance_direction_usd, 'CREDIT')), UPPER(COALESCE(v_sh.initial_balance_direction_eur, 'CREDIT')), UPPER(COALESCE(v_sh.initial_balance_direction_gbp, 'CREDIT'))];

    -- 3. Update Shareholder record
    -- Calculate Deltas and Update Currents
    FOR v_i IN 1..4 LOOP
        v_old_signed := CASE WHEN v_old_dirs[v_i] = 'DEBIT' THEN -v_old_balances[v_i] ELSE v_old_balances[v_i] END;
        v_new_signed := CASE WHEN v_new_dirs[v_i] = 'DEBIT' THEN -v_new_balances[v_i] ELSE v_new_balances[v_i] END;
        v_delta := v_new_signed - v_old_signed;
        
        IF v_i = 1 THEN
            UPDATE public.shareholders SET initial_balance_egp = v_new_balances[v_i], initial_balance_direction_egp = v_new_dirs[v_i], initial_balance = v_new_balances[v_i], initial_balance_direction = v_new_dirs[v_i], current_balance_egp = COALESCE(current_balance_egp, 0) + v_delta WHERE id = p_shareholder_id;
        ELSIF v_i = 2 THEN
            UPDATE public.shareholders SET initial_balance_usd = v_new_balances[v_i], initial_balance_direction_usd = v_new_dirs[v_i], current_balance_usd = COALESCE(current_balance_usd, 0) + v_delta WHERE id = p_shareholder_id;
        ELSIF v_i = 3 THEN
            UPDATE public.shareholders SET initial_balance_eur = v_new_balances[v_i], initial_balance_direction_eur = v_new_dirs[v_i], current_balance_eur = COALESCE(current_balance_eur, 0) + v_delta WHERE id = p_shareholder_id;
        ELSIF v_i = 4 THEN
            UPDATE public.shareholders SET initial_balance_gbp = v_new_balances[v_i], initial_balance_direction_gbp = v_new_dirs[v_i], current_balance_gbp = COALESCE(current_balance_gbp, 0) + v_delta WHERE id = p_shareholder_id;
        END IF;
    END LOOP;

    -- 4. Ensure Shareholder GL Account exists
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id FROM public.accounts WHERE account_code = '310101' LIMIT 1;
        IF v_account_id IS NULL THEN
            SELECT id INTO v_account_id FROM public.accounts WHERE name LIKE '%' || v_sh.name || '%' LIMIT 1;
        END IF;
    END IF;

    -- 5. Sync General Ledger (journal_entries & account_ledger_entries)
    v_source_id := 'shareholders_' || p_shareholder_id::text;
    v_desc := 'رصيد افتتاحي - ' || COALESCE(v_sh.name, '');

    -- Find existing journal entry
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'opening_balance'
      AND (source_id = v_source_id OR source_id = p_shareholder_id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    -- Check if any non-zero balance exists
    IF v_new_balances[1] = 0 AND v_new_balances[2] = 0 AND v_new_balances[3] = 0 AND v_new_balances[4] = 0 THEN
        IF v_je_id IS NOT NULL THEN
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
            DELETE FROM public.journal_entries WHERE id = v_je_id;
            v_je_id := NULL;
        END IF;
    ELSE
        IF v_je_id IS NOT NULL THEN
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
            UPDATE public.journal_entries
            SET description = v_desc,
                source_id = v_source_id,
                entry_date = CURRENT_DATE,
                status = 'posted'
            WHERE id = v_je_id;
        ELSE
            v_entry_number := 'OB-SH-' || LPAD((COALESCE((SELECT MAX(id) FROM public.journal_entries), 0) + 1)::text, 5, '0');

            INSERT INTO public.journal_entries (
                source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
            ) VALUES (
                'opening_balance', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
            ) RETURNING id INTO v_je_id;
        END IF;

        -- Insert Ledger Lines for each currency
        IF v_account_id IS NOT NULL THEN
            FOR v_i IN 1..4 LOOP
                v_curr := v_currencies[v_i];
                v_new_bal := v_new_balances[v_i];
                v_new_dir := v_new_dirs[v_i];
                
                IF v_new_bal > 0 THEN
                    -- Resolve Equity Account
                    v_equity_account_id := public.resolve_opening_balance_equity_account(v_curr, v_company_id);
                    IF v_equity_account_id IS NULL THEN
                        SELECT id INTO v_equity_account_id FROM public.accounts WHERE account_code = '3901' LIMIT 1;
                    END IF;
                    IF v_equity_account_id IS NULL THEN
                        SELECT id INTO v_equity_account_id FROM public.accounts WHERE account_code = '3900' LIMIT 1;
                    END IF;
                    
                    IF v_equity_account_id IS NOT NULL THEN
                        -- Handle Base Currency Amount
                        IF v_curr = 'EGP' THEN
                            v_rate := 1.0;
                        ELSE
                            v_rate := public.fn_get_exchange_rate(v_curr);
                        END IF;
                        v_base_amount := ROUND(v_new_bal * v_rate, 2);

                        IF v_new_dir = 'DEBIT' THEN
                            INSERT INTO public.account_ledger_entries (
                                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                            ) VALUES (
                                v_je_id, v_account_id, v_new_bal, 0, v_curr, v_base_amount, v_desc, v_company_id
                            );
                            INSERT INTO public.account_ledger_entries (
                                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                            ) VALUES (
                                v_je_id, v_equity_account_id, 0, v_new_bal, v_curr, v_base_amount, v_desc, v_company_id
                            );
                        ELSE -- CREDIT
                            INSERT INTO public.account_ledger_entries (
                                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                            ) VALUES (
                                v_je_id, v_account_id, 0, v_new_bal, v_curr, v_base_amount, v_desc, v_company_id
                            );
                            INSERT INTO public.account_ledger_entries (
                                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                            ) VALUES (
                                v_je_id, v_equity_account_id, v_new_bal, 0, v_curr, v_base_amount, v_desc, v_company_id
                            );
                        END IF;
                    END IF;
                END IF;
            END LOOP;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shareholder_id', p_shareholder_id,
        'journal_entry_id', v_je_id
    );
END;
$$;

-- 3. Update sync_shareholder_opening_balance_gl (Sets OB-SH- prefix)
CREATE OR REPLACE FUNCTION public.sync_shareholder_opening_balance_gl()
RETURNS TRIGGER AS $$
DECLARE
    v_equity_account_id BIGINT;
    v_je_id BIGINT;
    v_desc TEXT;
    v_account_id BIGINT;
    v_company_id UUID;
    v_new_balance NUMERIC;
    v_entry_number TEXT;
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
        v_entry_number := 'OB-SH-' || LPAD((COALESCE((SELECT MAX(id) FROM journal_entries), 0) + 1)::text, 5, '0');

        INSERT INTO journal_entries (
            entry_number, entry_date, description, status,
            is_auto_generated, source_type, source_id, created_by, company_id
        ) VALUES (
            v_entry_number,
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

GRANT EXECUTE ON FUNCTION public.rpc_update_shareholder_all_balances(uuid, numeric, text, numeric, text, numeric, text, numeric, text) TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';

COMMIT;
