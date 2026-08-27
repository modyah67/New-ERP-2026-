-- Migration 295: Fix Profit Distribution Reverse & State Management
-- Scope: ONLY profit distribution page logic. No changes to any other module.
--
-- Fixes:
--   1. reverse_journal_entry signature mismatch (4 args vs 3)
--   2. reverse_journal_entry was a NO-OP
--   3. No profitability snapshot for change detection
--   4. Account 3100 (Retained Earnings) missing
--   5. needs_profit_redistribution never reset after distribution

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Create Account 3100 (Retained Earnings) if missing
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_equity_parent BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '3100') THEN
    -- Find equity parent (account_code = '3')
    SELECT id INTO v_equity_parent FROM public.accounts
    WHERE account_code = '3' LIMIT 1;

    INSERT INTO public.accounts (
      account_code, name, name_ar, account_type,
      is_leaf, allow_posting, is_active, parent_id
    ) VALUES (
      '3100',
      'Retained Earnings',
      'الأرباح المبقاة',
      'equity',
      true, true, true,
      v_equity_parent
    );
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Add profitability_snapshot column to export_shipments
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.export_shipments
ADD COLUMN IF NOT EXISTS profitability_snapshot JSONB DEFAULT NULL;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Create reverse_profit_distribution_entry (dedicated RPC)
--    Does NOT touch the general reverse_journal_entry function
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.reverse_profit_distribution_entry(
  p_journal_entry_id BIGINT,
  p_user_id UUID,
  p_reversal_date DATE,
  p_reason TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original    RECORD;
  v_line        RECORD;
  v_rev_lines   JSONB := '[]'::JSONB;
  v_rev_je_id   BIGINT;
  v_company_id  UUID;
BEGIN
  -- Fetch the original journal entry
  SELECT * INTO v_original FROM public.journal_entries WHERE id = p_journal_entry_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'القيد المحاسبي رقم % غير موجود', p_journal_entry_id;
  END IF;

  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

  -- Build reversed lines (swap debit/credit)
  FOR v_line IN
    SELECT * FROM public.account_ledger_entries
    WHERE journal_entry_id = p_journal_entry_id
    ORDER BY id ASC
  LOOP
    v_rev_lines := v_rev_lines || jsonb_build_object(
      'account_id', v_line.account_id,
      'debit', COALESCE(v_line.credit, 0),
      'credit', COALESCE(v_line.debit, 0),
      'base_debit', COALESCE(v_line.base_credit, v_line.credit, 0),
      'base_credit', COALESCE(v_line.base_debit, v_line.debit, 0),
      'currency', COALESCE(v_line.currency, 'EGP'),
      'amount_in_base_currency', v_line.amount_in_base_currency,
      'description', COALESCE(p_reason, 'عكس قيد رقم ' || p_journal_entry_id::TEXT)
    );
  END LOOP;

  IF jsonb_array_length(v_rev_lines) = 0 THEN
    RAISE EXCEPTION 'القيد رقم % لا يحتوي على بنود', p_journal_entry_id;
  END IF;

  -- Post the reversal journal entry
  v_rev_je_id := public.post_journal_entry(
    'profit_distribution_reversal',
    COALESCE(p_reason, 'عكس قيد توزيع أرباح رقم ' || p_journal_entry_id::TEXT),
    p_reversal_date,
    v_company_id,
    p_user_id,
    v_rev_lines,
    v_original.source_id  -- same shipment link
  );

  RETURN v_rev_je_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reverse_profit_distribution_entry(BIGINT, UUID, DATE, TEXT) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Rewrite distribute_shipment_profit with fixed reverse call + snapshot
-- ═══════════════════════════════════════════════════════════════════════════
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
  -- STEP 5: UPDATE SHIPMENT STATE (snapshot + reset redistribution flag)
  -- =========================================================================
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false,
      profitability_snapshot = jsonb_build_object(
        'net_profit_egp', v_shipment_profit,
        'revenue_egp', COALESCE(v_revenue_egp, 0),
        'cost_egp', COALESCE(v_cost_egp, 0),
        'distributed_at', NOW()::TEXT
      )
  WHERE id = v_shipment_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.distribute_shipment_profit(TEXT) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Create check_profit_redistribution_needed (RPC for Flutter)
-- ═══════════════════════════════════════════════════════════════════════════
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
  v_exchange_rate NUMERIC;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- Get current snapshot and profitability data
  SELECT profitability_snapshot, net_profit_egp, total_revenue_egp, total_landed_cost, COALESCE(exchange_rate, 1.0)
  INTO v_snapshot, v_current_profit, v_current_revenue, v_current_cost, v_exchange_rate
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

  -- Also check live cost items total in case total_landed_cost wasn't updated
  DECLARE
    v_live_cost NUMERIC;
  BEGIN
    SELECT COALESCE(SUM(total_price), 0) INTO v_live_cost
    FROM public.shipment_cost_items
    WHERE shipment_id = v_shipment_id;

    IF v_live_cost != v_snap_cost AND v_live_cost != COALESCE(v_current_cost, 0) THEN
      RETURN true;
    END IF;
  END;

  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_profit_redistribution_needed(TEXT) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Reset needs_profit_redistribution to false for all shipments
--    (the field will now be managed by the RPC + snapshot comparison)
-- ═══════════════════════════════════════════════════════════════════════════
UPDATE public.export_shipments SET needs_profit_redistribution = false;


-- Register profit_distribution_reversal as source type
INSERT INTO public.sys_document_types (code, name)
SELECT 'profit_distribution_reversal', 'عكس قيد توزيع أرباح'
WHERE NOT EXISTS (
  SELECT 1 FROM public.sys_document_types WHERE code = 'profit_distribution_reversal'
);

NOTIFY pgrst, 'reload schema';

COMMIT;
