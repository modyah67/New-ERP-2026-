-- Migration 299: Complete restoration and fix of distribute_shipment_profit
-- 
-- This migration fixes the schema mismatch error caused by migration 298.
-- Migration 298 assumed that profit_distribution_settings had a 'company_id' 
-- and a 'settings' jsonb column, which caused the RPC to fail silently and 
-- crash with: column "company_id" does not exist.
--
-- Here we RESTORE the original (and correct) distribution logic from 295 
-- that works perfectly with the real schema of profit_distribution_settings,
-- AND we apply the surgical fix for the "random company" bug (Retained Earnings
-- 3100 not found) by anchoring the company_id through the accounts table.
-- We also use the get_shipment_profitability_fingerprint introduced in 297.

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
  v_reversal_je_id BIGINT;
  v_new_je_id BIGINT;
  v_je_lines JSONB := '[]'::JSONB;
  v_total_distribution NUMERIC := 0;
  v_new_distributions JSONB := '[]'::JSONB;
  v_desc TEXT;
  v_dist_idx INT;
  v_shareholder_acct BIGINT;
  v_line_debit NUMERIC;
  v_line_credit NUMERIC;
  v_line_base_debit NUMERIC;
  v_line_base_credit NUMERIC;
  v_re_debit NUMERIC;
  v_re_credit NUMERIC;
  v_i INT;
  v_old_distribution_exists BOOLEAN;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;
  
  -- =========================================================================
  -- STEP 0: SMART COMPANY ID RESOLUTION
  -- =========================================================================
  -- Find the company that owns the Retained Earnings account to avoid picking
  -- a random company (like 'Main Company') when sys_companies has multiple rows.
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
  
  -- If we STILL have exactly 0, there is nothing to distribute
  IF v_shipment_profit = 0 THEN
      RETURN;
  END IF;

  IF v_shipment_profit < 0 THEN
      v_desc := 'توزيع خسائر شحنة تصدير رقم ' || p_shipment_id_str;
  END IF;

  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'إعدادات التوزيع غير موجودة';
  END IF;

  -- =========================================================================
  -- STEP 1: REVERSE EXISTING DISTRIBUTIONS (using dedicated function)
  -- =========================================================================
  FOR v_dist IN SELECT id, journal_entry_id, shareholder_id, amount_egp, currency, converted_amount
                FROM public.shareholder_profit_distributions
                WHERE shipment_id = v_shipment_id AND deleted_at IS NULL
  LOOP
    IF v_dist.journal_entry_id IS NOT NULL THEN
        -- Reverse the GL Entry using the DEDICATED reversal function
        v_reversal_je_id := public.reverse_profit_distribution_entry(
            v_dist.journal_entry_id, 
            auth.uid(), 
            CURRENT_DATE,
            'إلغاء ' || v_desc
        );
        -- Update the record to point to the reversal entry and soft-delete it
        UPDATE public.shareholder_profit_distributions 
        SET deleted_at = NOW(), reversal_journal_entry_id = v_reversal_je_id
        WHERE id = v_dist.id;
    ELSE
        -- No GL entry existed (legacy data), just soft delete
        UPDATE public.shareholder_profit_distributions SET deleted_at = NOW() WHERE id = v_dist.id;
    END IF;

    -- Reverse the shareholder balance that was added
    IF v_dist.currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - COALESCE(v_dist.converted_amount, v_dist.amount_egp, 0) WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - COALESCE(v_dist.converted_amount, 0) WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - COALESCE(v_dist.converted_amount, 0) WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - COALESCE(v_dist.converted_amount, 0) WHERE id = v_dist.shareholder_id;
    END IF;
  END LOOP;

  -- =========================================================================
  -- STEP 2: CALCULATE NEW DISTRIBUTIONS
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

  -- Gather distributions in JSON array for processing
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

  -- =========================================================================
  -- STEP 3: BUILD JOURNAL ENTRY LINES AND UPDATE ENTITIES
  -- =========================================================================
  
  FOR v_dist_idx IN 0 .. jsonb_array_length(v_new_distributions) - 1 LOOP
      v_person_id := (v_new_distributions -> v_dist_idx ->> 'shareholder_id')::UUID;
      v_share := (v_new_distributions -> v_dist_idx ->> 'amount_egp')::NUMERIC;
      v_final_amount := (v_new_distributions -> v_dist_idx ->> 'converted_amount')::NUMERIC;
      v_final_currency := v_new_distributions -> v_dist_idx ->> 'currency';

      -- Update Shareholder Balance (Dual Tracking)
      IF v_final_currency = 'EGP' THEN
        UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'USD' THEN
        UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'EUR' THEN
        UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
      ELSIF v_final_currency = 'GBP' THEN
        UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
      END IF;

      -- Resolve shareholder account
      SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_person_id;

      -- Set debit/credit values for the JE line depending on profit or loss
      IF v_share > 0 THEN
          v_line_debit := 0; v_line_credit := v_final_amount;
          v_line_base_debit := 0; v_line_base_credit := v_share;
      ELSE
          v_line_debit := ABS(v_final_amount); v_line_credit := 0;
          v_line_base_debit := ABS(v_share); v_line_base_credit := 0;
      END IF;

      -- Add Journal Line for Shareholder
      v_je_lines := v_je_lines || jsonb_build_object(
          'account_id', v_shareholder_acct,
          'debit', v_line_debit,
          'credit', v_line_credit,
          'base_debit', v_line_base_debit,
          'base_credit', v_line_base_credit,
          'currency', v_final_currency,
          'amount_in_base_currency', ABS(v_share),
          'description', v_desc || ' - مساهم'
      );

      v_total_distribution := v_total_distribution + v_share;
  END LOOP;

  -- =========================================================================
  -- STEP 4: POST JOURNAL ENTRY & SAVE DISTRIBUTIONS
  -- =========================================================================
  IF v_total_distribution != 0 THEN
      
      -- Set debit/credit values for retained earnings depending on profit or loss
      IF v_total_distribution > 0 THEN
          v_re_debit := v_total_distribution; v_re_credit := 0;
      ELSE
          v_re_debit := 0; v_re_credit := ABS(v_total_distribution);
      END IF;

      -- Add Retained Earnings Line
      v_je_lines := jsonb_build_array(jsonb_build_object(
          'account_id', v_retained_earnings_acct,
          'debit', v_re_debit,
          'credit', v_re_credit,
          'base_debit', v_re_debit,
          'base_credit', v_re_credit,
          'currency', 'EGP',
          'amount_in_base_currency', ABS(v_total_distribution),
          'description', v_desc
      )) || v_je_lines;

      -- Post the GL Entry
      v_new_je_id := public.post_journal_entry(
          'profit_distribution',
          v_desc,
          CURRENT_DATE,
          v_company_id,
          auth.uid(),
          v_je_lines,
          v_shipment_id::TEXT -- source_id
      );

      -- Save distributions with Journal Entry ID
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
            v_new_je_id
          );
      END LOOP;
  END IF;

  -- =========================================================================
  -- STEP 5: UPDATE SHIPMENT STATE (robust snapshot + reset redistribution flag)
  -- =========================================================================
 UPDATE public.export_shipments
SET needs_profit_redistribution = false,
    profitability_snapshot = jsonb_build_object('fingerprint', public.get_shipment_profitability_fingerprint(v_shipment_id))
WHERE id = v_shipment_id;

END;
$$;
