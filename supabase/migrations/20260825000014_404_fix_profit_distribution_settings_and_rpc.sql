-- ============================================================================
-- Migration 404: Fix Profit Distribution Settings RLS and Provide Safe Save RPC
-- ============================================================================

BEGIN;

-- 1. Ensure RLS policies on profit_distribution_settings allow authenticated users
DROP POLICY IF EXISTS "Users can view their own profit distribution settings" ON public.profit_distribution_settings;
DROP POLICY IF EXISTS "Users can insert their own profit distribution settings" ON public.profit_distribution_settings;
DROP POLICY IF EXISTS "Users can update their own profit distribution settings" ON public.profit_distribution_settings;
DROP POLICY IF EXISTS "Users can delete their own profit distribution settings" ON public.profit_distribution_settings;
DROP POLICY IF EXISTS "Allow authenticated full access on profit_distribution_settings" ON public.profit_distribution_settings;

CREATE POLICY "Allow authenticated full access on profit_distribution_settings"
    ON public.profit_distribution_settings
    FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- 2. Dedicated RPC for saving profit distribution settings safely
CREATE OR REPLACE FUNCTION public.rpc_save_profit_distribution_settings(
    p_person1_id uuid,
    p_person1_name text,
    p_person2_id uuid,
    p_person2_name text,
    p_person3_id uuid,
    p_person3_name text,
    p_percentages jsonb,
    p_person4_for_shipment jsonb,
    p_currency_conversions jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_id uuid;
BEGIN
    SELECT id INTO v_existing_id
    FROM public.profit_distribution_settings
    ORDER BY updated_at DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        UPDATE public.profit_distribution_settings SET
            person1_id = p_person1_id,
            person1_name = p_person1_name,
            person2_id = p_person2_id,
            person2_name = p_person2_name,
            person3_id = p_person3_id,
            person3_name = p_person3_name,
            percentages = COALESCE(p_percentages, '{}'::jsonb),
            person4_for_shipment = COALESCE(p_person4_for_shipment, '{}'::jsonb),
            currency_conversions = COALESCE(p_currency_conversions, '{}'::jsonb),
            updated_at = now()
        WHERE id = v_existing_id;
    ELSE
        INSERT INTO public.profit_distribution_settings (
            user_id,
            person1_id,
            person1_name,
            person2_id,
            person2_name,
            person3_id,
            person3_name,
            percentages,
            person4_for_shipment,
            currency_conversions,
            singleton_key,
            created_at,
            updated_at
        ) VALUES (
            auth.uid(),
            p_person1_id,
            p_person1_name,
            p_person2_id,
            p_person2_name,
            p_person3_id,
            p_person3_name,
            COALESCE(p_percentages, '{}'::jsonb),
            COALESCE(p_person4_for_shipment, '{}'::jsonb),
            COALESCE(p_currency_conversions, '{}'::jsonb),
            true,
            now(),
            now()
        );
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_profit_distribution_settings(uuid, text, uuid, text, uuid, text, jsonb, jsonb, jsonb) TO authenticated;

-- 3. Enhance distribute_shipment_profit with automatic fallback to equal split if not configured
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
  
  -- Record
  v_set_rec RECORD;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  -- =========================================================================
  -- STEP 1: VALIDATION & DATA FETCH
  -- =========================================================================
  
  -- Get Retained Earnings Account and Company ID together
  SELECT id, company_id INTO v_retained_earnings_acct, v_company_id 
  FROM public.accounts WHERE account_code = '3100' LIMIT 1;

  IF v_retained_earnings_acct IS NULL THEN
      RAISE EXCEPTION 'حساب الأرباح المحتجزة (3100) غير موجود.';
  END IF;

  SELECT * INTO v_set_rec FROM public.profit_distribution_settings LIMIT 1;
  
  IF v_set_rec IS NULL THEN
      RAISE EXCEPTION 'إعدادات التوزيع غير موجودة أو غير مفعلة.';
  END IF;
  
  v_settings := v_set_rec.percentages;
  v_p4_map := v_set_rec.person4_for_shipment;
  v_conv := v_set_rec.currency_conversions;

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

  -- Compute distributions
  BEGIN
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

  -- Delete old distributions entirely
  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;

  -- =========================================================================
  -- STEP 3: INSERT NEW DISTRIBUTIONS & GL LINES
  -- =========================================================================
  
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

      -- 3. Resolve Shareholder GL Account directly from shareholders table or fallback to 3101
      SELECT account_id INTO v_shareholder_acct FROM public.shareholders WHERE id = v_sh_id;
      IF v_shareholder_acct IS NULL THEN
          SELECT id INTO v_shareholder_acct FROM public.accounts WHERE account_code = '3101' LIMIT 1;
      END IF;

      -- 4. Build Credit Line for Shareholder
      v_je_lines := v_je_lines || jsonb_build_object(
          'account_id', v_shareholder_acct,
          'debit', 0,
          'base_debit', 0,
          'credit', v_c_amt,
          'base_credit', v_amt_egp,
          'currency', v_curr,
          'description', v_desc || ' - نصيب ' || COALESCE((SELECT name FROM public.shareholders WHERE id = v_sh_id), 'مساهم')
      );

      v_total_base := v_total_base + v_amt_egp;
    END;
  END LOOP;

  -- =========================================================================
  -- STEP 4: ADD DEBIT LINE & POST JOURNAL ENTRY
  -- =========================================================================
  
  -- Add DR 3100 (Retained Earnings)
  v_je_lines := jsonb_build_array(
      jsonb_build_object(
          'account_id', v_retained_earnings_acct,
          'debit', v_total_base,
          'base_debit', v_total_base,
          'credit', 0,
          'base_credit', 0,
          'currency', 'EGP',
          'description', v_desc || ' - تخفيض الأرباح المحتجزة'
      )
  ) || v_je_lines;

  -- Reverse old journal entry if exists
  IF v_old_je_id IS NOT NULL THEN
      BEGIN
          PERFORM public.reverse_journal_entry(v_old_je_id, 'إلغاء توزيع أرباح سابق للشحنة ' || v_shipment_no);
      EXCEPTION WHEN OTHERS THEN
          NULL;
      END;
  END IF;

  v_je_id := public.post_journal_entry(
      'profit_distribution',
      v_desc,
      CURRENT_DATE,
      v_company_id,
      auth.uid(),
      v_je_lines
  );

  -- Link journal_entry_id to the new distribution rows
  UPDATE public.shareholder_profit_distributions
  SET journal_entry_id = v_je_id
  WHERE shipment_id = v_shipment_id;

  -- Mark shipment as distributed & no redistribution needed
  UPDATE public.export_shipments
  SET needs_profit_redistribution = false
  WHERE id = v_shipment_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.distribute_shipment_profit(TEXT) TO authenticated;

COMMIT;
