-- ==============================================================================
-- FIX: Export Shipments COGS & Expense Entries - 5-Level Chart of Accounts (COA)
-- 1. Ensure Level 5 COGS account 34111 exists & is leaf
-- 2. Migrate existing ledger lines pointing to obsolete 3412 (e.g. EXP-00006) -> 34111
-- 3. Delete / Archive obsolete account 3412
-- 4. Update rpc_process_export_shipment_ledger to strictly resolve Level 5 accounts
-- 5. Update post_journal_entry to enforce is_leaf = true for all ledger entry lines
-- ==============================================================================

BEGIN;

-- ── 1. Ensure 34111 (Raw Material Purchase Costs / Crop Cost of Sales) exists ─
DO $$
DECLARE
  v_p34   BIGINT;
  v_p341  BIGINT;
  v_p3411 BIGINT;
  v_cid   UUID;
BEGIN
  SELECT id INTO v_cid FROM public.sys_companies ORDER BY created_at ASC LIMIT 1;

  -- Ensure 34
  SELECT id INTO v_p34 FROM public.accounts WHERE account_code = '34' LIMIT 1;
  IF v_p34 IS NULL THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, normal_balance, level, is_leaf, is_active, allow_posting, company_id)
    VALUES ('34', 'Cost of Sales', 'تكاليف المبيعات', 'expense', 'Debit', 2, false, true, false, v_cid)
    RETURNING id INTO v_p34;
  END IF;

  -- Ensure 341
  SELECT id INTO v_p341 FROM public.accounts WHERE account_code = '341' LIMIT 1;
  IF v_p341 IS NULL THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, normal_balance, level, is_leaf, is_active, allow_posting, parent_id, company_id)
    VALUES ('341', 'Cost of Sales', 'تكاليف المبيعات', 'expense', 'Debit', 3, false, true, false, v_p34, v_cid)
    RETURNING id INTO v_p341;
  END IF;

  -- Ensure 3411
  SELECT id INTO v_p3411 FROM public.accounts WHERE account_code = '3411' LIMIT 1;
  IF v_p3411 IS NULL THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, normal_balance, level, is_leaf, is_active, allow_posting, parent_id, company_id)
    VALUES ('3411', 'Cost of Sales Control', 'تكاليف المبيعات', 'expense', 'Debit', 4, false, true, false, v_p341, v_cid)
    RETURNING id INTO v_p3411;
  END IF;

  -- Ensure 34111 (Level 5 posting account)
  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '34111') THEN
    INSERT INTO public.accounts (account_code, name, account_name, account_type, normal_balance, level, is_leaf, is_active, allow_posting, parent_id, company_id, sort_order)
    VALUES ('34111', 'Raw Material Purchase Costs - Sales Cost', 'تكاليف مشتريات خام - تكلفه بيع', 'expense', 'Debit', 5, true, true, true, v_p3411, v_cid, 34111);
  ELSE
    UPDATE public.accounts
    SET level = 5,
        is_leaf = true,
        is_active = true,
        allow_posting = true,
        parent_id = v_p3411
    WHERE account_code = '34111';
  END IF;
END $$;

-- ── 2. Migrate existing ledger entries referencing obsolete 3412 -> 34111 ──────
DO $$
DECLARE
  v_old_acct_id BIGINT;
  v_new_acct_id BIGINT;
  v_updated_cnt INT := 0;
BEGIN
  SELECT id INTO v_old_acct_id FROM public.accounts WHERE account_code = '3412';
  SELECT id INTO v_new_acct_id FROM public.accounts WHERE account_code = '34111' AND is_leaf = true LIMIT 1;

  IF v_old_acct_id IS NOT NULL AND v_new_acct_id IS NOT NULL THEN
    UPDATE public.account_ledger_entries
    SET account_id = v_new_acct_id
    WHERE account_id = v_old_acct_id;

    GET DIAGNOSTICS v_updated_cnt = ROW_COUNT;
    RAISE NOTICE 'Updated % ledger entry lines from account 3412 (id: %) to 34111 (id: %)', v_updated_cnt, v_old_acct_id, v_new_acct_id;

    -- Delete or archive obsolete 3412
    DELETE FROM public.accounts WHERE id = v_old_acct_id;
    RAISE NOTICE 'Deleted obsolete account 3412';
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- If FK constraint prevents delete, archive it safely
  IF v_old_acct_id IS NOT NULL THEN
    UPDATE public.accounts 
    SET is_active = false, 
        is_leaf = false, 
        allow_posting = false,
        account_name = account_name || ' (ملغي - قديم)'
    WHERE id = v_old_acct_id;
    RAISE NOTICE 'Archived obsolete account 3412';
  END IF;
END $$;

-- ── 3. Deploy updated rpc_process_export_shipment_ledger ───────────────────────
CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_ledger(
  p_shipment_id bigint,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue numeric := 0;
  v_discount numeric := 0;
  v_paid numeric := 0;
  v_net_revenue numeric := 0;
  v_desc text;
  v_old_amount numeric := 0;
  v_company_id uuid;
  v_ar_acct bigint;
  v_rev_acct bigint;
  v_disc_acct bigint;
  v_cogs_acct bigint;
  v_inv_acct bigint;
  v_pay_acct bigint;
  v_sale_lines jsonb;
  v_sale_je_id bigint;
  v_cogs_je_id bigint;
  v_pay_je_id bigint;
  v_je_id bigint;
  v_raw_ar bigint;
  v_base_revenue numeric := 0;
  v_base_discount numeric := 0;
  v_base_net numeric := 0;
  v_base_paid numeric := 0;
  v_exch_rate numeric := 1.0;
  v_cogs_amount numeric := 0;
  v_entry_date date;
  v_customer_name text;
  v_currency text;
  v_revenue_code text;
BEGIN
  -- 1. Get Matching Company ID from accounts table
  SELECT company_id INTO v_company_id FROM public.accounts WHERE company_id IS NOT NULL LIMIT 1;
  IF v_company_id IS NULL THEN 
    v_company_id := 'a0000000-0000-0000-0000-000000000001'::uuid;
  END IF;

  -- 2. Fetch Export Shipment
  SELECT * INTO v_shipment
  FROM public.export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'لا يوجد عميل مخصص للشحنة');
  END IF;

  -- 3. Calculate Revenue from Items
  SELECT COALESCE(
    SUM(COALESCE(NULLIF(amount, 0), quantity * COALESCE(export_price_per_carton, price, 0))),
    0
  )
  INTO v_total_revenue
  FROM public.export_shipment_items
  WHERE shipment_id = p_shipment_id;

  IF v_total_revenue = 0 THEN
    v_total_revenue := COALESCE(v_shipment.total_revenue_foreign, 0);
  END IF;

  v_discount := COALESCE(v_shipment.discount_amount, 0);
  v_paid := COALESCE(v_shipment.paid_amount, 0);
  v_net_revenue := GREATEST(v_total_revenue - v_discount, 0);

  -- 4. Currency and Exchange Rate
  v_currency := COALESCE(NULLIF(v_shipment.currency_code, ''), NULLIF(v_shipment.currency, ''), 'USD');
  v_exch_rate := COALESCE(v_shipment.exchange_rate, 1.0);
  IF v_exch_rate <= 0 THEN
    v_exch_rate := 1.0;
  END IF;

  v_base_revenue := ROUND(v_total_revenue * v_exch_rate, 2);
  v_base_discount := ROUND(v_discount * v_exch_rate, 2);
  v_base_net := ROUND(v_net_revenue * v_exch_rate, 2);
  v_base_paid := ROUND(v_paid * v_exch_rate, 2);

  -- 5. Calculate COGS (Cost of Goods Sold)
  SELECT COALESCE(SUM(
    ROUND(
      COALESCE(esi.quantity, 0) * 
      COALESCE(
        CASE WHEN COALESCE(pol.carton_count, 0) > 0 THEN pol.final_cost / pol.carton_count ELSE NULL END,
        NULLIF(esi.price, 0),
        po.packing_cost_per_carton,
        0
      ),
      2
    )
  ), 0)
  INTO v_cogs_amount
  FROM public.export_shipment_items esi
  LEFT JOIN public.packing_order_lines pol ON pol.id = esi.packing_order_line_id
  LEFT JOIN public.packing_orders po ON po.id = esi.packing_order_id
  WHERE esi.shipment_id = p_shipment_id;

  IF v_cogs_amount = 0 THEN
    v_cogs_amount := COALESCE(v_shipment.total_fruit_cost, 0) + COALESCE(v_shipment.total_packing_material_cost, 0);
  END IF;
  IF v_cogs_amount = 0 AND COALESCE(v_shipment.cost_per_carton, 0) > 0 AND COALESCE(v_shipment.carton_count, 0) > 0 THEN
    v_cogs_amount := ROUND(v_shipment.cost_per_carton * v_shipment.carton_count, 2);
  END IF;
  IF v_cogs_amount = 0 AND COALESCE(v_shipment.total_landed_cost, 0) > 0 THEN
    v_cogs_amount := v_shipment.total_landed_cost;
  END IF;

  -- 6. Update Shipment Record with figures
  UPDATE public.export_shipments
  SET currency_code = v_currency,
      currency = v_currency,
      exchange_rate = v_exch_rate,
      total_revenue_foreign = v_total_revenue,
      total_revenue_egp = v_base_revenue,
      total_fruit_cost = v_cogs_amount,
      updated_at = now()
  WHERE id = p_shipment_id;

  -- 7. Clean up existing Journal Entries for this shipment
  FOR v_je_id IN
      SELECT id FROM public.journal_entries
      WHERE (source_type IN ('export_shipment', 'export_discount', 'customer_payment') AND source_id = p_shipment_id::text)
         OR (description ILIKE '%' || v_shipment.shipment_no || '%')
  LOOP
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      DELETE FROM public.journal_entries WHERE id = v_je_id;
  END LOOP;

  -- 8. Customer Ledger cleanup & update
  SELECT
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM public.ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  UPDATE public.customers
  SET balance = COALESCE(balance, 0) - v_old_amount + (v_net_revenue - v_paid),
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  DELETE FROM public.ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- 9. Resolve GL Accounts (Strictly Level 5 Leaf Accounts)
  -- A. AR Account (حساب العميل): 12511 (عملاء تصدير) أو 12512 (عملاء محلي)
  SELECT c.account_id INTO v_raw_ar FROM public.customers c WHERE c.id = v_shipment.customer_id;
  IF v_raw_ar IS NOT NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE id = v_raw_ar AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;

  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code = '12511' AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;
  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code = '12512' AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;
  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code LIKE '1251%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;
  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code LIKE '125%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;

  -- B. Revenue Account (حساب الإيراد): حسب نوع المحصول 41111 (فراولة), 41112 (مانجو), 41113 (بلح), 41114 (بلوبيري)
  SELECT 
    CASE 
      WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%مانجو%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%mango%') THEN '41112'
      WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%بلح%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%تمر%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%date%') THEN '41113'
      WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%فراول%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%strawberr%') THEN '41111'
      WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%بلوبير%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%blueberr%') THEN '41114'
      WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%فرز%') THEN '41121'
      ELSE NULL
    END
  INTO v_revenue_code
  FROM public.export_shipment_items
  WHERE shipment_id = p_shipment_id;

  IF v_revenue_code IS NOT NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = v_revenue_code AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;

  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = '41112' AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;
  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code LIKE '4111%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;
  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code LIKE '41%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;

  -- C. Discount Account: 41131 (خصم مسموح به - مبيعات تصدير)
  SELECT id INTO v_disc_acct FROM public.accounts WHERE account_code = '41131' AND is_leaf = true AND is_active = true LIMIT 1;
  IF v_disc_acct IS NULL THEN
    SELECT id INTO v_disc_acct FROM public.accounts WHERE account_name ILIKE '%خصم%' AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;

  -- D. Inventory Account: 12413 (مخزن الإنتاج التام)
  SELECT id INTO v_inv_acct FROM public.accounts WHERE account_code = '12413' AND is_leaf = true AND is_active = true LIMIT 1;
  IF v_inv_acct IS NULL THEN
    SELECT id INTO v_inv_acct FROM public.accounts WHERE account_code LIKE '1241%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;

  -- E. COGS Account: 34111 (تكاليف مشتريات خام / تكلفة المحاصيل المباعة - مستوى 5 ترحيل معتمد)
  SELECT id INTO v_cogs_acct FROM public.accounts 
  WHERE account_code = '34111' AND is_leaf = true AND is_active = true LIMIT 1;

  IF v_cogs_acct IS NULL THEN
    SELECT id INTO v_cogs_acct FROM public.accounts 
    WHERE account_code LIKE '3411%' AND is_leaf = true AND is_active = true 
    ORDER BY account_code LIMIT 1;
  END IF;

  IF v_cogs_acct IS NULL THEN
    SELECT id INTO v_cogs_acct FROM public.accounts 
    WHERE account_code LIKE '341%' AND is_leaf = true AND is_active = true 
    ORDER BY account_code LIMIT 1;
  END IF;

  -- F. Treasury / Bank Account (في حالة السداد)
  IF v_paid > 0 THEN
    IF v_shipment.payment_source_type = 'bank' THEN
      IF v_currency = 'USD' THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12112' AND is_leaf = true AND is_active = true LIMIT 1; -- CIB USD
      ELSE
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12111' AND is_leaf = true AND is_active = true LIMIT 1; -- CIB EGP
      END IF;
      IF v_pay_acct IS NULL THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code LIKE '1211%' AND is_leaf = true AND is_active = true LIMIT 1;
      END IF;
    ELSE
      IF v_currency = 'USD' THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12212' AND is_leaf = true AND is_active = true LIMIT 1; -- Treasury USD
      ELSE
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12211' AND is_leaf = true AND is_active = true LIMIT 1; -- Treasury EGP
      END IF;
      IF v_pay_acct IS NULL THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code LIKE '1221%' AND is_leaf = true AND is_active = true LIMIT 1;
      END IF;
    END IF;
  END IF;

  -- 10. Dates and Descriptions
  v_entry_date := COALESCE(
    v_shipment.shipment_date,
    (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::date,
    CURRENT_DATE
  );
  SELECT name INTO v_customer_name FROM public.customers WHERE id = v_shipment.customer_id;
  v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no || COALESCE(' - العميل: ' || v_customer_name, '');

  -- 11. Legacy Customer Ledger Records
  IF v_total_revenue > 0 THEN
    INSERT INTO public.ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      v_currency, 'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  IF v_discount > 0 THEN
    INSERT INTO public.ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
      v_currency, 'export_shipment', p_shipment_id::TEXT, v_desc || ' (خصم مسموح به)', p_user_id
    );
  END IF;

  IF v_paid > 0 THEN
    INSERT INTO public.ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'credit', v_paid,
      v_currency, 'export_shipment', p_shipment_id::TEXT, v_desc || ' (سداد دفعة نقدية)', p_user_id
    );
  END IF;

  -- 12. ── JOURNAL ENTRY 1: Sales Revenue & Discount (متزن تماماً مدين = دائن) ──
  IF v_total_revenue > 0 AND v_ar_acct IS NOT NULL AND v_rev_acct IS NOT NULL THEN
    v_sale_lines := jsonb_build_array();

    -- الطرف المدين: العميل بالصافي المستحق
    IF v_net_revenue > 0 THEN
      v_sale_lines := v_sale_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', v_ar_acct,
          'debit', v_net_revenue,
          'credit', 0,
          'base_debit', v_base_net,
          'base_credit', 0,
          'currency', v_currency,
          'description', v_desc || ' - استحقاق صافي قيمة الشحنة'
        )
      );
    END IF;

    -- الطرف المدين: الخصم المسموح به (إذا وجد)
    IF v_discount > 0 THEN
      v_sale_lines := v_sale_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', COALESCE(v_disc_acct, v_rev_acct),
          'debit', v_discount,
          'credit', 0,
          'base_debit', v_base_discount,
          'base_credit', 0,
          'currency', v_currency,
          'description', v_desc || ' - خصم مسموح به'
        )
      );
    END IF;

    -- الطرف الدائن: إيرادات مبيعات المحاصيل بالإجمالي
    v_sale_lines := v_sale_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', v_rev_acct,
        'debit', 0,
        'credit', v_total_revenue,
        'base_debit', 0,
        'base_credit', v_base_revenue,
        'currency', v_currency,
        'description', v_desc || ' - إيرادات مبيعات المحاصيل'
      )
    );

    v_sale_je_id := public.post_journal_entry(
      'export_shipment',
      v_desc || ' - إثبات مبيعات التصدير',
      v_entry_date,
      v_company_id,
      p_user_id,
      v_sale_lines,
      p_shipment_id::text
    );
  END IF;

  -- 13. ── JOURNAL ENTRY 2: Cost of Goods Sold (تكلفة البضاعة المباعة والمخزون) ──
  IF v_cogs_amount > 0 AND v_cogs_acct IS NOT NULL AND v_inv_acct IS NOT NULL THEN
    v_cogs_je_id := public.post_journal_entry(
      'export_shipment',
      v_desc || ' - تكلفة البضاعة المباعة',
      v_entry_date,
      v_company_id,
      p_user_id,
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cogs_acct,
          'debit', v_cogs_amount,
          'credit', 0,
          'base_debit', v_cogs_amount,
          'base_credit', 0,
          'currency', 'EGP',
          'description', v_desc || ' - تكلفة المحاصيل المباعة'
        ),
        jsonb_build_object(
          'account_id', v_inv_acct,
          'debit', 0,
          'credit', v_cogs_amount,
          'base_debit', 0,
          'base_credit', v_cogs_amount,
          'currency', 'EGP',
          'description', v_desc || ' - صرف من مخزن الإنتاج التام (12413)'
        )
      ),
      p_shipment_id::text
    );
  END IF;

  -- 14. ── JOURNAL ENTRY 3: Customer Advance Payment (سداد العميل النقدي / البنكي) ──
  IF v_paid > 0 AND v_pay_acct IS NOT NULL AND v_ar_acct IS NOT NULL THEN
    v_pay_je_id := public.post_journal_entry(
      'customer_payment',
      v_desc || ' - سداد دفعة من العميل',
      v_entry_date,
      v_company_id,
      p_user_id,
      jsonb_build_array(
        jsonb_build_object(
          'account_id', v_pay_acct,
          'debit', v_paid,
          'credit', 0,
          'base_debit', v_base_paid,
          'base_credit', 0,
          'currency', v_currency,
          'description', v_desc || ' - إيداع مسدد من العميل'
        ),
        jsonb_build_object(
          'account_id', v_ar_acct,
          'debit', 0,
          'credit', v_paid,
          'base_debit', 0,
          'base_credit', v_base_paid,
          'currency', v_currency,
          'description', v_desc || ' - تخفيض حساب العميل بالمسدد'
        )
      ),
      p_shipment_id::text
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم ترحيل قيود الشحنة بنجاح باستخدام حسابات المستوى الخامس',
    'sale_journal_entry_id', v_sale_je_id,
    'cogs_journal_entry_id', v_cogs_je_id,
    'cogs_account_code', '34111',
    'payment_journal_entry_id', v_pay_je_id,
    'revenue_egp', v_base_revenue,
    'discount_egp', v_base_discount,
    'net_egp', v_base_net,
    'cogs_egp', v_cogs_amount,
    'paid_egp', v_base_paid
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(bigint, uuid) TO authenticated, service_role, anon;

-- ── 4. Deploy updated post_journal_entry with Leaf Account Validation ─────────
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
AS $$
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
    v_cost_center_id TEXT;
    v_branch_id     BIGINT;
    v_actual_date   DATE;
    v_base_amount   NUMERIC;
    v_is_leaf       BOOLEAN;
    v_acct_code     TEXT;
BEGIN
    -- Idempotency safeguard
    IF p_source_type IS NOT NULL AND p_source_id IS NOT NULL 
       AND p_source_type NOT IN ('manual', 'adjustment', 'lot_price_adjustment') THEN
        SELECT id INTO v_je_id
        FROM public.journal_entries
        WHERE source_type = p_source_type
          AND source_id = p_source_id
          AND deleted_at IS NULL
        ORDER BY id ASC
        LIMIT 1;

        IF v_je_id IS NOT NULL THEN
            RETURN v_je_id;
        END IF;
    END IF;

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
        v_account_id    := (v_line->>'account_id')::BIGINT;
        v_debit         := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit        := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit    := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit   := COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency      := COALESCE(v_line->>'currency', 'EGP');
        v_desc          := COALESCE(v_line->>'description', p_description);
        v_cost_center_id:= COALESCE(NULLIF(v_line->>'cost_center_id', ''), NULL);
        v_branch_id     := CASE WHEN (v_line->>'branch_id') ~ '^[0-9]+$' THEN (v_line->>'branch_id')::BIGINT ELSE NULL END;

        -- Strict validation: Account must exist AND be a leaf posting account
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
            currency, amount_in_base_currency, description, company_id, cost_center_id, branch_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, v_base_amount, v_desc, p_company_id, v_cost_center_id, v_branch_id
        );
    END LOOP;

    -- Balance check
    IF ROUND(v_total_debit, 2) != ROUND(v_total_credit, 2) THEN
        RAISE EXCEPTION 'Journal entry lines do not balance: Debit = %, Credit = % (diff: %)',
            v_total_debit, v_total_credit, ABS(v_total_debit - v_total_credit);
    END IF;

    RETURN v_je_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;

COMMIT;
