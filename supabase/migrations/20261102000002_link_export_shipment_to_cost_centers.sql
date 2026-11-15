-- ==============================================================================
-- Migration: 20261102000002_link_export_shipment_to_cost_centers.sql
-- Description:
--   1. Adds shipment_no, packing_order_number, and packing_order_id columns
--      to public.cost_center_transactions for full traceability.
--   2. Updates rpc_process_export_shipment_ledger to:
--      a) Explicitly map each exported fruit item / revenue line to its
--         corresponding variety Cost Center (e.g. CC-MANGO-2026-2027)
--         and leaf Revenue GL Account (Level 5).
--      b) Pass cost_center_id in journal entry lines for sales revenue, COGS,
--         discounts, and inventory deduction.
--      c) Insert or upsert granular records into public.cost_center_transactions
--         carrying shipment_no, packing_order_number, quantity, unit price,
--         and revenue in foreign & base currency (EGP), ensuring immediate
--         real-time visibility in the Cost Centers report without manual intervention.
-- ==============================================================================

-- ── 1. Schema Enhancements: Add Traceability Columns ─────────────────────────
ALTER TABLE public.cost_center_transactions
  ADD COLUMN IF NOT EXISTS shipment_no text,
  ADD COLUMN IF NOT EXISTS packing_order_number text,
  ADD COLUMN IF NOT EXISTS packing_order_id bigint;

CREATE INDEX IF NOT EXISTS idx_cct_shipment_no ON public.cost_center_transactions(shipment_no);
CREATE INDEX IF NOT EXISTS idx_cct_packing_order_id ON public.cost_center_transactions(packing_order_id);

-- ── 2. Deploy Updated rpc_process_export_shipment_ledger ──────────────────────
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
  v_disc_acct bigint;
  v_cogs_acct bigint;
  v_inv_acct bigint;
  v_pay_acct bigint;
  v_sale_lines jsonb := '[]'::jsonb;
  v_cogs_lines jsonb := '[]'::jsonb;
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
  v_total_cogs numeric := 0;
  v_entry_date date;
  v_customer_name text;
  v_currency text;

  -- Item iteration variables
  v_item RECORD;
  v_item_crop_name text;
  v_item_foreign numeric;
  v_item_egp numeric;
  v_item_qty numeric;
  v_item_price_foreign numeric;
  v_item_price_egp numeric;
  v_item_cogs numeric;
  v_item_rev_acct bigint;
  v_item_rev_code text;
  v_cc_code text;
  v_cc_name text;
  v_cc_db_id bigint;
  v_po_order_num text;
  v_po_product_name text;
  v_po_fruit_type_id bigint;
  v_display_po text;
  v_first_cc_code text := NULL;
  v_items_count int := 0;
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

  -- 3. Calculate Currency & Exchange Rate
  v_currency := COALESCE(NULLIF(v_shipment.currency_code, ''), NULLIF(v_shipment.currency, ''), 'USD');
  v_exch_rate := COALESCE(v_shipment.exchange_rate, 1.0);
  IF v_exch_rate <= 0 THEN
    v_exch_rate := 1.0;
  END IF;

  -- Calculate Revenue from Items
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

  v_base_revenue := ROUND(v_total_revenue * v_exch_rate, 2);
  v_base_discount := ROUND(v_discount * v_exch_rate, 2);
  v_base_net := ROUND(v_net_revenue * v_exch_rate, 2);
  v_base_paid := ROUND(v_paid * v_exch_rate, 2);

  -- 4. Clean up existing Journal Entries for this shipment
  FOR v_je_id IN
      SELECT id FROM public.journal_entries
      WHERE (source_type IN ('export_shipment', 'export_discount', 'customer_payment') AND source_id = p_shipment_id::text)
         OR (description ILIKE '%' || v_shipment.shipment_no || '%')
  LOOP
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      DELETE FROM public.journal_entries WHERE id = v_je_id;
  END LOOP;

  -- 5. Clean up existing Cost Center Transactions for this shipment
  DELETE FROM public.cost_center_transactions
  WHERE source_type = 'export_shipment'
    AND (source_id LIKE 'shipment_' || p_shipment_id || '_item_%' 
         OR source_id = 'shipment_' || p_shipment_id
         OR source_id = p_shipment_id::text);

  -- 6. Customer Ledger cleanup & update
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

  -- 7. Dates and Descriptions
  v_entry_date := COALESCE(
    v_shipment.shipment_date,
    (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::date,
    CURRENT_DATE
  );
  SELECT name INTO v_customer_name FROM public.customers WHERE id = v_shipment.customer_id;
  v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no || COALESCE(' - العميل: ' || v_customer_name, '');

  -- 8. Customer Ledger Records (Single-currency legacy ledger)
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

  -- 9. Resolve Shared Header Accounts (Strictly Level 5 Leaf Accounts)
  -- AR Account (حساب العميل): 12511 (عملاء تصدير) أو 12512 (عملاء محلي)
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

  -- Discount Account: 41131 (خصم مسموح به - مبيعات تصدير)
  SELECT id INTO v_disc_acct FROM public.accounts WHERE account_code = '41131' AND is_leaf = true AND is_active = true LIMIT 1;
  IF v_disc_acct IS NULL THEN
    SELECT id INTO v_disc_acct FROM public.accounts WHERE account_name ILIKE '%خصم%' AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;

  -- Inventory Account: 12413 (مخزن الإنتاج التام)
  SELECT id INTO v_inv_acct FROM public.accounts WHERE account_code = '12413' AND is_leaf = true AND is_active = true LIMIT 1;
  IF v_inv_acct IS NULL THEN
    SELECT id INTO v_inv_acct FROM public.accounts WHERE account_code LIKE '1241%' AND is_leaf = true AND is_active = true LIMIT 1;
  END IF;

  -- COGS Account: 34111 (تكاليف مشتريات خام / تكلفة المحاصيل المباعة)
  SELECT id INTO v_cogs_acct FROM public.accounts WHERE account_code = '34111' AND is_leaf = true AND is_active = true LIMIT 1;
  IF v_cogs_acct IS NULL THEN
    SELECT id INTO v_cogs_acct FROM public.accounts WHERE account_code LIKE '3411%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;
  IF v_cogs_acct IS NULL THEN
    SELECT id INTO v_cogs_acct FROM public.accounts WHERE account_code LIKE '341%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
  END IF;

  -- Treasury / Bank Account (في حالة السداد)
  IF v_paid > 0 THEN
    IF v_shipment.payment_source_type = 'bank' THEN
      IF v_currency = 'USD' THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12112' AND is_leaf = true AND is_active = true LIMIT 1;
      ELSE
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12111' AND is_leaf = true AND is_active = true LIMIT 1;
      END IF;
      IF v_pay_acct IS NULL THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code LIKE '1211%' AND is_leaf = true AND is_active = true LIMIT 1;
      END IF;
    ELSE
      IF v_currency = 'USD' THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12212' AND is_leaf = true AND is_active = true LIMIT 1;
      ELSE
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code = '12211' AND is_leaf = true AND is_active = true LIMIT 1;
      END IF;
      IF v_pay_acct IS NULL THEN
        SELECT id INTO v_pay_acct FROM public.accounts WHERE account_code LIKE '1221%' AND is_leaf = true AND is_active = true LIMIT 1;
      END IF;
    END IF;
  END IF;

  -- 10. Item Processing: Map Cost Centers, Build JE Lines, and Populate Cost Center Transactions
  v_sale_lines := jsonb_build_array();
  v_cogs_lines := jsonb_build_array();

  FOR v_item IN
    SELECT 
      esi.*,
      pol.final_cost AS pol_final_cost,
      pol.carton_count AS pol_carton_count,
      po.order_number AS po_order_number,
      po.product_name AS po_product_name,
      po.fruit_type_id AS po_fruit_type_id,
      po.packing_cost_per_carton AS po_packing_cost_per_carton
    FROM public.export_shipment_items esi
    LEFT JOIN public.packing_order_lines pol ON pol.id = esi.packing_order_line_id
    LEFT JOIN public.packing_orders po ON po.id = esi.packing_order_id
    WHERE esi.shipment_id = p_shipment_id
    ORDER BY esi.sort_order ASC, esi.id ASC
  LOOP
    v_items_count := v_items_count + 1;
    v_item_crop_name := COALESCE(NULLIF(v_item.product_name, ''), NULLIF(v_item.invoice_product_name, ''), v_item.po_product_name, 'محصول');
    v_po_order_num := v_item.po_order_number;
    v_po_fruit_type_id := v_item.po_fruit_type_id;
    v_display_po := COALESCE(NULLIF(v_po_order_num, ''), CASE WHEN v_item.packing_order_id IS NOT NULL THEN v_item.packing_order_id::text ELSE NULL END);

    -- A. Resolve Variety Cost Center
    v_cc_code := NULL;
    v_cc_name := NULL;
    v_cc_db_id := NULL;

    SELECT code, name_ar, id INTO v_cc_code, v_cc_name, v_cc_db_id
    FROM public.cost_centers
    WHERE is_active = true
      AND (
        ((v_item_crop_name ILIKE '%مانجو%' OR v_item_crop_name ILIKE '%mango%') AND (crop_code = 'MANGO' OR code LIKE 'CC-MANGO%' OR name_ar LIKE '%مانجو%'))
        OR ((v_item_crop_name ILIKE '%عنب%' OR v_item_crop_name ILIKE '%grape%') AND (crop_code = 'GRAPES' OR code LIKE 'CC-GRAPES%' OR name_ar LIKE '%عنب%'))
        OR ((v_item_crop_name ILIKE '%فراول%' OR v_item_crop_name ILIKE '%strawberr%') AND (crop_code = 'STRAWBERRY' OR code LIKE 'CC-STRAWBERRY%' OR name_ar LIKE '%فراول%'))
        OR ((v_item_crop_name ILIKE '%بلح%' OR v_item_crop_name ILIKE '%تمر%' OR v_item_crop_name ILIKE '%date%') AND (crop_code = 'DATES' OR code LIKE 'CC-DATES%' OR name_ar LIKE '%بلح%'))
        OR ((v_item_crop_name ILIKE '%بلوبير%' OR v_item_crop_name ILIKE '%blueberr%') AND (crop_code = 'BLUEBERRY' OR code LIKE 'CC-BLUEBERRY%' OR name_ar LIKE '%بلوبير%'))
        OR (v_po_fruit_type_id IS NOT NULL AND product_id = v_po_fruit_type_id)
        OR (name_ar ILIKE '%' || v_item_crop_name || '%' OR crop_name ILIKE '%' || v_item_crop_name || '%')
      )
    ORDER BY (CASE WHEN is_closed IS NOT TRUE THEN 0 ELSE 1 END), id ASC
    LIMIT 1;

    -- Fallback to active variety cost center
    IF v_cc_code IS NULL THEN
      SELECT code, name_ar, id INTO v_cc_code, v_cc_name, v_cc_db_id
      FROM public.cost_centers
      WHERE is_active = true AND (is_closed IS NOT TRUE OR is_closed IS NULL)
      ORDER BY id ASC LIMIT 1;
    END IF;

    IF v_first_cc_code IS NULL AND v_cc_code IS NOT NULL THEN
      v_first_cc_code := v_cc_code;
    END IF;

    -- B. Resolve Revenue GL Leaf Account (Level 5)
    v_item_rev_code := CASE
      WHEN v_item_crop_name ILIKE '%مانجو%' OR v_item_crop_name ILIKE '%mango%' THEN '41112'
      WHEN v_item_crop_name ILIKE '%بلح%' OR v_item_crop_name ILIKE '%تمر%' OR v_item_crop_name ILIKE '%date%' THEN '41113'
      WHEN v_item_crop_name ILIKE '%فراول%' OR v_item_crop_name ILIKE '%strawberr%' THEN '41111'
      WHEN v_item_crop_name ILIKE '%بلوبير%' OR v_item_crop_name ILIKE '%blueberr%' THEN '41114'
      WHEN v_item_crop_name ILIKE '%فرز%' THEN '41121'
      ELSE '41112'
    END;

    SELECT id INTO v_item_rev_acct FROM public.accounts WHERE account_code = v_item_rev_code AND is_leaf = true AND is_active = true LIMIT 1;
    IF v_item_rev_acct IS NULL THEN
      SELECT id INTO v_item_rev_acct FROM public.accounts WHERE account_code LIKE '4111%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
    END IF;
    IF v_item_rev_acct IS NULL THEN
      SELECT id INTO v_item_rev_acct FROM public.accounts WHERE account_code LIKE '41%' AND is_leaf = true AND is_active = true ORDER BY account_code LIMIT 1;
    END IF;

    -- C. Compute item financial figures
    v_item_foreign := COALESCE(NULLIF(v_item.amount, 0), v_item.quantity * COALESCE(v_item.export_price_per_carton, v_item.price, 0));
    v_item_egp := ROUND(v_item_foreign * v_exch_rate, 2);
    v_item_qty := COALESCE(v_item.quantity, 0);
    v_item_price_foreign := COALESCE(NULLIF(v_item.export_price_per_carton, 0), v_item.price, 0);
    v_item_price_egp := ROUND(v_item_price_foreign * v_exch_rate, 2);

    -- D. Build Revenue Credit Line
    IF v_item_foreign > 0 AND v_item_rev_acct IS NOT NULL THEN
      v_sale_lines := v_sale_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', v_item_rev_acct,
          'debit', 0,
          'credit', v_item_foreign,
          'base_debit', 0,
          'base_credit', v_item_egp,
          'currency', v_currency,
          'cost_center_id', v_cc_code,
          'description', v_desc || ' - إيراد مبيعات: ' || v_item_crop_name
        )
      );
    END IF;

    -- E. Compute Item COGS & Build COGS Line
    v_item_cogs := ROUND(
      COALESCE(v_item.quantity, 0) * 
      COALESCE(
        CASE WHEN COALESCE(v_item.pol_carton_count, 0) > 0 THEN v_item.pol_final_cost / v_item.pol_carton_count ELSE NULL END,
        NULLIF(v_item.price, 0),
        v_item.po_packing_cost_per_carton,
        0
      ),
      2
    );
    v_total_cogs := v_total_cogs + v_item_cogs;

    IF v_item_cogs > 0 AND v_cogs_acct IS NOT NULL AND v_inv_acct IS NOT NULL THEN
      v_cogs_lines := v_cogs_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cogs_acct,
          'debit', v_item_cogs,
          'credit', 0,
          'base_debit', v_item_cogs,
          'base_credit', 0,
          'currency', 'EGP',
          'cost_center_id', v_cc_code,
          'description', v_desc || ' - تكلفة مبيعات: ' || v_item_crop_name
        ),
        jsonb_build_object(
          'account_id', v_inv_acct,
          'debit', 0,
          'credit', v_item_cogs,
          'base_debit', 0,
          'base_credit', v_item_cogs,
          'currency', 'EGP',
          'cost_center_id', v_cc_code,
          'description', v_desc || ' - صرف من مخزن الإنتاج التام (12413): ' || v_item_crop_name
        )
      );
    END IF;

    -- F. Insert record into public.cost_center_transactions for this item
    INSERT INTO public.cost_center_transactions (
      cost_center_id,
      cost_center_code,
      cost_center_name,
      cost_center_type,
      source_type,
      source_id,
      transaction_date,
      supplier_id,
      supplier_name,
      product_id,
      item_name,
      category,
      quantity,
      unit_price,
      currency,
      exchange_rate,
      total_in_currency,
      amount,
      amount_in_base_currency,
      description,
      notes,
      shipment_no,
      packing_order_number,
      packing_order_id,
      is_confirmed,
      created_at,
      updated_at
    ) VALUES (
      COALESCE(v_cc_code, 'CC-MANGO-2026-2027'),
      COALESCE(v_cc_code, 'CC-MANGO-2026-2027'),
      COALESCE(v_cc_name, 'مركز التكلفة'),
      'variety',
      'export_shipment',
      'shipment_' || p_shipment_id || '_item_' || v_item.id,
      v_entry_date,
      v_shipment.customer_id::text,
      COALESCE(v_customer_name, v_shipment.customer_name, 'عميل تصدير'),
      v_po_fruit_type_id,
      'مبيعات تصدير - ' || v_item_crop_name,
      'إيرادات المبيعات',
      v_item_qty,
      v_item_price_egp,
      v_currency,
      v_exch_rate,
      v_item_foreign,
      v_item_egp,
      v_item_egp,
      'شحنة تصدير رقم ' || v_shipment.shipment_no || COALESCE(' | أمر تعبئة #' || v_display_po, ''),
      'شحنة: ' || v_shipment.shipment_no || COALESCE(' - أمر تعبئة: #' || v_display_po, ''),
      v_shipment.shipment_no,
      v_display_po,
      v_item.packing_order_id,
      true,
      now(),
      now()
    )
    ON CONFLICT (source_type, source_id) DO UPDATE SET
      cost_center_id = EXCLUDED.cost_center_id,
      cost_center_code = EXCLUDED.cost_center_code,
      cost_center_name = EXCLUDED.cost_center_name,
      amount = EXCLUDED.amount,
      amount_in_base_currency = EXCLUDED.amount_in_base_currency,
      quantity = EXCLUDED.quantity,
      unit_price = EXCLUDED.unit_price,
      currency = EXCLUDED.currency,
      exchange_rate = EXCLUDED.exchange_rate,
      total_in_currency = EXCLUDED.total_in_currency,
      supplier_name = EXCLUDED.supplier_name,
      supplier_id = EXCLUDED.supplier_id,
      item_name = EXCLUDED.item_name,
      category = EXCLUDED.category,
      description = EXCLUDED.description,
      notes = EXCLUDED.notes,
      shipment_no = EXCLUDED.shipment_no,
      packing_order_number = EXCLUDED.packing_order_number,
      packing_order_id = EXCLUDED.packing_order_id,
      updated_at = now();
  END LOOP;

  -- Fallback for shipments with no items
  IF v_items_count = 0 AND v_total_revenue > 0 THEN
    SELECT code, name_ar INTO v_cc_code, v_cc_name FROM public.cost_centers WHERE is_active = true ORDER BY id ASC LIMIT 1;
    SELECT id INTO v_item_rev_acct FROM public.accounts WHERE account_code = '41112' AND is_leaf = true LIMIT 1;

    IF v_item_rev_acct IS NOT NULL THEN
      v_sale_lines := v_sale_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', v_item_rev_acct,
          'debit', 0,
          'credit', v_total_revenue,
          'base_debit', 0,
          'base_credit', v_base_revenue,
          'currency', v_currency,
          'cost_center_id', v_cc_code,
          'description', v_desc || ' - إيرادات مبيعات تصدير'
        )
      );
    END IF;

    INSERT INTO public.cost_center_transactions (
      cost_center_id, cost_center_code, cost_center_name, cost_center_type,
      source_type, source_id, transaction_date, supplier_id, supplier_name,
      item_name, category, quantity, unit_price, currency, exchange_rate,
      total_in_currency, amount, amount_in_base_currency, description, notes,
      shipment_no, is_confirmed, created_at, updated_at
    ) VALUES (
      COALESCE(v_cc_code, 'CC-MANGO-2026-2027'),
      COALESCE(v_cc_code, 'CC-MANGO-2026-2027'),
      COALESCE(v_cc_name, 'مركز التكلفة'),
      'variety',
      'export_shipment',
      'shipment_' || p_shipment_id,
      v_entry_date,
      v_shipment.customer_id::text,
      COALESCE(v_customer_name, v_shipment.customer_name, 'عميل تصدير'),
      'مبيعات تصدير - شحنة #' || v_shipment.shipment_no,
      'إيرادات المبيعات',
      COALESCE(v_shipment.carton_count, 1),
      ROUND(v_base_revenue / GREATEST(COALESCE(v_shipment.carton_count, 1), 1), 2),
      v_currency,
      v_exch_rate,
      v_total_revenue,
      v_base_revenue,
      v_base_revenue,
      'شحنة تصدير رقم ' || v_shipment.shipment_no,
      'شحنة: ' || v_shipment.shipment_no,
      v_shipment.shipment_no,
      true,
      now(),
      now()
    )
    ON CONFLICT (source_type, source_id) DO UPDATE SET
      amount = EXCLUDED.amount,
      amount_in_base_currency = EXCLUDED.amount_in_base_currency,
      total_in_currency = EXCLUDED.total_in_currency,
      updated_at = now();
  END IF;

  -- 11. ── JOURNAL ENTRY 1: Sales Revenue & Discount (متزن تماماً: مدين = دائن) ──
  IF v_total_revenue > 0 AND v_ar_acct IS NOT NULL AND jsonb_array_length(v_sale_lines) > 0 THEN
    -- A. الطرف المدين: العميل بالصافي المستحق
    IF v_net_revenue > 0 THEN
      v_sale_lines := jsonb_build_array(
        jsonb_build_object(
          'account_id', v_ar_acct,
          'debit', v_net_revenue,
          'credit', 0,
          'base_debit', v_base_net,
          'base_credit', 0,
          'currency', v_currency,
          'description', v_desc || ' - استحقاق صافي قيمة الشحنة'
        )
      ) || v_sale_lines;
    END IF;

    -- B. الطرف المدين: الخصم المسموح به (إذا وجد)
    IF v_discount > 0 THEN
      v_sale_lines := jsonb_build_array(
        jsonb_build_object(
          'account_id', COALESCE(v_disc_acct, v_ar_acct),
          'debit', v_discount,
          'credit', 0,
          'base_debit', v_base_discount,
          'base_credit', 0,
          'currency', v_currency,
          'cost_center_id', v_first_cc_code,
          'description', v_desc || ' - خصم مسموح به'
        )
      ) || v_sale_lines;
    END IF;

    v_sale_je_id := public.post_journal_entry(
      'export_shipment',
      v_desc || ' - إثبات مبيعات التصدير',
      v_entry_date,
      v_company_id,
      p_user_id,
      v_sale_lines,
      p_shipment_id::text
    );

    -- Update journal_entry_id in cost_center_transactions
    UPDATE public.cost_center_transactions
    SET journal_entry_id = v_sale_je_id
    WHERE source_type = 'export_shipment'
      AND (source_id LIKE 'shipment_' || p_shipment_id || '_item_%' 
           OR source_id = 'shipment_' || p_shipment_id);
  END IF;

  -- 12. ── JOURNAL ENTRY 2: Cost of Goods Sold (تكلفة البضاعة المباعة والمخزون) ──
  IF v_total_cogs = 0 THEN
    v_total_cogs := COALESCE(v_shipment.total_fruit_cost, 0) + COALESCE(v_shipment.total_packing_material_cost, 0);
  END IF;
  IF v_total_cogs = 0 AND COALESCE(v_shipment.cost_per_carton, 0) > 0 AND COALESCE(v_shipment.carton_count, 0) > 0 THEN
    v_total_cogs := ROUND(v_shipment.cost_per_carton * v_shipment.carton_count, 2);
  END IF;
  IF v_total_cogs = 0 AND COALESCE(v_shipment.total_landed_cost, 0) > 0 THEN
    v_total_cogs := v_shipment.total_landed_cost;
  END IF;

  IF v_total_cogs > 0 AND v_cogs_acct IS NOT NULL AND v_inv_acct IS NOT NULL THEN
    IF jsonb_array_length(v_cogs_lines) = 0 THEN
      v_cogs_lines := jsonb_build_array(
        jsonb_build_object(
          'account_id', v_cogs_acct,
          'debit', v_total_cogs,
          'credit', 0,
          'base_debit', v_total_cogs,
          'base_credit', 0,
          'currency', 'EGP',
          'cost_center_id', v_first_cc_code,
          'description', v_desc || ' - تكلفة المحاصيل المباعة'
        ),
        jsonb_build_object(
          'account_id', v_inv_acct,
          'debit', 0,
          'credit', v_total_cogs,
          'base_debit', 0,
          'base_credit', v_total_cogs,
          'currency', 'EGP',
          'cost_center_id', v_first_cc_code,
          'description', v_desc || ' - صرف من مخزن الإنتاج التام (12413)'
        )
      );
    END IF;

    v_cogs_je_id := public.post_journal_entry(
      'export_shipment',
      v_desc || ' - تكلفة البضاعة المباعة',
      v_entry_date,
      v_company_id,
      p_user_id,
      v_cogs_lines,
      p_shipment_id::text
    );
  END IF;

  -- 13. ── JOURNAL ENTRY 3: Customer Advance Payment (سداد العميل النقدي / البنكي) ──
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

  -- 14. Update Shipment Record with final calculated values
  UPDATE public.export_shipments
  SET currency_code = v_currency,
      currency = v_currency,
      exchange_rate = v_exch_rate,
      total_revenue_foreign = v_total_revenue,
      total_revenue_egp = v_base_revenue,
      total_fruit_cost = v_total_cogs,
      updated_at = now()
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم ترحيل قيود الشحنة وربط مراكز التكلفة وحركات الأصناف بنجاح',
    'sale_journal_entry_id', v_sale_je_id,
    'cogs_journal_entry_id', v_cogs_je_id,
    'payment_journal_entry_id', v_pay_je_id,
    'revenue_egp', v_base_revenue,
    'discount_egp', v_base_discount,
    'net_egp', v_base_net,
    'cogs_egp', v_total_cogs,
    'items_recorded', v_items_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(bigint, uuid) TO authenticated, service_role, anon;

-- ── 3. Backfill Existing Export Shipments ──────────────────────────────────────
DO $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN SELECT id FROM public.export_shipments ORDER BY id ASC LOOP
    PERFORM public.rpc_process_export_shipment_ledger(v_rec.id);
  END LOOP;
END;
$$;

