-- ==============================================================================
-- ملف 04: تصفير كامل لمراكز التكلفة والبيانات التشغيلية (يشتغل بعد كل ملفات الماستر)
-- العميل ينشئ مراكز التكلفة حسب احتياجاته من واجهة التطبيق
-- ==============================================================================

-- 1. إزالة ربط مراكز التكلفة من الجداول المرتبطة أولاً
UPDATE public.accounts
    SET cost_center_id = NULL
    WHERE cost_center_id IS NOT NULL;

UPDATE public.cost_report_categories
    SET cost_center_id = NULL
    WHERE cost_center_id IS NOT NULL;

DELETE FROM public.cost_report_categories
    WHERE name IN (
      'تكلفة المحاصيل',
      'مواد التعبئة',
      'تعبئة وتغليف',
      'تكلفة شركات الشحن',
      'تكلفة المخلصين',
      'لوجستيك ونقل',
      'أخرى',
      'other'
    );

UPDATE public.fruit_types
    SET cost_center_id = NULL
    WHERE cost_center_id IS NOT NULL;

UPDATE public.purchase_invoice_items
    SET cost_center_id = NULL
    WHERE cost_center_id IS NOT NULL;

UPDATE public.account_ledger_entries
    SET cost_center_id = NULL
    WHERE cost_center_id IS NOT NULL;

-- 2. حذف كل معاملات مراكز التكلفة
DELETE FROM public.cost_center_transactions;

-- 3. حذف كل مراكز التكلفة
DELETE FROM public.cost_centers;

-- 4. حذف كل البيانات التشغيلية التي تظهر في تقارير التكلفة
DELETE FROM public.shipment_cost_items;
DELETE FROM public.general_cost_items;
DELETE FROM public.prep_center_cost_items;

-- 5. حذف بيانات الشحنات والأوامر والاستلامات التشغيلية
DO $$ BEGIN DELETE FROM public.lot_returns; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.lot_receipts; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.packing_order_cost_items; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.packing_orders; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_returns; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_containers; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_costs; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_customs; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_documents; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_history; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipment_items; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN DELETE FROM public.export_shipments; EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- 6. تصفير الأرصدة الافتتاحية للموردين وشركات الشحن والجهات التشغيلية بأمان تام
DO $$
BEGIN
  -- شركات الشحن
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'shipping_companies' AND column_name = 'initial_balance') THEN
    EXECUTE 'UPDATE public.shipping_companies SET initial_balance = 0';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'shipping_companies' AND column_name = 'current_balance') THEN
    EXECUTE 'UPDATE public.shipping_companies SET current_balance = 0';
  END IF;

  -- موردو النقل واللوجستيات
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'transport_suppliers' AND column_name = 'initial_balance') THEN
    EXECUTE 'UPDATE public.transport_suppliers SET initial_balance = 0';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'transport_suppliers' AND column_name = 'current_balance') THEN
    EXECUTE 'UPDATE public.transport_suppliers SET current_balance = 0';
  END IF;

  -- المخلصون الجمركيون
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clearing_agents' AND column_name = 'initial_balance') THEN
    EXECUTE 'UPDATE public.clearing_agents SET initial_balance = 0';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clearing_agents' AND column_name = 'current_balance') THEN
    EXECUTE 'UPDATE public.clearing_agents SET current_balance = 0';
  END IF;

  -- موردو المحاصيل والخدمات
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'initial_balance') THEN
    EXECUTE 'UPDATE public.suppliers SET initial_balance = 0';
  END IF;

  -- أرصدة مواد التعبئة الافتتاحية
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'raw_materials' AND column_name = 'initial_quantity') THEN
    EXECUTE 'UPDATE public.raw_materials SET initial_quantity = 0, initial_avg_price = 0';
  END IF;
END $$;

-- التحقق من النتيجة
DO $$
DECLARE
  v_cc INTEGER;
  v_sci INTEGER;
  v_gci INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cc FROM public.cost_centers;
  SELECT COUNT(*) INTO v_sci FROM public.shipment_cost_items;
  SELECT COUNT(*) INTO v_gci FROM public.general_cost_items;

  IF v_cc = 0 AND v_sci = 0 AND v_gci = 0 THEN
    RAISE NOTICE 'تم التصفير الكامل بنجاح - كل الجداول فارغة الآن';
  ELSE
    RAISE WARNING 'cost_centers: %, shipment_cost_items: %, general_cost_items: %', v_cc, v_sci, v_gci;
  END IF;
END $$;
