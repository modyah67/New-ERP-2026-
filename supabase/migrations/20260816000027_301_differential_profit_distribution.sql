-- Migration 301: Differential Profit Distribution
--
-- This migration completely changes how profit distribution and redistribution works.
-- Instead of deleting old distributions and reversing the entire journal entry, it:
-- 1. Calculates the DIFFERENCE between the old distribution amount and the new one.
-- 2. UPDATES the existing `shareholder_profit_distributions` row instead of creating a new one.
-- 3. Posts a SINGLE adjustment (تسوية) journal entry for the net differences.

CREATE OR REPLACE FUNCTION public.distribute_shipment_profit(
  p_shipment_id_str text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shipment_id BIGINT;
  v_company_id UUID;
  v_person_id UUID;
  v_pct NUMERIC;
  v_shipment_profit NUMERIC;
  v_revenue_egp NUMERIC;
  v_cost_egp NUMERIC;
  v_shipment_exchange_rate NUMERIC;
  v_share NUMERIC;
  v_settings RECORD;
  v_shipment_pcts jsonb;
  v_p4_map jsonb;
  v_conv jsonb;
  v_target_currency text;
  v_final_currency text;
  v_final_amount NUMERIC;
  v_rate NUMERIC;
  
  -- Audit and GL variables
  v_dist RECORD;
  v_retained_earnings_acct BIGINT;
  v_new_je_id BIGINT;
  v_je_lines JSONB := '[]'::JSONB;
  
  v_new_distributions JSONB := '[]'::JSONB;
  v_desc TEXT;
  v_dist_idx INT;
  v_shareholder_acct BIGINT;
  
  v_total_diff_base NUMERIC := 0;
  v_has_differences BOOLEAN := false;
  
  v_diff_amount NUMERIC;
  v_diff_conv NUMERIC;
  
  v_is_redistribution BOOLEAN := false;
  v_je_desc TEXT;
  
  v_old_amount NUMERIC;
  v_old_conv NUMERIC;
  v_old_currency TEXT;
  v_old_id UUID;
  v_found_old BOOLEAN;
  v_processed_old_ids UUID[] := '{}';
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;
  
  -- =========================================================================
  -- STEP 0: SMART COMPANY ID RESOLUTION
  -- =========================================================================
  SELECT company_id, id INTO v_company_id, v_retained_earnings_acct
  FROM public.accounts
  WHERE code = '3100'
  LIMIT 1;

  IF v_company_id IS NULL OR v_retained_earnings_acct IS NULL THEN
      RAISE EXCEPTION 'GL Account 3100 not found in database.';
  END IF;

  v_desc := 'توزيع أرباح شحنة تصدير رقم ' || p_shipment_id_str;

  -- Fetch shipment net profit
  SELECT net_profit_egp, total_revenue_egp, total_landed_cost, COALESCE(exchange_rate, 1.0)
  INTO v_shipment_profit, v_revenue_egp, v_cost_egp, v_shipment_exchange_rate
  FROM public.export_shipments
  WHERE id = v_shipment_id AND status != 'cancelled';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الشحنة غير موجودة أو أنها ملغاة.';
  END IF;

  -- If net_profit_egp is 0 or NULL, attempt on-the-fly calculation
  IF v_shipment_profit IS NULL OR v_shipment_profit <= 0 THEN
    v_shipment_profit := COALESCE(v_revenue_egp, 0) - COALESCE(v_cost_egp, 0);

    IF v_shipment_profit <= 0 THEN
      SELECT COALESCE(SUM(quantity * export_price_per_carton * v_shipment_exchange_rate), 0)
      INTO v_revenue_egp
      FROM public.export_shipment_items
      WHERE shipment_id = v_shipment_id;

      SELECT COALESCE(SUM(total_price), 0)
      INTO v_cost_egp
      FROM public.shipment_cost_items
      WHERE shipment_id = v_shipment_id;

      v_shipment_profit := COALESCE(v_revenue_egp, 0) - COALESCE(v_cost_egp, 0);
    END IF;

    IF v_shipment_profit != 0 THEN
      UPDATE public.export_shipments
      SET net_profit_egp = v_shipment_profit
      WHERE id = v_shipment_id;
    END IF;
  END IF;
  
  IF v_shipment_profit = 0 THEN
      RAISE EXCEPTION 'لا يوجد ربح لتوزيعه (صافي الربح = 0).';
  END IF;

  IF v_shipment_profit < 0 THEN
      v_desc := 'توزيع خسائر شحنة تصدير رقم ' || p_shipment_id_str;
  END IF;

  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'إعدادات التوزيع غير موجودة';
  END IF;

  -- =========================================================================
  -- STEP 1: CALCULATE TARGET DISTRIBUTIONS
  -- =========================================================================
  IF v_settings.percentages IS NOT NULL AND jsonb_typeof(v_settings.percentages) = 'object' THEN
    v_shipment_pcts := v_settings.percentages -> p_shipment_id_str;
  END IF;

  IF v_settings.person4_for_shipment IS NOT NULL AND jsonb_typeof(v_settings.person4_for_shipment) = 'object' THEN
    v_p4_map := v_settings.person4_for_shipment;
  ELSE
    v_p4_map := '{}'::jsonb;
  END IF;

  IF v_settings.currency_conversions IS NOT NULL AND jsonb_typeof(v_settings.currency_conversions) = 'object' THEN
    v_conv := v_settings.currency_conversions -> p_shipment_id_str;
  END IF;
  IF v_conv IS NULL THEN v_conv := '{}'::jsonb; END IF;

  FOR v_i IN 1..3 LOOP
    IF v_i = 1 THEN v_person_id := v_settings.person1_id;
    ELSIF v_i = 2 THEN v_person_id := v_settings.person2_id;
    ELSIF v_i = 3 THEN v_person_id := v_settings.person3_id;
    END IF;

    v_pct := 0;
    IF v_shipment_pcts IS NOT NULL THEN
      v_pct := COALESCE((v_shipment_pcts ->> (v_i - 1))::NUMERIC, 0);
    END IF;

    CONTINUE WHEN v_pct IS NULL OR v_pct = 0 OR v_person_id IS NULL;

    v_share := ROUND(v_shipment_profit * (v_pct / 100.0), 2);
    v_target_currency := v_conv -> (v_i - 1)::text ->> 'currency';
    v_rate := (v_conv -> (v_i - 1)::text ->> 'rate')::NUMERIC;
    
    IF v_target_currency IS NOT NULL AND v_target_currency != '' AND v_target_currency != 'EGP' AND v_rate IS NOT NULL AND v_rate > 0 THEN
      v_final_currency := v_target_currency;
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

  -- Person 4 safe block
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
      v_target_currency := v_conv -> '3' ->> 'currency';
      v_rate := (v_conv -> '3' ->> 'rate')::NUMERIC;
      
      IF v_target_currency IS NOT NULL AND v_target_currency != '' AND v_target_currency != 'EGP' AND v_rate IS NOT NULL AND v_rate > 0 THEN
        v_final_currency := v_target_currency;
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

  -- =========================================================================
  -- STEP 2: DIFFERENTIAL LOGIC & GL LINES
  -- =========================================================================
  -- Determine if it's redistribution
  IF EXISTS (SELECT 1 FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id AND deleted_at IS NULL) THEN
      v_is_redistribution := true;
      v_je_desc := 'تسوية أرباح شحنة رقم ' || p_shipment_id_str;
  ELSE
      v_is_redistribution := false;
      v_je_desc := v_desc;
  END IF;

  -- Iterate through TARGET distributions
  FOR v_dist_idx IN 0 .. jsonb_array_length(v_new_distributions) - 1 LOOP
      v_person_id := (v_new_distributions -> v_dist_idx ->> 'shareholder_id')::UUID;
      v_share := (v_new_distributions -> v_dist_idx ->> 'amount_egp')::NUMERIC;
      v_final_amount := (v_new_distributions -> v_dist_idx ->> 'converted_amount')::NUMERIC;
      v_final_currency := v_new_distributions -> v_dist_idx ->> 'currency';
      
      v_found_old := false;
      v_old_amount := 0;
      v_old_conv := 0;
      v_old_currency := v_final_currency;
      
      -- Find matching old distribution for this person
      SELECT id, amount_egp, converted_amount, currency INTO v_old_id, v_old_amount, v_old_conv, v_old_currency
      FROM public.shareholder_profit_distributions
      WHERE shipment_id = v_shipment_id AND shareholder_id = v_person_id AND deleted_at IS NULL
      LIMIT 1;

      IF FOUND THEN
          v_found_old := true;
          v_processed_old_ids := array_append(v_processed_old_ids, v_old_id);
      END IF;
      
      -- Calculate Differences (New - Old)
      v_diff_amount := v_share - COALESCE(v_old_amount, 0);
      v_diff_conv := v_final_amount - COALESCE(v_old_conv, 0);
      
      -- We must handle currency changes! If currency changed, we must fully reverse the old in its currency, and fully post new in its currency.
      IF v_found_old AND v_old_currency != v_final_currency THEN
          v_has_differences := true;
          SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_person_id;
          
          -- 1. Reverse old currency entirely
          v_je_lines := v_je_lines || jsonb_build_object(
              'account_id', v_shareholder_acct,
              'debit', v_old_conv, 'credit', 0,
              'base_debit', v_old_amount, 'base_credit', 0,
              'currency', v_old_currency,
              'amount_in_base_currency', v_old_amount,
              'description', v_je_desc || ' - إلغاء عملة مساهم'
          );
          v_total_diff_base := v_total_diff_base - v_old_amount;
          
          IF v_old_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_old_conv WHERE id = v_person_id;
          ELSIF v_old_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_old_conv WHERE id = v_person_id;
          ELSIF v_old_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_old_conv WHERE id = v_person_id;
          ELSIF v_old_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_old_conv WHERE id = v_person_id; END IF;

          -- 2. Post new currency entirely
          v_je_lines := v_je_lines || jsonb_build_object(
              'account_id', v_shareholder_acct,
              'debit', 0, 'credit', v_final_amount,
              'base_debit', 0, 'base_credit', v_share,
              'currency', v_final_currency,
              'amount_in_base_currency', v_share,
              'description', v_je_desc || ' - مساهم'
          );
          v_total_diff_base := v_total_diff_base + v_share;
          
          IF v_final_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
          ELSIF v_final_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
          ELSIF v_final_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
          ELSIF v_final_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id; END IF;

      ELSIF v_diff_amount != 0 THEN
          -- Normal difference update in same currency
          v_has_differences := true;
          SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_person_id;
          
          v_je_lines := v_je_lines || jsonb_build_object(
              'account_id', v_shareholder_acct,
              'debit', CASE WHEN v_diff_amount < 0 THEN ABS(v_diff_conv) ELSE 0 END,
              'credit', CASE WHEN v_diff_amount > 0 THEN v_diff_conv ELSE 0 END,
              'base_debit', CASE WHEN v_diff_amount < 0 THEN ABS(v_diff_amount) ELSE 0 END,
              'base_credit', CASE WHEN v_diff_amount > 0 THEN ABS(v_diff_amount) ELSE 0 END,
              'currency', v_final_currency,
              'amount_in_base_currency', ABS(v_diff_amount),
              'description', v_je_desc || ' - مساهم'
          );
          
          v_total_diff_base := v_total_diff_base + v_diff_amount;
          
          -- Update dual balances (adding positive difference or adding negative difference to reduce)
          IF v_final_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_diff_conv WHERE id = v_person_id;
          ELSIF v_final_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_diff_conv WHERE id = v_person_id;
          ELSIF v_final_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_diff_conv WHERE id = v_person_id;
          ELSIF v_final_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_diff_conv WHERE id = v_person_id; END IF;
      END IF;

      -- Update or Insert distribution DB row (NO NEW JOURNAL ENTRY ID GENERATED YET)
      IF v_found_old THEN
          -- Only update if there was an actual change in the numbers/currency
          IF v_diff_amount != 0 OR v_old_currency != v_final_currency THEN
              UPDATE public.shareholder_profit_distributions 
              SET amount_egp = v_share,
                  converted_amount = v_final_amount,
                  currency = v_final_currency,
                  percentage = (v_new_distributions -> v_dist_idx ->> 'percentage')::NUMERIC,
                  person_index = (v_new_distributions -> v_dist_idx ->> 'person_index')::INT,
                  rate_to_egp = (v_new_distributions -> v_dist_idx ->> 'rate_to_egp')::NUMERIC,
                  updated_at = NOW()
              WHERE id = v_old_id;
          END IF;
      ELSE
          -- Insert new distribution
          v_has_differences := true;
          INSERT INTO public.shareholder_profit_distributions (
            shipment_id, shareholder_id, person_index, percentage, amount_egp,
            currency, converted_amount, rate_to_egp, created_by
          ) VALUES (
            v_shipment_id, v_person_id, 
            (v_new_distributions -> v_dist_idx ->> 'person_index')::INT, 
            (v_new_distributions -> v_dist_idx ->> 'percentage')::NUMERIC, 
            v_share, v_final_currency, v_final_amount, 
            (v_new_distributions -> v_dist_idx ->> 'rate_to_egp')::NUMERIC, 
            auth.uid()
          );
      END IF;
  END LOOP;

  -- Handle shareholders that were removed (exist in old, not in new)
  FOR v_dist IN 
      SELECT id, shareholder_id, amount_egp, converted_amount, currency 
      FROM public.shareholder_profit_distributions 
      WHERE shipment_id = v_shipment_id AND deleted_at IS NULL AND NOT (id = ANY(v_processed_old_ids))
  LOOP
      v_has_differences := true;
      SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_dist.shareholder_id;
      
      -- Fully reverse this person's old balance
      v_je_lines := v_je_lines || jsonb_build_object(
          'account_id', v_shareholder_acct,
          'debit', v_dist.converted_amount, 'credit', 0,
          'base_debit', v_dist.amount_egp, 'base_credit', 0,
          'currency', v_dist.currency,
          'amount_in_base_currency', v_dist.amount_egp,
          'description', v_je_desc || ' - إزالة مساهم'
      );
      
      v_total_diff_base := v_total_diff_base - v_dist.amount_egp;
      
      -- Remove from balances
      IF v_dist.currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
      ELSIF v_dist.currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
      ELSIF v_dist.currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
      ELSIF v_dist.currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id; END IF;

      -- Mark distribution as deleted
      UPDATE public.shareholder_profit_distributions SET deleted_at = NOW() WHERE id = v_dist.id;
  END LOOP;

  -- =========================================================================
  -- STEP 3: POST JOURNAL ENTRY FOR DIFFERENCES
  -- =========================================================================
  IF v_has_differences AND v_total_diff_base != 0 THEN
      -- Add Retained Earnings Line to balance the entry
      v_je_lines := jsonb_build_array(jsonb_build_object(
          'account_id', v_retained_earnings_acct,
          'debit', CASE WHEN v_total_diff_base > 0 THEN ABS(v_total_diff_base) ELSE 0 END,
          'credit', CASE WHEN v_total_diff_base < 0 THEN ABS(v_total_diff_base) ELSE 0 END,
          'base_debit', CASE WHEN v_total_diff_base > 0 THEN ABS(v_total_diff_base) ELSE 0 END,
          'base_credit', CASE WHEN v_total_diff_base < 0 THEN ABS(v_total_diff_base) ELSE 0 END,
          'currency', 'EGP',
          'amount_in_base_currency', ABS(v_total_diff_base),
          'description', v_je_desc
      )) || v_je_lines;

      -- Post the single GL Adjustment Entry
      v_new_je_id := public.post_journal_entry(
          'profit_distribution',
          v_je_desc,
          CURRENT_DATE,
          v_company_id,
          auth.uid(),
          v_je_lines,
          v_shipment_id::TEXT
      );

      -- Update distributions to associate with the LATEST journal entry that touched them
      UPDATE public.shareholder_profit_distributions
      SET journal_entry_id = v_new_je_id
      WHERE shipment_id = v_shipment_id AND deleted_at IS NULL;
  END IF;

  -- =========================================================================
  -- STEP 4: UPDATE SHIPMENT STATE
  -- =========================================================================
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false,
      profitability_snapshot = jsonb_build_object('fingerprint', public.get_shipment_profitability_fingerprint(v_shipment_id))
  WHERE id = v_shipment_id;

END;
$$;
