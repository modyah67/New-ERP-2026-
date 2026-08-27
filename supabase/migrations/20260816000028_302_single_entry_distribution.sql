-- Migration 302: Update existing profit distribution journal entry directly

BEGIN;

CREATE OR REPLACE FUNCTION public.distribute_shipment_profit(
  p_shipment_id_str TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shipment_id BIGINT;
  v_company_id UUID;
  v_shipment_no TEXT;
  v_shipment_profit NUMERIC;
  v_fingerprint TEXT;
  
  v_new_distributions JSONB := '[]'::jsonb;
  
  -- Settings
  v_settings JSONB;
  v_is_active BOOLEAN;
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
  
  -- Journal Entry
  v_je_lines JSONB := '[]'::jsonb;
  v_desc TEXT;
  v_retained_earnings_acct BIGINT;
  v_shareholder_acct BIGINT;
  v_je_id BIGINT;
  v_total_base NUMERIC := 0;
  
  -- Old data
  v_old_dist RECORD;
  v_old_je_id BIGINT;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- =========================================================================
  -- STEP 1: VALIDATION & DATA FETCH
  -- =========================================================================
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

  SELECT shipment_no, net_profit_egp
  INTO v_shipment_no, v_shipment_profit
  FROM public.export_shipments
  WHERE id = v_shipment_id;

  IF v_shipment_no IS NULL THEN
    RAISE EXCEPTION 'Shipment % not found', p_shipment_id_str;
  END IF;

  IF v_shipment_profit IS NULL OR v_shipment_profit = 0 THEN
    RAISE EXCEPTION 'لا يوجد أرباح لهذه الشحنة لتوزيعها.';
  END IF;

  v_desc := 'توزيع أرباح شحنة تصدير رقم ' || v_shipment_no;

  -- Retained Earnings Account
  SELECT id INTO v_retained_earnings_acct FROM public.accounts WHERE account_code = '3100' AND company_id = v_company_id LIMIT 1;
  IF v_retained_earnings_acct IS NULL THEN
    RAISE EXCEPTION 'حساب الأرباح المحتجزة (3100) غير موجود.';
  END IF;

  -- Fetch Settings
  SELECT is_active, percentages, p4_shipment_map, currency_conversions, person1_id, person2_id, person3_id
  INTO v_is_active, v_settings, v_p4_map, v_conv, v_person_id, v_person_id, v_person_id -- dummy targets for person_id just to check if row exists
  FROM public.profit_distribution_settings
  WHERE company_id = v_company_id
  LIMIT 1;

  IF NOT FOUND OR v_is_active = false THEN
    RAISE EXCEPTION 'إعدادات التوزيع غير موجودة أو غير مفعلة.';
  END IF;

  -- Re-fetch settings properly into a record to access person1..3
  DECLARE
    v_set_rec RECORD;
  BEGIN
    SELECT * INTO v_set_rec FROM public.profit_distribution_settings WHERE company_id = v_company_id LIMIT 1;
    
    IF v_settings IS NOT NULL AND jsonb_typeof(v_settings) = 'object' THEN
      v_shipment_pcts := v_settings -> p_shipment_id_str;
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

    -- Calculate distributions
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

    -- Person 4
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
  END;

  IF jsonb_array_length(v_new_distributions) = 0 THEN
    RAISE EXCEPTION 'لم يتم تعيين نسب للمساهمين لهذه الشحنة. تأكد من حفظ نسب التوزيع أولاً.';
  END IF;

  -- =========================================================================
  -- STEP 2: CLEAR OLD DISTRIBUTIONS & REVERT BALANCES
  -- =========================================================================
  
  -- Find the existing journal entry ID for this shipment's distribution
  SELECT journal_entry_id INTO v_old_je_id 
  FROM public.shareholder_profit_distributions 
  WHERE shipment_id = v_shipment_id AND deleted_at IS NULL AND journal_entry_id IS NOT NULL 
  LIMIT 1;

  FOR v_old_dist IN 
      SELECT id, shareholder_id, converted_amount, currency 
      FROM public.shareholder_profit_distributions 
      WHERE shipment_id = v_shipment_id AND deleted_at IS NULL
  LOOP
      -- Revert balances
      IF v_old_dist.currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;
      ELSIF v_old_dist.currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;
      ELSIF v_old_dist.currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id;
      ELSIF v_old_dist.currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_old_dist.converted_amount WHERE id = v_old_dist.shareholder_id; END IF;
  END LOOP;

  -- Delete old distributions entirely (Hard delete to avoid clutter, or soft delete if preferred. We'll HARD DELETE to keep it perfectly clean as user requested "no new entries").
  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;

  -- =========================================================================
  -- STEP 3: INSERT NEW DISTRIBUTIONS & GL LINES
  -- =========================================================================
  
  FOR v_dist_idx IN 0 .. jsonb_array_length(v_new_distributions) - 1 LOOP
      v_person_id := (v_new_distributions -> v_dist_idx ->> 'shareholder_id')::UUID;
      v_share := (v_new_distributions -> v_dist_idx ->> 'amount_egp')::NUMERIC;
      v_final_amount := (v_new_distributions -> v_dist_idx ->> 'converted_amount')::NUMERIC;
      v_final_currency := v_new_distributions -> v_dist_idx ->> 'currency';

      -- Add balances
      IF v_final_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id; END IF;

      -- Create GL line for shareholder
      SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_person_id;
      
      v_je_lines := v_je_lines || jsonb_build_object(
          'account_id', v_shareholder_acct,
          'debit', 0, 'credit', v_final_amount,
          'base_debit', 0, 'base_credit', v_share,
          'currency', v_final_currency,
          'amount_in_base_currency', v_share,
          'description', v_desc || ' - مساهم'
      );
      
      v_total_base := v_total_base + v_share;
  END LOOP;

  -- Add Retained Earnings Line
  v_je_lines := jsonb_build_array(jsonb_build_object(
      'account_id', v_retained_earnings_acct,
      'debit', v_total_base, 'credit', 0,
      'base_debit', v_total_base, 'base_credit', 0,
      'currency', 'EGP',
      'amount_in_base_currency', v_total_base,
      'description', v_desc
  )) || v_je_lines;

  -- Post or Update Journal Entry
  IF v_old_je_id IS NOT NULL THEN
      -- UPDATE Existing Journal Entry
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_old_je_id;
      
      -- Re-insert ledger entries
      FOR v_dist_idx IN 0 .. jsonb_array_length(v_je_lines) - 1 LOOP
          INSERT INTO public.account_ledger_entries (
              journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id, created_at
          ) VALUES (
              v_old_je_id,
              (v_je_lines -> v_dist_idx ->> 'account_id')::BIGINT,
              (v_je_lines -> v_dist_idx ->> 'debit')::NUMERIC,
              (v_je_lines -> v_dist_idx ->> 'credit')::NUMERIC,
              v_je_lines -> v_dist_idx ->> 'currency',
              (v_je_lines -> v_dist_idx ->> 'amount_in_base_currency')::NUMERIC,
              v_je_lines -> v_dist_idx ->> 'description',
              v_company_id,
              NOW()
          );
      END LOOP;
      v_je_id := v_old_je_id;
  ELSE
      -- Create NEW Journal Entry
      v_je_id := public.post_journal_entry(
          'profit_distribution',
          v_desc,
          CURRENT_DATE,
          v_company_id,
          auth.uid(),
          v_je_lines,
          v_shipment_id::TEXT
      );
  END IF;

  -- Re-insert distributions with the je_id
  FOR v_dist_idx IN 0 .. jsonb_array_length(v_new_distributions) - 1 LOOP
      INSERT INTO public.shareholder_profit_distributions (
        shipment_id, shareholder_id, person_index, percentage, amount_egp,
        currency, converted_amount, rate_to_egp, created_by, journal_entry_id
      ) VALUES (
        v_shipment_id, 
        (v_new_distributions -> v_dist_idx ->> 'shareholder_id')::UUID, 
        (v_new_distributions -> v_dist_idx ->> 'person_index')::INT, 
        (v_new_distributions -> v_dist_idx ->> 'percentage')::NUMERIC, 
        (v_new_distributions -> v_dist_idx ->> 'amount_egp')::NUMERIC, 
        v_new_distributions -> v_dist_idx ->> 'currency', 
        (v_new_distributions -> v_dist_idx ->> 'converted_amount')::NUMERIC, 
        (v_new_distributions -> v_dist_idx ->> 'rate_to_egp')::NUMERIC, 
        auth.uid(),
        v_je_id
      );
  END LOOP;

  -- =========================================================================
  -- STEP 4: UPDATE SHIPMENT STATE
  -- =========================================================================
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false,
      profitability_snapshot = jsonb_build_object('fingerprint', public.get_shipment_profitability_fingerprint(v_shipment_id))
  WHERE id = v_shipment_id;

END;
$$;

COMMIT;
