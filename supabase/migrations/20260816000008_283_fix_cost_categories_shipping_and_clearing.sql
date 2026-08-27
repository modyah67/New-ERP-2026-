-- ============================================================================
-- Migration 283: Fix Cost Categories Separation for Shipping & Clearing Agents
-- ============================================================================

BEGIN;

-- 1. Ensure all standard cost report categories exist
INSERT INTO public.cost_report_categories (name, scope, is_system, type) VALUES
  ('تكلفة المحاصيل',      'both', true, 'direct'),
  ('مواد التعبئة',         'both', true, 'direct'),
  ('تعبئة وتغليف',          'both', true, 'direct'),
  ('تكلفة شركات الشحن',    'both', true, 'direct'),
  ('تكلفة المخلصين',       'both', true, 'direct'),
  ('لوجستيك ونقل',         'both', true, 'direct'),
  ('مصاريف إدارية',         'both', true, 'direct'),
  ('أخرى',                 'both', true, 'direct')
ON CONFLICT (name) DO UPDATE 
SET scope = EXCLUDED.scope,
    is_system = EXCLUDED.is_system,
    type = EXCLUDED.type;

ALTER TABLE public.cost_report_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read access on cost_report_categories" ON public.cost_report_categories;
CREATE POLICY "Allow read access on cost_report_categories" ON public.cost_report_categories FOR SELECT USING (true);
GRANT SELECT ON public.cost_report_categories TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(text) TO authenticated, anon, service_role;

-- 2. Correct existing shipment cost items data
DO $$
DECLARE
  v_shipping_cat_id INTEGER;
  v_clearing_cat_id INTEGER;
BEGIN
  SELECT id INTO v_shipping_cat_id FROM public.cost_report_categories WHERE name = 'تكلفة شركات الشحن' LIMIT 1;
  SELECT id INTO v_clearing_cat_id FROM public.cost_report_categories WHERE name = 'تكلفة المخلصين' LIMIT 1;

  -- Fix shipping companies
  UPDATE public.shipment_cost_items
  SET report_category_id = v_shipping_cat_id,
      category = 'freight'
  WHERE vendor_type = 'shipping_company' OR shipping_company_id IS NOT NULL;

  -- Fix clearing agents
  UPDATE public.shipment_cost_items
  SET report_category_id = v_clearing_cat_id,
      category = 'clearance'
  WHERE vendor_type = 'clearing_agent' OR clearing_agent_id IS NOT NULL;
END $$;

-- 3. Update rpc_save_profitability_expense with auto-category resolution
DROP FUNCTION IF EXISTS public.rpc_save_profitability_expense(
  INTEGER, TEXT, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, BIGINT, INTEGER, BIGINT, BIGINT
);

CREATE OR REPLACE FUNCTION public.rpc_save_profitability_expense(
  p_shipment_id          INTEGER,
  p_category             TEXT,
  p_report_category_id   INTEGER,
  p_description          TEXT,
  p_quantity             NUMERIC,
  p_unit_price           NUMERIC,
  p_exchange_rate        NUMERIC,
  p_original_currency    TEXT,
  p_supplier_id          TEXT,
  p_supplier_currency    TEXT,
  p_source_type          TEXT,
  p_source_id            BIGINT,
  p_expense_account_id   INTEGER DEFAULT NULL,
  p_shipping_company_id  BIGINT DEFAULT NULL,
  p_clearing_agent_id    BIGINT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_price          NUMERIC;
  v_currency             TEXT;
  v_supplier_uuid        UUID;
  v_company_id           UUID;
  v_treasury_tx_id       BIGINT;
  v_bank_tx_id           INTEGER;
  v_je_id                BIGINT;
  v_tx_desc              TEXT;
  v_current_bal          NUMERIC;
  v_new_item_id          BIGINT;
  v_resolved_acct        INTEGER;
  v_category             TEXT;
  v_report_category_id   INTEGER;
BEGIN
  IF p_shipment_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'رقم الشحنة مطلوب');
  END IF;
  IF p_source_type NOT IN ('treasury', 'bank') THEN
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح');
  END IF;
  IF p_source_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'مصدر الدفع مطلوب');
  END IF;

  v_total_price := COALESCE(p_quantity, 1) * COALESCE(p_unit_price, 0);
  IF v_total_price <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  v_currency := COALESCE(NULLIF(p_original_currency, ''), 'EGP');

  -- Resolve supplier uuid (optional)
  v_supplier_uuid := NULL;
  IF p_supplier_id IS NOT NULL AND p_supplier_id != '' THEN
    BEGIN
      v_supplier_uuid := p_supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_uuid := NULL;
    END;
  END IF;

  -- Resolve expense account, category, and report category based on entity type
  v_resolved_acct := NULL;
  v_category := COALESCE(p_category, 'other');
  v_report_category_id := p_report_category_id;

  IF p_shipping_company_id IS NOT NULL THEN
    v_category := 'freight';
    SELECT id INTO v_report_category_id FROM public.cost_report_categories WHERE name = 'تكلفة شركات الشحن' LIMIT 1;
    SELECT sc.account_id INTO v_resolved_acct
    FROM public.shipping_companies sc WHERE sc.id = p_shipping_company_id;
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'شركة الشحن لا تمتلك حساب في شجرة الحسابات');
    END IF;

  ELSIF p_clearing_agent_id IS NOT NULL THEN
    v_category := 'clearance';
    SELECT id INTO v_report_category_id FROM public.cost_report_categories WHERE name = 'تكلفة المخلصين' LIMIT 1;
    SELECT ca.account_id INTO v_resolved_acct
    FROM public.clearing_agents ca WHERE ca.id = p_clearing_agent_id;
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'المخلص لا يمتلك حساب في شجرة الحسابات');
    END IF;

  ELSIF p_expense_account_id IS NOT NULL THEN
    SELECT id INTO v_resolved_acct FROM accounts
    WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'حساب المصروفات المحدد غير صالح');
    END IF;

  ELSIF v_supplier_uuid IS NOT NULL THEN
    SELECT s.account_id INTO v_resolved_acct FROM suppliers s WHERE s.id = v_supplier_uuid;
    IF v_resolved_acct IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'المورد لا يمتلك حساب في شجرة الحسابات');
    END IF;
  END IF;

  IF v_resolved_acct IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'يجب اختيار حساب مصروفات أو تحديد جهة');
  END IF;

  -- Resolve company_id
  IF p_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_source_id;
  ELSE
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_source_id::integer;
  END IF;

  IF v_company_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم العثور على الشركة');
  END IF;

  -- 1. Insert the cost item
  INSERT INTO public.shipment_cost_items (
    shipment_id, category, report_category_id, description,
    quantity, unit_price, exchange_rate, original_currency,
    supplier_id, supplier_currency,
    payment_source_type, payment_source_id,
    expense_account_id, shipping_company_id, clearing_agent_id,
    vendor_type, vendor_id,
    sort_order
  ) VALUES (
    p_shipment_id, v_category, v_report_category_id, p_description,
    COALESCE(p_quantity, 1), COALESCE(p_unit_price, 0), COALESCE(p_exchange_rate, 1),
    v_currency, p_supplier_id, p_supplier_currency,
    p_source_type, p_source_id,
    v_resolved_acct, p_shipping_company_id, p_clearing_agent_id,
    CASE 
      WHEN p_shipping_company_id IS NOT NULL THEN 'shipping_company'
      WHEN p_clearing_agent_id IS NOT NULL THEN 'clearing_agent'
      ELSE NULL
    END,
    COALESCE(p_shipping_company_id, p_clearing_agent_id)::integer,
    (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM public.shipment_cost_items WHERE shipment_id = p_shipment_id)
  ) RETURNING id INTO v_new_item_id;

  -- 2. Pay
  v_tx_desc := 'سداد بند تكلفة شحنة: ' || COALESCE(p_description, 'غير محدد')
               || ' (بند ' || v_new_item_id::text || ')';

  IF p_source_type = 'treasury' THEN
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_total_price THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_total_price;
    END IF;

    PERFORM public.spend_custody(
      p_source_id, v_currency, v_total_price, v_tx_desc,
      NULL, v_supplier_uuid, NULL, NULL, NULL,
      v_resolved_acct
    );

    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type = 'expense' AND amount = v_total_price AND currency = v_currency
      AND (v_supplier_uuid IS NULL OR supplier_id = v_supplier_uuid)
    ORDER BY created_at DESC LIMIT 1;

    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id = v_company_id
      AND je.entry_date = CURRENT_DATE
    ORDER BY je.id DESC LIMIT 1;

    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_treasury_tx_id,
        journal_entry_id = v_je_id
    WHERE id = v_new_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', v_new_item_id,
      'tx_id', v_treasury_tx_id,
      'type', 'treasury',
      'journal_entry_id', v_je_id
    );

  ELSIF p_source_type = 'bank' THEN
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_total_price THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_total_price;
    END IF;

    DECLARE v_bank_res JSONB;
    BEGIN
      v_bank_res := public.withdraw_bank_account(
        p_source_id::integer, v_total_price, v_tx_desc,
        CASE WHEN v_supplier_uuid IS NOT NULL THEN 'supplier' ELSE NULL END,
        CASE WHEN v_supplier_uuid IS NOT NULL THEN v_supplier_uuid::text ELSE NULL END,
        NULL,
        v_resolved_acct
      );

      v_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
      v_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

      UPDATE public.shipment_cost_items
      SET bank_transaction_id = v_bank_tx_id,
          journal_entry_id    = v_je_id
      WHERE id = v_new_item_id;

      RETURN json_build_object(
        'success', true,
        'cost_item_id', v_new_item_id,
        'tx_id', v_bank_tx_id,
        'type', 'bank',
        'journal_entry_id', v_je_id
      );
    END;
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_profitability_expense(
  INTEGER, TEXT, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, BIGINT, INTEGER, BIGINT, BIGINT
) TO authenticated, service_role;

-- 4. Rewrite vw_cost_details_live with crystal-clear categorization
DROP VIEW IF EXISTS public.vw_cost_details_live CASCADE;
CREATE OR REPLACE VIEW public.vw_cost_details_live AS

-- 1. Crops from Lots
SELECT
  l.receipt_date::date::text AS shipment_date,
  (SELECT STRING_AGG(DISTINCT s.shipment_no, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS shipment_no,
  (SELECT STRING_AGG(DISTINCT s.customer_name, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS customer_name,
  'تكلفة المحاصيل' AS category,
  COALESCE(l.product_name, 'محصول') AS item_name,
  l.gross_weight_kg AS quantity,
  ROUND(((l.total_fruit_cost * COALESCE(l.exchange_rate, 1.0)) / NULLIF(l.gross_weight_kg, 0))::numeric, 2) AS unit_price,
  ROUND((l.total_fruit_cost * COALESCE(l.exchange_rate, 1.0))::numeric, 2) AS amount,
  COALESCE(l.currency, 'EGP') AS currency,
  COALESCE(l.exchange_rate, 1.0) AS exchange_rate,
  ROUND(l.total_fruit_cost::numeric, 2) AS total_in_currency,
  l.notes AS notes,
  (SELECT MIN(po.export_shipment_id) FROM public.packing_orders po WHERE po.lot_id = l.id) AS shipment_id
FROM public.lot_receipts l
WHERE l.is_confirmed = TRUE

UNION ALL

-- 1.5 Crop Returns
SELECT
  r.created_at::date::text AS shipment_date,
  (SELECT STRING_AGG(DISTINCT s.shipment_no, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS shipment_no,
  (SELECT STRING_AGG(DISTINCT s.customer_name, ', ') FROM public.packing_orders po JOIN public.export_shipments s ON s.id = po.export_shipment_id WHERE po.lot_id = l.id) AS customer_name,
  'تكلفة المحاصيل' AS category,
  'مرتجع ' || COALESCE(l.product_name, 'محصول') AS item_name,
  -r.returned_quantity AS quantity,
  ROUND(((r.return_value * COALESCE(l.exchange_rate, 1.0)) / NULLIF(r.returned_quantity, 0))::numeric, 2) AS unit_price,
  ROUND(-(r.return_value * COALESCE(l.exchange_rate, 1.0))::numeric, 2) AS amount,
  COALESCE(l.currency, 'EGP') AS currency,
  COALESCE(l.exchange_rate, 1.0) AS exchange_rate,
  ROUND(-(r.return_value)::numeric, 2) AS total_in_currency,
  r.notes AS notes,
  (SELECT MIN(po.export_shipment_id) FROM public.packing_orders po WHERE po.lot_id = l.id) AS shipment_id
FROM public.lot_returns r
JOIN public.lot_receipts l ON l.id = r.lot_receipt_id

UNION ALL

-- 2. Packing Materials from Packing Orders
SELECT
  COALESCE(po.packed_at, po.created_at)::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  'مواد التعبئة' AS category,
  COALESCE(m->>'product_name', 'مادة تعبئة') AS item_name,
  (m->>'used_qty')::numeric AS quantity,
  ROUND(((m->>'total')::numeric / NULLIF((m->>'used_qty')::numeric, 0))::numeric, 2) AS unit_price,
  ROUND((m->>'total')::numeric, 2) AS amount,
  COALESCE(m->>'currency', 'EGP') AS currency,
  COALESCE((m->>'exchange_rate')::numeric, 1.0) AS exchange_rate,
  ROUND(COALESCE((m->>'total_foreign')::numeric, ((m->>'total')::numeric / NULLIF(COALESCE((m->>'exchange_rate')::numeric, 1.0), 0)))::numeric, 2) AS total_in_currency,
  po.notes AS notes,
  s.id AS shipment_id
FROM public.packing_orders po
LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
CROSS JOIN LATERAL (
  SELECT jsonb_array_elements(
    COALESCE(
      (po.notes::jsonb -> 'materials'),
      '[]'::jsonb
    )
  ) AS m
) mat
WHERE (m->>'total')::numeric > 0 AND po.status = 'completed'

UNION ALL

-- 3. Packing Cost Items from Packing Orders
SELECT
  COALESCE(po.packed_at, po.created_at)::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  'تعبئة وتغليف' AS category,
  COALESCE(c->>'name', 'بند تكلفة تعبئة') AS item_name,
  (c->>'quantity')::numeric AS quantity,
  ROUND(((COALESCE(c->>'total_egp', c->>'total'))::numeric / NULLIF((c->>'quantity')::numeric, 0))::numeric, 2) AS unit_price,
  ROUND((COALESCE(c->>'total_egp', c->>'total'))::numeric, 2) AS amount,
  COALESCE(c->>'supplier_currency', 'EGP') AS currency,
  COALESCE((c->>'exchange_rate')::numeric, 1.0) AS exchange_rate,
  ROUND((c->>'total')::numeric, 2) AS total_in_currency,
  po.notes AS notes,
  s.id AS shipment_id
FROM public.packing_orders po
LEFT JOIN public.export_shipments s ON s.id = po.export_shipment_id
CROSS JOIN LATERAL (
  SELECT jsonb_array_elements(
    COALESCE(
      (po.notes::jsonb -> 'cost_items'),
      '[]'::jsonb
    )
  ) AS c
) cit
WHERE (COALESCE(c->>'total_egp', c->>'total'))::numeric > 0 AND po.status IN ('completed', 'cancelled')

UNION ALL

-- 4. Shipment Cost Items with explicit categorization
SELECT
  s.shipment_date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  CASE
    WHEN sci.vendor_type = 'shipping_company' OR sci.shipping_company_id IS NOT NULL OR sci.category IN ('freight', 'TRANSPORT', 'shipping') THEN 'تكلفة شركات الشحن'
    WHEN sci.vendor_type = 'clearing_agent' OR sci.clearing_agent_id IS NOT NULL OR sci.category IN ('clearance', 'CLEARING', 'clearing') THEN 'تكلفة المخلصين'
    WHEN crc.name IS NOT NULL AND crc.name NOT IN ('أخرى', 'OTHER') THEN crc.name
    WHEN sci.category IN ('packing', 'packaging', 'manual_packing') THEN 'تعبئة وتغليف'
    WHEN sci.category IN ('crop', 'manual_crop') THEN 'تكلفة المحاصيل'
    WHEN sci.category IN ('packing_material') THEN 'مواد التعبئة'
    ELSE COALESCE(crc.name, 'أخرى')
  END AS category,
  sci.description AS item_name,
  sci.quantity AS quantity,
  ROUND((sci.total_price / NULLIF(sci.quantity, 0))::numeric, 2) AS unit_price,
  ROUND(sci.total_price::numeric, 2) AS amount,
  COALESCE(sci.supplier_currency, sci.original_currency, 'EGP') AS currency,
  COALESCE(sci.exchange_rate, 1.0) AS exchange_rate,
  ROUND((sci.total_price / NULLIF(COALESCE(sci.exchange_rate, 1.0), 0))::numeric, 2) AS total_in_currency,
  sci.description AS notes,
  s.id AS shipment_id
FROM public.shipment_cost_items sci
JOIN public.export_shipments s ON s.id = sci.shipment_id
LEFT JOIN public.cost_report_categories crc ON crc.id = sci.report_category_id
WHERE sci.category NOT IN ('crop', 'packing')
  AND NOT (sci.category = 'other' AND sci.description LIKE 'محصول%')

UNION ALL

-- 5. Prep Center Costs
SELECT
  s.shipment_date::date::text AS shipment_date,
  s.shipment_no AS shipment_no,
  s.customer_name AS customer_name,
  'تعبئة وتغليف' AS category,
  pci.description AS item_name,
  pci.qty AS quantity,
  ROUND((pci.total_cost / NULLIF(pci.qty, 0))::numeric, 2) AS unit_price,
  ROUND(pci.total_cost::numeric, 2) AS amount,
  'EGP' AS currency,
  1.0 AS exchange_rate,
  ROUND(pci.total_cost::numeric, 2) AS total_in_currency,
  pci.notes AS notes,
  pci.shipment_id AS shipment_id
FROM public.prep_center_cost_items pci
JOIN public.export_shipments s ON s.id = pci.shipment_id

UNION ALL

-- 6. General Cost Items
SELECT
  gci.cost_date::date::text AS shipment_date,
  NULL AS shipment_no,
  NULL AS customer_name,
  'مصاريف إدارية' AS category,
  gci.name AS item_name,
  1 AS quantity,
  ROUND((gci.amount * 1.0)::numeric, 2) AS unit_price,
  ROUND((gci.amount * 1.0)::numeric, 2) AS amount,
  'EGP' AS currency,
  1.0 AS exchange_rate,
  ROUND((gci.amount * 1.0)::numeric, 2) AS total_in_currency,
  NULL AS notes,
  NULL AS shipment_id
FROM public.general_cost_items gci;

ALTER VIEW public.vw_cost_details_live OWNER TO postgres;
GRANT SELECT ON public.vw_cost_details_live TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload_schema';

COMMIT;
