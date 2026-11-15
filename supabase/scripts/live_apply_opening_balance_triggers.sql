-- ============================================================================
-- LIVE DEPLOYMENT: Synchronize Entity Opening Balance GL & 6 Triggers
-- Target: Live Production Database (rakdzuvlauphupkywoik.supabase.co)
-- ============================================================================

-- 1. Main Function
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
    v_source_id TEXT;
    v_entry_number TEXT;
    v_new_json JSONB;
    v_old_json JSONB;
    v_is_multi BOOLEAN := false;
    v_balances_map JSONB := NULL;
    r_key TEXT;
    r_item JSONB;
    r_cur TEXT;
    r_amt NUMERIC;
    r_dir TEXT;
    r_rate NUMERIC;
    r_base_amt NUMERIC;
    r_has_entries BOOLEAN := false;
    v_base_balance NUMERIC;
BEGIN
    v_new_json := to_jsonb(NEW);
    IF TG_OP = 'UPDATE' THEN
        v_old_json := to_jsonb(OLD);
    END IF;

    -- Check if initial_balance or direction or multi-currency map changed on UPDATE
    IF TG_OP = 'UPDATE' THEN
        IF TG_TABLE_NAME = 'shareholders' THEN
            IF (v_new_json->>'initial_balance_egp') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_egp') 
               AND (v_new_json->>'initial_balance_usd') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_usd')
               AND (v_new_json->>'initial_balance_eur') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_eur')
               AND (v_new_json->>'initial_balance_gbp') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_gbp')
               AND (v_new_json->>'initial_balance_direction') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction')
               AND (v_new_json->>'initial_balance_direction_egp') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction_egp')
               AND (v_new_json->>'account_id') IS NOT DISTINCT FROM (v_old_json->>'account_id') THEN
                RETURN NEW;
            END IF;
        ELSIF TG_TABLE_NAME = 'suppliers' THEN
            IF (v_new_json->>'initial_balance') IS NOT DISTINCT FROM (v_old_json->>'initial_balance') 
               AND (v_new_json->>'initial_balance_direction') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction')
               AND (v_new_json->'initial_balances_by_currency') IS NOT DISTINCT FROM (v_old_json->'initial_balances_by_currency')
               AND (v_new_json->>'account_id') IS NOT DISTINCT FROM (v_old_json->>'account_id') THEN
                RETURN NEW;
            END IF;
        ELSE
            IF (v_new_json->>'initial_balance') IS NOT DISTINCT FROM (v_old_json->>'initial_balance') 
               AND (v_new_json->>'initial_balance_direction') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction')
               AND (v_new_json->>'account_id') IS NOT DISTINCT FROM (v_old_json->>'account_id') THEN
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    -- Extract balance & description by table
    IF TG_TABLE_NAME = 'shareholders' THEN
        v_new_balance := COALESCE((v_new_json->>'initial_balance_egp')::numeric, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');
    ELSIF TG_TABLE_NAME = 'customers' THEN
        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');
    ELSIF TG_TABLE_NAME = 'clearing_agents' THEN
        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');
    ELSIF TG_TABLE_NAME = 'shipping_companies' THEN
        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');
    ELSIF TG_TABLE_NAME = 'transport_suppliers' THEN
        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');
    ELSE
        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);
        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');
    END IF;

    IF (v_new_json->>'account_id') IS NOT NULL THEN
        v_account_id := (v_new_json->>'account_id')::bigint;
    END IF;
    IF (v_new_json->>'company_id') IS NOT NULL THEN
        v_company_id := (v_new_json->>'company_id')::uuid;
    END IF;
    
    -- Direction default
    IF TG_TABLE_NAME = 'customers' THEN
        v_direction := COALESCE(v_new_json->>'initial_balance_direction', 'DEBIT');
    ELSIF TG_TABLE_NAME = 'shareholders' THEN
        v_direction := COALESCE(v_new_json->>'initial_balance_direction_egp', v_new_json->>'initial_balance_direction', 'CREDIT');
    ELSE
        v_direction := COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT');
    END IF;
    
    -- Extract currency
    v_currency := UPPER(COALESCE(v_new_json->>'currency', 'EGP'));
    IF v_currency = '' OR v_currency = 'MULTI' THEN
        v_currency := 'EGP';
    END IF;

    -- Resolve account_id if missing
    IF v_account_id IS NULL THEN
        IF TG_TABLE_NAME = 'customers' THEN
            SELECT id INTO v_account_id FROM accounts 
            WHERE (
                (COALESCE(v_new_json->>'company_type', v_new_json->>'customer_type', 'export') IN ('local', 'محلي', 'local_customer', 'عملاء محلي') AND account_code = '12512')
                OR (COALESCE(v_new_json->>'company_type', v_new_json->>'customer_type', 'export') NOT IN ('local', 'محلي', 'local_customer', 'عملاء محلي') AND account_code = '12511')
                OR account_code IN ('12511', '12512', '1251')
            )
              AND (company_id = v_company_id OR company_id IS NULL) 
            ORDER BY (company_id = v_company_id) DESC, id ASC 
            LIMIT 1;
        ELSIF TG_TABLE_NAME = 'suppliers' THEN
            SELECT id INTO v_account_id FROM accounts 
            WHERE (account_code = '2111' || LPAD(COALESCE(v_new_json->>'code', v_new_json->>'supplier_code', '')::text, 2, '0') 
                OR account_code = '2111' || COALESCE(v_new_json->>'code', v_new_json->>'supplier_code', '')::text
                OR account_code = '2112' || LPAD(COALESCE(v_new_json->>'code', v_new_json->>'supplier_code', '')::text, 2, '0') 
                OR account_code = '2112' || COALESCE(v_new_json->>'code', v_new_json->>'supplier_code', '')::text
                OR account_code = '2000' || LPAD(COALESCE(v_new_json->>'code', v_new_json->>'supplier_code', '')::text, 2, '0')
                OR account_code = '2000' || COALESCE(v_new_json->>'code', v_new_json->>'supplier_code', '')::text)
              AND (company_id = v_company_id OR company_id IS NULL) 
            ORDER BY (company_id = v_company_id) DESC, id ASC 
            LIMIT 1;
        ELSIF TG_TABLE_NAME = 'clearing_agents' THEN
            SELECT id INTO v_account_id FROM accounts 
            WHERE (account_code = '21116'
                OR account_code = '2114' || LPAD(COALESCE(v_new_json->>'code', '')::text, 2, '0') 
                OR account_code = '2114' || COALESCE(v_new_json->>'code', '')::text
                OR account_code = '2104' || LPAD(COALESCE(v_new_json->>'code', '')::text, 2, '0')
                OR account_code = '2104' || COALESCE(v_new_json->>'code', '')::text)
              AND (company_id = v_company_id OR company_id IS NULL) 
            ORDER BY (company_id = v_company_id) DESC, id ASC 
            LIMIT 1;
        ELSIF TG_TABLE_NAME = 'shipping_companies' THEN
            SELECT id INTO v_account_id FROM accounts 
            WHERE (account_code = '21115'
                OR account_code = '2113' || LPAD(COALESCE(v_new_json->>'code', '')::text, 2, '0') 
                OR account_code = '2113' || COALESCE(v_new_json->>'code', '')::text
                OR account_code = '2103' || LPAD(COALESCE(v_new_json->>'code', '')::text, 2, '0')
                OR account_code = '2103' || COALESCE(v_new_json->>'code', '')::text)
              AND (company_id = v_company_id OR company_id IS NULL) 
            ORDER BY (company_id = v_company_id) DESC, id ASC 
            LIMIT 1;
        ELSIF TG_TABLE_NAME = 'transport_suppliers' THEN
            SELECT id INTO v_account_id FROM accounts 
            WHERE (account_code = '21116'
                OR account_code = '2111' || LPAD(COALESCE(v_new_json->>'code', '')::text, 2, '0')
                OR account_code = '2111' || COALESCE(v_new_json->>'code', '')::text)
              AND (company_id = v_company_id OR company_id IS NULL) 
            ORDER BY (company_id = v_company_id) DESC, id ASC 
            LIMIT 1;
        END IF;
    END IF;

    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Unique source_id per table to prevent entity collision
    v_source_id := TG_TABLE_NAME || '_' || (v_new_json->>'id');

    -- Check for existing journal entry for this entity
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE source_type::text = 'opening_balance' 
      AND (source_id::text = v_source_id OR source_id::text = (v_new_json->>'id'))
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    -- Setup Multi-Currency branch (Suppliers or Shareholders)
    IF TG_TABLE_NAME = 'suppliers' THEN
        v_is_multi := COALESCE((v_new_json->>'is_multi_currency')::boolean, false);
        v_balances_map := v_new_json->'initial_balances_by_currency';
    ELSIF TG_TABLE_NAME = 'shareholders' THEN
        v_is_multi := true;
        v_balances_map := jsonb_build_object(
            'EGP', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_egp')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction_egp', v_new_json->>'initial_balance_direction', 'CREDIT')),
            'USD', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_usd')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT')),
            'EUR', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_eur')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT')),
            'GBP', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_gbp')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT'))
        );
    END IF;

    IF (TG_TABLE_NAME = 'suppliers' AND v_is_multi = true AND v_balances_map IS NOT NULL AND jsonb_typeof(v_balances_map) = 'object')
       OR (TG_TABLE_NAME = 'shareholders' AND v_balances_map IS NOT NULL) THEN
        
        -- Check if any balance is non-zero
        FOR r_key, r_item IN SELECT * FROM jsonb_each(v_balances_map) LOOP
            IF COALESCE((r_item->>'amount')::numeric, 0) > 0 THEN
                r_has_entries := true;
            END IF;
        END LOOP;

        IF NOT r_has_entries THEN
            IF v_je_id IS NOT NULL THEN
                DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
                DELETE FROM journal_entries WHERE id = v_je_id;
            END IF;
            RETURN NEW;
        END IF;

        IF v_je_id IS NOT NULL THEN
            DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
            UPDATE journal_entries 
            SET description = v_desc,
                source_id = v_source_id,
                entry_date = CURRENT_DATE,
                status = 'posted'
            WHERE id = v_je_id;
        ELSE
            -- Deterministic sequence without race conditions
            v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);
            IF v_entry_number IS NULL OR v_entry_number = '' THEN
                RAISE EXCEPTION 'Failed to generate entry_number via fn_get_next_sequence for opening_balance (company_id: %)', v_company_id;
            END IF;

            INSERT INTO journal_entries (
                source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
            ) VALUES (
                'opening_balance', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
            ) RETURNING id INTO v_je_id;
        END IF;

        -- Insert ledger entries for each currency with non-zero balance
        FOR r_key, r_item IN SELECT * FROM jsonb_each(v_balances_map) LOOP
            r_cur := UPPER(COALESCE(r_item->>'currency', r_key));
            r_amt := COALESCE((r_item->>'amount')::numeric, 0);
            r_dir := UPPER(COALESCE(r_item->>'direction', 'CREDIT'));
            
            -- Deterministic exchange rate lookup
            IF r_cur = 'EGP' THEN
                r_rate := 1.0;
            ELSE
                r_rate := COALESCE((r_item->>'exchange_rate')::numeric, NULL);
                IF r_rate IS NULL OR r_rate <= 0 THEN
                    SELECT rate_to_egp INTO r_rate 
                    FROM exchange_rates 
                    WHERE currency_code = r_cur 
                    ORDER BY effective_from DESC, updated_at DESC, id DESC 
                    LIMIT 1;
                END IF;
                IF r_rate IS NULL OR r_rate <= 0 THEN r_rate := 1.0; END IF;
            END IF;

            r_base_amt := r_amt * r_rate;

            IF r_amt > 0 THEN
                -- Resolve corresponding equity account
                v_equity_account_id := public.resolve_opening_balance_equity_account(r_cur, v_company_id);

                IF v_equity_account_id IS NULL THEN
                    SELECT id INTO v_equity_account_id
                    FROM accounts
                    WHERE account_code::text = ANY(
                        CASE r_cur
                            WHEN 'USD' THEN ARRAY['23421', '2332', '3902', '2312', '3002']
                            WHEN 'EUR' THEN ARRAY['23421', '2333', '3903', '2313', '3003']
                            WHEN 'GBP' THEN ARRAY['23421', '2334', '3904', '2314', '3004']
                            ELSE ARRAY['23421', '2331', '3901', '2311', '3001']
                        END
                    )
                    AND (company_id = v_company_id OR company_id IS NULL)
                    ORDER BY (company_id = v_company_id) DESC, id ASC
                    LIMIT 1;
                END IF;

                IF v_equity_account_id IS NULL THEN
                    SELECT id INTO v_equity_account_id
                    FROM accounts
                    WHERE account_code::text IN ('23421', '2342', '2330', '233', '2310', '231', '3900', '3901', '3001', '3000', '3300')
                      AND (company_id = v_company_id OR company_id IS NULL)
                    ORDER BY (company_id = v_company_id) DESC, id ASC
                    LIMIT 1;
                END IF;

                IF v_equity_account_id IS NULL THEN
                    SELECT id INTO v_equity_account_id
                    FROM accounts
                    WHERE account_type = 'equity' AND (allow_posting = true OR is_leaf = true)
                      AND (company_id = v_company_id OR company_id IS NULL)
                    ORDER BY (company_id = v_company_id) DESC, id ASC
                    LIMIT 1;
                END IF;

                -- Insert balanced double-entry lines
                IF v_account_id IS NOT NULL AND v_equity_account_id IS NOT NULL THEN
                    IF r_dir = 'DEBIT' THEN
                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                        VALUES (v_je_id, v_account_id, r_amt, 0, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);
                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                        VALUES (v_je_id, v_equity_account_id, 0, r_amt, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);
                    ELSE
                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                        VALUES (v_je_id, v_account_id, 0, r_amt, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);
                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)
                        VALUES (v_je_id, v_equity_account_id, r_amt, 0, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);
                    END IF;
                END IF;
            END IF;
        END LOOP;

        RETURN NEW;
    END IF;

    -- =========================================================================
    -- Standard single-currency path (Customers, Clearing, Shipping, Transport, Single-currency Suppliers)
    -- =========================================================================
    v_equity_account_id := public.resolve_opening_balance_equity_account(v_currency, v_company_id);

    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id
        FROM accounts
        WHERE account_code::text = ANY(
            CASE v_currency
                WHEN 'USD' THEN ARRAY['23421', '2332', '3902', '2312', '3002']
                WHEN 'EUR' THEN ARRAY['23421', '2333', '3903', '2313', '3003']
                WHEN 'GBP' THEN ARRAY['23421', '2334', '3904', '2314', '3004']
                ELSE ARRAY['23421', '2331', '3901', '2311', '3001']
            END
        )
        AND (company_id = v_company_id OR company_id IS NULL)
        ORDER BY (company_id = v_company_id) DESC, id ASC
        LIMIT 1;
    END IF;

    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id
        FROM accounts
        WHERE account_code::text IN ('23421', '2342', '2330', '233', '2310', '231', '3900', '3901', '3001', '3000', '3300')
          AND (company_id = v_company_id OR company_id IS NULL)
        ORDER BY (company_id = v_company_id) DESC, id ASC
        LIMIT 1;
    END IF;

    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id
        FROM accounts
        WHERE account_type = 'equity' AND (allow_posting = true OR is_leaf = true)
          AND (company_id = v_company_id OR company_id IS NULL)
        ORDER BY (company_id = v_company_id) DESC, id ASC
        LIMIT 1;
    END IF;
    
    IF v_equity_account_id IS NULL OR v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

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
        
        -- Deterministic sequence without race conditions
        v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);
        IF v_entry_number IS NULL OR v_entry_number = '' THEN
            RAISE EXCEPTION 'Failed to generate entry_number via fn_get_next_sequence for opening_balance (company_id: %)', v_company_id;
        END IF;

        INSERT INTO journal_entries (
            source_type, source_id, entry_date, description, created_by, company_id, entry_number, status
        ) VALUES (
            'opening_balance', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'
        ) RETURNING id INTO v_je_id;
    END IF;

    -- Calculate base currency balance using deterministic exchange rate
    r_rate := 1.0;
    IF v_currency IS NOT NULL AND v_currency <> 'EGP' THEN
        SELECT rate_to_egp INTO r_rate 
        FROM exchange_rates 
        WHERE currency_code = v_currency 
        ORDER BY effective_from DESC, updated_at DESC, id DESC 
        LIMIT 1;
        IF r_rate IS NULL OR r_rate <= 0 THEN r_rate := 1.0; END IF;
    END IF;
    v_base_balance := v_new_balance * r_rate;

    -- Create double-entry lines based strictly on chosen direction
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
$$;

-- 2. Triggers for all 6 Entities
DROP TRIGGER IF EXISTS trg_supplier_opening_balance_gl ON public.suppliers;
CREATE TRIGGER trg_supplier_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, initial_balances_by_currency, account_id
ON public.suppliers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_customer_opening_balance_gl ON public.customers;
CREATE TRIGGER trg_customer_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.customers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

-- ⚠️ ORDER-DEPENDENT: assumes trg_create_shareholder_account (alphabetically
-- earlier) fires first on the same AFTER INSERT event and populates account_id
-- via its own UPDATE, which re-triggers this trigger. Renaming either trigger
-- breaks this chain silently.
DROP TRIGGER IF EXISTS trg_shareholder_opening_balance_gl ON public.shareholders;
CREATE TRIGGER trg_shareholder_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance_egp, initial_balance_usd, initial_balance_eur, initial_balance_gbp, initial_balance_direction, initial_balance_direction_egp, account_id
ON public.shareholders
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_shipping_company_opening_balance_gl ON public.shipping_companies;
CREATE TRIGGER trg_shipping_company_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.shipping_companies
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_clearing_agent_opening_balance_gl ON public.clearing_agents;
CREATE TRIGGER trg_clearing_agent_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.clearing_agents
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();

DROP TRIGGER IF EXISTS trg_transport_supplier_opening_balance_gl ON public.transport_suppliers;
CREATE TRIGGER trg_transport_supplier_opening_balance_gl
AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id
ON public.transport_suppliers
FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();
