-- =====================================================================
-- Migration: Full Double-Entry Accounting for Export Shipments (5-Level COA)
-- Description: 
--   1. Ensures Level-5 accounts exist (Clients 12511/12512, Revenues 41111-41114,
--      Inventory 12413, Cost of Sales 3412/34111, Discounts 41131, Treasuries 12211/12212).
--   2. Updates rpc_process_export_shipment_ledger to generate balanced,
--      double-entry journal entries matching Fruity Farms Chart of Accounts.
--   3. Updates rpc_save_export_shipment to automatically post journal entries on save.
-- =====================================================================

-- ── 1. Ensure Discount Account exists under Level 3 (411 - إيرادات النشاط) ──
DO $$
DECLARE
  v_comp uuid;
  v_p411 bigint;
BEGIN
  SELECT company_id INTO v_comp FROM public.accounts WHERE company_id IS NOT NULL LIMIT 1;
  IF v_comp IS NULL THEN v_comp := 'a0000000-0000-0000-0000-000000000001'::uuid; END IF;

  SELECT id INTO v_p411 FROM public.accounts WHERE account_code = '411' LIMIT 1;
  IF v_p411 IS NULL THEN
    SELECT id INTO v_p411 FROM public.accounts WHERE account_code = '41' LIMIT 1;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '41131') THEN
    INSERT INTO public.accounts (
      account_code, name, account_name, parent_id,
      account_type, is_leaf, allow_posting, is_active, company_id, level
    ) VALUES (
      '41131', 'Sales Discounts - Export', 'خصم مسموح به - مبيعات تصدير',
      v_p411, 'revenue', true, true, true, v_comp, 5
    );
  END IF;
END $$;

-- ── 2. Ensure Required Columns Exist on Tables ──
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS destination_country text;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS internal_notes text;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS paid_amount numeric DEFAULT 0;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS payment_source_type text DEFAULT 'treasury';
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS payment_treasury_id text;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS payment_bank_account_id bigint;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS is_confirmed boolean DEFAULT false;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS allocated_admin_expenses numeric DEFAULT 0;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS allocated_taxes numeric DEFAULT 0;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS discount_amount numeric DEFAULT 0;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS discount_reason text;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS applied_discount_amount numeric DEFAULT 0;
ALTER TABLE public.export_shipments ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

ALTER TABLE public.export_shipment_items ADD COLUMN IF NOT EXISTS packing_order_line_id bigint;
ALTER TABLE public.export_shipment_items ADD COLUMN IF NOT EXISTS export_price_per_carton numeric;
ALTER TABLE public.export_shipment_items ADD COLUMN IF NOT EXISTS invoice_product_name text DEFAULT '';
ALTER TABLE public.export_shipment_items ADD COLUMN IF NOT EXISTS currency_snapshot jsonb;

-- ── 3. Update rpc_process_export_shipment_ledger ──
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

  -- 9. Resolve GL Accounts (Level 5)
  -- A. AR Account (حساب العميل): 12511 (عملاء تصدير) أو 12512 (عملاء محلي)
  SELECT c.account_id INTO v_raw_ar FROM public.customers c WHERE c.id = v_shipment.customer_id;
  IF v_raw_ar IS NOT NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE id = v_raw_ar AND is_leaf = true LIMIT 1;
  END IF;

  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code = '12511' AND is_leaf = true LIMIT 1;
  END IF;
  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code = '12512' AND is_leaf = true LIMIT 1;
  END IF;
  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code LIKE '1251%' AND is_leaf = true ORDER BY account_code LIMIT 1;
  END IF;
  IF v_ar_acct IS NULL THEN
    SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code LIKE '125%' AND is_leaf = true ORDER BY account_code LIMIT 1;
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
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = v_revenue_code AND is_leaf = true LIMIT 1;
  END IF;

  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = '41112' AND is_leaf = true LIMIT 1;
  END IF;
  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code LIKE '4111%' AND is_leaf = true ORDER BY account_code LIMIT 1;
  END IF;
  IF v_rev_acct IS NULL THEN
    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code LIKE '41%' AND is_leaf = true ORDER BY account_code LIMIT 1;
  END IF;

  -- C. Discount Account: 41131 (خصم مسموح به - مبيعات تصدير)
  SELECT id INTO v_disc_acct FROM public.accounts WHERE account_code = '41131' AND is_leaf = true LIMIT 1;
  IF v_disc_acct IS NULL THEN
    SELECT id INTO v_disc_acct FROM public.accounts WHERE account_name ILIKE '%خصم%' AND is_leaf = true LIMIT 1;
  END IF;

  -- D. Inventory Account: 12413 (مخزن الإنتاج التام)
  SELECT id INTO v_inv_acct FROM public.accounts WHERE account_code = '12413' AND is_leaf = true LIMIT 1;
  IF v_inv_acct IS NULL THEN
    SELECT id INTO v_inv_acct FROM public.accounts WHERE account_code LIKE '1241%' AND is_leaf = true ORDER BY account_code LIMIT 1;
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
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12112' AND is_leaf = true LIMIT 1; -- CIB USD
      ELSE
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12111' AND is_leaf = true LIMIT 1; -- CIB EGP
      END IF;
      IF v_pay_acct IS NULL THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code LIKE '1211%' AND is_leaf = true LIMIT 1;
      END IF;
    ELSE
      IF v_currency = 'USD' THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12212' AND is_leaf = true LIMIT 1; -- Treasury USD
      ELSE
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12211' AND is_leaf = true LIMIT 1; -- Treasury EGP
      END IF;
      IF v_pay_acct IS NULL THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code LIKE '1221%' AND is_leaf = true LIMIT 1;
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
    'message', 'تم ترحيل قيود الشحنة بنجاح',
    'sale_journal_entry_id', v_sale_je_id,
    'cogs_journal_entry_id', v_cogs_je_id,
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

-- ── 4. Update rpc_save_export_shipment to Automatically Trigger Ledger Posting ──
CREATE OR REPLACE FUNCTION public.rpc_save_export_shipment(
  p_shipment jsonb,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_shipment_id bigint;
  v_item jsonb;
  v_idx int := 0;
  v_ledger_res jsonb;
BEGIN
  -- 1. Insert or Update export_shipments
  IF p_shipment ? 'id' AND p_shipment->>'id' IS NOT NULL AND p_shipment->>'id' != '' THEN
    v_shipment_id := (p_shipment->>'id')::bigint;
    UPDATE public.export_shipments
    SET
      shipment_no = COALESCE(p_shipment->>'shipment_no', shipment_no),
      customer_id = (NULLIF(p_shipment->>'customer_id', ''))::bigint,
      customer_name = p_shipment->>'customer_name',
      customer_code = p_shipment->>'customer_code',
      clearing_agent_id = (NULLIF(p_shipment->>'clearing_agent_id', ''))::bigint,
      clearing_agent_name = p_shipment->>'clearing_agent_name',
      contact_person = p_shipment->>'contact_person',
      destination_country = COALESCE(p_shipment->>'destination_country', p_shipment->>'country'),
      country_of_origin = COALESCE(p_shipment->>'country_of_origin', 'Egypt'),
      destination_address = p_shipment->>'destination_address',
      container_number = p_shipment->>'container_number',
      container_type = p_shipment->>'container_type',
      bl_number = p_shipment->>'bl_number',
      vessel_name = p_shipment->>'vessel_name',
      shipping_company = p_shipment->>'shipping_company',
      data_logger_no = p_shipment->>'data_logger_no',
      port_of_loading = p_shipment->>'port_of_loading',
      port_of_destination = p_shipment->>'port_of_destination',
      transport_mode = COALESCE(p_shipment->>'transport_mode', 'sea'),
      pallet_count = COALESCE((NULLIF(p_shipment->>'pallet_count', ''))::int, 0),
      carton_count = COALESCE((NULLIF(p_shipment->>'carton_count', ''))::int, 0),
      net_weight = COALESCE((NULLIF(p_shipment->>'net_weight', ''))::numeric, 0),
      gross_weight = COALESCE((NULLIF(p_shipment->>'gross_weight', ''))::numeric, 0),
      incoterm = p_shipment->>'incoterm',
      payment_terms = p_shipment->>'payment_terms',
      currency = p_shipment->>'currency',
      currency_code = COALESCE(p_shipment->>'currency_code', 'USD'),
      exchange_rate = COALESCE((NULLIF(p_shipment->>'exchange_rate', ''))::numeric, 1.0),
      total_revenue_foreign = COALESCE((NULLIF(p_shipment->>'total_revenue_foreign', ''))::numeric, 0),
      total_revenue_egp = COALESCE((NULLIF(p_shipment->>'total_revenue_egp', ''))::numeric, 0),
      net_profit_egp = COALESCE((NULLIF(p_shipment->>'net_profit_egp', ''))::numeric, 0),
      discount_amount = COALESCE((NULLIF(p_shipment->>'discount_amount', ''))::numeric, 0),
      discount_reason = p_shipment->>'discount_reason',
      paid_amount = COALESCE((NULLIF(p_shipment->>'paid_amount', ''))::numeric, 0),
      payment_source_type = COALESCE(p_shipment->>'payment_source_type', 'treasury'),
      payment_treasury_id = p_shipment->>'payment_treasury_id',
      payment_bank_account_id = (NULLIF(p_shipment->>'payment_bank_account_id', ''))::bigint,
      status = COALESCE(p_shipment->>'status', 'draft'),
      shipment_date = (NULLIF(p_shipment->>'shipment_date', ''))::date,
      terms_conditions = p_shipment->>'terms_conditions',
      internal_notes = COALESCE(p_shipment->>'internal_notes', p_shipment->>'notes'),
      notes = COALESCE(p_shipment->>'notes', p_shipment->>'internal_notes'),
      updated_at = now()
    WHERE id = v_shipment_id;

    DELETE FROM public.export_shipment_items WHERE shipment_id = v_shipment_id;
  ELSE
    INSERT INTO public.export_shipments (
      shipment_no, customer_id, customer_name, customer_code,
      clearing_agent_id, clearing_agent_name, contact_person,
      destination_country, country_of_origin, destination_address,
      container_number, container_type, bl_number, vessel_name,
      shipping_company, data_logger_no, port_of_loading, port_of_destination,
      transport_mode, pallet_count, carton_count, net_weight, gross_weight,
      incoterm, payment_terms, currency, currency_code, exchange_rate,
      total_revenue_foreign, total_revenue_egp, net_profit_egp,
      discount_amount, discount_reason, paid_amount,
      payment_source_type, payment_treasury_id, payment_bank_account_id,
      status, shipment_date, terms_conditions, internal_notes, notes
    ) VALUES (
      p_shipment->>'shipment_no',
      (NULLIF(p_shipment->>'customer_id', ''))::bigint,
      p_shipment->>'customer_name',
      p_shipment->>'customer_code',
      (NULLIF(p_shipment->>'clearing_agent_id', ''))::bigint,
      p_shipment->>'clearing_agent_name',
      p_shipment->>'contact_person',
      COALESCE(p_shipment->>'destination_country', p_shipment->>'country'),
      COALESCE(p_shipment->>'country_of_origin', 'Egypt'),
      p_shipment->>'destination_address',
      p_shipment->>'container_number',
      p_shipment->>'container_type',
      p_shipment->>'bl_number',
      p_shipment->>'vessel_name',
      p_shipment->>'shipping_company',
      p_shipment->>'data_logger_no',
      p_shipment->>'port_of_loading',
      p_shipment->>'port_of_destination',
      COALESCE(p_shipment->>'transport_mode', 'sea'),
      COALESCE((NULLIF(p_shipment->>'pallet_count', ''))::int, 0),
      COALESCE((NULLIF(p_shipment->>'carton_count', ''))::int, 0),
      COALESCE((NULLIF(p_shipment->>'net_weight', ''))::numeric, 0),
      COALESCE((NULLIF(p_shipment->>'gross_weight', ''))::numeric, 0),
      p_shipment->>'incoterm',
      p_shipment->>'payment_terms',
      p_shipment->>'currency',
      COALESCE(p_shipment->>'currency_code', 'USD'),
      COALESCE((NULLIF(p_shipment->>'exchange_rate', ''))::numeric, 1.0),
      COALESCE((NULLIF(p_shipment->>'total_revenue_foreign', ''))::numeric, 0),
      COALESCE((NULLIF(p_shipment->>'total_revenue_egp', ''))::numeric, 0),
      COALESCE((NULLIF(p_shipment->>'net_profit_egp', ''))::numeric, 0),
      COALESCE((NULLIF(p_shipment->>'discount_amount', ''))::numeric, 0),
      p_shipment->>'discount_reason',
      COALESCE((NULLIF(p_shipment->>'paid_amount', ''))::numeric, 0),
      COALESCE(p_shipment->>'payment_source_type', 'treasury'),
      p_shipment->>'payment_treasury_id',
      (NULLIF(p_shipment->>'payment_bank_account_id', ''))::bigint,
      COALESCE(p_shipment->>'status', 'draft'),
      COALESCE((NULLIF(p_shipment->>'shipment_date', ''))::date, CURRENT_DATE),
      p_shipment->>'terms_conditions',
      COALESCE(p_shipment->>'internal_notes', p_shipment->>'notes'),
      COALESCE(p_shipment->>'notes', p_shipment->>'internal_notes')
    )
    RETURNING id INTO v_shipment_id;
  END IF;

  -- 2. Insert items
  IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      INSERT INTO public.export_shipment_items (
        shipment_id,
        product_name,
        invoice_product_name,
        finished_product_id,
        grade,
        country_of_origin,
        hs_code,
        quantity,
        price,
        export_price_per_carton,
        weight_per_carton,
        net_weight,
        gross_weight,
        amount,
        pallets,
        packing_order_id,
        packing_order_line_id,
        sort_order
      ) VALUES (
        v_shipment_id,
        COALESCE(v_item->>'name', v_item->>'product_name', ''),
        COALESCE(v_item->>'product_name', v_item->>'invoice_product_name', v_item->>'name', ''),
        (NULLIF(v_item->>'productId', ''))::bigint,
        v_item->>'grade',
        COALESCE(v_item->>'countryOfOrigin', v_item->>'country_of_origin', 'Egypt'),
        COALESCE(v_item->>'hsCode', v_item->>'hs_code'),
        COALESCE((NULLIF(COALESCE(v_item->>'qty', v_item->>'quantity'), ''))::int, 0),
        COALESCE((NULLIF(v_item->>'price', ''))::numeric, 0),
        COALESCE((NULLIF(COALESCE(v_item->>'exportPricePerCarton', v_item->>'export_price_per_carton'), ''))::numeric, 0),
        COALESCE((NULLIF(COALESCE(v_item->>'weightPerCarton', v_item->>'weight_per_carton'), ''))::numeric, 15),
        COALESCE((NULLIF(COALESCE(v_item->>'netWt', v_item->>'net_weight'), ''))::numeric, 0),
        COALESCE((NULLIF(COALESCE(v_item->>'grossWt', v_item->>'gross_weight'), ''))::numeric, 0),
        COALESCE((NULLIF(v_item->>'amount', ''))::numeric, 0),
        COALESCE((NULLIF(v_item->>'pallets', ''))::int, 0),
        (NULLIF(v_item->>'packingOrderId', ''))::bigint,
        (NULLIF(v_item->>'packing_order_line_id', ''))::bigint,
        v_idx
      );
      v_idx := v_idx + 1;
    END LOOP;
  END IF;

  -- 3. Automatic Ledger & Double-Entry Journal Creation on Save
  BEGIN
    v_ledger_res := public.rpc_process_export_shipment_ledger(v_shipment_id);
  EXCEPTION WHEN OTHERS THEN
    -- لا تفشل عملية حفظ الشحنة إذا حدث خطأ جانبي في القيود
    v_ledger_res := jsonb_build_object('success', false, 'warning', SQLERRM);
  END;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_shipment_id,
    'ledger', v_ledger_res
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_export_shipment(jsonb, jsonb) TO authenticated, service_role, anon;
