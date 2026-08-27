-- Migration 410: Fix export shipment COGS calculation from packing orders and fix multi-currency JE summary

CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_ledger(
    p_shipment_id bigint,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue numeric;
  v_discount numeric;
  v_desc text;
  v_old_amount numeric;
  v_company_id uuid;
  v_ar_acct bigint;
  v_rev_acct bigint;
  v_disc_acct bigint;
  v_cogs_acct bigint;
  v_inv_acct bigint;
  v_lines jsonb;
  v_sale_je_id bigint;
  v_disc_je_id bigint;
  v_je_id bigint;
  v_raw_ar bigint;
  v_base_revenue numeric;
  v_base_discount numeric;
  v_exch_rate numeric;
  v_cogs_amount numeric := 0;
  v_entry_date date;
BEGIN
  -- 1. Get Company ID
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN 
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1; 
  END IF;

  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'لا يوجد عميل مخصص للشحنة');
  END IF;

  -- 2. Calculate Revenue from items
  SELECT COALESCE(
    SUM(COALESCE(NULLIF(amount, 0), quantity * COALESCE(export_price_per_carton, 0))),
    0
  )
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  -- FALLBACK: If items sum to 0, fallback to total_revenue_foreign
  IF v_total_revenue = 0 THEN
    v_total_revenue := COALESCE(v_shipment.total_revenue_foreign, 0);
  END IF;

  v_discount := COALESCE(v_shipment.discount_amount, 0);

  -- 3. Determine Accurate Exchange Rate from public.exchange_rates
  v_exch_rate := COALESCE(v_shipment.exchange_rate, 1);
  IF (v_exch_rate IS NULL OR v_exch_rate <= 1) AND COALESCE(v_shipment.currency_code, 'EGP') != 'EGP' THEN
     SELECT rate_to_egp INTO v_exch_rate
     FROM public.exchange_rates
     WHERE currency_code = v_shipment.currency_code
     LIMIT 1;
     
     IF v_exch_rate IS NULL OR v_exch_rate <= 1 THEN
        IF v_shipment.currency_code = 'USD' THEN v_exch_rate := 50.0;
        ELSIF v_shipment.currency_code = 'EUR' THEN v_exch_rate := 54.0;
        ELSIF v_shipment.currency_code = 'GBP' THEN v_exch_rate := 64.0;
        ELSIF v_shipment.currency_code = 'SAR' THEN v_exch_rate := 13.3;
        ELSIF v_shipment.currency_code = 'AED' THEN v_exch_rate := 13.6;
        ELSE v_exch_rate := 1.0;
        END IF;
     END IF;
  END IF;

  IF v_exch_rate IS NULL OR v_exch_rate <= 0 THEN
     v_exch_rate := 1.0;
  END IF;

  v_base_revenue := ROUND(v_total_revenue * v_exch_rate, 2);
  v_base_discount := ROUND(v_discount * v_exch_rate, 2);

  -- 4. Calculate COGS (تكلفة البضاعة المباعة المنصرفة من مخزون الإنتاج التام 1031)
  -- Priority 1: From packing orders linked via shipment items
  SELECT COALESCE(SUM(po.total_packing_cost), 0)
  INTO v_cogs_amount
  FROM public.export_shipment_items esi
  JOIN public.packing_orders po ON po.id = esi.packing_order_id
  WHERE esi.shipment_id = p_shipment_id
    AND po.status != 'cancelled';

  -- Priority 2: From packing orders directly linked to this shipment
  IF v_cogs_amount = 0 THEN
    SELECT COALESCE(SUM(po.total_packing_cost), 0)
    INTO v_cogs_amount
    FROM public.packing_orders po
    WHERE po.export_shipment_id = p_shipment_id
      AND po.status != 'cancelled';
  END IF;

  -- Priority 3: From shipment direct fields (if no packing orders linked)
  IF v_cogs_amount = 0 THEN
    v_cogs_amount := COALESCE(v_shipment.total_fruit_cost, 0) + COALESCE(v_shipment.total_packing_material_cost, 0);
  END IF;

  -- Priority 4: From cost_per_carton * carton_count
  IF v_cogs_amount = 0 AND COALESCE(v_shipment.cost_per_carton, 0) > 0 AND COALESCE(v_shipment.carton_count, 0) > 0 THEN
    v_cogs_amount := ROUND(v_shipment.cost_per_carton * v_shipment.carton_count, 2);
  END IF;

  -- Priority 5: From total_landed_cost
  IF v_cogs_amount = 0 AND COALESCE(v_shipment.total_landed_cost, 0) > 0 THEN
    v_cogs_amount := v_shipment.total_landed_cost;
  END IF;

  -- Update shipment record with exchange rate and calculated base figures
  UPDATE public.export_shipments
  SET exchange_rate = v_exch_rate,
      total_revenue_egp = v_base_revenue,
      total_fruit_cost = CASE WHEN COALESCE(total_fruit_cost, 0) = 0 AND v_cogs_amount > 0 THEN v_cogs_amount ELSE total_fruit_cost END,
      updated_at = now()
  WHERE id = p_shipment_id;

  -- 5. Customer Ledger Reversal
  SELECT
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM public.ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  UPDATE public.customers
  SET balance = COALESCE(balance, 0) - v_old_amount + (v_total_revenue - v_discount),
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  DELETE FROM public.ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- 6. Clean up any existing Journal Entries for this shipment
  FOR v_je_id IN
      SELECT id FROM public.journal_entries
      WHERE source_type IN ('export_shipment', 'export_discount')
        AND source_id = p_shipment_id::text
  LOOP
      PERFORM public.reverse_journal_entry(v_je_id, p_user_id, 'تحديث الشحنة');
  END LOOP;

  DELETE FROM public.account_ledger_entries
  WHERE journal_entry_id IN (
    SELECT id FROM public.journal_entries
    WHERE source_type IN ('export_shipment', 'export_discount')
      AND source_id = p_shipment_id::text
  );
  DELETE FROM public.journal_entries
  WHERE source_type IN ('export_shipment', 'export_discount')
    AND source_id = p_shipment_id::text;

  -- 7. Post New Journal Entries
  IF v_total_revenue > 0 THEN
    v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no;

    -- Legacy customer ledger entry
    INSERT INTO public.ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      COALESCE(v_shipment.currency_code, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );

    IF v_discount > 0 THEN
      INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_text, description, created_by
      ) VALUES (
        'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
        COALESCE(v_shipment.currency_code, 'USD'),
        'export_shipment', p_shipment_id::TEXT, v_desc || ' (خصم)', p_user_id
      );
    END IF;

    -- AR Account
    SELECT c.account_id INTO v_raw_ar FROM public.customers c WHERE c.id = v_shipment.customer_id;
    IF v_raw_ar IS NOT NULL THEN
      SELECT id INTO v_ar_acct FROM public.accounts WHERE id = v_raw_ar AND is_leaf = true LIMIT 1;
    END IF;

    IF v_ar_acct IS NULL THEN
      SELECT a.id INTO v_ar_acct
      FROM public.customers c
      JOIN public.accounts a ON (
        a.name ILIKE 'Customer - ' || COALESCE(c.name, '') || '%'
        OR a.account_name ILIKE 'عميل - ' || COALESCE(c.name, '') || '%'
      )
      WHERE c.id = v_shipment.customer_id AND a.is_leaf = true AND a.company_id = v_company_id LIMIT 1;
    END IF;

    IF v_ar_acct IS NULL THEN
      SELECT id INTO v_ar_acct
      FROM public.accounts
      WHERE company_id = v_company_id AND account_code LIKE '102%' AND is_leaf = true
      ORDER BY account_code ASC LIMIT 1;
    END IF;

    IF v_ar_acct IS NULL THEN
      v_ar_acct := public.resolve_gl_account('1020', v_company_id);
    END IF;

    -- Revenue Account
    SELECT id INTO v_rev_acct FROM public.accounts WHERE company_id = v_company_id AND account_code IN ('4101', '4200', '4000') AND is_leaf = true LIMIT 1;
    IF v_rev_acct IS NULL THEN
      v_rev_acct := public.resolve_gl_account('4101', v_company_id);
    END IF;

    -- Discount Account
    SELECT id INTO v_disc_acct FROM public.accounts WHERE company_id = v_company_id AND account_code = '4105' AND is_leaf = true LIMIT 1;
    IF v_disc_acct IS NULL AND v_discount > 0 THEN
      v_disc_acct := public.resolve_gl_account('4105', v_company_id);
    END IF;

    -- COGS & Finished Goods Inventory Accounts
    v_cogs_acct := public.resolve_gl_account('5000', v_company_id);
    v_inv_acct  := public.resolve_gl_account('1031', v_company_id);

    -- Safe entry date calculation
    v_entry_date := COALESCE(
      v_shipment.shipment_date,
      (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::date,
      (NOW() AT TIME ZONE 'Africa/Cairo')::date
    );

    -- ── JOURNAL ENTRY 1: Sale & COGS (متزن بالكامل بالعملة الأساسية) ──
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', v_ar_acct,
        'debit', v_total_revenue,
        'credit', 0,
        'base_debit', v_base_revenue,
        'base_credit', 0,
        'currency', COALESCE(v_shipment.currency_code, 'USD'),
        'description', v_desc || ' - استحقاق مبيعات'
      ),
      jsonb_build_object(
        'account_id', v_rev_acct,
        'debit', 0,
        'credit', v_total_revenue,
        'base_debit', 0,
        'base_credit', v_base_revenue,
        'currency', COALESCE(v_shipment.currency_code, 'USD'),
        'description', v_desc || ' - إيراد مبيعات تصدير'
      )
    );

    -- إضافة طرفي قيد تكلفة البضاعة المباعة (من 1031 إلى 5000)
    IF v_cogs_amount > 0 AND v_cogs_acct IS NOT NULL AND v_inv_acct IS NOT NULL THEN
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cogs_acct,
          'debit', v_cogs_amount,
          'credit', 0,
          'base_debit', v_cogs_amount,
          'base_credit', 0,
          'currency', 'EGP',
          'description', v_desc || ' - إثبات تكلفة البضاعة المباعة'
        ),
        jsonb_build_object(
          'account_id', v_inv_acct,
          'debit', 0,
          'credit', v_cogs_amount,
          'base_debit', 0,
          'base_credit', v_cogs_amount,
          'currency', 'EGP',
          'description', v_desc || ' - صرف من مخزون الإنتاج التام'
        )
      );
    END IF;

    v_sale_je_id := public.post_journal_entry(
      'export_shipment',
      v_desc || ' - قيد البيع',
      v_entry_date,
      v_company_id,
      p_user_id,
      v_lines,
      p_shipment_id::text
    );

    IF v_discount > 0 AND v_disc_acct IS NOT NULL THEN
      v_disc_je_id := public.post_journal_entry(
        'export_discount',
        v_desc || ' - قيد الخصم التجاري',
        v_entry_date,
        v_company_id,
        p_user_id,
        jsonb_build_array(
          jsonb_build_object(
            'account_id', v_disc_acct,
            'debit', v_discount,
            'credit', 0,
            'base_debit', v_base_discount,
            'base_credit', 0,
            'currency', COALESCE(v_shipment.currency_code, 'USD'),
            'description', v_desc || ' - خصم مسموح به'
          ),
          jsonb_build_object(
            'account_id', v_ar_acct,
            'debit', 0,
            'credit', v_discount,
            'base_debit', 0,
            'base_credit', v_base_discount,
            'currency', COALESCE(v_shipment.currency_code, 'USD'),
            'description', v_desc || ' - تخفيض مديونية العميل بالخصم'
          )
        ),
        p_shipment_id::text
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'sale_journal_entry_id', v_sale_je_id,
    'cogs_amount', v_cogs_amount,
    'discount_journal_entry_id', v_disc_je_id
  );
END;
$$;
