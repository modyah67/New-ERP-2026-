-- Migration: Fix profit distribution journal entry balancing
-- Description: Updates distribute_shipment_profit to pass base_debit and base_credit to post_journal_entry

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
  v_total_debit NUMERIC := 0;
  v_new_distributions JSONB := '[]'::JSONB;
  v_desc TEXT;
  v_dist_idx INT;
  v_shareholder_acct BIGINT;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;
  
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

  SELECT id INTO v_retained_earnings_acct FROM public.accounts WHERE account_code = '3100' LIMIT 1;
  
  IF v_retained_earnings_acct IS NULL THEN
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

      v_shipment_profit := v_revenue_egp - v_cost_egp;
    END IF;

    IF v_shipment_profit > 0 THEN
      UPDATE public.export_shipments
      SET net_profit_egp = v_shipment_profit
      WHERE id = v_shipment_id;
    END IF;
  END IF;

  IF v_shipment_profit IS NULL OR v_shipment_profit <= 0 THEN
    RAISE EXCEPTION 'لا يوجد أرباح مسجلة لهذه الشحنة (إجمالي الربح صفر أو بالسالب) أو أنها ملغاة.';
  END IF;

  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;
  IF v_settings IS NULL THEN
    RAISE EXCEPTION 'لم يتم إعداد إعدادات توزيع الأرباح.';
  END IF;

  -- =========================================================================
  -- STEP 1: REVERSE OLD DISTRIBUTIONS (AUDIT TRAIL)
  -- =========================================================================
  FOR v_dist IN SELECT * FROM public.shareholder_profit_distributions 
                WHERE shipment_id = v_shipment_id AND deleted_at IS NULL LOOP
    
    -- Reverse the Shareholder's Balance (Entity update)
    IF v_dist.currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    END IF;

    -- Reverse the GL Entry if it exists
    IF v_dist.journal_entry_id IS NOT NULL THEN
        v_reversal_je_id := public.post_journal_entry(
            'profit_distribution_reversal',
            'إلغاء وتعديل ' || v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'account_id', account_id,
                    'debit', credit,    
                    'credit', debit,
                    'base_debit', CASE WHEN debit = 0 THEN amount_in_base_currency ELSE 0 END,
                    'base_credit', CASE WHEN credit = 0 THEN amount_in_base_currency ELSE 0 END,
                    'currency', currency,
                    'amount_in_base_currency', amount_in_base_currency,
                    'description', description || ' (عكس)'
                )
             )
             FROM public.account_ledger_entries
             WHERE journal_entry_id = v_dist.journal_entry_id
               AND deleted_at IS NULL
            ),
            v_shipment_id::TEXT
        );
        
        -- Mark as deleted and link the reversal
        UPDATE public.shareholder_profit_distributions 
        SET deleted_at = NOW(), reversal_journal_entry_id = v_reversal_je_id
        WHERE id = v_dist.id;
    ELSE
        -- No GL entry existed (legacy data), just soft delete
        UPDATE public.shareholder_profit_distributions SET deleted_at = NOW() WHERE id = v_dist.id;
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

      -- Add Credit Line for Shareholder
      v_je_lines := v_je_lines || jsonb_build_object(
          'account_id', v_shareholder_acct,
          'debit', 0,
          'credit', v_final_amount,
          'base_debit', 0,
          'base_credit', v_share,
          'currency', v_final_currency,
          'amount_in_base_currency', v_share,
          'description', v_desc || ' - مساهم'
      );

      v_total_debit := v_total_debit + v_share;
  END LOOP;

  -- =========================================================================
  -- STEP 4: POST JOURNAL ENTRY & SAVE DISTRIBUTIONS
  -- =========================================================================
  IF v_total_debit > 0 THEN
      -- Add Debit Line for Retained Earnings (Profit Account)
      v_je_lines := jsonb_build_array(jsonb_build_object(
          'account_id', v_retained_earnings_acct,
          'debit', v_total_debit,
          'credit', 0,
          'base_debit', v_total_debit,
          'base_credit', 0,
          'currency', 'EGP',
          'amount_in_base_currency', v_total_debit,
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

END;
$$;

GRANT EXECUTE ON FUNCTION public.distribute_shipment_profit(TEXT) TO authenticated;
