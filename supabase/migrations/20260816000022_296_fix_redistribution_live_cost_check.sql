-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION 296: FIX PROFIT REDISTRIBUTION SNAPSHOT CHECK
-- ═══════════════════════════════════════════════════════════════════════════
-- This migration fixes the bug where check_profit_redistribution_needed
-- returns true unconditionally due to comparing the sum of shipment_cost_items
-- against the total_landed_cost (which includes crops & packing).
-- 
-- The fix:
-- 1. `distribute_shipment_profit` now saves `shipment_costs_sum` inside the snapshot.
-- 2. `check_profit_redistribution_needed` compares the live sum strictly with the saved sum.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Update distribute_shipment_profit
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
  v_revenue_egp NUMERIC;
  v_cost_egp NUMERIC;
  v_shipment_costs_sum NUMERIC;
  v_old_distribution_exists BOOLEAN;
  v_new_distributions JSONB;
  
  -- Settings
  v_settings JSONB;
  v_is_active BOOLEAN;
  v_persons JSONB;
  
  -- Iteration
  v_dist_idx INT;
  v_person_id UUID;
  v_pct NUMERIC;
  v_share NUMERIC;
  v_rate NUMERIC;
  v_final_currency TEXT;
  v_final_amount NUMERIC;
  v_total_distribution NUMERIC := 0;
  
  -- Journal Entry
  v_je_lines JSONB := '[]'::jsonb;
  v_desc TEXT;
  v_retained_earnings_acct BIGINT;
  v_shareholder_acct BIGINT;
  v_new_je_id BIGINT;
  v_line_debit NUMERIC;
  v_line_credit NUMERIC;
  v_line_base_debit NUMERIC;
  v_line_base_credit NUMERIC;
  v_re_debit NUMERIC;
  v_re_credit NUMERIC;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- =========================================================================
  -- STEP 1: VALIDATION & DATA FETCH
  -- =========================================================================
  
  -- Get Shipment Info
  SELECT company_id, shipment_no, net_profit_egp, total_revenue_egp, total_landed_cost
  INTO v_company_id, v_shipment_no, v_shipment_profit, v_revenue_egp, v_cost_egp
  FROM public.export_shipments
  WHERE id = v_shipment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shipment % not found.', v_shipment_id;
  END IF;

  -- Check if already distributed
  SELECT EXISTS (
    SELECT 1 FROM public.shareholder_profit_distributions 
    WHERE shipment_id = v_shipment_id AND deleted_at IS NULL
  ) INTO v_old_distribution_exists;

  -- If old distributions exist, we must reverse them first
  IF v_old_distribution_exists THEN
    PERFORM public.reverse_profit_distribution_entry(v_shipment_id);
  END IF;

  -- Calculate live shipment_cost_items sum for the snapshot
  SELECT COALESCE(SUM(total_price), 0) INTO v_shipment_costs_sum
  FROM public.shipment_cost_items
  WHERE shipment_id = v_shipment_id;

  -- Get Retained Earnings Account (3100)
  SELECT id INTO v_retained_earnings_acct
  FROM public.accounts
  WHERE code = '3100' AND company_id = v_company_id;

  IF v_retained_earnings_acct IS NULL THEN
    RAISE EXCEPTION 'Retained Earnings account (3100) not found.';
  END IF;

  -- Get Distribution Settings
  SELECT settings INTO v_settings
  FROM public.profit_distribution_settings
  WHERE company_id = v_company_id;

  IF v_settings IS NULL THEN
    RAISE EXCEPTION 'Profit distribution settings not found.';
  END IF;

  v_is_active := (v_settings ->> 'is_active')::BOOLEAN;
  IF NOT COALESCE(v_is_active, false) THEN
    RAISE EXCEPTION 'Profit distribution is disabled in settings.';
  END IF;

  v_persons := v_settings -> 'persons';
  v_desc := 'توزيع أرباح الشحنة ' || v_shipment_no;

  -- =========================================================================
  -- STEP 2: CALCULATE SHARES
  -- =========================================================================
  v_new_distributions := '[]'::jsonb;

  -- Person 1
  v_person_id := (v_persons -> 'person1' ->> 'id')::UUID;
  IF v_person_id IS NOT NULL THEN
    v_pct := (v_persons -> 'person1' ->> 'percentage')::NUMERIC;
    v_share := (v_shipment_profit * v_pct) / 100.0;
    
    v_final_currency := COALESCE(v_persons -> 'person1' ->> 'currency', 'EGP');
    
    IF v_final_currency != 'EGP' THEN
      v_rate := (v_persons -> 'person1' ->> 'exchange_rate_to_egp')::NUMERIC;
      IF COALESCE(v_rate, 0) = 0 THEN v_rate := 1; END IF;
      v_final_amount := v_share / v_rate;
    ELSE
      v_rate := 1;
      v_final_amount := v_share;
    END IF;

    IF v_pct > 0 THEN
      v_new_distributions := v_new_distributions || jsonb_build_object(
          'shareholder_id', v_person_id,
          'person_index', 1,
          'percentage', v_pct,
          'amount_egp', v_share,
          'currency', v_final_currency,
          'converted_amount', v_final_amount,
          'rate_to_egp', NULLIF(v_rate, 0)
      );
    END IF;
  END IF;

  -- Person 2
  v_person_id := (v_persons -> 'person2' ->> 'id')::UUID;
  IF v_person_id IS NOT NULL THEN
    v_pct := (v_persons -> 'person2' ->> 'percentage')::NUMERIC;
    v_share := (v_shipment_profit * v_pct) / 100.0;
    
    v_final_currency := COALESCE(v_persons -> 'person2' ->> 'currency', 'EGP');
    
    IF v_final_currency != 'EGP' THEN
      v_rate := (v_persons -> 'person2' ->> 'exchange_rate_to_egp')::NUMERIC;
      IF COALESCE(v_rate, 0) = 0 THEN v_rate := 1; END IF;
      v_final_amount := v_share / v_rate;
    ELSE
      v_rate := 1;
      v_final_amount := v_share;
    END IF;

    IF v_pct > 0 THEN
      v_new_distributions := v_new_distributions || jsonb_build_object(
          'shareholder_id', v_person_id,
          'person_index', 2,
          'percentage', v_pct,
          'amount_egp', v_share,
          'currency', v_final_currency,
          'converted_amount', v_final_amount,
          'rate_to_egp', NULLIF(v_rate, 0)
      );
    END IF;
  END IF;

  -- Person 3
  v_person_id := (v_persons -> 'person3' ->> 'id')::UUID;
  IF v_person_id IS NOT NULL THEN
    v_pct := (v_persons -> 'person3' ->> 'percentage')::NUMERIC;
    v_share := (v_shipment_profit * v_pct) / 100.0;
    
    v_final_currency := COALESCE(v_persons -> 'person3' ->> 'currency', 'EGP');
    
    IF v_final_currency != 'EGP' THEN
      v_rate := (v_persons -> 'person3' ->> 'exchange_rate_to_egp')::NUMERIC;
      IF COALESCE(v_rate, 0) = 0 THEN v_rate := 1; END IF;
      v_final_amount := v_share / v_rate;
    ELSE
      v_rate := 1;
      v_final_amount := v_share;
    END IF;

    IF v_pct > 0 THEN
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
  -- STEP 5: UPDATE SHIPMENT STATE (snapshot + reset redistribution flag)
  -- =========================================================================
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false,
      profitability_snapshot = jsonb_build_object(
        'net_profit_egp', v_shipment_profit,
        'revenue_egp', COALESCE(v_revenue_egp, 0),
        'cost_egp', COALESCE(v_cost_egp, 0),
        'shipment_costs_sum', v_shipment_costs_sum,
        'distributed_at', NOW()::TEXT
      )
  WHERE id = v_shipment_id;

END;
$$;


-- 2. Update check_profit_redistribution_needed
CREATE OR REPLACE FUNCTION public.check_profit_redistribution_needed(
  p_shipment_id_str TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shipment_id BIGINT;
  v_snapshot JSONB;
  v_current_profit NUMERIC;
  v_current_revenue NUMERIC;
  v_current_cost NUMERIC;
  v_snap_profit NUMERIC;
  v_snap_revenue NUMERIC;
  v_snap_cost NUMERIC;
  v_snap_live_cost NUMERIC;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- Get current snapshot and profitability data
  SELECT profitability_snapshot, net_profit_egp, total_revenue_egp, total_landed_cost
  INTO v_snapshot, v_current_profit, v_current_revenue, v_current_cost
  FROM public.export_shipments
  WHERE id = v_shipment_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- If no snapshot exists, no distribution was done → no redistribution needed
  IF v_snapshot IS NULL THEN
    RETURN false;
  END IF;

  -- Extract snapshot values
  v_snap_profit := COALESCE((v_snapshot ->> 'net_profit_egp')::NUMERIC, 0);
  v_snap_revenue := COALESCE((v_snapshot ->> 'revenue_egp')::NUMERIC, 0);
  v_snap_cost := COALESCE((v_snapshot ->> 'cost_egp')::NUMERIC, 0);
  v_snap_live_cost := COALESCE((v_snapshot ->> 'shipment_costs_sum')::NUMERIC, 0);

  -- Compare current vs snapshot
  -- If net profit changed → redistribution needed
  IF COALESCE(v_current_profit, 0) != v_snap_profit THEN
    RETURN true;
  END IF;

  -- If revenue changed → redistribution needed
  IF COALESCE(v_current_revenue, 0) != v_snap_revenue THEN
    RETURN true;
  END IF;

  -- If cost changed → redistribution needed
  IF COALESCE(v_current_cost, 0) != v_snap_cost THEN
    RETURN true;
  END IF;

  -- Check live cost items total strictly against the saved sum in the snapshot
  DECLARE
    v_live_cost NUMERIC;
  BEGIN
    SELECT COALESCE(SUM(total_price), 0) INTO v_live_cost
    FROM public.shipment_cost_items
    WHERE shipment_id = v_shipment_id;

    -- If snapshot doesn't have shipment_costs_sum (old snapshot), we bypass this check
    -- to avoid forcing a redistribution just because the snapshot format was upgraded.
    IF (v_snapshot ? 'shipment_costs_sum') THEN
      IF v_live_cost != v_snap_live_cost THEN
        RETURN true;
      END IF;
    END IF;
  END;

  RETURN false;
END;
$$;

NOTIFY pgrst, 'reload schema';
