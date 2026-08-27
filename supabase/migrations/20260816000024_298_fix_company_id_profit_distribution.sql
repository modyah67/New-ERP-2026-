-- Migration 298: Fix Company ID Resolution in Profit Distribution
-- 
-- The previous migration relied on `SELECT id FROM public.sys_companies LIMIT 1`.
-- In a multi-company DB (e.g., 35 companies), this non-deterministic query 
-- often picks a company that has no accounts (like 'Main Company' instead of 'متجر ES'),
-- causing `Retained Earnings account (3100) not found.`
-- This prevents the profit distribution from completing, and because the snapshot
-- remains NULL, the Flutter UI shows "إعادة توزيع الأرباح".
--
-- This migration surgically updates `distribute_shipment_profit` to smartly
-- infer the `company_id` from `profit_distribution_settings` or `accounts` 
-- since `export_shipments` lacks a `company_id` column.

CREATE OR REPLACE FUNCTION public.distribute_shipment_profit(
    p_shipment_id_str text)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE SECURITY DEFINER
AS $BODY$
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
  v_shipment_no TEXT;
  
  -- Audit and GL variables
  v_retained_earnings_acct BIGINT;
  v_new_je_id BIGINT;
  v_je_lines JSONB := '[]'::JSONB;
  v_total_distribution NUMERIC := 0;
  v_new_distributions JSONB := '[]'::JSONB;
  v_desc TEXT;
  
  -- Fingerprint variables
  v_old_snapshot JSONB;
  v_old_distribution_exists BOOLEAN;
  v_is_active BOOLEAN;
  v_persons JSONB;
  v_final_currency TEXT;
  v_rate NUMERIC;
  v_final_amount NUMERIC;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- =========================================================================
  -- STEP 0: SMART COMPANY ID RESOLUTION
  -- =========================================================================
  -- We MUST find the correct company that has profit distribution configured.
  -- Since export_shipments doesn't have company_id, we infer it from settings.
  SELECT company_id INTO v_company_id 
  FROM public.profit_distribution_settings 
  WHERE is_active = true 
  LIMIT 1;

  IF v_company_id IS NULL THEN
    -- Fallback to the company that has the Retained Earnings account
    SELECT company_id INTO v_company_id 
    FROM public.accounts 
    WHERE code = '3100' 
    LIMIT 1;
    
    IF v_company_id IS NULL THEN
      -- Final fallback
      SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;
  END IF;

  -- Fetch shipment details
  SELECT shipment_no, net_profit_egp, total_revenue_egp, total_landed_cost, COALESCE(exchange_rate, 1.0), profitability_snapshot
  INTO v_shipment_no, v_shipment_profit, v_revenue_egp, v_cost_egp, v_shipment_exchange_rate, v_old_snapshot
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
  END IF;

  IF v_shipment_profit <= 0 THEN
    RAISE EXCEPTION 'لا يوجد ربح لتوزيعه (صافي الربح صفر أو سالب).';
  END IF;

  -- =========================================================================
  -- STEP 1: REVERSE OLD DISTRIBUTION IF IT EXISTS
  -- =========================================================================
  SELECT EXISTS (
    SELECT 1 FROM public.shareholder_profit_distributions 
    WHERE shipment_id = v_shipment_id AND deleted_at IS NULL
  ) INTO v_old_distribution_exists;

  -- If old distributions exist, we must reverse them first
  IF v_old_distribution_exists THEN
    PERFORM public.reverse_profit_distribution_entry(p_shipment_id_str);
  END IF;

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

  -- Person 4
  v_person_id := (v_persons -> 'person4' ->> 'id')::UUID;
  IF v_person_id IS NOT NULL THEN
    v_pct := (v_persons -> 'person4' ->> 'percentage')::NUMERIC;
    v_share := (v_shipment_profit * v_pct) / 100.0;
    
    v_final_currency := COALESCE(v_persons -> 'person4' ->> 'currency', 'EGP');
    
    IF v_final_currency != 'EGP' THEN
      v_rate := (v_persons -> 'person4' ->> 'exchange_rate_to_egp')::NUMERIC;
      IF COALESCE(v_rate, 0) = 0 THEN v_rate := 1; END IF;
      v_final_amount := v_share / v_rate;
    ELSE
      v_rate := 1;
      v_final_amount := v_share;
    END IF;

    IF v_pct > 0 THEN
      v_new_distributions := v_new_distributions || jsonb_build_object(
          'shareholder_id', v_person_id,
          'person_index', 4,
          'percentage', v_pct,
          'amount_egp', v_share,
          'currency', v_final_currency,
          'converted_amount', v_final_amount,
          'rate_to_egp', NULLIF(v_rate, 0)
      );
    END IF;
  END IF;

  IF jsonb_array_length(v_new_distributions) = 0 THEN
    RAISE EXCEPTION 'لم يتم تعيين نسب للمساهمين.';
  END IF;

  -- =========================================================================
  -- STEP 3: CREATE NEW JOURNAL ENTRY
  -- =========================================================================
  INSERT INTO public.journal_entries (
    company_id, entry_date, description, reference_type, reference_id,
    status, created_by, source_module, is_system_generated
  ) VALUES (
    v_company_id, CURRENT_DATE, v_desc, 'export_shipment_profit', v_shipment_id,
    'posted', auth.uid(), 'exports', true
  ) RETURNING id INTO v_new_je_id;

  -- Create GL line for Retained Earnings (Debit)
  v_total_distribution := 0;
  
  -- Create GL lines for each shareholder (Credit)
  DECLARE
    dist RECORD;
    v_sh_acct BIGINT;
    v_sh_amt NUMERIC;
  BEGIN
    FOR dist IN SELECT * FROM jsonb_array_elements(v_new_distributions)
    LOOP
      v_sh_amt := (dist.value ->> 'amount_egp')::NUMERIC;
      v_total_distribution := v_total_distribution + v_sh_amt;
      
      SELECT default_account_id INTO v_sh_acct
      FROM public.shareholders
      WHERE id = (dist.value ->> 'shareholder_id')::UUID;

      IF v_sh_acct IS NULL THEN
        RAISE EXCEPTION 'المساهم ليس لديه حساب افتراضي.';
      END IF;

      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, base_debit, base_credit,
        description, is_reconciliation, company_id
      ) VALUES (
        v_new_je_id, v_sh_acct, 0, v_sh_amt, 0, v_sh_amt,
        v_desc || ' - مساهم ' || (dist.value ->> 'person_index'), false, v_company_id
      );
    END LOOP;
  END;

  -- Insert Debit for Retained Earnings
  INSERT INTO public.account_ledger_entries (
    journal_entry_id, account_id, debit, credit, base_debit, base_credit,
    description, is_reconciliation, company_id
  ) VALUES (
    v_new_je_id, v_retained_earnings_acct, v_total_distribution, 0, v_total_distribution, 0,
    v_desc || ' - إجمالي', false, v_company_id
  );

  -- =========================================================================
  -- STEP 4: INSERT NEW DISTRIBUTIONS INTO DATABASE
  -- =========================================================================
  DECLARE
    dist RECORD;
  BEGIN
    FOR dist IN SELECT * FROM jsonb_array_elements(v_new_distributions)
    LOOP
      INSERT INTO public.shareholder_profit_distributions (
        shipment_id, journal_entry_id, shareholder_id, percentage,
        amount_egp, currency, converted_amount, rate_to_egp
      ) VALUES (
        v_shipment_id,
        v_new_je_id,
        (dist.value ->> 'shareholder_id')::UUID,
        (dist.value ->> 'percentage')::NUMERIC,
        (dist.value ->> 'amount_egp')::NUMERIC,
        (dist.value ->> 'currency')::TEXT,
        (dist.value ->> 'converted_amount')::NUMERIC,
        (dist.value ->> 'rate_to_egp')::NUMERIC
      );
    END LOOP;
  END;

  -- =========================================================================
  -- STEP 5: MARK SHIPMENT AS DISTRIBUTED AND UPDATE SNAPSHOT
  -- =========================================================================
  UPDATE public.export_shipments
SET needs_profit_redistribution = false,
    profitability_snapshot = jsonb_build_object('fingerprint', public.get_shipment_profitability_fingerprint(v_shipment_id))
WHERE id = v_shipment_id;

END;
$BODY$;
