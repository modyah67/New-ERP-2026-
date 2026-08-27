-- ============================================================================
-- Migration 354: Add rpc_update_shareholder_initial_balance & Seed Shareholders
-- ============================================================================

BEGIN;

-- 1. Create or Replace rpc_update_shareholder_initial_balance
CREATE OR REPLACE FUNCTION public.rpc_update_shareholder_initial_balance(
    p_shareholder_id uuid,
    p_new_balance numeric,
    p_new_direction text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_sh RECORD;
    v_old_balance NUMERIC;
    v_old_direction TEXT;
    v_old_signed NUMERIC;
    v_new_signed NUMERIC;
    v_delta NUMERIC;
    v_account_id BIGINT;
    v_equity_account_id BIGINT;
    v_company_id UUID;
    v_je_id BIGINT;
    v_source_id TEXT;
    v_desc TEXT;
    v_entry_number TEXT;
    v_new_current NUMERIC;
BEGIN
    -- 1. Validation
    IF p_shareholder_id IS NULL THEN
        RAISE EXCEPTION 'معرف المساهم مطلوب.';
    END IF;

    IF p_new_balance IS NULL OR p_new_balance < 0 THEN
        RAISE EXCEPTION 'المبلغ غير صالح (يجب أن يكون أكبر من أو يساوي الصفر).';
    END IF;

    p_new_direction := UPPER(COALESCE(p_new_direction, 'CREDIT'));
    IF p_new_direction NOT IN ('DEBIT', 'CREDIT') THEN
        RAISE EXCEPTION 'اتجاه الرصيد يجب أن يكون مدين (DEBIT) أو دائن (CREDIT).';
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
    v_old_balance := COALESCE(v_sh.initial_balance_egp, 0);
    v_old_direction := UPPER(COALESCE(v_sh.initial_balance_direction_egp, 'CREDIT'));

    -- 3. Calculate Signed Delta: CREDIT is positive (+), DEBIT is negative (-)
    v_old_signed := CASE WHEN v_old_direction = 'DEBIT' THEN -v_old_balance ELSE v_old_balance END;
    v_new_signed := CASE WHEN p_new_direction = 'DEBIT' THEN -p_new_balance ELSE p_new_balance END;
    v_delta := v_new_signed - v_old_signed;

    -- 4. Update Shareholder record
    UPDATE public.shareholders
    SET initial_balance_egp = p_new_balance,
        initial_balance_direction_egp = p_new_direction,
        initial_balance = p_new_balance,
        initial_balance_direction = p_new_direction,
        current_balance_egp = COALESCE(current_balance_egp, 0) + v_delta
    WHERE id = p_shareholder_id
    RETURNING current_balance_egp INTO v_new_current;

    -- 5. Ensure Shareholder GL Account exists
    IF v_account_id IS NULL THEN
        SELECT id INTO v_account_id FROM public.accounts WHERE account_code = '310101' LIMIT 1;
        IF v_account_id IS NULL THEN
            SELECT id INTO v_account_id FROM public.accounts WHERE name LIKE '%' || v_sh.name || '%' LIMIT 1;
        END IF;
    END IF;

    -- 6. Resolve Opening Balance Equity Account (3901 for EGP)
    v_equity_account_id := public.resolve_opening_balance_equity_account('EGP', v_company_id);
    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id FROM public.accounts WHERE account_code = '3901' LIMIT 1;
    END IF;
    IF v_equity_account_id IS NULL THEN
        SELECT id INTO v_equity_account_id FROM public.accounts WHERE account_code = '3900' LIMIT 1;
    END IF;

    -- 7. Sync General Ledger (journal_entries & account_ledger_entries)
    v_source_id := 'shareholders_' || p_shareholder_id::text;
    v_desc := 'رصيد افتتاحي - ' || COALESCE(v_sh.name, '');

    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'opening_balance'
      AND (source_id = v_source_id OR source_id = p_shareholder_id::text)
      AND (company_id = v_company_id OR company_id IS NULL)
    ORDER BY id DESC
    LIMIT 1;

    IF p_new_balance = 0 THEN
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

        -- Insert Ledger Lines
        IF v_account_id IS NOT NULL AND v_equity_account_id IS NOT NULL THEN
            IF p_new_direction = 'DEBIT' THEN
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_je_id, v_account_id, p_new_balance, 0, 'EGP', p_new_balance, v_desc, v_company_id
                );
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_je_id, v_equity_account_id, 0, p_new_balance, 'EGP', p_new_balance, v_desc, v_company_id
                );
            ELSE -- CREDIT
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_je_id, v_account_id, 0, p_new_balance, 'EGP', p_new_balance, v_desc, v_company_id
                );
                INSERT INTO public.account_ledger_entries (
                    journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
                ) VALUES (
                    v_je_id, v_equity_account_id, p_new_balance, 0, 'EGP', p_new_balance, v_desc, v_company_id
                );
            END IF;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shareholder_id', p_shareholder_id,
        'old_balance', v_old_balance,
        'old_direction', v_old_direction,
        'new_balance', p_new_balance,
        'new_direction', p_new_direction,
        'delta', v_delta,
        'new_current_balance', v_new_current,
        'journal_entry_id', v_je_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_update_shareholder_initial_balance(uuid, numeric, text) TO authenticated, anon, service_role;

-- 2. Seed the 3 hardcoded shareholders if not existing
DO $$
DECLARE
  v_p1_id UUID;
  v_p2_id UUID;
  v_p3_id UUID;
  v_company_id UUID;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
    SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
  END IF;

  -- 1. إسلام
  IF NOT EXISTS (SELECT 1 FROM public.shareholders WHERE name = 'إسلام') THEN
    INSERT INTO public.shareholders (code, name, company_id, initial_balance_egp, current_balance_egp, initial_balance_direction_egp)
    VALUES ('00001', 'إسلام', v_company_id, 0, 0, 'CREDIT');
  END IF;

  -- 2. عبدالباطن
  IF NOT EXISTS (SELECT 1 FROM public.shareholders WHERE name = 'عبدالباطن') THEN
    INSERT INTO public.shareholders (code, name, company_id, initial_balance_egp, current_balance_egp, initial_balance_direction_egp)
    VALUES ('00002', 'عبدالباطن', v_company_id, 0, 0, 'CREDIT');
  END IF;

  -- 3. عماد
  IF NOT EXISTS (SELECT 1 FROM public.shareholders WHERE name = 'عماد') THEN
    INSERT INTO public.shareholders (code, name, company_id, initial_balance_egp, current_balance_egp, initial_balance_direction_egp)
    VALUES ('00003', 'عماد', v_company_id, 0, 0, 'CREDIT');
  END IF;

  -- Fetch their IDs
  SELECT id INTO v_p1_id FROM public.shareholders WHERE name = 'إسلام' LIMIT 1;
  SELECT id INTO v_p2_id FROM public.shareholders WHERE name = 'عبدالباطن' LIMIT 1;
  SELECT id INTO v_p3_id FROM public.shareholders WHERE name = 'عماد' LIMIT 1;

  -- 3. Ensure profit_distribution_settings default row exists
  IF EXISTS (SELECT 1 FROM public.profit_distribution_settings LIMIT 1) THEN
    UPDATE public.profit_distribution_settings
    SET person1_id = v_p1_id,
        person1_name = 'إسلام',
        person2_id = v_p2_id,
        person2_name = 'عبدالباطن',
        person3_id = v_p3_id,
        person3_name = 'عماد',
        updated_at = NOW()
    WHERE id = (SELECT id FROM public.profit_distribution_settings ORDER BY updated_at DESC LIMIT 1);
  ELSE
    INSERT INTO public.profit_distribution_settings (
      person1_id, person1_name,
      person2_id, person2_name,
      person3_id, person3_name,
      percentages, person4_for_shipment, currency_conversions,
      user_id
    ) VALUES (
      v_p1_id, 'إسلام',
      v_p2_id, 'عبدالباطن',
      v_p3_id, 'عماد',
      '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
      COALESCE((SELECT id FROM auth.users LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)
    );
  END IF;

END $$;

COMMIT;
