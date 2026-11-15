-- ============================================================================
-- Migration: Complete Double-Entry GL Integration for Shareholder Profit Distribution
-- Ensures all profit distributions post double-entry journal entries directly
-- to Level 5 Shareholder Current Accounts (Group 232: 23211, 23212, 23213)
-- and Retained Earnings / Current Year Profit (23511 / 23411).
-- ============================================================================

-- 0. Ensure account_ledger_entries columns exist
ALTER TABLE IF EXISTS public.account_ledger_entries 
    ADD COLUMN IF NOT EXISTS cost_center_id TEXT,
    ADD COLUMN IF NOT EXISTS entity_type TEXT,
    ADD COLUMN IF NOT EXISTS entity_id TEXT;

CREATE INDEX IF NOT EXISTS idx_ale_entity ON public.account_ledger_entries(entity_type, entity_id);

-- 1. Ensure journal_entry_id column exists in shareholder_profit_distributions
ALTER TABLE public.shareholder_profit_distributions
ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_spd_journal_entry_id ON public.shareholder_profit_distributions(journal_entry_id);

-- 2. Update post_journal_entry to persist entity_type and entity_id into account_ledger_entries
CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type   TEXT,
    p_description   TEXT,
    p_entry_date    DATE,
    p_company_id    UUID,
    p_created_by    UUID,
    p_lines         JSONB,
    p_source_id     TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_je_id         BIGINT;
    v_entry_number  TEXT;
    v_total_debit   NUMERIC := 0;
    v_total_credit  NUMERIC := 0;
    v_line          JSONB;
    v_account_id    BIGINT;
    v_debit         NUMERIC;
    v_credit        NUMERIC;
    v_base_debit    NUMERIC;
    v_base_credit   NUMERIC;
    v_currency      TEXT;
    v_desc          TEXT;
    v_actual_date   DATE;
    v_base_amount   NUMERIC;
    v_is_leaf       BOOLEAN;
    v_acct_code     TEXT;
    v_entity_type   TEXT;
    v_entity_id     TEXT;
BEGIN
    -- Auto-provision or resolve company_id
    IF p_company_id IS NULL THEN
        SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    END IF;

    IF p_company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE id = p_company_id) THEN
        BEGIN
            INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)
            VALUES (p_company_id, 'شركة النظام', true, now(), now())
            ON CONFLICT (id) DO UPDATE SET 
                is_active = true,
                updated_at = now();
        EXCEPTION WHEN OTHERS THEN
            SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
        END;
    END IF;

    IF p_company_id IS NULL THEN
        INSERT INTO public.sys_companies (name, is_active, created_at, updated_at)
        VALUES ('الشركة الافتراضية', true, now(), now())
        RETURNING id INTO p_company_id;
    END IF;

    -- Timezone safeguard: Cairo local date
    v_actual_date := COALESCE(p_entry_date, (NOW() AT TIME ZONE 'Africa/Cairo')::DATE);
    IF p_entry_date = CURRENT_DATE AND (NOW() AT TIME ZONE 'Africa/Cairo')::DATE != CURRENT_DATE THEN
        v_actual_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;
    END IF;

    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, created_by, company_id
    ) VALUES (
        v_entry_number, v_actual_date, p_description, 'posted',
        true, p_source_type, p_source_id, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit:= COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);
        v_entity_type:= v_line->>'entity_type';
        v_entity_id  := v_line->>'entity_id';

        SELECT a.is_leaf, a.account_code INTO v_is_leaf, v_acct_code
        FROM public.accounts a WHERE a.id = v_account_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        IF v_is_leaf IS NOT TRUE THEN
            RAISE EXCEPTION 'Account % (ID: %) is a control/header account and cannot be posted to. Only Level 5 posting accounts (is_leaf = true) are allowed.', v_acct_code, v_account_id;
        END IF;

        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'Single line cannot have both debit and credit';
        END IF;

        IF v_debit = 0 AND v_credit = 0 THEN
            CONTINUE;
        END IF;

        v_total_debit  := v_total_debit + v_base_debit;
        v_total_credit := v_total_credit + v_base_credit;
        v_base_amount  := CASE WHEN v_debit > 0 THEN v_base_debit ELSE v_base_credit END;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id,
            entity_type, entity_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, v_base_amount, v_desc, p_company_id,
            v_entity_type, v_entity_id
        );
    END LOOP;

    IF ABS(v_total_debit - v_total_credit) > 0.05 THEN
        RAISE EXCEPTION 'Journal entry unbalanced in base currency: Total Base Debit = %, Total Base Credit = %', v_total_debit, v_total_credit;
    END IF;

    RETURN v_je_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;

-- 3. Canonical distribute_shipment_profit with full Double-Entry GL Integration
CREATE OR REPLACE FUNCTION public.distribute_shipment_profit(p_shipment_id_str text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_shipment_id BIGINT;
  v_company_id UUID;
  v_shipment_no TEXT;
  v_shipment_profit NUMERIC;
  
  v_new_distributions JSONB := '[]'::jsonb;
  
  -- Settings
  v_settings JSONB;
  v_shipment_pcts JSONB;
  v_conv JSONB;
  v_p4_map JSONB;
  
  -- Iteration
  v_dist_idx INT;
  v_person_id UUID;
  v_pct NUMERIC;
  v_share NUMERIC;
  v_rate NUMERIC;
  v_final_currency TEXT;
  v_final_amount NUMERIC;
  v_sh_name TEXT;
  
  -- Journal Entry
  v_je_lines JSONB := '[]'::jsonb;
  v_desc TEXT;
  v_debit_acct BIGINT;
  v_shareholder_acct BIGINT;
  v_je_id BIGINT;
  v_total_base NUMERIC := 0;
  
  -- Old data
  v_old_dist RECORD;
  v_old_je_id BIGINT;
  v_set_rec RECORD;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- ── STEP 1: VALIDATION & DATA FETCH ──
  SELECT s.shipment_no, s.net_profit_egp, 
         COALESCE(s.company_id, (SELECT id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1))
  INTO v_shipment_no, v_shipment_profit, v_company_id
  FROM public.export_shipments s
  WHERE s.id = v_shipment_id;

  IF v_shipment_no IS NULL THEN
    RAISE EXCEPTION 'الشحنة رقم % غير موجودة.', p_shipment_id_str;
  END IF;

  IF v_shipment_profit IS NULL OR v_shipment_profit = 0 THEN
    RAISE EXCEPTION 'لا يوجد أرباح مسجلة لهذه الشحنة لتوزيعها.';
  END IF;

  -- Resolve Debit Account (Current Year Profit 23511 or Retained Earnings 23411)
  SELECT id INTO v_debit_acct 
  FROM public.accounts 
  WHERE account_code = '23511' AND is_leaf = true LIMIT 1;

  IF v_debit_acct IS NULL THEN
    SELECT id INTO v_debit_acct 
    FROM public.accounts 
    WHERE account_code = '23411' AND is_leaf = true LIMIT 1;
  END IF;

  IF v_debit_acct IS NULL THEN
    SELECT id INTO v_debit_acct 
    FROM public.accounts 
    WHERE account_code IN ('23421', '23111') AND is_leaf = true LIMIT 1;
  END IF;

  IF v_debit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب توزيع الأرباح (23511 أو 23411) غير موجود في شجرة الحسابات.';
  END IF;

  SELECT * INTO v_set_rec FROM public.profit_distribution_settings LIMIT 1;
  IF v_set_rec IS NULL THEN
    RAISE EXCEPTION 'إعدادات التوزيع غير موجودة أو غير مفعلة.';
  END IF;

  v_settings := v_set_rec.percentages;
  v_p4_map := v_set_rec.person4_for_shipment;
  v_conv := v_set_rec.currency_conversions;

  v_desc := 'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no;

  -- Compute distributions
  IF v_settings IS NOT NULL AND jsonb_typeof(v_settings) = 'object' THEN
    v_shipment_pcts := v_settings -> p_shipment_id_str;
  END IF;

  -- Fallback: if no specific percentages set for this shipment, use default equal split
  IF v_shipment_pcts IS NULL OR jsonb_array_length(v_shipment_pcts) = 0 THEN
    v_shipment_pcts := '[33.33, 33.33, 33.34, 0.0]'::jsonb;
  END IF;

  IF v_conv IS NULL OR jsonb_typeof(v_conv) != 'object' THEN
    v_conv := '{}'::jsonb;
  END IF;
  IF v_conv -> p_shipment_id_str IS NOT NULL THEN
    v_conv := v_conv -> p_shipment_id_str;
  ELSE
    v_conv := '{}'::jsonb;
  END IF;

  IF v_p4_map IS NULL OR jsonb_typeof(v_p4_map) != 'object' THEN
    v_p4_map := '{}'::jsonb;
  END IF;

  -- Calculate distributions for Person 1..3
  FOR v_i IN 1..3 LOOP
    IF v_i = 1 THEN v_person_id := v_set_rec.person1_id;
    ELSIF v_i = 2 THEN v_person_id := v_set_rec.person2_id;
    ELSIF v_i = 3 THEN v_person_id := v_set_rec.person3_id;
    END IF;

    v_pct := 0;
    IF v_shipment_pcts IS NOT NULL THEN
      v_pct := COALESCE((v_shipment_pcts ->> (v_i - 1))::NUMERIC, 0);
    END IF;

    CONTINUE WHEN v_pct IS NULL OR v_pct = 0 OR v_person_id IS NULL;

    v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);
    v_final_currency := COALESCE(NULLIF(v_conv -> (v_i - 1)::text ->> 'currency', ''), 'EGP');
    v_rate := COALESCE((v_conv -> (v_i - 1)::text ->> 'rate')::NUMERIC, 0);
    
    IF v_final_currency != 'EGP' AND v_rate > 0 THEN
      v_final_amount := ROUND(v_share / v_rate, 2);
    ELSE
      v_final_currency := 'EGP';
      v_final_amount := v_share;
    END IF;

    v_new_distributions := v_new_distributions || jsonb_build_object(
        'shareholder_id', v_person_id,
        'person_index', v_i - 1,
        'percentage', v_pct,
        'amount_egp', v_share,
        'currency', v_final_currency,
        'converted_amount', v_final_amount,
        'rate_to_egp', NULLIF(v_rate, 0)
    );
  END LOOP;

  -- Person 4 calculation
  BEGIN
    IF (v_p4_map ->> p_shipment_id_str) IS NOT NULL AND (v_p4_map ->> p_shipment_id_str) != '' THEN
      v_person_id := (v_p4_map ->> p_shipment_id_str)::UUID;
    ELSE
      v_person_id := NULL;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_person_id := NULL;
  END;

  IF v_person_id IS NOT NULL THEN
    v_pct := GREATEST(100
      - COALESCE((v_shipment_pcts ->> 0)::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> 1)::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> 2)::NUMERIC, 0), 0);

    IF v_pct > 0 THEN
      v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);
      v_final_currency := COALESCE(NULLIF(v_conv -> '3' ->> 'currency', ''), 'EGP');
      v_rate := COALESCE((v_conv -> '3' ->> 'rate')::NUMERIC, 0);
      
      IF v_final_currency != 'EGP' AND v_rate > 0 THEN
        v_final_amount := ROUND(v_share / v_rate, 2);
      ELSE
        v_final_currency := 'EGP';
        v_final_amount := v_share;
      END IF;

      v_new_distributions := v_new_distributions || jsonb_build_object(
          'shareholder_id', v_person_id,
          'person_index', 3,
          'percentage', v_pct,
          'amount_egp', v_share,
          'currency', v_final_currency,
          'converted_amount', v_final_amount,
          'rate_to_egp', NULLIF(v_rate, 0)
      );
    END IF;
  END IF;

  IF jsonb_array_length(v_new_distributions) = 0 THEN
    RAISE EXCEPTION 'لم يتم تعيين نسب للمساهمين لهذه الشحنة. تأكد من حفظ نسب التوزيع أولاً.';
  END IF;

  -- ── STEP 2: CLEAR OLD DISTRIBUTIONS & REVERT BALANCES / ENTRIES ──
  
  -- Revert / Delete previous journal entries for this shipment
  FOR v_old_je_id IN 
    SELECT id FROM public.journal_entries 
    WHERE source_type = 'profit_distribution' AND source_id = p_shipment_id_str
  LOOP
    DELETE FROM public.journal_entries WHERE id = v_old_je_id;
  END LOOP;

  -- Revert balances from old distribution records
  FOR v_old_dist IN 
      SELECT id, shareholder_id, converted_amount, currency 
      FROM public.shareholder_profit_distributions 
      WHERE shipment_id = v_shipment_id AND deleted_at IS NULL
  LOOP
      IF v_old_dist.currency = 'EGP' THEN 
        UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;
      ELSIF v_old_dist.currency = 'USD' THEN 
        UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;
      ELSIF v_old_dist.currency = 'EUR' THEN 
        UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;
      ELSIF v_old_dist.currency = 'GBP' THEN 
        UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id; 
      END IF;
  END LOOP;

  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;

  -- ── STEP 3: INSERT NEW DISTRIBUTIONS & CONSTRUCT GL LINES ──
  
  FOR v_dist_idx IN 0 .. jsonb_array_length(v_new_distributions) - 1 LOOP
    DECLARE
      v_d JSONB := v_new_distributions -> v_dist_idx;
      v_sh_id UUID := (v_d ->> 'shareholder_id')::UUID;
      v_curr TEXT := v_d ->> 'currency';
      v_c_amt NUMERIC := (v_d ->> 'converted_amount')::NUMERIC;
      v_amt_egp NUMERIC := (v_d ->> 'amount_egp')::NUMERIC;
      v_r NUMERIC := (v_d ->> 'rate_to_egp')::NUMERIC;
    BEGIN
      -- 1. Insert distribution row
      INSERT INTO public.shareholder_profit_distributions (
          shipment_id,
          shareholder_id,
          person_index,
          percentage,
          amount_egp,
          currency,
          converted_amount,
          rate_to_egp
      ) VALUES (
          v_shipment_id,
          v_sh_id,
          (v_d ->> 'person_index')::INT,
          (v_d ->> 'percentage')::NUMERIC,
          v_amt_egp,
          v_curr,
          v_c_amt,
          v_r
      );

      -- 2. Update shareholder balance
      IF v_curr = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_c_amt WHERE id = v_sh_id;
      ELSIF v_curr = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_c_amt WHERE id = v_sh_id;
      ELSIF v_curr = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_c_amt WHERE id = v_sh_id;
      ELSIF v_curr = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_c_amt WHERE id = v_sh_id; END IF;

      -- 3. Resolve Shareholder Level 5 Posting Account (Group 232: 23211, 23212, 23213)
      SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_sh_id;
      
      IF v_shareholder_acct IS NULL THEN
        SELECT a.id INTO v_shareholder_acct
        FROM public.accounts a
        JOIN public.shareholders s ON s.id = v_sh_id
        WHERE a.is_leaf = true
          AND (
            (s.name LIKE '%عماد%' AND a.account_code = '23211') OR
            (s.name LIKE '%عبدالباطن%' AND a.account_code = '23212') OR
            (s.name LIKE '%إسلام%' AND a.account_code = '23213') OR
            (s.name LIKE '%اسلام%' AND a.account_code = '23213') OR
            a.name = 'Shareholder - ' || s.name
          )
        LIMIT 1;
      END IF;

      IF v_shareholder_acct IS NULL THEN
        SELECT id INTO v_shareholder_acct FROM public.accounts WHERE account_code = '2321' LIMIT 1;
      END IF;

      v_sh_name := COALESCE((SELECT name FROM public.shareholders WHERE id = v_sh_id), 'مساهم');

      -- 4. Build Credit Line for Shareholder with entity_type & entity_id
      v_je_lines := v_je_lines || jsonb_build_object(
          'account_id', v_shareholder_acct,
          'debit', 0,
          'base_debit', 0,
          'credit', v_c_amt,
          'base_credit', v_amt_egp,
          'currency', v_curr,
          'entity_type', 'shareholder',
          'entity_id', v_sh_id::text,
          'description', 'توزيع أرباح شحنة ' || v_shipment_no || ' - نصيب ' || v_sh_name
      );

      v_total_base := v_total_base + v_amt_egp;
    END;
  END LOOP;

  -- ── STEP 4: ADD BALANCING DEBIT LINE & POST JOURNAL ENTRY ──
  
  -- Add DR Current Year Profit / Retained Earnings (23511 / 23411)
  v_je_lines := jsonb_build_array(
      jsonb_build_object(
          'account_id', v_debit_acct,
          'debit', v_total_base,
          'base_debit', v_total_base,
          'credit', 0,
          'base_credit', 0,
          'currency', 'EGP',
          'description', 'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no || ' على المساهمين'
      )
  ) || v_je_lines;

  -- Post double-entry journal entry via unified posting engine
  v_je_id := public.post_journal_entry(
      'profit_distribution',
      'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no,
      (NOW() AT TIME ZONE 'Africa/Cairo')::DATE,
      v_company_id,
      auth.uid(),
      v_je_lines,
      p_shipment_id_str
  );

  -- Link journal_entry_id to distributions
  UPDATE public.shareholder_profit_distributions
  SET journal_entry_id = v_je_id
  WHERE shipment_id = v_shipment_id;

  -- Mark shipment redistribution flag
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false
  WHERE id = v_shipment_id;

END;
$function$;

GRANT EXECUTE ON FUNCTION public.distribute_shipment_profit(text) TO authenticated, service_role, anon;

-- 4. Canonical undo_profit_distribution
CREATE OR REPLACE FUNCTION public.undo_profit_distribution(p_shipment_id_text text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_shipment_id BIGINT;
  v_dist RECORD;
  v_old_je_id BIGINT;
BEGIN
  v_shipment_id := p_shipment_id_text::BIGINT;

  -- 1. Delete associated journal entries
  FOR v_old_je_id IN
    SELECT id FROM public.journal_entries
    WHERE source_type = 'profit_distribution'
      AND source_id = p_shipment_id_text
  LOOP
    DELETE FROM public.journal_entries WHERE id = v_old_je_id;
  END LOOP;

  -- 2. Revert shareholder balances
  FOR v_dist IN
    SELECT * FROM public.shareholder_profit_distributions 
    WHERE shipment_id = v_shipment_id AND deleted_at IS NULL
  LOOP
    IF v_dist.currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    END IF;
  END LOOP;

  -- 3. Delete distributions
  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;

  -- 4. Update shipment flag
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false
  WHERE id = v_shipment_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.undo_profit_distribution(text) TO authenticated, service_role, anon;

-- 5. Canonical rpc_get_profit_distribution_journal_entries
CREATE OR REPLACE FUNCTION public.rpc_get_profit_distribution_journal_entries(p_shipment_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(je.* ORDER BY je.created_at DESC), '[]'::JSONB)
  INTO v_result
  FROM (
      SELECT 
          je.id,
          je.entry_number,
          je.entry_date AS transaction_date,
          je.description,
          je.source_type,
          je.source_id,
          je.status,
          je.created_at,
          (
              SELECT jsonb_agg(
                  jsonb_build_object(
                      'account_name', a.name,
                      'account_code', a.account_code,
                      'debit', ale.debit,
                      'credit', ale.credit,
                      'currency', ale.currency
                  )
              )
              FROM public.account_ledger_entries ale
              JOIN public.accounts a ON a.id = ale.account_id
              WHERE ale.journal_entry_id = je.id
                AND ale.deleted_at IS NULL
          ) as lines
      FROM public.journal_entries je
      WHERE (je.source_type = 'profit_distribution' OR je.source_type = 'profit_distribution_reversal')
        AND je.source_id = p_shipment_id::TEXT
        AND je.deleted_at IS NULL
  ) je;
  
  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_get_profit_distribution_journal_entries(bigint) TO authenticated, service_role, anon;

-- 6. Backfill existing distributed shipments (like Shipment 1) to create missing GL entries
DO $do$
DECLARE
  r_shipment RECORD;
BEGIN
  FOR r_shipment IN
    SELECT DISTINCT shipment_id
    FROM public.shareholder_profit_distributions
    WHERE deleted_at IS NULL
      AND (journal_entry_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.journal_entries WHERE id = journal_entry_id))
  LOOP
    BEGIN
      PERFORM public.distribute_shipment_profit(r_shipment.shipment_id::text);
      RAISE NOTICE 'Successfully generated GL journal entry for shipment %', r_shipment.shipment_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipped shipment % during GL backfill: %', r_shipment.shipment_id, SQLERRM;
    END;
  END LOOP;
END;
$do$;

NOTIFY pgrst, 'reload schema';