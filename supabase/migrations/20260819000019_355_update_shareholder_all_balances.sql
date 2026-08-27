-- ============================================================================
-- Migration 355: Add rpc_update_shareholder_all_balances
-- ============================================================================

BEGIN;

-- Drop the old RPC from 354 if it exists to avoid ambiguity
DROP FUNCTION IF EXISTS public.rpc_update_shareholder_initial_balance(uuid, numeric, text);

-- Create the multi-currency RPC
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
            v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);
            IF v_entry_number IS NULL OR v_entry_number = '' THEN
                v_entry_number := 'OB-' || LPAD((COALESCE((SELECT MAX(id) FROM public.journal_entries), 0) + 1)::text, 5, '0');
            END IF;

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

GRANT EXECUTE ON FUNCTION public.rpc_update_shareholder_all_balances(uuid, numeric, text, numeric, text, numeric, text, numeric, text) TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';

COMMIT;
