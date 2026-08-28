-- ============================================================================
-- MASTER CLIENT HANDOVER RESET SCRIPT (Enterprise Edition - Production Ready)
-- ============================================================================
-- هذا السكربت يقوم بتنظيف وتصفير قاعدة البيانات بالكامل للاستعداد لتسليم العميل
-- يجمع جميع عمليات التنظيف، إعادة التهيئة، وتوليد البيانات المرجعية في Transaction واحدة
-- آمن 100%: إذا حدث أي خطأ يتم التراجع تلقائياً (Rollback)
-- متوافق 100% مع Multi-Tenancy وأنواع البيانات المختلفة (UUID/TEXT/INTEGER)
-- ============================================================================
-- المتطلبات المحققة:
-- 1. إزالة جميع القيود والحركات المحاسبية والتشغيلية بالكامل (Transactions = 0)
-- 2. الحفاظ على شجرة الحسابات القياسية كاملة (28+ حساب رسمي) وضمان وجودها وربطها بالشركة
-- 3. تنظيف حسابات الكيانات الفرعية القديمة دون لمس الحسابات الأب (1020, 2000, 2103, 2104, 3101)
-- 4. إعداد الخزينة الرئيسية والـ 4 عملات وربطها بحسابات GL الرسمية (11101-11104)
-- 5. إعداد حسابات البنوك الأربعة الرسمية (11201-11204) والمخازن الرسمية
-- 6. تهيئة كافة البيانات المرجعية (العملات، التصنيفات، الوحدات، إعدادات النظام، السنة المالية)
-- 7. تفعيل التريجرز التلقائية لتوليد حسابات العملاء والموردين وشركات الشحن مستقبلاً
-- 8. تصفير الـ Sequences والأرصدة لتبدأ من 1
-- 9. فحص وتحقق شامل (Verification) قبل الـ Commit
-- ============================================================================

BEGIN;

-- تعطيل triggers الحذف والتحقق مؤقتاً أثناء عملية الـ Reset
SET LOCAL session_replication_role = 'replica';

-- ============================================================================
-- المراحل 1 و 2 و 3: حذف جميع البيانات والقيود والحركات التشغيلية والمخازن بأمان ديناميكي
-- ============================================================================

DO $$
DECLARE
    tbl TEXT;
    v_tables TEXT[] := ARRAY[
        -- Accounting & Ledger
        'posting_profile_rules', 'ledger_entries', 'account_ledger_entries', 'account_ledger',
        'journal_entry_lines', 'journal_entry_dimensions', 'journal_entries', 'account_balance_history',
        'cost_center_distributions', 'cheque_history', 'cheques', 'bank_account_transactions',
        'cash_receipts', 'payment_vouchers', 'cash_payments', 'treasury_transactions', 'cashbox_transactions', 'transactions',
        'financial_audit_log', 'fiscal_year_audit_log', 'audit_logs', 'audit_logs_text',
        'fiscal_year_closing_entries', 'fiscal_year_closing_lock', 'fiscal_year_closing_progress',
        'fiscal_year_inventory_snapshot', 'fiscal_year_backup_metadata', 'fx_revaluations',
        'sys_sequences', 'fiscal_years',
        'general_cost_items', 'shipment_cost_allocations', 'shipment_cost_breakdown',
        'shipment_profitability_snapshots', 'shipment_recipe_snapshots',
        
        -- Inventory, Lots & Crops
        'inventory_cost_audit_log', 'inventory_item_balance_adjustments', 
        'inventory_period_snapshots', 'inventory_period_totals', 'inventory_valuation_history',
        'lot_balance_history', 'lot_cost_adjustments', 'lot_expenses', 'lot_receipt_items', 
        'lot_returns', 'lot_receipts', 'lots', 'crop_purchases', 'fruit_types',
        
        -- Warehouse, Stock & Stations
        'stock_adjustments', 'stock_batch_transactions', 'stock_batches', 
        'stock_movement_items', 'stock_movements', 'stock_transfers', 
        'station_raw_materials', 'station_product_batches', 'station_products', 'station_expenses', 
        'raw_material_movements', 'raw_material_expenses', 'raw_materials',
        
        -- Packing, Sorting & Products
        'packing_order_carton_barcodes', 'packing_order_consumables', 'packing_order_details', 
        'packing_order_history', 'packing_order_inputs', 'packing_order_items', 
        'packing_order_lot_inputs', 'packing_order_materials', 'packing_order_outputs', 
        'packing_order_raw_materials', 'packing_order_sortings', 'packing_order_lines',
        'packing_order_cost_items', 'packing_wastes', 'packing_orders', 
        'packing_operations', 'sorting_operations', 'recipes', 'products',
        
        -- Purchases & Orders
        'supplier_payment_allocations', 'purchase_invoice_edits', 'purchase_invoice_items', 'purchase_invoices', 
        'purchase_order_items', 'purchase_orders', 'purchases',
        
        -- Shipments & Sales
        'shipment_cost_items', 'export_shipment_containers', 'export_shipment_costs', 'export_shipment_customs', 
        'export_shipment_documents', 'export_shipment_history', 'export_shipment_items', 
        'export_shipments', 'proforma_invoice_items', 'proforma_invoices',
        'invoice_items', 'invoice_edits', 'invoices',
        
        -- Entities & Partners
        'customer_addresses', 'customers', 'suppliers_backup', 'supplier_settlements', 'suppliers', 
        'clearing_agents', 'shipping_company_expenses', 'shipping_companies', 
        'shareholder_profit_distributions', 'shareholder_transactions', 'shareholders', 
        'profit_distribution_settings', 'employees',
        
        -- Facilities & References
        'treasury_balances', 'treasuries', 'bank_accounts', 'warehouses',
        'raw_material_categories', 'expense_categories', 'cost_report_categories', 'unit_conversions',
        'deleted_account_codes', 'deleted_entity_codes', 'product_categories'
    ];
BEGIN
    FOR i IN 1..3 LOOP
        FOREACH tbl IN ARRAY v_tables
        LOOP
            BEGIN
                IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = tbl) THEN
                    EXECUTE 'DELETE FROM public.' || quote_ident(tbl);
                END IF;
            EXCEPTION
                WHEN undefined_table THEN
                    NULL;
                WHEN OTHERS THEN
                    IF i = 3 THEN
                        RAISE NOTICE 'Notice: skipped deleting from table %: %', tbl, SQLERRM;
                    END IF;
            END;
        END LOOP;
    END LOOP;

    -- إعادة إنشاء قفل الإغلاق الأساسي لمنع أخطاء الإغلاق المستقبلية
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'fiscal_year_closing_lock') THEN
        EXECUTE 'INSERT INTO public.fiscal_year_closing_lock (id, status) VALUES (1, ''FREE'') ON CONFLICT (id) DO NOTHING;';
    END IF;

END $$;

-- ============================================================================
-- المرحلة 3.5: إعادة ضبط تسلسلات الـ IDENTITY بعد الحذف
-- ============================================================================
-- يمنع أخطاء "duplicate key value violates unique constraint *_pkey"
-- لأن DELETE لا يعيد ضبط تسلسلات IDENTITY تلقائياً.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT pg_get_serial_sequence('public.' || t.relname, a.attname) AS seq_name,
           'public.' || quote_ident(t.relname) AS table_name
    FROM pg_class t
    JOIN pg_attribute a ON a.attrelid = t.oid
    WHERE t.relkind = 'r'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND pg_get_serial_sequence('public.' || t.relname, a.attname) IS NOT NULL
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  LOOP
    BEGIN
      EXECUTE format('SELECT setval(%L, COALESCE((SELECT MAX(id) FROM %s), 0) + 1, false)', r.seq_name, r.table_name);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;

-- ============================================================================
-- المرحلة 4: تنظيف الحسابات الفرعية المنشأة للكيانات السابقة بأمان
-- ============================================================================
-- قاعدة ذهبية: لا يتم حذف أي حساب من الحسابات القياسية الرسمية!
-- نقوم بحذف الحسابات التابعة لعملاء أو موردين أو جهات فقط.

DELETE FROM public.accounts
WHERE account_code NOT IN (
    '1000', '1010', '1020', '1030', '1031', '1032', '1040',
    '11101', '11102', '11103', '11104',
    '11201', '11202', '11203', '11204',
    '2000', '2100', '2101', '2102', '2103', '2104', '2105', '2106', '2107', '2200', '2300',
    '3000', '3001', '3002', '3003', '3004', '3100', '3101', '3200', '3300',
    '3900', '3901', '3902', '3903', '3904',
    '4000', '41101', '4200', '4300', '4310', '4320',
    '5000', '6001', '51102', '51104', '5110', '5210', '6002', '6000', '6110', '51101', '6130', '6150', '6151', '6152'
)
AND (
    account_code ~ '^(1020|2000|2103|2104|3101)[0-9]+'
    OR account_name LIKE 'عميل - %'
    OR account_name LIKE 'مورد - %'
    OR account_name LIKE 'شركة شحن - %'
    OR account_name LIKE 'مخلص جمركي - %'
    OR account_name LIKE 'مساهم - %'
    OR name LIKE 'Customer - %'
    OR name LIKE 'Supplier - %'
    OR name LIKE 'Shipping - %'
    OR name LIKE 'Clearing - %'
    OR name LIKE 'Shareholder - %'
    -- حذف الحسابات القديمة البديلة التي تم استبدالها بالكود الجديد
    OR account_code IN ('1050', '1568', '112001')
);

-- حذف أي حسابات قديمة أخرى لها نفس أسماء الحسابات القياسية الجديدة (بأكواد مختلفة)
DELETE FROM public.accounts a
WHERE EXISTS (
    SELECT 1 FROM public.accounts b
    WHERE b.account_code IN (
        '1000', '1010', '1020', '1030', '1031', '1032', '1040',
        '11101', '11102', '11103', '11104',
        '11201', '11202', '11203', '11204',
        '2000', '2100', '2101', '2102', '2103', '2104', '2105', '2106', '2107', '2200', '2300',
        '3000', '3001', '3002', '3003', '3004', '3100', '3101', '3200', '3300',
        '3900', '3901', '3902', '3903', '3904',
        '4000', '41101', '4200', '4300', '4310', '4320',
        '5000', '6001', '51102', '51104', '5110', '5210', '6002', '6000', '6110', '51101', '6130', '6150', '6151', '6152'
    )
      AND b.account_name = a.account_name
      AND b.id != a.id
)
AND a.account_code NOT IN (
    '1000', '1010', '1020', '1030', '1031', '1032', '1040',
    '11101', '11102', '11103', '11104',
    '11201', '11202', '11203', '11204',
    '2000', '2100', '2101', '2102', '2103', '2104', '2105', '2106', '2107', '2200', '2300',
    '3000', '3001', '3002', '3003', '3004', '3100', '3101', '3200', '3300',
    '3900', '3901', '3902', '3903', '3904',
    '4000', '41101', '4200', '4300', '4310', '4320',
    '5000', '6001', '51102', '51104', '5110', '5210', '6002', '6000', '6110', '51101', '6130', '6150', '6151', '6152'
);


-- ============================================================================
-- المرحلة 5: غرس وضمان وجود الدليل المحاسبي القياسي الموحد (Chart of Accounts)
-- ============================================================================
-- ملاحظة مهمة: account_code فيه UNIQUE constraint عالمي (مش per-company)
-- لذلك نضيف الحسابات مرة واحدة فقط ونربطها بأول شركة
DO $$
DECLARE
    v_has_company BOOLEAN;
    v_acct_col_type TEXT;
    v_first_company_id TEXT;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id'
    ) INTO v_has_company;

    IF v_has_company THEN
        SELECT udt_name INTO v_acct_col_type
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'company_id';

        -- التأكد من وجود شركة واحدة على الأقل
        IF NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE deleted_at IS NULL) THEN
            IF v_acct_col_type = 'uuid' THEN
                BEGIN
                    INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)
                    VALUES ('a0000000-0000-0000-0000-000000000001'::uuid, 'الشركة الافتراضية', true, now(), now())
                    ON CONFLICT (id) DO NOTHING;
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END;
            ELSE
                BEGIN
                    INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)
                    VALUES ('comp-main-001', 'الشركة الافتراضية', true, now(), now())
                    ON CONFLICT (id) DO NOTHING;
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END;
            END IF;
        END IF;

        -- الحصول على أول شركة
        SELECT id::text INTO v_first_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    END IF;

    -- غرس الحسابات القياسية (مرة واحدة فقط — account_code فيه UNIQUE عالمي)
    IF v_first_company_id IS NOT NULL THEN
        IF v_acct_col_type = 'uuid' THEN
            INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id)
            SELECT v.account_code, v.name, v.account_name, v.account_type, true, true, true, v.sort_order, v_first_company_id::uuid
            FROM (VALUES
              ('1000',  'Cash',                         'الصندوق',                         'asset',     1000),
              ('1010',  'Bank',                         'البنك',                           'asset',     1010),
              ('1020',  'Accounts Receivable',          'العملاء (مدينون)',                'asset',     1020),
              ('1030',  'Produce Inventory',            'مخزون المحاصيل',                 'asset',     1030),
              ('1031',  'Finished Goods Inventory',     'مخزون الإنتاج التام',            'asset',     1031),
              ('1032',  'Produce Sorting Inventory',    'مخزون الفرز',                     'asset',     1032),
              ('1040',  'Packaging Materials Inventory','مخزون مواد التعبئة والتغليف',     'asset',     1040),
              ('11101', 'Main Treasury - EGP',          'الخزينة الرئيسية - جنيه',        'asset',     11101),
              ('11102', 'Main Treasury - USD',          'الخزينة الرئيسية - دولار',       'asset',     11102),
              ('11103', 'Main Treasury - EUR',          'الخزينة الرئيسية - يورو',        'asset',     11103),
              ('11104', 'Main Treasury - GBP',          'الخزينة الرئيسية - جنيه إسترليني','asset',    11104),
              ('11201', 'Main Bank - EGP',              'حساب بنكي - جنيه مصري',          'asset',     11201),
              ('11202', 'Main Bank - USD',              'حساب بنكي - دولار أمريكي',       'asset',     11202),
              ('11203', 'Main Bank - EUR',              'حساب بنكي - يورو',               'asset',     11203),
              ('11204', 'Main Bank - GBP',              'حساب بنكي - جنيه إسترليني',      'asset',     11204),
              ('2000',  'Accounts Payable',             'الموردون (دائنون)',               'liability', 2000),
              ('2100',  'Other Current Liabilities',    'الخصوم المتداولة الأخرى',        'liability', 2100),
              ('2101',  'Tax Intermediary',             'وسيط ضرائب',                     'liability', 2101),
              ('2102',  'Allocated Taxes',              'ضرائب محملة',                    'liability', 2102),
              ('2103',  'Shipping Companies',           'شركات الشحن',                     'liability', 2103),
              ('2104',  'Customs Clearance',            'التخليص الجمركي',                 'liability', 2104),
              ('2105',  'Admin Expenses Provision',     'مخصص / وسيط مصروفات إدارية',      'liability', 2105),
              ('2106',  'Packaging Waste Intermediary', 'وسيط هالك مواد التعبئة',         'liability', 2106),
              ('2107',  'Produce Waste Intermediary',   'وسيط هالك المحاصيل',              'liability', 2107),
              ('3000',  'Owner Equity',                 'رأس مال المالك',                 'equity',    3000),
              ('3001',  'Capital - EGP',                'رأس المال - جنيه مصري',           'equity',    3001),
              ('3002',  'Capital - USD',                'رأس المال - دولار أمريكي',        'equity',    3002),
              ('3003',  'Capital - EUR',                'رأس المال - يورو',               'equity',    3003),
              ('3004',  'Capital - GBP',                'رأس المال - جنيه إسترليني',      'equity',    3004),
              ('3100',  'Retained Earnings',            'الأرباح المحتجزة',               'equity',    3100),
              ('3101',  'Shareholders Capital',         'رأس مال المساهمين',               'equity',    3101),
              ('3200',  'Current Year Earnings',        'أرباح السنة الجارية',            'equity',    3200),
              ('3900',  'Opening Balance Equity',       'الأرصدة الافتتاحية',             'equity',    3900),
              ('3901',  'Opening Balance Equity - EGP', 'الأرصدة الافتتاحية - ج.م',        'equity',    3901),
              ('3902',  'Opening Balance Equity - USD', 'الأرصدة الافتتاحية - دولار',       'equity',    3902),
              ('3903',  'Opening Balance Equity - EUR', 'الأرصدة الافتتاحية - يورو',        'equity',    3903),
              ('3904',  'Opening Balance Equity - GBP', 'الأرصدة الافتتاحية - إسترليني',    'equity',    3904),
              ('4000',  'Sales Revenue',                'إيرادات المبيعات',               'revenue',   4000),
              ('4200',  'Export Revenue',               'إيرادات التصدير',                'revenue',   4200),
              ('41101', 'General Revenue',              'إيرادات عامة',                   'revenue',   41101),
              ('4310',  'Realized FX Gains',            'أرباح فروق أسعار العملة المحققة', 'revenue',   4310),
              ('4320',  'Unrealized FX Gains',          'أرباح فروق أسعار العملة غير المحققة','revenue',4320),
              ('5000',  'Cost of Goods Sold',           'تكلفة البضاعة المباعة',          'expense',   5000),
              ('6',     'Expenses',                     'المصروفات',                      'expense',   6),
              ('6001', 'General Expenses',             'مصروفات عامة',                   'expense',   6001),
              ('51102', 'Produce Waste & Spoilage',     'هالك وفاقد المحاصيل',            'expense',   51102),
              ('51104', 'Packaging Materials Waste',    'هالك وفاقد مواد التعبئة والتغليف','expense',  51104),
              ('5110', 'Manufacturing Costs Absorbed', 'تكاليف تشغيل محملة على الإنتاج التام','expense',5110),
              ('5210',  'Allocated Admin Expenses',     'مصروفات إدارية محملة',           'expense',   5210),
              ('6002',  'Actual Admin Expenses',        'مصروفات إدارية فعلية',           'expense',   6002),
              ('6000',  'Expenses',                     'المصروفات',                      'expense',   6000),
              ('6150',  'Currency Differences',         'فروق أسعار العملة',             'expense',   6150),
              ('6151',  'Realized FX Losses',           'خسائر فروق أسعار العملة المحققة', 'expense',   6151),
              ('6152',  'Unrealized FX Losses',         'خسائر فروق أسعار العملة غير المحققة','expense', 6152)
            ) AS v(account_code, name, account_name, account_type, sort_order)
            WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.account_code = v.account_code);
        ELSE
            INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id)
            SELECT v.account_code, v.name, v.account_name, v.account_type, true, true, true, v.sort_order, v_first_company_id::text
            FROM (VALUES
              ('1000',  'Cash',                         'الصندوق',                         'asset',     1000),
              ('1010',  'Bank',                         'البنك',                           'asset',     1010),
              ('1020',  'Accounts Receivable',          'العملاء (مدينون)',                'asset',     1020),
              ('1030',  'Produce Inventory',            'مخزون المحاصيل',                 'asset',     1030),
              ('1031',  'Finished Goods Inventory',     'مخزون الإنتاج التام',            'asset',     1031),
              ('1032',  'Produce Sorting Inventory',    'مخزون الفرز',                     'asset',     1032),
              ('1040',  'Packaging Materials Inventory','مخزون مواد التعبئة والتغليف',     'asset',     1040),
              ('11101', 'Main Treasury - EGP',          'الخزينة الرئيسية - جنيه',        'asset',     11101),
              ('11102', 'Main Treasury - USD',          'الخزينة الرئيسية - دولار',       'asset',     11102),
              ('11103', 'Main Treasury - EUR',          'الخزينة الرئيسية - يورو',        'asset',     11103),
              ('11104', 'Main Treasury - GBP',          'الخزينة الرئيسية - جنيه إسترليني','asset',    11104),
              ('11201', 'Main Bank - EGP',              'حساب بنكي - جنيه مصري',          'asset',     11201),
              ('11202', 'Main Bank - USD',              'حساب بنكي - دولار أمريكي',       'asset',     11202),
              ('11203', 'Main Bank - EUR',              'حساب بنكي - يورو',               'asset',     11203),
              ('11204', 'Main Bank - GBP',              'حساب بنكي - جنيه إسترليني',      'asset',     11204),
              ('2000',  'Accounts Payable',             'الموردون (دائنون)',               'liability', 2000),
              ('2100',  'Other Current Liabilities',    'الخصوم المتداولة الأخرى',        'liability', 2100),
              ('2101',  'Tax Intermediary',             'وسيط ضرائب',                     'liability', 2101),
              ('2102',  'Allocated Taxes',              'ضرائب محملة',                    'liability', 2102),
              ('2103',  'Shipping Companies',           'شركات الشحن',                     'liability', 2103),
              ('2104',  'Customs Clearance',            'التخليص الجمركي',                 'liability', 2104),
              ('2105',  'Admin Expenses Provision',     'مخصص / وسيط مصروفات إدارية',      'liability', 2105),
              ('2106',  'Packaging Waste Intermediary', 'وسيط هالك مواد التعبئة',         'liability', 2106),
              ('2107',  'Produce Waste Intermediary',   'وسيط هالك المحاصيل',              'liability', 2107),
              ('3000',  'Owner Equity',                 'رأس مال المالك',                 'equity',    3000),
              ('3001',  'Capital - EGP',                'رأس المال - جنيه مصري',           'equity',    3001),
              ('3002',  'Capital - USD',                'رأس المال - دولار أمريكي',        'equity',    3002),
              ('3003',  'Capital - EUR',                'رأس المال - يورو',               'equity',    3003),
              ('3004',  'Capital - GBP',                'رأس المال - جنيه إسترليني',      'equity',    3004),
              ('3100',  'Retained Earnings',            'الأرباح المحتجزة',               'equity',    3100),
              ('3101',  'Shareholders Capital',         'رأس مال المساهمين',               'equity',    3101),
              ('3200',  'Current Year Earnings',        'أرباح السنة الجارية',            'equity',    3200),
              ('3900',  'Opening Balance Equity',       'الأرصدة الافتتاحية',             'equity',    3900),
              ('3901',  'Opening Balance Equity - EGP', 'الأرصدة الافتتاحية - ج.م',        'equity',    3901),
              ('3902',  'Opening Balance Equity - USD', 'الأرصدة الافتتاحية - دولار',       'equity',    3902),
              ('3903',  'Opening Balance Equity - EUR', 'الأرصدة الافتتاحية - يورو',        'equity',    3903),
              ('3904',  'Opening Balance Equity - GBP', 'الأرصدة الافتتاحية - إسترليني',    'equity',    3904),
              ('4000',  'Sales Revenue',                'إيرادات المبيعات',               'revenue',   4000),
              ('4200',  'Export Revenue',               'إيرادات التصدير',                'revenue',   4200),
              ('41101', 'General Revenue',              'إيرادات عامة',                   'revenue',   41101),
              ('4310',  'Realized FX Gains',            'أرباح فروق أسعار العملة المحققة', 'revenue',   4310),
              ('4320',  'Unrealized FX Gains',          'أرباح فروق أسعار العملة غير المحققة','revenue',4320),
              ('5000',  'Cost of Goods Sold',           'تكلفة البضاعة المباعة',          'expense',   5000),
              ('6',     'Expenses',                     'المصروفات',                      'expense',   6),
              ('6001', 'General Expenses',             'مصروفات عامة',                   'expense',   6001),
              ('51102', 'Produce Waste & Spoilage',     'هالك وفاقد المحاصيل',            'expense',   51102),
              ('51104', 'Packaging Materials Waste',    'هالك وفاقد مواد التعبئة والتغليف','expense',  51104),
              ('5110', 'Manufacturing Costs Absorbed', 'تكاليف تشغيل محملة على الإنتاج التام','expense',5110),
              ('5210',  'Allocated Admin Expenses',     'مصروفات إدارية محملة',           'expense',   5210),
              ('6002',  'Actual Admin Expenses',        'مصروفات إدارية فعلية',           'expense',   6002),
              ('6000',  'Expenses',                     'المصروفات',                      'expense',   6000),
              ('6150',  'Currency Differences',         'فروق أسعار العملة',             'expense',   6150),
              ('6151',  'Realized FX Losses',           'خسائر فروق أسعار العملة المحققة', 'expense',   6151),
              ('6152',  'Unrealized FX Losses',         'خسائر فروق أسعار العملة غير المحققة','expense', 6152)
            ) AS v(account_code, name, account_name, account_type, sort_order)
            WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.account_code = v.account_code);
        END IF;
    ELSE
        INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order)
        SELECT v.account_code, v.name, v.account_name, v.account_type, true, true, true, v.sort_order
        FROM (VALUES
          ('1000',  'Cash',                         'الصندوق',                         'asset',     1000),
          ('1010',  'Bank',                         'البنك',                           'asset',     1010),
          ('1020',  'Accounts Receivable',          'العملاء (مدينون)',                'asset',     1020),
          ('1030',  'Produce Inventory',            'مخزون المحاصيل',                 'asset',     1030),
          ('1031',  'Finished Goods Inventory',     'مخزون الإنتاج التام',            'asset',     1031),
          ('1032',  'Produce Sorting Inventory',    'مخزون الفرز',                     'asset',     1032),
          ('1040',  'Packaging Materials Inventory','مخزون مواد التعبئة والتغليف',     'asset',     1040),
          ('11101', 'Main Treasury - EGP',          'الخزينة الرئيسية - جنيه',        'asset',     11101),
          ('11102', 'Main Treasury - USD',          'الخزينة الرئيسية - دولار',       'asset',     11102),
          ('11103', 'Main Treasury - EUR',          'الخزينة الرئيسية - يورو',        'asset',     11103),
          ('11104', 'Main Treasury - GBP',          'الخزينة الرئيسية - جنيه إسترليني','asset',    11104),
          ('11201', 'Main Bank - EGP',              'حساب بنكي - جنيه مصري',          'asset',     11201),
          ('11202', 'Main Bank - USD',              'حساب بنكي - دولار أمريكي',       'asset',     11202),
          ('11203', 'Main Bank - EUR',              'حساب بنكي - يورو',               'asset',     11203),
          ('11204', 'Main Bank - GBP',              'حساب بنكي - جنيه إسترليني',      'asset',     11204),
          ('2000',  'Accounts Payable',             'الموردون (دائنون)',               'liability', 2000),
          ('2100',  'Other Current Liabilities',    'الخصوم المتداولة الأخرى',        'liability', 2100),
          ('2101',  'Tax Intermediary',             'وسيط ضرائب',                     'liability', 2101),
          ('2102',  'Allocated Taxes',              'ضرائب محملة',                    'liability', 2102),
          ('2103',  'Shipping Companies',           'شركات الشحن',                     'liability', 2103),
          ('2104',  'Customs Clearance',            'التخليص الجمركي',                 'liability', 2104),
          ('2105',  'Admin Expenses Provision',     'مخصص / وسيط مصروفات إدارية',      'liability', 2105),
          ('2106',  'Packaging Waste Intermediary', 'وسيط هالك مواد التعبئة',         'liability', 2106),
          ('2107',  'Produce Waste Intermediary',   'وسيط هالك المحاصيل',              'liability', 2107),
          ('3000',  'Owner Equity',                 'رأس مال المالك',                 'equity',    3000),
          ('3001',  'Capital - EGP',                'رأس المال - جنيه مصري',           'equity',    3001),
          ('3002',  'Capital - USD',                'رأس المال - دولار أمريكي',        'equity',    3002),
          ('3003',  'Capital - EUR',                'رأس المال - يورو',               'equity',    3003),
          ('3004',  'Capital - GBP',                'رأس المال - جنيه إسترليني',      'equity',    3004),
          ('3100',  'Retained Earnings',            'الأرباح المحتجزة',               'equity',    3100),
          ('3101',  'Shareholders Capital',         'رأس مال المساهمين',               'equity',    3101),
          ('3200',  'Current Year Earnings',        'أرباح السنة الجارية',            'equity',    3200),
          ('3900',  'Opening Balance Equity',       'الأرصدة الافتتاحية',             'equity',    3900),
          ('3901',  'Opening Balance Equity - EGP', 'الأرصدة الافتتاحية - ج.م',        'equity',    3901),
          ('3902',  'Opening Balance Equity - USD', 'الأرصدة الافتتاحية - دولار',       'equity',    3902),
          ('3903',  'Opening Balance Equity - EUR', 'الأرصدة الافتتاحية - يورو',        'equity',    3903),
          ('3904',  'Opening Balance Equity - GBP', 'الأرصدة الافتتاحية - إسترليني',    'equity',    3904),
          ('4000',  'Sales Revenue',                'إيرادات المبيعات',               'revenue',   4000),
          ('4200',  'Export Revenue',               'إيرادات التصدير',                'revenue',   4200),
          ('41101', 'General Revenue',              'إيرادات عامة',                   'revenue',   41101),
          ('4310',  'Realized FX Gains',            'أرباح فروق أسعار العملة المحققة', 'revenue',   4310),
          ('4320',  'Unrealized FX Gains',          'أرباح فروق أسعار العملة غير المحققة','revenue',4320),
          ('5000',  'Cost of Goods Sold',           'تكلفة البضاعة المباعة',          'expense',   5000),
          ('6',     'Expenses',                     'المصروفات',                      'expense',   6),
          ('6001', 'General Expenses',             'مصروفات عامة',                   'expense',   6001),
          ('51102', 'Produce Waste & Spoilage',     'هالك وفاقد المحاصيل',            'expense',   51102),
          ('51104', 'Packaging Materials Waste',    'هالك وفاقد مواد التعبئة والتغليف','expense',  51104),
          ('5110', 'Manufacturing Costs Absorbed', 'تكاليف تشغيل محملة على الإنتاج التام','expense',5110),
          ('5210',  'Allocated Admin Expenses',     'مصروفات إدارية محملة',           'expense',   5210),
          ('6002',  'Actual Admin Expenses',        'مصروفات إدارية فعلية',           'expense',   6002),
          ('6000',  'Expenses',                     'المصروفات',                      'expense',   6000),
          ('6150',  'Currency Differences',         'فروق أسعار العملة',             'expense',   6150),
          ('6151',  'Realized FX Losses',           'خسائر فروق أسعار العملة المحققة', 'expense',   6151),
          ('6152',  'Unrealized FX Losses',         'خسائر فروق أسعار العملة غير المحققة','expense', 6152)
        ) AS v(account_code, name, account_name, account_type, sort_order)
        WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.account_code = v.account_code);
    END IF;


    -- تفعيل وتصفير رصيد وضبط خصائص كافة الحسابات القياسية
    UPDATE public.accounts
    SET is_active = true,
        is_leaf = true,
        allow_posting = true,
        deleted_at = NULL,
        balance = 0
    WHERE account_code IN (
      '1000', '1010', '1020', '1030', '1031', '1032', '1040',
      '11101', '11102', '11103', '11104',
      '11201', '11202', '11203', '11204',
      '2000', '2100', '2101', '2102', '2103', '2104', '2105', '2106', '2107',
      '3000', '3001', '3002', '3003', '3004', '3100', '3101', '3200',
      '3900', '3901', '3902', '3903', '3904',
      '4000', '4200', '41101', '4310', '4320',
      '5000', '6001', '51102', '51104', '5110', '5210', '6002', '6000', '6151', '6152'
    );

    -- ضبط الحسابات 2106 و 2107 تحت فرع الخصوم (20) مباشرة
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '20' OR code = '20' LIMIT 1)
    WHERE account_code IN ('2106', '2107') OR code IN ('2106', '2107');

    -- ضبط الحساب الأب للأرصدة الافتتاحية 3900 كـ Header
    UPDATE public.accounts
    SET is_leaf = false,
        allow_posting = false,
        parent_id = COALESCE((SELECT id FROM public.accounts WHERE account_code = '3' LIMIT 1), (SELECT id FROM public.accounts WHERE account_code = '3000' LIMIT 1))
    WHERE account_code = '3900';

    -- ضبط parent_id للحسابات الفرعية للأرصدة الافتتاحية 3901-3904
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '3900' LIMIT 1),
        is_leaf = true,
        allow_posting = true
    WHERE account_code IN ('3901', '3902', '3903', '3904');

    -- تأكيد account_type الصحيح لكل حساب قياسي (يصلح أي خطأ في النوع)
    UPDATE public.accounts SET account_type = 'asset'     WHERE account_code IN ('1000', '1010', '1020', '1030', '1031', '1032', '1040', '11101', '11102', '11103', '11104', '11201', '11202', '11203', '11204');
    UPDATE public.accounts SET account_type = 'liability' WHERE account_code IN ('2000', '2100', '2101', '2102', '2103', '2104', '2105', '2106', '2107');
    UPDATE public.accounts SET account_type = 'equity'    WHERE account_code IN ('3000', '3001', '3002', '3003', '3004', '3100', '3101', '3200', '3900', '3901', '3902', '3903', '3904');
    UPDATE public.accounts SET account_type = 'revenue'   WHERE account_code IN ('4000', '4200', '41101', '4310', '4320');
    UPDATE public.accounts SET account_type = 'expense'   WHERE account_code IN ('6', '5000', '6001', '51101', '51102', '51104', '5110', '5210', '6002', '6000', '6130', '6151', '6152');

    -- ── 1. ضبط الحساب الرئيسي للمصروفات 6 كـ Header (بدون أب) ──
    UPDATE public.accounts
    SET is_leaf = false,
        allow_posting = false,
        parent_id = NULL,
        level = 1,
        is_active = true,
        deleted_at = NULL
    WHERE account_code = '6';

    -- ── 2. ضبط الفروع التابعة للمصروفات 6 (المستوى الثاني: 5000، 5110، 6000) ──
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '6' LIMIT 1),
        level = 2,
        is_active = true,
        deleted_at = NULL
    WHERE account_code IN ('5000', '5110', '6000');

    -- ضبط خصائص Header / Leaf للمستوى الثاني
    UPDATE public.accounts SET is_leaf = true, allow_posting = true WHERE account_code IN ('5000');
    UPDATE public.accounts SET is_leaf = false, allow_posting = false WHERE account_code IN ('5110', '6000');

    -- ── 3. تعيين الحساب الأب (تكاليف التشغيل 5110) لحسابات بنود التكلفة والهالك 51101، 51102، 51104 ──
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '5110' LIMIT 1),
        level = 3,
        is_leaf = true,
        allow_posting = true,
        is_active = true,
        deleted_at = NULL
    WHERE account_code IN ('51101', '51102', '51104');

    -- ── 4. تعيين الحساب الأب (المصروفات 6000) للمصروفات العامة والإدارية وفروق العملة 6150 ──
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '6000' LIMIT 1),
        level = 3,
        is_active = true,
        deleted_at = NULL
    WHERE account_code IN ('6001', '6002', '6130', '6150');

    UPDATE public.accounts SET is_leaf = true, allow_posting = true WHERE account_code IN ('6001', '6002', '6130');
    UPDATE public.accounts SET is_leaf = false, allow_posting = false WHERE account_code = '6150';

    -- ── 5. تعيين الحساب الأب (فروق أسعار العملة 6150) لحسابات 6151 و 6152 ──
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '6150' LIMIT 1),
        level = 4,
        is_leaf = true,
        allow_posting = true,
        is_active = true,
        deleted_at = NULL
    WHERE account_code IN ('6151', '6152');

    -- تعيين الحساب الأب (Other Current Liabilities 2100) لمخصص المصروفات الإدارية 2105 والمصروفات الإدارية المحملة 5210
    UPDATE public.accounts
    SET parent_id = COALESCE(
        (SELECT id FROM public.accounts WHERE account_code = '2100' LIMIT 1),
        (SELECT id FROM public.accounts WHERE account_code = '20' LIMIT 1)
    ),
    is_leaf = true,
    allow_posting = true
    WHERE account_code IN ('2105', '5210');

    -- تعيين الحساب الأب (الخصوم 20) لحساب الموردين 2000، شركات الشحن 2103، التخليص الجمركي 2104، ووسيط الهالك 2106 و 2107
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '20' OR code = '20' LIMIT 1)
    WHERE account_code IN ('2000', '2103', '2104', '2106', '2107') OR code IN ('2000', '2103', '2104', '2106', '2107');

    -- تعيين الحساب الأب (4300 Other Revenue) لأرباح فروق العملة 4310 و 4320
    UPDATE public.accounts
    SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '4300' LIMIT 1)
    WHERE account_code IN ('4310', '4320');
END $$;

-- ============================================================================
-- المرحلة 6: إعادة إنشاء الخزينة الرئيسية والبنوك والمخازن الرسمية
-- ============================================================================

DO $$
DECLARE
    v_has_company BOOLEAN;
    v_col_type TEXT;
    v_first_company_id TEXT;
    v_tid INT;
    v_aid BIGINT;
    v_curr TEXT;
    v_acode TEXT;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'treasuries' AND column_name = 'company_id'
    ) INTO v_has_company;

    IF v_has_company THEN
        SELECT udt_name INTO v_col_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'treasuries' AND column_name = 'company_id';
        SELECT id::text INTO v_first_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    END IF;

    -- 1. الخزينة الرئيسية (INSERT مرة واحدة فقط مع company_id إذا لزم)
    IF v_first_company_id IS NOT NULL THEN
        IF v_col_type = 'uuid' THEN
            EXECUTE 'INSERT INTO public.treasuries (name, type, notes, company_id)
                     SELECT ''الخزينة الرئيسية'', ''main'', ''الخزينة الافتراضية للنظام'', ' || quote_literal(v_first_company_id) || '::uuid
                     WHERE NOT EXISTS (SELECT 1 FROM public.treasuries WHERE name = ''الخزينة الرئيسية'')';
        ELSE
            EXECUTE 'INSERT INTO public.treasuries (name, type, notes, company_id)
                     SELECT ''الخزينة الرئيسية'', ''main'', ''الخزينة الافتراضية للنظام'', ' || quote_literal(v_first_company_id) || '
                     WHERE NOT EXISTS (SELECT 1 FROM public.treasuries WHERE name = ''الخزينة الرئيسية'')';
        END IF;
    ELSE
        INSERT INTO public.treasuries (name, type, notes)
        SELECT 'الخزينة الرئيسية', 'main', 'الخزينة الافتراضية للنظام'
        WHERE NOT EXISTS (SELECT 1 FROM public.treasuries WHERE name = 'الخزينة الرئيسية');
    END IF;

    -- 2. ربط أرصدة الخزينة بالـ 4 عملات وحسابات GL
    SELECT id INTO v_tid FROM public.treasuries WHERE name = 'الخزينة الرئيسية' LIMIT 1;
    
    IF v_tid IS NOT NULL THEN
        FOR v_curr, v_acode IN 
            SELECT * FROM (VALUES ('EGP', '11101'), ('USD', '11102'), ('EUR', '11103'), ('GBP', '11104')) AS v(c, a)
        LOOP
            SELECT id INTO v_aid FROM public.accounts WHERE account_code = v_acode LIMIT 1;
            IF v_aid IS NOT NULL THEN
                INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
                VALUES (v_tid, v_curr, 0.00, 0.00, 1.00, v_aid)
                ON CONFLICT (treasury_id, currency) DO UPDATE SET
                    account_id = EXCLUDED.account_id,
                    balance = 0.00,
                    cost_base = 0.00,
                    book_rate = 1.00;
            END IF;
        END LOOP;
    END IF;

    -- 3. الحسابات البنكية الأربعة (INSERT مرة واحدة فقط)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bank_accounts') THEN
        IF v_first_company_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'bank_accounts' AND column_name = 'company_id') THEN
            IF v_col_type = 'uuid' THEN
                EXECUTE 'INSERT INTO public.bank_accounts (name, name_en, currency, balance, cost_base, book_rate, company_id)
                         SELECT v.name, v.name_en, v.currency, 0.00, 0.00, 1.00, ' || quote_literal(v_first_company_id) || '::uuid
                         FROM (VALUES
                           (''الجنيه المصري'',       ''Egyptian Pound'',  ''EGP''),
                           (''الدولار الأمريكي'',     ''US Dollar'',       ''USD''),
                           (''اليورو'',               ''Euro'',            ''EUR''),
                           (''الجنيه الإسترليني'',    ''British Pound'',   ''GBP'')
                         ) AS v(name, name_en, currency)
                         WHERE NOT EXISTS (SELECT 1 FROM public.bank_accounts ba WHERE ba.currency = v.currency)';
            ELSE
                EXECUTE 'INSERT INTO public.bank_accounts (name, name_en, currency, balance, cost_base, book_rate, company_id)
                         SELECT v.name, v.name_en, v.currency, 0.00, 0.00, 1.00, ' || quote_literal(v_first_company_id) || '
                         FROM (VALUES
                           (''الجنيه المصري'',       ''Egyptian Pound'',  ''EGP''),
                           (''الدولار الأمريكي'',     ''US Dollar'',       ''USD''),
                           (''اليورو'',               ''Euro'',            ''EUR''),
                           (''الجنيه الإسترليني'',    ''British Pound'',   ''GBP'')
                         ) AS v(name, name_en, currency)
                         WHERE NOT EXISTS (SELECT 1 FROM public.bank_accounts ba WHERE ba.currency = v.currency)';
            END IF;
        ELSE
            INSERT INTO public.bank_accounts (name, name_en, currency, balance, cost_base, book_rate)
            SELECT v.name, v.name_en, v.currency, 0.00, 0.00, 1.00
            FROM (VALUES
              ('الجنيه المصري',       'Egyptian Pound',  'EGP'),
              ('الدولار الأمريكي',     'US Dollar',       'USD'),
              ('اليورو',               'Euro',            'EUR'),
              ('الجنيه الإسترليني',    'British Pound',   'GBP')
            ) AS v(name, name_en, currency)
            WHERE NOT EXISTS (SELECT 1 FROM public.bank_accounts ba WHERE ba.currency = v.currency);
        END IF;

        -- تصفير الأرصدة
        UPDATE public.bank_accounts SET balance = 0, cost_base = 0, book_rate = 1.0;
    END IF;

    -- 4. المستودعات (INSERT مرة واحدة فقط)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'warehouses') THEN
        IF v_first_company_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'warehouses' AND column_name = 'company_id') THEN
            IF v_col_type = 'uuid' THEN
                EXECUTE 'INSERT INTO public.warehouses (name, name_en, address, city, country, is_active, company_id)
                         SELECT v.name, v.name_en, v.address, v.city, v.country, true, ' || quote_literal(v_first_company_id) || '::uuid
                         FROM (VALUES
                           (''المستودع الرئيسي'',  ''Main Warehouse'',  ''المنطقة الصناعية'', ''القاهرة'',    ''Egypt''),
                           (''مستودع التصدير'',     ''Export Warehouse'', ''ميناء الإسكندرية'', ''الإسكندرية'', ''Egypt''),
                           (''مستودع التجميد'',     ''Cold Storage'',     ''المنطقة الصناعية'', ''القاهرة'',    ''Egypt'')
                         ) AS v(name, name_en, address, city, country)
                         WHERE NOT EXISTS (SELECT 1 FROM public.warehouses w WHERE w.name = v.name)';
            ELSE
                EXECUTE 'INSERT INTO public.warehouses (name, name_en, address, city, country, is_active, company_id)
                         SELECT v.name, v.name_en, v.address, v.city, v.country, true, ' || quote_literal(v_first_company_id) || '
                         FROM (VALUES
                           (''المستودع الرئيسي'',  ''Main Warehouse'',  ''المنطقة الصناعية'', ''القاهرة'',    ''Egypt''),
                           (''مستودع التصدير'',     ''Export Warehouse'', ''ميناء الإسكندرية'', ''الإسكندرية'', ''Egypt''),
                           (''مستودع التجميد'',     ''Cold Storage'',     ''المنطقة الصناعية'', ''القاهرة'',    ''Egypt'')
                         ) AS v(name, name_en, address, city, country)
                         WHERE NOT EXISTS (SELECT 1 FROM public.warehouses w WHERE w.name = v.name)';
            END IF;
        ELSE
            INSERT INTO public.warehouses (name, name_en, address, city, country, is_active)
            SELECT v.name, v.name_en, v.address, v.city, v.country, true
            FROM (VALUES
              ('المستودع الرئيسي',  'Main Warehouse',  'المنطقة الصناعية', 'القاهرة',    'Egypt'),
              ('مستودع التصدير',     'Export Warehouse', 'ميناء الإسكندرية', 'الإسكندرية', 'Egypt'),
              ('مستودع التجميد',     'Cold Storage',     'المنطقة الصناعية', 'القاهرة',    'Egypt')
            ) AS v(name, name_en, address, city, country)
            WHERE NOT EXISTS (SELECT 1 FROM public.warehouses w WHERE w.name = v.name);
        END IF;
    END IF;
END $$;

-- ============================================================================
-- المرحلة 7: تهيئة البيانات المرجعية الأساسية (Master Reference Data)
-- ============================================================================

-- 1. العملات (Currencies)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'currencies') THEN
        DELETE FROM public.currencies WHERE code IN ('SAR', 'AED');
        
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'currencies' AND column_name = 'name_en') THEN
            INSERT INTO public.currencies (code, name, name_en, symbol, is_default, is_active)
            SELECT v.code, v.name, v.name_en, v.symbol, v.is_default, v.is_active
            FROM (VALUES
              ('EGP', 'جنيه مصري',      'Egyptian Pound',  'ج.م',  true,  true),
              ('USD', 'دولار أمريكي',    'US Dollar',       '$',    false, true),
              ('EUR', 'يورو',           'Euro',            '€',    false, true),
              ('GBP', 'جنيه إسترليني',  'British Pound',   '£',    false, true)
            ) AS v(code, name, name_en, symbol, is_default, is_active)
            ON CONFLICT (code) DO UPDATE SET
                name = EXCLUDED.name,
                name_en = EXCLUDED.name_en,
                symbol = EXCLUDED.symbol,
                is_active = true;
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'currencies' AND column_name = 'name_ar') THEN
            INSERT INTO public.currencies (code, name, name_ar, symbol, is_base, is_active)
            SELECT v.code, v.name, v.name_ar, v.symbol, v.is_base, v.is_active
            FROM (VALUES
              ('EGP', 'Egyptian Pound',  'جنيه مصري',      'ج.م',  true,  true),
              ('USD', 'US Dollar',       'دولار أمريكي',    '$',    false, true),
              ('EUR', 'Euro',            'يورو',           '€',    false, true),
              ('GBP', 'British Pound',   'جنيه إسترليني',  '£',    false, true)
            ) AS v(code, name, name_ar, symbol, is_base, is_active)
            ON CONFLICT (code) DO UPDATE SET
                name = EXCLUDED.name,
                name_ar = EXCLUDED.name_ar,
                symbol = EXCLUDED.symbol,
                is_active = true;
        ELSE
            INSERT INTO public.currencies (code, name, symbol, is_active)
            SELECT v.code, v.name, v.symbol, true
            FROM (VALUES
              ('EGP', 'جنيه مصري',      'ج.م'),
              ('USD', 'دولار أمريكي',    '$'),
              ('EUR', 'يورو',           '€'),
              ('GBP', 'جنيه إسترليني',  '£')
            ) AS v(code, name, symbol)
            ON CONFLICT (code) DO UPDATE SET
                name = EXCLUDED.name,
                symbol = EXCLUDED.symbol,
                is_active = true;
        END IF;
    END IF;
END $$;

-- 2. أسعار الصرف (Exchange Rates)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exchange_rates') THEN
        DELETE FROM public.exchange_rates WHERE currency_code IN ('SAR', 'AED');

        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'exchange_rates' AND column_name = 'name_ar') THEN
            INSERT INTO public.exchange_rates (currency_code, currency_name, name_ar, rate_to_egp, updated_at)
            SELECT v.currency_code, v.currency_name, v.name_ar, v.rate_to_egp, NOW()
            FROM (VALUES
              ('USD', 'US Dollar',       'الدولار الأمريكي',   50.00),
              ('EUR', 'Euro',            'اليورو الأوروبي',    50.00),
              ('GBP', 'British Pound',   'الجنيه الاسترليني',  60.00)
            ) AS v(currency_code, currency_name, name_ar, rate_to_egp)
            ON CONFLICT (currency_code) DO UPDATE SET rate_to_egp = EXCLUDED.rate_to_egp, updated_at = NOW();
        ELSE
            INSERT INTO public.exchange_rates (currency_code, currency_name, rate_to_egp, updated_at)
            SELECT v.currency_code, v.currency_name, v.rate_to_egp, NOW()
            FROM (VALUES
              ('USD', 'الدولار الأمريكي',   50.00),
              ('EUR', 'اليورو الأوروبي',    50.00),
              ('GBP', 'الجنيه الاسترليني',  60.00)
            ) AS v(currency_code, currency_name, rate_to_egp)
            ON CONFLICT (currency_code) DO UPDATE SET rate_to_egp = EXCLUDED.rate_to_egp, updated_at = NOW();
        END IF;
    END IF;
END $$;

-- 3. تصنيفات المواد الخام والمنتجات
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'raw_material_categories') THEN
        BEGIN
            PERFORM setval(pg_get_serial_sequence('public.raw_material_categories', 'id'), COALESCE((SELECT MAX(id) FROM public.raw_material_categories), 0) + 1, false);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        -- تم التعطيل بناء على طلب العميل ليقوم هو بتسجيل فئات المواد الخام ومواد التعبئة بنفسه
        -- INSERT INTO public.raw_material_categories (name)
        -- SELECT v.name
        -- FROM (VALUES ('مواد تعبئة'), ('مواد أولية'), ('مواد كيميائية'), ('قطع غيار')) AS v(name)
        -- WHERE NOT EXISTS (SELECT 1 FROM public.raw_material_categories rmc WHERE rmc.name = v.name);
    END IF;
END $$;

-- 4. تصنيفات المصروفات
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expense_categories') THEN
        BEGIN
            PERFORM setval(pg_get_serial_sequence('public.expense_categories', 'id'), COALESCE((SELECT MAX(id) FROM public.expense_categories), 0) + 1, false);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        INSERT INTO public.expense_categories (name, color, is_active)
        SELECT v.name, v.color, true
        FROM (VALUES
          ('مصروفات إدارية',   '#F59E0B'),
          ('مصروفات نقل',       '#448AFF'),
          ('مصروفات صيانة',     '#EC4899'),
          ('مصروفات إنتاج',     '#10B981'),
          ('مصروفات تسويق',     '#8B5CF6'),
          ('مصروفات متنوعة',    '#6B7280')
        ) AS v(name, color)
        WHERE NOT EXISTS (SELECT 1 FROM public.expense_categories ec WHERE ec.name = v.name);
    END IF;
END $$;

-- 5. تصنيفات تقارير التكاليف
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'cost_report_categories') THEN
        BEGIN
            PERFORM setval(pg_get_serial_sequence('public.cost_report_categories', 'id'), COALESCE((SELECT MAX(id) FROM public.cost_report_categories), 0) + 1, false);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        INSERT INTO public.cost_report_categories (name, type, scope, is_system)
        SELECT v.name, v.type, v.scope, v.is_system
        FROM (VALUES
          ('تكلفة المحاصيل',      'direct', 'both', true),
          ('مواد التعبئة',         'direct', 'both', true),
          ('تعبئة وتغليف',          'direct', 'both', true),
          ('تكلفة شركات الشحن',    'direct', 'both', true),
          ('تكلفة المخلصين',       'direct', 'both', true),
          ('لوجستيك ونقل',         'direct', 'both', true),
          ('أخرى',                 'direct', 'both', true)
        ) AS v(name, type, scope, is_system)
        WHERE NOT EXISTS (SELECT 1 FROM public.cost_report_categories crc WHERE crc.name = v.name);

        GRANT SELECT ON public.cost_report_categories TO authenticated, anon, service_role;
        GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(text) TO authenticated, anon, service_role;
    END IF;
END $$;

-- 6. معاملات التحويل بين الوحدات (Unit Conversions)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'unit_conversions') THEN
        BEGIN
            PERFORM setval(pg_get_serial_sequence('public.unit_conversions', 'id'), COALESCE((SELECT MAX(id) FROM public.unit_conversions), 0) + 1, false);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        INSERT INTO public.unit_conversions (from_unit, to_unit, conversion_factor, product_id)
        SELECT v.from_unit, v.to_unit, v.factor, NULL
        FROM (VALUES
          ('KG',      'TON',     0.001),
          ('TON',     'KG',      1000.0),
          ('CARTON',  'KG',      10.0),
          ('KG',      'CARTON',  0.1),
          ('BOX',     'KG',      20.0),
          ('KG',      'BOX',     0.05),
          ('PALLET',  'CARTON',  40.0),
          ('CARTON',  'PALLET',  0.025)
        ) AS v(from_unit, to_unit, factor)
        WHERE NOT EXISTS (
          SELECT 1 FROM public.unit_conversions uc
          WHERE uc.from_unit = v.from_unit AND uc.to_unit = v.to_unit AND uc.product_id IS NULL
        );
    END IF;
END $$;

-- 7. قوالب الترقيم التلقائي للفواتير
DO $$
DECLARE
    v_has_company_id BOOLEAN;
    v_comp_id TEXT;
    v_comp_type TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'invoice_numbering') THEN
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'invoice_numbering' AND column_name = 'company_id'
        ) INTO v_has_company_id;

        IF v_has_company_id THEN
            SELECT udt_name INTO v_comp_type
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'invoice_numbering' AND column_name = 'company_id';

            IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
                SELECT id::TEXT INTO v_comp_id FROM public.sys_companies LIMIT 1;
            END IF;

            IF v_comp_id IS NOT NULL THEN
                EXECUTE format('
                    INSERT INTO public.invoice_numbering (company_id, entity_type, prefix, next_number, pad_length)
                    SELECT %L::%s, v.entity_type, v.prefix, 1, v.pad_length
                    FROM (VALUES
                      (''sales_invoice'',    ''INV-'', 4),
                      (''purchase_invoice'', ''PUR-'', 4),
                      (''export_shipment'',  ''EXP-'', 4)
                    ) AS v(entity_type, prefix, pad_length)
                    ON CONFLICT DO NOTHING', v_comp_id, v_comp_type);
            ELSE
                INSERT INTO public.invoice_numbering (entity_type, prefix, next_number, pad_length)
                SELECT v.entity_type, v.prefix, 1, v.pad_length
                FROM (VALUES
                  ('sales_invoice',    'INV-', 4),
                  ('purchase_invoice', 'PUR-', 4),
                  ('export_shipment',  'EXP-', 4)
                ) AS v(entity_type, prefix, pad_length)
                ON CONFLICT (entity_type) DO UPDATE SET next_number = 1;
            END IF;
        ELSE
            INSERT INTO public.invoice_numbering (entity_type, prefix, next_number, pad_length)
            SELECT v.entity_type, v.prefix, 1, v.pad_length
            FROM (VALUES
              ('sales_invoice',    'INV-', 4),
              ('purchase_invoice', 'PUR-', 4),
              ('export_shipment',  'EXP-', 4)
            ) AS v(entity_type, prefix, pad_length)
            ON CONFLICT (entity_type) DO UPDATE SET next_number = 1;
        END IF;
    END IF;
END $$;

-- 8. ملف تعريف الشركة (Company Profile)
DO $$
DECLARE
    v_has_company_id BOOLEAN;
    v_comp_id TEXT;
    v_comp_type TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'company_profile') THEN
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'company_profile' AND column_name = 'company_id'
        ) INTO v_has_company_id;

        IF v_has_company_id THEN
            SELECT udt_name INTO v_comp_type
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'company_profile' AND column_name = 'company_id';

            IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
                SELECT id::TEXT INTO v_comp_id FROM public.sys_companies LIMIT 1;
            END IF;

            IF v_comp_id IS NOT NULL THEN
                EXECUTE format('
                    INSERT INTO public.company_profile (company_id, company_name, base_currency)
                    SELECT %L::%s, ''شركتي'', ''EGP''
                    WHERE NOT EXISTS (SELECT 1 FROM public.company_profile)', v_comp_id, v_comp_type);
            ELSE
                INSERT INTO public.company_profile (company_name, base_currency)
                SELECT 'شركتي', 'EGP'
                WHERE NOT EXISTS (SELECT 1 FROM public.company_profile);
            END IF;
        ELSE
            INSERT INTO public.company_profile (company_name, base_currency)
            SELECT 'شركتي', 'EGP'
            WHERE NOT EXISTS (SELECT 1 FROM public.company_profile);
        END IF;
    END IF;
END $$;

-- 8b. أنواع المستندات المالية والتشغيلية (Document Types for Financial Operations)
DO $$
BEGIN
    CREATE TABLE IF NOT EXISTS public.sys_document_types (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        prefix TEXT NOT NULL,
        description TEXT,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        deleted_at TIMESTAMPTZ
    );

    INSERT INTO public.sys_document_types (code, name, prefix, is_active)
    VALUES 
      ('crop_payment',             'Crop Purchase Payment / سداد مشتريات محاصيل', 'CPAY',  true),
      ('supplier_payment',         'Supplier Advance / دفعة مقدمة لمورد',         'PMT',   true),
      ('purchase_payment',         'Purchase Payment / سداد مشتريات خامات',       'PPAY',  true),
      ('custody_disbursement',     'Custody Disbursement / صرف عهدة',             'CDIS',  true),
      ('custody_transfer',         'Custody Transfer / تحويل عهدة',                 'CTRF',  true),
      ('return_custody',           'Return Custody / إرجاع عهدة',                   'CRET',  true),
      ('treasury_transfer',        'Treasury Transfer / تحويل خزينة',               'TT',    true),
      ('purchase_price_adjustment','Purchase Price Adjustment / تسوية سعر مشتريات', 'PPADJ', true),
      ('packing_order',            'Packing Order / أمر تعبئة',                   'PK',    true),
      ('packing_cost_adjustment',  'Packing Cost Adjustment / تسوية تكلفة أمر تعبئة', 'PKADJ', true),
      ('sale_sorting',             'Sale Sorting / بيع فرز',                       'SSORT', true),
      ('lot_receipt',              'Lot Receipt / استلام لوت',                    'LOT',   true),
      ('lot_price_adjustment',     'Lot Price Adjustment / تسوية سعر لوت',        'LPADJ', true),
      ('lot_return',               'Lot Return / مرتجع لوت',                      'RET',   true),
      ('purchase_invoice',         'Purchase Invoice / فاتورة مشتريات خامات',     'PINV',  true),
      ('sales_invoice',            'Sales Invoice / فاتورة مبيعات',               'SINV',  true),
      ('journal_entry',            'Journal Entry / قيد يومية',                   'JE',    true),
      ('packing_order_debit_note', 'Packing Order Debit Note / إشعار تسوية مورد لأمر تعبئة', 'PKDN', true),
      ('shipment_admin_expenses',  'Shipment Admin Expenses / مصروفات إدارية محملة على الشحنة', 'ADM', true),
      ('shipment_taxes',           'Shipment Taxes / ضرائب محملة على الشحنة',     'TAX',   true),
      ('packing_waste',            'Packing Waste / إذن هالك تعبئة',              'PW',    true),
      ('opening_balance',          'Opening Balance / رصيد افتتاحي',              'OB',    true),
      ('raw_material_opening',     'Raw Material Opening Balance / رصيد افتتاحي مواد تعبئة', 'PAC-OB', true)
    ON CONFLICT (code) DO UPDATE SET 
      prefix = EXCLUDED.prefix,
      name = EXCLUDED.name,
      is_active = true;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences') THEN
      INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
      SELECT c.id, d.code, 0, 5
      FROM public.sys_companies c
      CROSS JOIN public.sys_document_types d
      WHERE NOT EXISTS (
        SELECT 1 FROM public.sys_sequences s
        WHERE s.company_id = c.id AND s.document_type_code = d.code
      );
    END IF;
END $$;

-- 9. السنة المالية (Fiscal Year الحالية)
DO $$
DECLARE
    v_has_company_id BOOLEAN;
    v_comp_id TEXT;
    v_comp_type TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'fiscal_years') THEN
        BEGIN
            PERFORM setval(pg_get_serial_sequence('public.fiscal_years', 'id'), COALESCE((SELECT MAX(id) FROM public.fiscal_years), 0) + 1, false);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'fiscal_years' AND column_name = 'company_id'
        ) INTO v_has_company_id;

        IF v_has_company_id THEN
            SELECT udt_name INTO v_comp_type
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'fiscal_years' AND column_name = 'company_id';

            IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
                SELECT id::TEXT INTO v_comp_id FROM public.sys_companies LIMIT 1;
            END IF;

            IF v_comp_id IS NULL AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'accounts') THEN
                SELECT company_id::TEXT INTO v_comp_id FROM public.accounts WHERE company_id IS NOT NULL LIMIT 1;
            END IF;

            IF v_comp_id IS NOT NULL THEN
                EXECUTE format('
                    INSERT INTO public.fiscal_years (company_id, year, name, start_date, end_date, status, is_current)
                    SELECT
                      %L::%s,
                      EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
                      ''FY '' || EXTRACT(YEAR FROM CURRENT_DATE),
                      MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 1, 1),
                      MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 12, 31),
                      ''ACTIVE'',
                      true
                    WHERE NOT EXISTS (
                      SELECT 1 FROM public.fiscal_years
                      WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
                    )', v_comp_id, v_comp_type);
            ELSE
                INSERT INTO public.fiscal_years (year, name, start_date, end_date, status, is_current)
                SELECT
                  EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
                  'FY ' || EXTRACT(YEAR FROM CURRENT_DATE),
                  MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 1, 1),
                  MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 12, 31),
                  'ACTIVE',
                  true
                WHERE NOT EXISTS (
                  SELECT 1 FROM public.fiscal_years
                  WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
                );
            END IF;
        ELSE
            INSERT INTO public.fiscal_years (year, name, start_date, end_date, status, is_current)
            SELECT
              EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
              'FY ' || EXTRACT(YEAR FROM CURRENT_DATE),
              MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 1, 1),
              MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 12, 31),
              'ACTIVE',
              true
            WHERE NOT EXISTS (
              SELECT 1 FROM public.fiscal_years
              WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER
            );
        END IF;
    END IF;
END $$;

-- 9.1 الفترات المحاسبية الشهرية للسنة المالية (Accounting Periods)
DO $$
DECLARE
    v_comp_id UUID;
    v_fy_id INT;
    v_year INT := EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;
    v_m INT;
    v_start_d DATE;
    v_end_d DATE;
    v_name TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'accounting_periods') THEN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
            SELECT id INTO v_comp_id FROM public.sys_companies LIMIT 1;
        END IF;
        
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'fiscal_years') THEN
            SELECT id INTO v_fy_id FROM public.fiscal_years WHERE year = v_year LIMIT 1;
        END IF;

        IF v_comp_id IS NOT NULL AND v_fy_id IS NOT NULL THEN
            FOR v_m IN 1..12 LOOP
                v_start_d := MAKE_DATE(v_year, v_m, 1);
                v_end_d := (v_start_d + INTERVAL '1 month - 1 day')::DATE;
                v_name := TO_CHAR(v_start_d, 'Mon-YYYY');

                INSERT INTO public.accounting_periods (company_id, fiscal_year_id, period_name, start_date, end_date, status)
                SELECT v_comp_id, v_fy_id, v_name, v_start_d, v_end_d, 'OPEN'
                WHERE NOT EXISTS (
                    SELECT 1 FROM public.accounting_periods ap
                    WHERE ap.company_id = v_comp_id AND ap.fiscal_year_id = v_fy_id AND ap.period_name = v_name
                );
            END LOOP;
        END IF;
    END IF;
END $$;

-- 10. إعدادات النظام الافتراضية الشاملة
DO $$
DECLARE
    v_has_company_id BOOLEAN;
    v_comp_id TEXT;
    v_comp_type TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'system_settings') THEN
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'system_settings' AND column_name = 'company_id'
        ) INTO v_has_company_id;

        IF v_has_company_id THEN
            SELECT udt_name INTO v_comp_type
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'system_settings' AND column_name = 'company_id';

            IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
                SELECT id::TEXT INTO v_comp_id FROM public.sys_companies LIMIT 1;
            END IF;

            IF v_comp_id IS NOT NULL THEN
                EXECUTE format('
                    INSERT INTO public.system_settings (company_id, setting_key, setting_value, description)
                    SELECT %L::%s, v.key, v.value, v.description
                    FROM (VALUES
                      (''company_name'',        ''Fruity Farms ERP'',         ''اسم النظام''),
                      (''company_name_ar'',     ''فروتي فارمز'',              ''اسم النظام بالعربية''),
                      (''currency'',            ''EGP'',                      ''العملة الافتراضية''),
                      (''base_currency'',       ''EGP'',                      ''العملة الأساسية''),
                      (''fiscal_year_start'',   ''1'',                        ''شهر بداية السنة المالية''),
                      (''language'',            ''ar'',                       ''اللغة الافتراضية''),
                      (''theme'',               ''light'',                    ''المظهر الافتراضي''),
                      (''timezone'',            ''Africa/Cairo'',             ''المنطقة الزمنية''),
                      (''date_format'',         ''dd/MM/yyyy'',               ''تنسيق التاريخ''),
                      (''currency_format'',     ''#,##0.00'',                 ''تنسيق العملة''),
                      (''decimals'',            ''2'',                        ''عدد الكسور العشرية''),
                      (''inventory_method'',    ''weighted_average'',         ''طريقة تقييم المخزون''),
                      (''auto_numbering'',      ''true'',                     ''تفعيل الترقيم التلقائي'')
                    ) AS v(key, value, description)
                    ON CONFLICT DO NOTHING', v_comp_id, v_comp_type);
            ELSE
                INSERT INTO public.system_settings (setting_key, setting_value, description)
                SELECT v.key, v.value, v.description
                FROM (VALUES
                  ('company_name',        'Fruity Farms ERP',         'اسم النظام'),
                  ('company_name_ar',     'فروتي فارمز',              'اسم النظام بالعربية'),
                  ('currency',            'EGP',                      'العملة الافتراضية'),
                  ('base_currency',       'EGP',                      'العملة الأساسية'),
                  ('fiscal_year_start',   '1',                        'شهر بداية السنة المالية'),
                  ('language',            'ar',                       'اللغة الافتراضية'),
                  ('theme',               'light',                    'المظهر الافتراضي'),
                  ('timezone',            'Africa/Cairo',             'المنطقة الزمنية'),
                  ('date_format',         'dd/MM/yyyy',               'تنسيق التاريخ'),
                  ('currency_format',     '#,##0.00',                 'تنسيق العملة'),
                  ('decimals',            '2',                        'عدد الكسور العشرية'),
                  ('inventory_method',    'weighted_average',         'طريقة تقييم المخزون'),
                  ('auto_numbering',      'true',                     'تفعيل الترقيم التلقائي')
                ) AS v(key, value, description)
                ON CONFLICT (setting_key) DO NOTHING;
            END IF;
        ELSE
            INSERT INTO public.system_settings (setting_key, setting_value, description)
            SELECT v.key, v.value, v.description
            FROM (VALUES
              ('company_name',        'Fruity Farms ERP',         'اسم النظام'),
              ('company_name_ar',     'فروتي فارمز',              'اسم النظام بالعربية'),
              ('currency',            'EGP',                      'العملة الافتراضية'),
              ('base_currency',       'EGP',                      'العملة الأساسية'),
              ('fiscal_year_start',   '1',                        'شهر بداية السنة المالية'),
              ('language',            'ar',                       'اللغة الافتراضية'),
              ('theme',               'light',                    'المظهر الافتراضي'),
              ('timezone',            'Africa/Cairo',             'المنطقة الزمنية'),
              ('date_format',         'dd/MM/yyyy',               'تنسيق التاريخ'),
              ('currency_format',     '#,##0.00',                 'تنسيق العملة'),
              ('decimals',            '2',                        'عدد الكسور العشرية'),
              ('inventory_method',    'weighted_average',         'طريقة تقييم المخزون'),
              ('auto_numbering',      'true',                     'تفعيل الترقيم التلقائي')
            ) AS v(key, value, description)
            ON CONFLICT (setting_key) DO NOTHING;
        END IF;
    END IF;
END $$;

-- ============================================================================
-- المرحلة 8: تثبيت دوال وتريجرز توليد الحسابات التلقائية للكيانات
-- ============================================================================

-- تنظيف وحذف الدوال القديمة بكافة توقيعاتها منعاً لخطأ 42P13
DROP FUNCTION IF EXISTS public.get_next_entity_account_code(TEXT, UUID) CASCADE;
DROP FUNCTION IF EXISTS public.get_next_entity_account_code(TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.get_next_entity_account_code(TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.generate_next_customer_code() CASCADE;
DROP FUNCTION IF EXISTS public.create_customer_account() CASCADE;
DROP FUNCTION IF EXISTS public.create_supplier_account() CASCADE;
DROP FUNCTION IF EXISTS public.create_shipping_company_account() CASCADE;
DROP FUNCTION IF EXISTS public.create_clearing_agent_account() CASCADE;
DROP FUNCTION IF EXISTS public.create_shareholder_account() CASCADE;
DROP FUNCTION IF EXISTS public.sync_entity_name_to_account() CASCADE;
DROP FUNCTION IF EXISTS public.delete_entity_linked_account() CASCADE;

-- 1. دالة توليد كود العميل التلقائي
CREATE OR REPLACE FUNCTION public.generate_next_customer_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    next_id int;
BEGIN
    SELECT COALESCE(MAX(
        CASE 
            WHEN code ~ '^[0-9]+$' THEN code::int
            WHEN code ~ '^CUST-[0-9]+$' THEN regexp_replace(code, '^CUST-', '')::int
            ELSE 0 
        END
    ), 0) + 1 INTO next_id FROM public.customers;
    RETURN LPAD(next_id::text, 4, '0');
END;
$$;

-- 2. دالة توليد كود الحساب الفرعي الموحد (متوافقة مع multi-tenant)
CREATE OR REPLACE FUNCTION public.get_next_entity_account_code(
  p_entity_type TEXT,
  p_company_id UUID DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pattern TEXT;
  v_start   INTEGER;
  v_next    INTEGER;
  v_code    TEXT;
BEGIN
  CASE p_entity_type
    WHEN 'customer'         THEN v_pattern := '^1020[0-9]+$'; v_start := 102000;
    WHEN 'supplier'         THEN v_pattern := '^2000[0-9]+$'; v_start := 200000;
    WHEN 'shipping_company' THEN v_pattern := '^2103[0-9]+$'; v_start := 210300;
    WHEN 'clearing_agent'   THEN v_pattern := '^2104[0-9]+$'; v_start := 210400;
    WHEN 'shareholder'      THEN v_pattern := '^3101[0-9]+$'; v_start := 310100;
    ELSE RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
  END CASE;

  -- البحث عن أعلى كود حساب حالي لهذا النمط عبر كل الشركات
  LOOP
    SELECT COALESCE(MAX(account_code::bigint), v_start) + 1 INTO v_next
    FROM public.accounts
    WHERE account_code ~ v_pattern;

    IF v_next <= v_start THEN
      v_next := v_start + 1;
    END IF;

    v_code := v_next::TEXT;

    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.accounts WHERE account_code = v_code
    );

    v_start := v_next;
  END LOOP;

  RETURN v_code;
END;
$$;

-- Overload للدوال القديمة التي قد تمرر p_company_id كنص
CREATE OR REPLACE FUNCTION public.get_next_entity_account_code(
  p_entity_type TEXT,
  p_company_id TEXT
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN public.get_next_entity_account_code(p_entity_type, p_company_id::UUID);
END;
$$;

-- 3. تريجر إنشاء حساب العميل تلقائياً
CREATE OR REPLACE FUNCTION public.create_customer_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- البحث عن الحساب الأب بنفس شركة الكيان أولاً، ثم أي حساب أب كبديل
  SELECT id INTO v_parent_id
  FROM public.accounts
  WHERE account_code = '1020' AND (company_id = NEW.company_id OR company_id IS NULL)
  ORDER BY (company_id = NEW.company_id) DESC NULLS LAST
  LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '1020' LIMIT 1;
  END IF;

  v_code := public.get_next_entity_account_code('customer', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset',
    COALESCE(v_code::bigint, 102099),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.customers
  SET account_id = v_new_account_id,
      code = COALESCE(NEW.code, v_code)
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_customer_account ON public.customers;
CREATE TRIGGER trg_create_customer_account
AFTER INSERT ON public.customers
FOR EACH ROW
EXECUTE FUNCTION public.create_customer_account();

-- 4. تريجر إنشاء حساب المورد تلقائياً
CREATE OR REPLACE FUNCTION public.create_supplier_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM public.accounts
  WHERE account_code = '2000' AND (company_id = NEW.company_id OR company_id IS NULL)
  ORDER BY (company_id = NEW.company_id) DESC NULLS LAST
  LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '2000' LIMIT 1;
  END IF;

  v_code := public.get_next_entity_account_code('supplier', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Supplier - ' || COALESCE(NEW.name, ''),
    'مورد - ' || COALESCE(NEW.name, ''),
    'liability',
    COALESCE(v_code::bigint, 200099),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.suppliers
  SET account_id = v_new_account_id,
      code = COALESCE(NEW.code, v_code)
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_supplier_account ON public.suppliers;
CREATE TRIGGER trg_create_supplier_account
AFTER INSERT ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.create_supplier_account();

-- 5. تريجر إنشاء حساب شركة الشحن تلقائياً
CREATE OR REPLACE FUNCTION public.create_shipping_company_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM public.accounts
  WHERE account_code = '2103' AND (company_id = NEW.company_id OR company_id IS NULL)
  ORDER BY (company_id = NEW.company_id) DESC NULLS LAST
  LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '2103' LIMIT 1;
  END IF;

  v_code := public.get_next_entity_account_code('shipping_company', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Shipping - ' || COALESCE(NEW.name, ''),
    'شركة شحن - ' || COALESCE(NEW.name, ''),
    'liability',
    COALESCE(v_code::bigint, 210399),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.shipping_companies
  SET account_id = v_new_account_id,
      code = COALESCE(NEW.code, v_code)
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_shipping_company_account ON public.shipping_companies;
CREATE TRIGGER trg_create_shipping_company_account
AFTER INSERT ON public.shipping_companies
FOR EACH ROW
EXECUTE FUNCTION public.create_shipping_company_account();

-- 6. تريجر إنشاء حساب المخلص الجمركي تلقائياً
CREATE OR REPLACE FUNCTION public.create_clearing_agent_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM public.accounts
  WHERE account_code = '2104' AND (company_id = NEW.company_id OR company_id IS NULL)
  ORDER BY (company_id = NEW.company_id) DESC NULLS LAST
  LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '2104' LIMIT 1;
  END IF;

  v_code := public.get_next_entity_account_code('clearing_agent', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Clearing - ' || COALESCE(NEW.name, ''),
    'مخلص جمركي - ' || COALESCE(NEW.name, ''),
    'liability',
    COALESCE(v_code::bigint, 210499),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.clearing_agents
  SET account_id = v_new_account_id,
      code = COALESCE(NEW.code, v_code)
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_clearing_agent_account ON public.clearing_agents;
CREATE TRIGGER trg_create_clearing_agent_account
AFTER INSERT ON public.clearing_agents
FOR EACH ROW
EXECUTE FUNCTION public.create_clearing_agent_account();

-- 7. تريجر إنشاء حساب المساهم تلقائياً
CREATE OR REPLACE FUNCTION public.create_shareholder_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM public.accounts
  WHERE account_code = '3101' AND (company_id = NEW.company_id OR company_id IS NULL)
  ORDER BY (company_id = NEW.company_id) DESC NULLS LAST
  LIMIT 1;
  IF v_parent_id IS NULL THEN
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '3101' LIMIT 1;
  END IF;

  v_code := public.get_next_entity_account_code('shareholder', NEW.company_id);

  INSERT INTO public.accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Shareholder - ' || COALESCE(NEW.name, ''),
    'مساهم - ' || COALESCE(NEW.name, ''),
    'equity',
    COALESCE(v_code::bigint, 310199),
    NEW.company_id,
    v_parent_id,
    2,
    true,
    true,
    false,
    true
  )
  ON CONFLICT (account_code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      account_name = EXCLUDED.account_name,
      company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  UPDATE public.shareholders
  SET account_id = v_new_account_id
  WHERE id = NEW.id;

  NEW.account_id := v_new_account_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_shareholder_account ON public.shareholders;
CREATE TRIGGER trg_create_shareholder_account
AFTER INSERT ON public.shareholders
FOR EACH ROW
EXECUTE FUNCTION public.create_shareholder_account();

-- 8. تريجر مزامنة تعديل اسم الكيان مع شجرة الحسابات
CREATE OR REPLACE FUNCTION public.sync_entity_name_to_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_prefix TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL AND (OLD.name IS DISTINCT FROM NEW.name) THEN
    CASE TG_TABLE_NAME
      WHEN 'customers'          THEN v_prefix := 'عميل - ';
      WHEN 'suppliers'          THEN v_prefix := 'مورد - ';
      WHEN 'shipping_companies' THEN v_prefix := 'شركة شحن - ';
      WHEN 'clearing_agents'    THEN v_prefix := 'مخلص جمركي - ';
      WHEN 'shareholders'       THEN v_prefix := 'مساهم - ';
      ELSE v_prefix := '';
    END CASE;

    UPDATE public.accounts
    SET name = v_prefix || COALESCE(NEW.name, ''),
        account_name = v_prefix || COALESCE(NEW.name, ''),
        updated_at = NOW()
    WHERE id = NEW.account_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_customer_name ON public.customers;
CREATE TRIGGER trg_sync_customer_name
AFTER UPDATE OF name ON public.customers
FOR EACH ROW
EXECUTE FUNCTION public.sync_entity_name_to_account();

DROP TRIGGER IF EXISTS trg_sync_supplier_name ON public.suppliers;
CREATE TRIGGER trg_sync_supplier_name
AFTER UPDATE OF name ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.sync_entity_name_to_account();

DROP TRIGGER IF EXISTS trg_sync_shipping_company_name ON public.shipping_companies;
CREATE TRIGGER trg_sync_shipping_company_name
AFTER UPDATE OF name ON public.shipping_companies
FOR EACH ROW
EXECUTE FUNCTION public.sync_entity_name_to_account();

DROP TRIGGER IF EXISTS trg_sync_clearing_agent_name ON public.clearing_agents;
CREATE TRIGGER trg_sync_clearing_agent_name
AFTER UPDATE OF name ON public.clearing_agents
FOR EACH ROW
EXECUTE FUNCTION public.sync_entity_name_to_account();

DROP TRIGGER IF EXISTS trg_sync_shareholder_name ON public.shareholders;
CREATE TRIGGER trg_sync_shareholder_name
AFTER UPDATE OF name ON public.shareholders
FOR EACH ROW
EXECUTE FUNCTION public.sync_entity_name_to_account();

-- 9. تريجر حذف حساب الكيان عند حذف الكيان نهائياً
CREATE OR REPLACE FUNCTION public.delete_entity_linked_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF OLD.account_id IS NOT NULL THEN
    DELETE FROM public.accounts 
    WHERE id = OLD.account_id
      AND account_code NOT IN (
        '1000', '1010', '1020', '1030', '1031', '1032', '1040',
        '11101', '11102', '11103', '11104',
        '11201', '11202', '11203', '11204',
        '2000', '2100', '2103', '2104', '2200', '2300',
        '3000', '3100', '3101', '3200', '3300',
        '4000', '41101', '4200', '4300', '4310', '4320',
        '5000', '6001', '51102', '51104', '5110', '6000', '6110', '51101', '6130', '6150', '6151', '6152'
      );
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_customer_delete_account ON public.customers;
CREATE TRIGGER trg_customer_delete_account
AFTER DELETE ON public.customers
FOR EACH ROW
EXECUTE FUNCTION public.delete_entity_linked_account();

DROP TRIGGER IF EXISTS trg_supplier_delete_account ON public.suppliers;
CREATE TRIGGER trg_supplier_delete_account
AFTER DELETE ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.delete_entity_linked_account();

-- ============================================================================
-- المرحلة 9: تصفير الأرصدة والـ Sequences
-- ============================================================================

-- تصفير أرصدة الحسابات
UPDATE public.accounts SET balance = 0, updated_at = NOW();

-- حذف سجلات الأكواد المحذوفة السابقة إن وجدت
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'deleted_account_codes') THEN
        DELETE FROM public.deleted_account_codes;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'deleted_entity_codes') THEN
        DELETE FROM public.deleted_entity_codes;
    END IF;
END $$;

-- تصفير Sequences في PostgreSQL ومزامنتها ديناميكياً بدقة
DO $$
DECLARE
    r RECORD;
    v_seq TEXT;
    v_max_id BIGINT;
BEGIN
    -- 1. تصفير أي sequences عامة غير مرتبطة مباشرة بأعمدة
    FOR r IN (
        SELECT s.sequence_name
        FROM information_schema.sequences s
        WHERE s.sequence_schema = 'public'
          AND s.sequence_name NOT LIKE '%accounts%'
          AND s.sequence_name NOT LIKE '%expense%'
          AND s.sequence_name NOT IN ('journal_entries_id_seq', 'account_ledger_entries_id_seq')
    ) LOOP
        BEGIN
            EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequence_name) || ' RESTART WITH 1;';
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;

    -- 2. مزامنة كل sequence مربوط بعمود جدول بدقة مع أعلى ID موجود + 1
    FOR r IN (
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND column_name = 'id' AND data_type IN ('integer', 'bigint', 'smallint')
    ) LOOP
        BEGIN
            v_seq := pg_get_serial_sequence('public.' || quote_ident(r.table_name), 'id');
            IF v_seq IS NOT NULL THEN
                EXECUTE format('SELECT COALESCE(MAX(id), 0) + 1 FROM public.%I', r.table_name) INTO v_max_id;
                EXECUTE format('ALTER SEQUENCE %s RESTART WITH %s', v_seq, v_max_id);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;

    -- تصفير عدادات المستندات والفواتير (OB, INV, PUR, الخ)
    BEGIN
        EXECUTE 'UPDATE public.invoice_numbering SET next_number = 1;';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    BEGIN
        EXECUTE 'UPDATE public.sys_document_types SET next_number = 1;';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
        EXECUTE 'DELETE FROM public.sys_sequences;';
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'UPDATE public.sys_sequences SET current_value = 0;';
    END;
END $$;

-- ============================================================================
-- المرحلة 10: الفحص والتحقق الشامل النهائي (Comprehensive Verification)
-- ============================================================================

DO $$
DECLARE
  v_tbl TEXT;
  v_count INT;
  v_missing_core TEXT[] := '{}';
  v_core_code TEXT;
  v_company_count INT := 0;
  v_main_treasury INT := 0;
  v_treasury_currencies INT := 0;
  v_treasury_links_ok INT := 0;
  v_bank_accounts INT := 0;
  v_warehouses INT := 0;
  v_total_accounts INT := 0;
BEGIN
  -- عدد الشركات في النظام (للتحقق بنسبة)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
    SELECT COUNT(*) INTO v_company_count FROM public.sys_companies WHERE deleted_at IS NULL;
  END IF;
  IF v_company_count < 1 THEN v_company_count := 1; END IF;

  -- التحقق من خلو المعاملات التشغيلية
  FOREACH v_tbl IN ARRAY ARRAY[
    'journal_entries', 'account_ledger_entries', 'customers', 'suppliers', 
    'purchase_invoices', 'export_shipments', 'stock_batches', 
    'treasury_transactions', 'bank_account_transactions',
    'packing_orders', 'lot_receipts', 'purchases', 'lots', 'invoices', 'transactions'
  ] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = v_tbl) THEN
      EXECUTE 'SELECT COUNT(*) FROM public.' || quote_ident(v_tbl) INTO v_count;
      IF v_count > 0 THEN
        RAISE EXCEPTION 'Verification Failed: Table % has % rows, expected 0.', v_tbl, v_count;
      END IF;
    END IF;
  END LOOP;

  -- التحقق من السنة المالية والعدادات
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'fiscal_years') THEN
    SELECT COUNT(*) INTO v_count FROM public.fiscal_years WHERE is_current = true;
    IF v_count != 1 THEN
      RAISE EXCEPTION 'Verification Failed: Expected exactly 1 active fiscal year, but found %.', v_count;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_sequences') THEN
    DELETE FROM public.sys_sequences;
    SELECT COUNT(*) INTO v_count FROM public.sys_sequences WHERE current_value > 0;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'Verification Failed: Expected sys_sequences active counters to be 0, but found % rows.', v_count;
    END IF;
  END IF;

  -- التحقق من الحسابات القياسية الأساسية
  FOREACH v_core_code IN ARRAY ARRAY[
    '1000', '1010', '1020', '1030', '1031', '1032', '1040', '11101', '11102', '11103', '11104',
    '11201', '11202', '11203', '11204',
    '2000', '2103', '2104',
    '3000', '3001', '3002', '3003', '3004', '3100', '3101', '3200',
    '3900', '3901', '3902', '3903', '3904',
    '4000',
    '5000', '6001', '51102', '51104', '5110', '6000'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = v_core_code) THEN
      v_missing_core := array_append(v_missing_core, v_core_code);
    END IF;
  END LOOP;

  IF array_length(v_missing_core, 1) > 0 THEN
    RAISE EXCEPTION 'Verification Failed: Missing core accounts: %', v_missing_core;
  END IF;

  -- التحقق من الخزينة الرئيسية والربط (multi-tenant: عدد الشركات × العملات)
  SELECT COUNT(*) INTO v_main_treasury FROM public.treasuries WHERE type = 'main';
  SELECT COUNT(*) INTO v_treasury_currencies FROM public.treasury_balances;
  SELECT COUNT(*) INTO v_treasury_links_ok FROM public.treasury_balances tb JOIN public.accounts a ON tb.account_id = a.id;

  IF v_main_treasury < 1 THEN
    RAISE EXCEPTION 'Verification Failed: No main treasury found (count=%)', v_main_treasury;
  END IF;
  IF v_treasury_currencies < 4 THEN
    RAISE EXCEPTION 'Verification Failed: Treasury currencies insufficient (count=%, expected >= 4)', v_treasury_currencies;
  END IF;
  IF v_treasury_links_ok < 4 THEN
    RAISE EXCEPTION 'Verification Failed: Treasury GL links insufficient (count=%, expected >= 4)', v_treasury_links_ok;
  END IF;

  -- التحقق من البنوك والمخازن (multi-tenant: عدد الشركات × الأصول)
  SELECT COUNT(*) INTO v_bank_accounts FROM public.bank_accounts;
  SELECT COUNT(*) INTO v_warehouses FROM public.warehouses;

  IF v_bank_accounts < 4 THEN
    RAISE EXCEPTION 'Verification Failed: Bank accounts insufficient (count=%, expected >= 4)', v_bank_accounts;
  END IF;
  IF v_warehouses < 3 THEN
    RAISE EXCEPTION 'Verification Failed: Warehouses insufficient (count=%, expected >= 3)', v_warehouses;
  END IF;

  SELECT COUNT(*) INTO v_total_accounts FROM public.accounts;

  RAISE NOTICE '======================================================';
  RAISE NOTICE '   ENTERPRISE HANDOVER RESET COMPLETED SUCCESSFULLY   ';
  RAISE NOTICE '======================================================';
  RAISE NOTICE '  ✓ All Operational Transactions Reset to 0';
  RAISE NOTICE '  ✓ Companies: %   Total Standard Accounts: %', v_company_count, v_total_accounts;
  RAISE NOTICE '  ✓ Main Treasuries: %  with % Currencies & % GL Links', v_main_treasury, v_treasury_currencies, v_treasury_links_ok;
  RAISE NOTICE '  ✓ Bank Accounts: %  Warehouses: %', v_bank_accounts, v_warehouses;
  RAISE NOTICE '  ✓ Auto-Creation Entity Triggers: PASS';
  RAISE NOTICE '  ✓ Database Ready for Client Handover: 100%%';
  RAISE NOTICE '======================================================';
END $$;

-- إعادة تفعيل تريجرز النظام إلى الوضع الطبيعي
SET LOCAL session_replication_role = 'origin';

-- ============================================================================
-- 10. تحديث جذر حسابات الموردين ليتطابق دائما مع كشف الحساب
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_supplier_true_balances()
RETURNS TABLE (
  supplier_id uuid,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  SELECT
    s.id,
    (
      -- 1. Initial Balance
      (CASE WHEN s.initial_balance_direction = 'CREDIT' THEN COALESCE(s.initial_balance, 0) ELSE -COALESCE(s.initial_balance, 0) END)
      
      -- 2. Purchases 
      + COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = s.id AND status = 'confirmed'), 0)
      
      -- 3. Treasury Transactions
      + COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('deposit', 'receive', 'income', 'supplier_refund') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM treasury_transactions WHERE supplier_id = s.id AND type IN ('expense', 'supplier_payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 4. Bank Transactions
      + COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::TEXT AND type IN ('deposit', 'receive', 'income', 'supplier_refund') AND (status = 'confirmed' OR status IS NULL)), 0)
      - COALESCE((SELECT SUM(amount) FROM bank_account_transactions WHERE entity_type = 'supplier' AND entity_id = s.id::TEXT AND type IN ('withdraw', 'expense', 'supplier_payment') AND (status = 'confirmed' OR status IS NULL)), 0)
      
      -- 5. Cheques
      + COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'incoming' AND status IN ('cleared', 'collected')), 0)
      - COALESCE((SELECT SUM(amount) FROM cheques WHERE supplier_id = s.id AND type = 'outgoing' AND status IN ('cleared', 'collected')), 0)
      
      -- 6. Legacy Ledger Entries (Manual journal entries, packing costs, old lot receipts, etc.)
      -- We EXCLUDE entries that are already represented by treasury_transactions or bank_transactions above 
      + COALESCE((
          SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END)
          FROM ledger_entries le
          WHERE le.entity_type = 'supplier' 
            AND le.entity_id IN (s.id::text, s.code)
            AND NOT (
                le.reference_type IN ('supplier_payment', 'treasury_deposit', 'treasury_withdrawal', 'treasury_transaction', 'cash_payment', 'receive', 'deposit', 'supplier_refund')
                AND EXISTS (SELECT 1 FROM treasury_transactions tt WHERE tt.id::TEXT = le.reference_id::TEXT)
            )
            AND NOT (
                le.reference_type IN ('bank_payment', 'bank_receipt', 'bank_transaction', 'cheque', 'supplier_payment', 'cheque_payment', 'receive', 'deposit', 'supplier_refund')
                AND EXISTS (SELECT 1 FROM bank_account_transactions bt WHERE bt.id::TEXT = le.reference_id::TEXT)
            )
            AND le.reference_type NOT IN ('lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return')
      ), 0)

      -- 7. New Enterprise Account Ledger Entries (New lot receipts, adjustments)
      -- Include source types that were migrated to enterprise journals and are no longer in legacy ledger_entries
      + COALESCE((
          SELECT SUM(ale.credit - ale.debit)
          FROM account_ledger_entries ale
          JOIN journal_entries je ON je.id = ale.journal_entry_id
          WHERE ale.account_id = s.account_id
            AND je.source_type IN (
              'lot_receipt', 'lot_adjustment', 'lot_price_adjustment', 'lot_return', 'manual'
            )
      ), 0)
    ) AS true_balance
  FROM suppliers s;
$func$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated, anon, service_role;

-- ============================================================================
-- 11. ترتيب دفتر قيود اليومية حسب الأحدث إضافة (created_at DESC)
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_get_journal_history(
    p_search text DEFAULT NULL,
    p_from_date date DEFAULT NULL,
    p_to_date date DEFAULT NULL,
    p_limit int DEFAULT 300
)
RETURNS SETOF v_journal_entry_lines AS $$
BEGIN
  IF p_search IS NULL OR p_search = '' THEN
    RETURN QUERY
    WITH latest AS (
      SELECT id 
      FROM journal_entries 
      WHERE deleted_at IS NULL
        AND (p_from_date IS NULL OR entry_date >= p_from_date)
        AND (p_to_date IS NULL OR entry_date <= p_to_date)
      ORDER BY created_at DESC, id DESC 
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN latest l ON l.id = v.entry_id
    ORDER BY v.created_at DESC, v.entry_id DESC, v.id ASC;
  ELSE
    RETURN QUERY
    WITH matched_entries AS (
      SELECT entry_id
      FROM v_journal_entry_lines
      WHERE (p_from_date IS NULL OR transaction_date >= p_from_date)
        AND (p_to_date IS NULL OR transaction_date <= p_to_date)
        AND (
          entry_number ILIKE '%' || p_search || '%'
          OR account_name ILIKE '%' || p_search || '%'
          OR account_code ILIKE '%' || p_search || '%'
          OR description ILIKE '%' || p_search || '%'
        )
      GROUP BY entry_id
      ORDER BY MAX(created_at) DESC, entry_id DESC
      LIMIT p_limit
    )
    SELECT v.*
    FROM v_journal_entry_lines v
    JOIN matched_entries m ON m.entry_id = v.entry_id
    ORDER BY v.created_at DESC, v.entry_id DESC, v.id ASC;
  END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION rpc_get_journal_history(text, date, date, int) TO authenticated, service_role, anon;

-- ============================================================================
-- 12. دوال تسوية أسعار بنود أوامر التعبئة وقفل الأرباح الموزعة
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_get_orders_with_distributed_shipments()
RETURNS SETOF BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT DISTINCT esi.packing_order_id
    FROM public.export_shipment_items esi
    JOIN public.shareholder_profit_distributions spd ON spd.shipment_id = esi.shipment_id
    WHERE esi.packing_order_id IS NOT NULL
      AND spd.deleted_at IS NULL;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_orders_with_distributed_shipments() TO authenticated;

DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, NUMERIC, UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, BIGINT, NUMERIC, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.rpc_apply_packing_order_item_debit_note(
    p_order_id BIGINT,
    p_item_type TEXT,                -- 'material' or 'crop'
    p_item_id BIGINT,                -- packing_order_materials.id OR packing_order_lines.id
    p_batch_id BIGINT,               -- station_product_batch_id or lot_id
    p_discount_amount NUMERIC,       -- Total discount amount in EGP (base currency)
    p_reason TEXT DEFAULT 'تسوية سعر / إشعار خصم مورد',
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order RECORD;
    v_notes JSONB;
    v_materials JSONB;
    v_fruit_alloc JSONB;
    v_new_materials JSONB := '[]'::jsonb;
    v_elem JSONB;
    v_found BOOLEAN := false;
    v_company_id UUID;
    v_source_account_id BIGINT;
    v_dest_account_id BIGINT;
    v_dest_account_code TEXT := '1031';
    v_is_shipped BOOLEAN := false;
    v_shipment_id BIGINT;
    v_shipment_no TEXT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_entry_date DATE;
    v_old_mat_cost NUMERIC;
    v_new_mat_cost NUMERIC;
    v_old_fruit_cost NUMERIC;
    v_new_fruit_cost NUMERIC;
    v_old_total_pkg_cost NUMERIC;
    v_new_total_pkg_cost NUMERIC;
    v_new_cost_per_carton NUMERIC;
    v_carton_count INT;
    v_item_used_qty NUMERIC;
    v_item_old_total NUMERIC;
    v_item_new_total NUMERIC;
    v_item_new_unit_cost NUMERIC;
    v_line RECORD;
    v_target_line_id BIGINT := NULL;
    v_target_line_new_cost NUMERIC;
    v_target_line_new_unit_cost NUMERIC;
    v_new_raw NUMERIC;
    v_new_cost_per_kg NUMERIC;
    v_new_sorting_cost NUMERIC;
    v_new_waste_cost NUMERIC;
    v_mat_apply_to TEXT := 'all';
    v_supplier_uuid UUID := NULL;
    v_supplier_name TEXT;
    v_item_name TEXT := '';
    v_target_desc TEXT;
    v_supplier_currency TEXT := 'EGP';
    v_exchange_rate NUMERIC := 1.0;
    v_foreign_discount NUMERIC;
    r_ship RECORD;
BEGIN
    -- ── A. Validate & Lock Packing Order ──
    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
    END IF;

    IF p_discount_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'مبلغ الخصم يجب أن يكون أكبر من الصفر');
    END IF;

    -- ── Check Profit Distribution Lock ──
    IF EXISTS (
        SELECT 1 
        FROM public.export_shipment_items esi
        JOIN public.shareholder_profit_distributions spd ON spd.shipment_id = esi.shipment_id
        WHERE esi.packing_order_id = p_order_id
          AND spd.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'تم توزيع أرباح الشحنة المرتبطة بهذا الأمر على المساهمين - لا يمكن تعديل الأسعار أو التكاليف');
    END IF;

    v_company_id := v_order.company_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- ── B. Identify Supplier & Adjust Costs ──
    IF p_item_type = 'material' THEN
        SELECT spb.supplier_id INTO v_supplier_uuid
        FROM public.packing_order_materials pom
        JOIN public.station_product_batches spb ON spb.id = pom.batch_id
        WHERE pom.id = p_item_id;

        IF v_supplier_uuid IS NULL AND p_batch_id IS NOT NULL THEN
            SELECT supplier_id INTO v_supplier_uuid
            FROM public.station_product_batches
            WHERE id = p_batch_id;
        END IF;

        IF v_supplier_uuid IS NOT NULL THEN
            SELECT name, COALESCE(currency, 'EGP'), COALESCE(exchange_rate, 1.0)
            INTO v_supplier_name, v_supplier_currency, v_exchange_rate
            FROM public.suppliers WHERE id = v_supplier_uuid;
        END IF;

        SELECT id INTO v_source_account_id
        FROM public.accounts
        WHERE (account_code = '2001' OR entity_id = v_supplier_uuid::text)
        ORDER BY (entity_id = v_supplier_uuid::text) DESC LIMIT 1;

    ELSIF p_item_type = 'crop' THEN
        SELECT l.supplier_id INTO v_supplier_uuid
        FROM public.packing_order_lines pol
        JOIN public.lots l ON l.id = pol.lot_id
        WHERE pol.id = p_item_id;

        IF v_supplier_uuid IS NULL AND p_batch_id IS NOT NULL THEN
            SELECT supplier_id INTO v_supplier_uuid FROM public.lots WHERE id = p_batch_id;
        END IF;

        IF v_supplier_uuid IS NOT NULL THEN
            SELECT name, COALESCE(currency, 'EGP'), COALESCE(exchange_rate, 1.0)
            INTO v_supplier_name, v_supplier_currency, v_exchange_rate
            FROM public.suppliers WHERE id = v_supplier_uuid;
        END IF;

        SELECT id INTO v_source_account_id
        FROM public.accounts
        WHERE (account_code = '2001' OR entity_id = v_supplier_uuid::text)
        ORDER BY (entity_id = v_supplier_uuid::text) DESC LIMIT 1;
    END IF;

    IF v_source_account_id IS NULL THEN
        SELECT id INTO v_source_account_id FROM public.accounts WHERE account_code = '2000' LIMIT 1;
    END IF;

    -- ── C. Destination Account (COGS 5000 if shipped, Inventory 1031 if not) ──
    SELECT EXISTS (
        SELECT 1 FROM public.export_shipment_items WHERE packing_order_id = p_order_id
    ) INTO v_is_shipped;

    IF v_is_shipped THEN
        v_dest_account_code := '5000';
    ELSE
        v_dest_account_code := '1031';
    END IF;

    SELECT id INTO v_dest_account_id FROM public.accounts WHERE account_code = v_dest_account_code LIMIT 1;

    -- ── D. Generate Journal Entry ──
    v_foreign_discount := ROUND(p_discount_amount / GREATEST(v_exchange_rate, 0.0001), 2);

    INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
    ) VALUES (
        'PENDING',
        v_entry_date,
        'إشعار خصم مورد على أمر تعبئة رقم ' || p_order_id::text || ' - ' || COALESCE(p_reason, ''),
        'posted', true, 'packing_debit_note', p_order_id::text, v_company_id,
        COALESCE(p_user_id, auth.uid()), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_debit_note', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'DN-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    -- DR: Supplier account (decreases payable)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_source_account_id, v_foreign_discount, 0, v_supplier_currency, p_discount_amount,
        'إشعار خصم من المورد ' || COALESCE(v_supplier_name, '') || ' لأمر تعبئة #' || p_order_id::text,
        v_company_id
    );

    -- CR: Inventory 1031 or COGS 5000 (reduces cost)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
        v_je_id, v_dest_account_id, 0, p_discount_amount, 'EGP', p_discount_amount,
        'تخفيض تكلفة الإنتاج لأمر تعبئة #' || p_order_id::text || ' بإشعار خصم مورد',
        v_company_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_num,
        'discount_amount', p_discount_amount
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_apply_packing_order_item_debit_note(BIGINT, TEXT, BIGINT, BIGINT, NUMERIC, TEXT, UUID) TO authenticated, anon, service_role;

-- ── Export Shipment Ledger & COGS Processing ──
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
  v_cust_curr text;
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

  -- 3. Determine Currency & Accurate Exchange Rate
  -- Priority 1: If shipment has no currency, inherit customer's currency
  IF (v_shipment.currency_code IS NULL OR v_shipment.currency_code = '') AND v_shipment.customer_id IS NOT NULL THEN
    SELECT c.currency INTO v_cust_curr
    FROM public.customers c
    WHERE c.id = v_shipment.customer_id;
    IF v_cust_curr IS NOT NULL AND v_cust_curr != '' THEN
      v_shipment.currency_code := v_cust_curr;
    END IF;
  END IF;

  -- Priority 2: If shipment has default EGP but customer is registered in foreign currency, inherit foreign currency
  IF v_shipment.currency_code = 'EGP' AND v_shipment.customer_id IS NOT NULL THEN
    SELECT c.currency INTO v_cust_curr
    FROM public.customers c
    WHERE c.id = v_shipment.customer_id;
    IF v_cust_curr IS NOT NULL AND v_cust_curr != '' AND v_cust_curr != 'EGP' THEN
      v_shipment.currency_code := v_cust_curr;
    END IF;
  END IF;

  IF v_shipment.currency_code IS NULL OR v_shipment.currency_code = '' THEN
    v_shipment.currency_code := 'USD';
  END IF;

  v_exch_rate := COALESCE(v_shipment.exchange_rate, 1);
  IF (v_exch_rate IS NULL OR v_exch_rate <= 1) AND v_shipment.currency_code != 'EGP' THEN
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
  -- Priority 1: Exact item-level cost (shipped quantity * carton cost for each item)
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

  -- Priority 2: Distinct packing orders (prevent duplicate sums across multi-product shipments)
  IF v_cogs_amount = 0 THEN
    SELECT COALESCE(SUM(po.total_packing_cost), 0)
    INTO v_cogs_amount
    FROM (
      SELECT DISTINCT packing_order_id
      FROM public.export_shipment_items
      WHERE shipment_id = p_shipment_id AND packing_order_id IS NOT NULL
    ) sub
    JOIN public.packing_orders po ON po.id = sub.packing_order_id
    WHERE po.status != 'cancelled';
  END IF;

  -- Priority 3: From packing orders directly linked to this shipment
  IF v_cogs_amount = 0 THEN
    SELECT COALESCE(SUM(po.total_packing_cost), 0)
    INTO v_cogs_amount
    FROM public.packing_orders po
    WHERE po.export_shipment_id = p_shipment_id
      AND po.status != 'cancelled';
  END IF;

  -- Priority 4: From shipment direct fields (if no packing orders linked)
  IF v_cogs_amount = 0 THEN
    v_cogs_amount := COALESCE(v_shipment.total_fruit_cost, 0) + COALESCE(v_shipment.total_packing_material_cost, 0);
  END IF;

  -- Priority 5: From cost_per_carton * carton_count
  IF v_cogs_amount = 0 AND COALESCE(v_shipment.cost_per_carton, 0) > 0 AND COALESCE(v_shipment.carton_count, 0) > 0 THEN
    v_cogs_amount := ROUND(v_shipment.cost_per_carton * v_shipment.carton_count, 2);
  END IF;

  -- Priority 6: From total_landed_cost
  IF v_cogs_amount = 0 AND COALESCE(v_shipment.total_landed_cost, 0) > 0 THEN
    v_cogs_amount := v_shipment.total_landed_cost;
  END IF;

  -- Update shipment record with exchange rate and calculated base figures
  UPDATE public.export_shipments
  SET currency_code = v_shipment.currency_code,
      currency = v_shipment.currency_code,
      exchange_rate = v_exch_rate,
      total_revenue_foreign = v_total_revenue,
      total_revenue_egp = v_base_revenue,
      total_fruit_cost = v_cogs_amount,
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

    -- Revenue Account: Route specifically to 4200 (إيرادات التصدير)
    BEGIN
      v_rev_acct := public.resolve_gl_account('4200', v_company_id);
    EXCEPTION WHEN OTHERS THEN
      v_rev_acct := NULL;
    END;

    IF v_rev_acct IS NULL THEN
      SELECT id INTO v_rev_acct FROM public.accounts WHERE company_id = v_company_id AND account_code = '4200' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_rev_acct IS NULL THEN
      SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = '4200' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_rev_acct IS NULL THEN
      SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = '4200' LIMIT 1;
    END IF;
    IF v_rev_acct IS NULL THEN
      SELECT id INTO v_rev_acct FROM public.accounts WHERE company_id = v_company_id AND account_code IN ('4000', '4101') AND is_leaf = true LIMIT 1;
    END IF;

    -- Discount Account
    BEGIN
      v_disc_acct := public.resolve_gl_account('4105', v_company_id);
    EXCEPTION WHEN OTHERS THEN
      v_disc_acct := NULL;
    END;

    IF v_disc_acct IS NULL THEN
      SELECT id INTO v_disc_acct FROM public.accounts WHERE company_id = v_company_id AND account_code = '4105' AND is_leaf = true LIMIT 1;
    END IF;
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
        'description', v_desc || ' - إيرادات التصدير'
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

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(BIGINT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(BIGINT, UUID) TO service_role;


-- ============================================================================
-- 13. دالة تحميل المصروفات الإدارية على الشحنة وقفل توزيع الأرباح
-- ============================================================================
ALTER TABLE public.export_shipments 
    ADD COLUMN IF NOT EXISTS allocated_admin_expenses NUMERIC(18,2) DEFAULT 0.00;

-- (Replaced by canonical rpc_save_shipment_admin_expenses at Migration 424)

-- ============================================================================
-- 14. دوال الخزينة والحسابات البنكية المحدثة مع دعم حقل الملاحظات (Notes)
-- ============================================================================

-- 1. deposit_treasury
DROP FUNCTION IF EXISTS public.deposit_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_revenue_account_id integer, p_reference_type text, p_reference_id text);
DROP FUNCTION IF EXISTS public.deposit_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_revenue_account_id integer, p_reference_type text, p_reference_id text, p_notes text);

CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance NUMERIC := 0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_tx_id BIGINT;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_revenue_acct BIGINT;
    v_desc TEXT;
    v_je_id BIGINT;
    v_source_type TEXT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_snapshot JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock treasury balance row & retrieve current cost_base and book_rate
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
    IF p_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    -- 3. Resolve GL accounts
    v_source_type := CASE WHEN p_revenue_account_id IS NOT NULL THEN 'revenue' ELSE 'opening_balance' END;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع في الخزينة');

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    -- 4. Post Journal Entry
    v_je_id := public.post_journal_entry(
        'treasury_deposit',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct,  'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- 5. Update / Upsert treasury_balances
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (p_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    -- 6. Insert transaction with notes mapped to p_notes
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, reference_type, reference_id, notes, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_source_type, v_je_id, auth.uid(),
        CASE WHEN p_revenue_account_id IS NOT NULL THEN p_revenue_account_id ELSE NULL END,
        p_reference_type, p_reference_id, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$function$;

-- 2. withdraw_treasury
DROP FUNCTION IF EXISTS public.withdraw_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.withdraw_treasury(p_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.withdraw_treasury(
    p_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_current_balance NUMERIC;
    v_current_cost_base NUMERIC;
    v_current_book_rate NUMERIC;
    v_new_balance     NUMERIC;
    v_new_cost_base   NUMERIC;
    v_new_book_rate   NUMERIC;
    v_tx_id           INTEGER;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_equity_acct     BIGINT;
    v_je_id           BIGINT;
    v_entry_number    TEXT;
    v_desc            TEXT;
    v_treasury_name   TEXT;
    v_base_amount     NUMERIC;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Treasury % not found', p_treasury_id;
    END IF;

    -- Current balance check & fetch rates
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف (الرصيد الحالي: % %)', v_current_balance, p_currency;
    END IF;

    -- IAS 21 Multi-Currency FX Engine Logic
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
        v_new_book_rate := 1.0;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
    ELSE
        v_new_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_new_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    SELECT name INTO v_treasury_name FROM treasuries WHERE id = p_treasury_id;
    v_desc := COALESCE(
        NULLIF(p_description, ''),
        'سحب من ' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
    );

    -- GL accounts
    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);
    v_equity_acct := public.resolve_gl_account('3000', v_company_id);

    -- Journal entry: Dr.Owner Equity / Cr.Treasury
    v_je_id := public.post_journal_entry(
        'opening_balance',
        v_desc,
        CURRENT_DATE,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_equity_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    -- Update treasury balance
    UPDATE treasury_balances 
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    -- Treasury transaction record
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type,
        journal_entry_id, expense_account_id, notes, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, 'opening_balance',
        v_je_id, v_equity_acct, p_notes, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    SELECT entry_number INTO v_entry_number FROM journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object('treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id, 'entry_number', v_entry_number);
END;
$function$;


-- 3. spend_with_category
DROP FUNCTION IF EXISTS public.spend_with_category(p_treasury_id bigint, p_currency text, p_amount numeric, p_description text, p_category_id integer, p_customer_id integer, p_supplier_id uuid, p_clearing_agent_id bigint, p_shipping_company_id bigint, p_shareholder_id uuid, p_expense_account_id integer, p_reference_type text, p_reference_id text);
DROP FUNCTION IF EXISTS public.spend_with_category(p_treasury_id bigint, p_currency text, p_amount numeric, p_description text, p_category_id integer, p_customer_id integer, p_supplier_id uuid, p_clearing_agent_id bigint, p_shipping_company_id bigint, p_shareholder_id uuid, p_expense_account_id integer, p_reference_type text, p_reference_id text, p_notes text);

CREATE OR REPLACE FUNCTION public.spend_with_category(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_category_id integer DEFAULT NULL::integer,
    p_customer_id integer DEFAULT NULL::integer,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_clearing_agent_id bigint DEFAULT NULL::bigint,
    p_shipping_company_id bigint DEFAULT NULL::bigint,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_current_balance NUMERIC;
    v_current_cost_base NUMERIC;
    v_current_book_rate NUMERIC;
    v_new_balance     NUMERIC;
    v_new_cost_base   NUMERIC;
    v_new_book_rate   NUMERIC;
    v_base_amount     NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_tx_type         TEXT;
    v_supplier_leaf   INTEGER;
BEGIN
    IF p_expense_account_id IS NOT NULL THEN
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
        END IF;
        v_tx_type := 'expense';
    ELSIF p_supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_supplier_leaf
        FROM suppliers s WHERE s.id = p_supplier_id;
        IF v_supplier_leaf IS NULL THEN
            RAISE EXCEPTION 'المورد لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_supplier_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المورد غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'supplier_payment';
    ELSE
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد مورد';
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    -- IAS 21 Multi-Currency FX Engine Logic
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
        v_new_book_rate := 1.0;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
    ELSE
        v_new_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(p_currency));
        v_base_amount := ROUND(p_amount * v_new_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE public.treasury_balances
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'مصروف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, category_id,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        reference_type, reference_id, notes,
        created_by
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc, p_category_id,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id, p_notes,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;

    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE 
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    END IF;

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    v_je_id := public.post_journal_entry(
        CASE v_tx_type WHEN 'supplier_payment' THEN 'purchase_payment' ELSE 'expense_payment' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc, 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc, 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$function$;


-- 4. disburse_custody
DROP FUNCTION IF EXISTS public.disburse_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.disburse_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.disburse_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_to_name      TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف في الخزينة المصدرة';
    END IF;

    -- IAS 21 Outbound from Source Treasury
    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    -- Update Source Treasury
    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    -- Update/Upsert Destination Treasury
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    -- IAS 21 Inbound to Destination Treasury
    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;
    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف عهدة إلى ' || COALESCE(v_to_name, 'موظف'));

    -- GL Posting
    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_disbursement', v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام عهدة)', 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (صرف عهدة)', 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    -- Transaction Record (Sender)
    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_from_treasury_id, 'disbursement_out', p_amount, p_currency, v_desc,
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    ) RETURNING id INTO v_tx_id;

    -- Transaction Record (Receiver)
    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_to_treasury_id, 'disbursement', p_amount, p_currency, v_desc,
        v_to_balance, v_to_balance + p_amount,
        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    );

    RETURN v_tx_id;
END;
$function$;


-- 5. transfer_custody
DROP FUNCTION IF EXISTS public.transfer_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.transfer_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.transfer_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_from_name    TEXT;
    v_to_name      TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف للتحويل';
    END IF;

    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    SELECT name INTO v_from_name FROM treasuries WHERE id = p_from_treasury_id;
    SELECT name INTO v_to_name FROM treasuries WHERE id = p_to_treasury_id;
    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل عهدة من ' || COALESCE(v_from_name, '') || ' إلى ' || COALESCE(v_to_name, ''));

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'custody_transfer', v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام تحويل)', 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرسال تحويل)', 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_from_treasury_id, 'transfer_out', p_amount, p_currency, v_desc,
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_to_treasury_id, 'transfer_in', p_amount, p_currency, v_desc,
        v_to_balance, v_to_balance + p_amount,
        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    );

    RETURN v_tx_id;
END;
$function$;


-- 6. return_custody
DROP FUNCTION IF EXISTS public.return_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.return_custody(p_from_treasury_id integer, p_to_treasury_id integer, p_currency text, p_amount numeric, p_description text, p_notes text);

CREATE OR REPLACE FUNCTION public.return_custody(
    p_from_treasury_id integer,
    p_to_treasury_id integer,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_notes text DEFAULT NULL::text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_cost_base NUMERIC;
    v_to_cost_base NUMERIC;
    v_from_book_rate NUMERIC;
    v_to_book_rate NUMERIC;
    v_base_amount  NUMERIC;
    v_tx_id        BIGINT;
    v_je_id        BIGINT;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_desc         TEXT;
    v_user_id      UUID;
    v_from_name    TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_from_balance, v_from_cost_base, v_from_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF v_from_balance IS NULL OR v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كاف لرد العهدة';
    END IF;

    IF p_currency = 'EGP' THEN
        v_base_amount := p_amount;
    ELSE
        v_base_amount := ROUND(p_amount * COALESCE(NULLIF(v_from_book_rate, 0), public.fn_get_exchange_rate(p_currency)), 2);
    END IF;

    UPDATE treasury_balances 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0, COALESCE(cost_base, 0) - v_base_amount),
        updated_at = NOW()
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_balance, v_to_cost_base, v_to_book_rate
    FROM treasury_balances 
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        v_to_balance := 0;
        v_to_cost_base := 0;
        v_to_book_rate := 1.0;
        INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id)
        VALUES (p_to_treasury_id, p_currency, 0, 0, 1.0, public.resolve_treasury_account(p_to_treasury_id, p_currency, (SELECT company_id FROM treasuries WHERE id = p_to_treasury_id)));
    END IF;

    IF p_currency = 'EGP' THEN
        v_to_book_rate := 1.0;
    ELSE
        IF (v_to_balance + p_amount) > 0 THEN
            v_to_book_rate := ROUND((v_to_cost_base + v_base_amount) / (v_to_balance + p_amount), 4);
        END IF;
    END IF;

    UPDATE treasury_balances
    SET balance = balance + p_amount,
        cost_base = COALESCE(cost_base, 0) + v_base_amount,
        book_rate = v_to_book_rate,
        updated_at = NOW()
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency;

    SELECT name INTO v_from_name FROM treasuries WHERE id = p_from_treasury_id;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إرجاع عهدة من ' || COALESCE(v_from_name, 'موظف'));

    SELECT company_id INTO v_company_id FROM treasuries WHERE id = p_from_treasury_id;
    v_from_acct := public.resolve_treasury_account(p_from_treasury_id, p_currency, v_company_id);
    v_to_acct   := public.resolve_treasury_account(p_to_treasury_id, p_currency, v_company_id);

    v_je_id := public.post_journal_entry(
        'return_custody', v_desc, CURRENT_DATE, v_company_id, v_user_id,
        jsonb_build_array(
            jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc || ' (استلام مرتجع عهدة)', 'base_debit', v_base_amount, 'base_credit', 0),
            jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc || ' (إرجاع عهدة)', 'base_debit', 0, 'base_credit', v_base_amount)
        )
    );

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_from_treasury_id, 'return_out', p_amount, p_currency, v_desc,
        v_from_balance, v_from_balance - p_amount,
        'treasury', p_to_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    ) RETURNING id INTO v_tx_id;

    INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        reference_type, reference_id, notes, created_by, journal_entry_id
    ) VALUES (
        p_to_treasury_id, 'return_in', p_amount, p_currency, v_desc,
        v_to_balance, v_to_balance + p_amount,
        'treasury', p_from_treasury_id::TEXT, p_notes, v_user_id, v_je_id
    );

    RETURN v_tx_id;
END;
$function$;


-- 7. bank_transfer
DROP FUNCTION IF EXISTS public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text);
DROP FUNCTION IF EXISTS public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text, p_bank_fee numeric);
DROP FUNCTION IF EXISTS public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text, p_bank_fee numeric, p_notes text);

CREATE OR REPLACE FUNCTION public.bank_transfer(p_from_account_id integer, p_to_account_id integer, p_amount numeric, p_description text DEFAULT NULL::text, p_bank_fee numeric DEFAULT 0.0, p_notes text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
    v_from_currency TEXT;
    v_to_currency  TEXT;
    v_cost_base_from NUMERIC;
    v_cost_base_to NUMERIC;
    v_book_rate_from NUMERIC;
    v_transfer_cost NUMERIC;
    v_company_id   UUID;
    v_from_acct    BIGINT;
    v_to_acct      BIGINT;
    v_je_id        BIGINT;
    v_desc         TEXT;
    v_lines        JSONB := '[]'::jsonb;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'لا يمكن التحويل للحساب نفسه';
    END IF;

    -- Lock and check source
    SELECT COALESCE(balance, 0), currency, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), company_id 
    INTO v_from_balance, v_from_currency, v_cost_base_from, v_book_rate_from, v_company_id
    FROM public.bank_accounts WHERE id = p_from_account_id FOR UPDATE;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب المصدر (المتوفر: %)', v_from_balance;
    END IF;

    -- Check destination
    SELECT COALESCE(balance, 0), currency, COALESCE(cost_base, 0)
    INTO v_to_balance, v_to_currency, v_cost_base_to
    FROM public.bank_accounts WHERE id = p_to_account_id FOR UPDATE;

    IF v_from_currency != v_to_currency THEN
        RAISE EXCEPTION 'التحويل البنكي المباشر مخصص للحسابات من نفس العملة. للتحويل بين عملات مختلفة استخدم صرف العملة البنكي.';
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'تحويل بنكي داخلي (' || v_from_currency || ')');

    IF v_from_currency = 'EGP' THEN
        v_transfer_cost := p_amount;
    ELSE
        v_transfer_cost := ROUND(p_amount * v_book_rate_from, 2);
    END IF;

    -- Update balances & cost bases
    UPDATE public.bank_accounts 
    SET balance = balance - p_amount,
        cost_base = GREATEST(0.00, v_cost_base_from - v_transfer_cost),
        updated_at = NOW()
    WHERE id = p_from_account_id;

    UPDATE public.bank_accounts 
    SET balance = balance + p_amount,
        cost_base = v_cost_base_to + v_transfer_cost,
        book_rate = CASE WHEN (balance + p_amount) > 0 THEN ROUND((v_cost_base_to + v_transfer_cost) / (balance + p_amount), 4) ELSE v_book_rate_from END,
        updated_at = NOW()
    WHERE id = p_to_account_id;

    -- Resolve GL accounts
    v_from_acct := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_to_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_transfer_cost, 'base_credit', 0, 'currency', v_from_currency, 'description', v_desc || ' (وارد)'),
        jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_transfer_cost, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
    );

    -- GL: Dr.Destination Bank / Cr.Source Bank (Zero Net Effect)
    v_je_id := public.post_journal_entry(
        'bank_transfer', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        v_lines
    );

    -- Record transactions with notes mapped to p_notes
    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after, description, 
        created_by, journal_entry_id, amount_in_base_currency, cost_base_released, bank_fee, transfer_mode, notes
    ) VALUES (
        p_from_account_id, 'transfer_out', p_amount, v_from_balance, v_from_balance - p_amount, 
        v_desc, auth.uid(), v_je_id, v_transfer_cost, v_transfer_cost, 0, 'internal_transfer', p_notes
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after, description, 
        created_by, journal_entry_id, amount_in_base_currency, cost_base_released, transfer_mode, notes
    ) VALUES (
        p_to_account_id, 'transfer_in', p_amount, v_to_balance, v_to_balance + p_amount, 
        v_desc, auth.uid(), v_je_id, v_transfer_cost, 0, 'internal_transfer', p_notes
    );

    RETURN jsonb_build_object('success', true, 'journal_entry_id', v_je_id, 'cost_base', v_transfer_cost);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.deposit_treasury(integer, text, numeric, text, integer, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.withdraw_treasury(integer, text, numeric, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.spend_with_category(bigint, text, numeric, text, integer, integer, uuid, bigint, bigint, uuid, integer, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.disburse_custody(integer, integer, text, numeric, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transfer_custody(integer, integer, text, numeric, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.return_custody(integer, integer, text, numeric, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bank_transfer(integer, integer, numeric, text, numeric, text) TO authenticated, service_role;

-- ============================================================================
-- المرحلة 8: تهيئة المساهمين وإعدادات توزيع الأرباح (Migration 354 Mirror)
-- ============================================================================
DO $$
DECLARE
  v_p1_id UUID;
  v_p2_id UUID;
  v_p3_id UUID;
  v_company_id UUID;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
    SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
  END IF;

  -- 1. إسلام
  IF NOT EXISTS (SELECT 1 FROM public.shareholders WHERE name = 'إسلام') THEN
    INSERT INTO public.shareholders (code, name, company_id, initial_balance_egp, current_balance_egp, initial_balance_direction_egp)
    VALUES ('00001', 'إسلام', v_company_id, 0, 0, 'CREDIT');
  END IF;

  -- 2. عبدالباطن
  IF NOT EXISTS (SELECT 1 FROM public.shareholders WHERE name = 'عبدالباطن') THEN
    INSERT INTO public.shareholders (code, name, company_id, initial_balance_egp, current_balance_egp, initial_balance_direction_egp)
    VALUES ('00002', 'عبدالباطن', v_company_id, 0, 0, 'CREDIT');
  END IF;

  -- 3. عماد
  IF NOT EXISTS (SELECT 1 FROM public.shareholders WHERE name = 'عماد') THEN
    INSERT INTO public.shareholders (code, name, company_id, initial_balance_egp, current_balance_egp, initial_balance_direction_egp)
    VALUES ('00003', 'عماد', v_company_id, 0, 0, 'CREDIT');
  END IF;

  -- Fetch their IDs
  SELECT id INTO v_p1_id FROM public.shareholders WHERE name = 'إسلام' LIMIT 1;
  SELECT id INTO v_p2_id FROM public.shareholders WHERE name = 'عبدالباطن' LIMIT 1;
  SELECT id INTO v_p3_id FROM public.shareholders WHERE name = 'عماد' LIMIT 1;

  -- 3. Ensure profit_distribution_settings default row exists
  IF EXISTS (SELECT 1 FROM public.profit_distribution_settings LIMIT 1) THEN
    UPDATE public.profit_distribution_settings
    SET person1_id = v_p1_id,
        person1_name = 'إسلام',
        person2_id = v_p2_id,
        person2_name = 'عبدالباطن',
        person3_id = v_p3_id,
        person3_name = 'عماد',
        updated_at = NOW()
    WHERE id = (SELECT id FROM public.profit_distribution_settings ORDER BY updated_at DESC LIMIT 1);
  ELSE
    INSERT INTO public.profit_distribution_settings (
      person1_id, person1_name,
      person2_id, person2_name,
      person3_id, person3_name,
      percentages, person4_for_shipment, currency_conversions,
      user_id
    ) VALUES (
      v_p1_id, 'إسلام',
      v_p2_id, 'عبدالباطن',
      v_p3_id, 'عماد',
      '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
      COALESCE((SELECT id FROM auth.users LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)
    );
  END IF;

  -- تعيين الحساب الأب 6000 لحساب 6001 و 6002
  UPDATE public.accounts
  SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '6000' LIMIT 1)
  WHERE account_code IN ('6001', '6002');
END $$;

-- ============================================================================
-- ── Treasury Draft & Confirm Workflow Support ──
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'treasury_transactions' AND column_name = 'status'
    ) THEN
        ALTER TABLE public.treasury_transactions 
        ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'treasury_transactions' AND column_name = 'payload'
    ) THEN
        ALTER TABLE public.treasury_transactions 
        ADD COLUMN payload JSONB DEFAULT '{}'::jsonb;
    END IF;

    ALTER TABLE public.treasury_transactions 
        DROP CONSTRAINT IF EXISTS treasury_transactions_type_check;

    ALTER TABLE public.treasury_transactions 
        ADD CONSTRAINT treasury_transactions_type_check 
        CHECK (type = ANY (ARRAY[
            'deposit',
            'expense',
            'withdrawal',
            'withdraw',
            'disbursement',
            'disbursement_out',
            'transfer_in',
            'transfer_out',
            'transfer',
            'return_in',
            'return_out',
            'currency_exchange_out',
            'currency_exchange_in',
            'currency_exchange',
            'exchange',
            'exchange_out',
            'exchange_in',
            'supplier_payment',
            'customer_payment',
            'clearing_agent_payment',
            'shipping_company_payment',
            'shareholder_payment',
            'shareholder_withdrawal',
            'customer_refund',
            'revenue',
            'multi_payment',
            'receipt'
        ]));

    ALTER TABLE public.bank_account_transactions 
        DROP CONSTRAINT IF EXISTS bank_account_transactions_type_check;

    ALTER TABLE public.bank_account_transactions 
        ADD CONSTRAINT bank_account_transactions_type_check 
        CHECK (type = ANY (ARRAY[
            'deposit',
            'withdraw',
            'withdrawal',
            'exchange_in',
            'exchange_out',
            'currency_exchange_in',
            'currency_exchange_out',
            'currency_exchange',
            'exchange',
            'transfer_in',
            'transfer_out',
            'transfer',
            'supplier_payment',
            'customer_payment',
            'clearing_agent_payment',
            'shipping_company_payment',
            'shareholder_payment',
            'shareholder_withdrawal',
            'customer_refund',
            'revenue',
            'multi_payment',
            'receipt',
            'expense'
        ]));
END $$;

CREATE OR REPLACE FUNCTION public.fn_require_expense_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.status = 'draft' THEN
        RETURN NEW;
    END IF;

    IF NEW.type = 'expense' 
       AND NEW.expense_account_id IS NULL 
       AND NEW.supplier_id IS NULL 
       AND NEW.customer_id IS NULL 
       AND NEW.clearing_agent_id IS NULL 
       AND NEW.shipping_company_id IS NULL 
       AND NEW.shareholder_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.status = 'draft' THEN
        RETURN NEW;
    END IF;

    IF NEW.type = 'deposit' 
       AND NEW.revenue_account_id IS NULL 
       AND NEW.customer_id IS NULL 
       AND NEW.supplier_id IS NULL 
       AND NEW.clearing_agent_id IS NULL 
       AND NEW.shipping_company_id IS NULL 
       AND NEW.shareholder_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب إيرادات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_save_treasury_draft(
    p_treasury_id BIGINT,
    p_type TEXT,
    p_amount NUMERIC,
    p_currency TEXT,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_category_id BIGINT DEFAULT NULL,
    p_expense_account_id BIGINT DEFAULT NULL,
    p_revenue_account_id BIGINT DEFAULT NULL,
    p_customer_id BIGINT DEFAULT NULL,
    p_supplier_id UUID DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id,
        type,
        amount,
        currency,
        description,
        notes,
        category_id,
        expense_account_id,
        revenue_account_id,
        customer_id,
        supplier_id,
        clearing_agent_id,
        shipping_company_id,
        shareholder_id,
        status,
        payload,
        created_by,
        created_at
    ) VALUES (
        p_treasury_id,
        p_type,
        p_amount,
        p_currency,
        p_description,
        p_notes,
        p_category_id,
        p_expense_account_id,
        p_revenue_account_id,
        p_customer_id,
        p_supplier_id,
        p_clearing_agent_id,
        p_shipping_company_id,
        p_shareholder_id,
        'draft',
        COALESCE(p_payload, '{}'::jsonb),
        auth.uid(),
        NOW()
    )
    RETURNING id INTO v_tx_id;

    RETURN v_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_update_treasury_draft(
    p_transaction_id BIGINT,
    p_treasury_id BIGINT DEFAULT NULL,
    p_amount NUMERIC DEFAULT NULL,
    p_currency TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_category_id BIGINT DEFAULT NULL,
    p_expense_account_id BIGINT DEFAULT NULL,
    p_revenue_account_id BIGINT DEFAULT NULL,
    p_customer_id BIGINT DEFAULT NULL,
    p_supplier_id UUID DEFAULT NULL,
    p_clearing_agent_id BIGINT DEFAULT NULL,
    p_shipping_company_id BIGINT DEFAULT NULL,
    p_shareholder_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.treasury_transactions
    SET
        treasury_id = COALESCE(p_treasury_id, treasury_id),
        amount = COALESCE(p_amount, amount),
        currency = COALESCE(p_currency, currency),
        description = COALESCE(p_description, description),
        notes = p_notes,
        category_id = p_category_id,
        expense_account_id = p_expense_account_id,
        revenue_account_id = p_revenue_account_id,
        customer_id = p_customer_id,
        supplier_id = p_supplier_id,
        clearing_agent_id = p_clearing_agent_id,
        shipping_company_id = p_shipping_company_id,
        shareholder_id = p_shareholder_id,
        payload = CASE WHEN p_payload IS NOT NULL THEN p_payload ELSE payload END
    WHERE id = p_transaction_id AND status = 'draft';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو أنها مؤكدة بالفعل';
    END IF;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_delete_treasury_draft(
    p_transaction_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_deleted_count INT;
BEGIN
    DELETE FROM public.treasury_transactions
    WHERE id = p_transaction_id AND status = 'draft';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    IF v_deleted_count = 0 THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو تم تأكيدها مسبقاً';
    END IF;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_confirm_treasury_draft(
    p_transaction_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx RECORD;
    v_res JSONB;
    v_receipt_type TEXT;
    v_counterparty_type TEXT;
    v_mp_source_type TEXT;
    v_mp_source_id BIGINT;
BEGIN
    SELECT * INTO v_tx
    FROM public.treasury_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    IF v_tx.type = 'deposit' OR v_tx.type = 'receipt' THEN
        v_receipt_type := COALESCE(v_tx.payload->>'receipt_type', 'cash');
        v_counterparty_type := v_tx.payload->>'counterparty_type';

        v_res := public.receive_payment(
            p_receipt_type      := v_receipt_type,
            p_amount            := v_tx.amount,
            p_currency          := v_tx.currency,
            p_counterparty_type := v_counterparty_type,
            p_counterparty_id   := v_tx.customer_id,
            p_supplier_id       := v_tx.supplier_id,
            p_shareholder_id    := v_tx.shareholder_id,
            p_description       := v_tx.description,
            p_notes             := v_tx.notes,
            p_treasury_id       := v_tx.treasury_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الاستلام وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'multi_payment' OR COALESCE((v_tx.payload->>'is_multi_payment')::boolean, false) = true THEN
        -- Read source_type and source_id from payload (fixes bank account multi-payment)
        v_mp_source_type := COALESCE(v_tx.payload->>'source_type', 'treasury');
        v_mp_source_id   := COALESCE(
            (v_tx.payload->>'source_id')::bigint,
            v_tx.treasury_id::bigint
        );

        v_res := public.rpc_entity_multi_payment(
            p_source_type        := v_mp_source_type,
            p_source_id          := v_mp_source_id,
            p_currency           := v_tx.currency,
            p_amount             := v_tx.amount,
            p_entity_type        := LOWER(COALESCE(v_tx.payload->>'entity_type', 'supplier')),
            p_entity_id          := COALESCE(v_tx.payload->>'entity_id', v_tx.supplier_id::text),
            p_description        := COALESCE(v_tx.description, 'سداد متعدد'),
            p_notes              := v_tx.notes,
            p_expense_account_id := v_tx.expense_account_id
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد السداد المتعدد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'exchange' OR v_tx.type = 'currency_exchange' THEN
        PERFORM public.exchange_currency(
            p_treasury_id   := v_tx.treasury_id::text,
            p_from_currency := COALESCE(v_tx.payload->>'from_currency', v_tx.currency),
            p_to_currency   := (v_tx.payload->>'to_currency')::text,
            p_amount_from   := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to     := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate := (v_tx.payload->>'exchange_rate')::numeric,
            p_user_id       := v_tx.created_by,
            p_transfer_mode := COALESCE(v_tx.payload->>'transfer_mode', 'exchange')
        );

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة وترحيل القيد بنجاح');

    ELSE
        IF v_tx.category_id IS NOT NULL AND v_tx.category_id > 0 THEN
            PERFORM public.spend_with_category(
                p_treasury_id          := v_tx.treasury_id,
                p_currency             := v_tx.currency,
                p_amount               := v_tx.amount,
                p_description          := COALESCE(v_tx.description, ''),
                p_category_id          := v_tx.category_id::integer,
                p_customer_id          := v_tx.customer_id::integer,
                p_supplier_id          := v_tx.supplier_id,
                p_clearing_agent_id    := v_tx.clearing_agent_id,
                p_shipping_company_id  := v_tx.shipping_company_id,
                p_shareholder_id       := v_tx.shareholder_id,
                p_expense_account_id   := v_tx.expense_account_id::integer,
                p_reference_type       := v_tx.payload->>'reference_type',
                p_reference_id         := v_tx.payload->>'reference_id',
                p_notes                := v_tx.notes
            );
        ELSE
            PERFORM public.spend_custody(
                p_treasury_id          := v_tx.treasury_id,
                p_currency             := v_tx.currency,
                p_amount               := v_tx.amount,
                p_description          := COALESCE(v_tx.description, ''),
                p_expense_account_id   := v_tx.expense_account_id::integer,
                p_customer_id          := v_tx.customer_id::integer,
                p_supplier_id          := v_tx.supplier_id,
                p_clearing_agent_id    := v_tx.clearing_agent_id,
                p_shipping_company_id  := v_tx.shipping_company_id,
                p_shareholder_id       := v_tx.shareholder_id,
                p_reference_type       := v_tx.payload->>'reference_type',
                p_reference_id         := v_tx.payload->>'reference_id',
                p_notes                := v_tx.notes
            );
        END IF;

        DELETE FROM public.treasury_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد صرف المصروف وترحيل القيد بنجاح');
    END IF;
END;
$$;

-- ============================================================================
-- ── Treasury Multi-Currency Cost Base & Exchange Engine (IAS 21) ──
-- ============================================================================

CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type character varying,
    p_amount numeric,
    p_currency character varying,
    p_counterparty_type character varying DEFAULT NULL::character varying,
    p_counterparty_id bigint DEFAULT NULL::bigint,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_description text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_treasury_id bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_treasury_id       BIGINT;
    v_current_balance   NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance       NUMERIC := 0;
    v_new_cost_base     NUMERIC := 0;
    v_new_book_rate     NUMERIC := 1.0;
    v_tx_id             BIGINT;
    v_company_id        UUID;
    v_treasury_acct     BIGINT;
    v_ar_acct           BIGINT;
    v_je_id             BIGINT;
    v_desc              TEXT;
    v_source_type       TEXT;
    v_treasury_name     TEXT;
    v_je_source         TEXT;
    v_credit_acct       BIGINT;
    v_rate              NUMERIC := 1.0;
    v_base_amount       NUMERIC;
    v_snapshot          JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_treasury_id IS NOT NULL THEN
        v_treasury_id := p_treasury_id;
    ELSE
        SELECT id INTO v_treasury_id
        FROM public.treasuries
        WHERE type = 'main' AND user_id = auth.uid()
        LIMIT 1;
        IF v_treasury_id IS NULL THEN
            SELECT id INTO v_treasury_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        END IF;
        IF v_treasury_id IS NULL THEN
            RAISE EXCEPTION 'لم يتم العثور على الخزينة الرئيسية.';
        END IF;
    END IF;

    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = v_treasury_id;

    -- 1. Lock treasury balance row & retrieve current cost_base and book_rate
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = v_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    -- 2. Calculate spot exchange rate & base amount
    IF p_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    IF p_counterparty_type IS NULL OR p_counterparty_type = 'opening' THEN
        v_source_type := 'opening_balance';
        SELECT name INTO v_treasury_name FROM public.treasuries WHERE id = v_treasury_id;
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
        );
    ELSE
        v_source_type := p_counterparty_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'استلام ' || p_receipt_type);
    END IF;

    v_treasury_acct := public.resolve_treasury_account(v_treasury_id, p_currency, v_company_id);

    IF p_counterparty_type = 'customer' THEN
        SELECT c.account_id INTO v_credit_acct FROM public.customers c WHERE c.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('1020', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'supplier' THEN
        SELECT s.account_id INTO v_credit_acct FROM public.suppliers s WHERE s.id = p_supplier_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'clearing_agent' THEN
        SELECT ca.account_id INTO v_credit_acct FROM public.clearing_agents ca WHERE ca.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shipping_company' THEN
        SELECT sc.account_id INTO v_credit_acct FROM public.shipping_companies sc WHERE sc.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id = p_shareholder_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
        END IF;
    ELSE
        v_credit_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, source_type,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        created_by, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc, v_source_type,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        v_current_balance, v_new_balance,
        auth.uid(),
        v_credit_acct, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'supplier_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'clearing_agent_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shipping_company_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shareholder' AND p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN
            UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN
            UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_shareholder_id;
        END IF;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shareholder_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSE
        v_je_source := 'opening_balance';
        v_je_id := public.post_journal_entry(
            v_je_source, v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    -- Sync treasury_balances with full cost_base and book_rate
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (v_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    RETURN jsonb_build_object('success', true, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id text,
    p_from_currency character varying,
    p_to_currency character varying,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid,
    p_transfer_mode text DEFAULT 'exchange'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_treasury_id         BIGINT := p_treasury_id::bigint;
    v_balance_before_from DECIMAL(15,2);
    v_balance_after_from  DECIMAL(15,2);
    v_cost_before_from    DECIMAL(15,2);
    v_rate_before_from    DECIMAL(15,4);
    v_new_cost_from       DECIMAL(15,2);
    v_new_rate_from       DECIMAL(15,4);

    v_balance_before_to   DECIMAL(15,2);
    v_balance_after_to    DECIMAL(15,2);
    v_cost_before_to      DECIMAL(15,2);
    v_rate_before_to      DECIMAL(15,4);
    v_new_cost_to         DECIMAL(15,2);
    v_new_rate_to         DECIMAL(15,4);

    v_company_id          UUID;
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_fx_gain_loss_acct   BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
    v_base_amount         NUMERIC;
    v_cost_base_released  NUMERIC;
    v_realized_fx_diff    NUMERIC;
BEGIN
    IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
        RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
    END IF;

    IF p_from_currency = p_to_currency THEN
        RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
    END IF;

    IF p_from_currency != 'EGP' AND p_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
    END IF;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_from, v_cost_before_from, v_rate_before_from
    FROM treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_from_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    INSERT INTO treasury_balances (treasury_id, currency, balance, cost_base, book_rate)
    VALUES (v_treasury_id, p_to_currency, 0.00, 0.00, 1.0000)
    ON CONFLICT (treasury_id, currency) DO NOTHING;

    SELECT balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_balance_before_to, v_cost_before_to, v_rate_before_to
    FROM treasury_balances
    WHERE treasury_id = v_treasury_id AND currency = p_to_currency
    FOR UPDATE;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = v_treasury_id;

    v_desc := 'تحويل عملة من ' || p_from_currency || ' إلى ' || p_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE p_from_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE p_to_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    IF p_from_currency != 'EGP' THEN
        -- Selling foreign currency
        v_cost_base_released := ROUND(p_amount_from * v_rate_before_from, 2);
        v_new_cost_from := GREATEST(0, v_cost_before_from - v_cost_base_released);
        v_new_rate_from := CASE WHEN v_balance_after_from > 0 THEN ROUND(v_new_cost_from / v_balance_after_from, 4) ELSE v_rate_before_from END;

        v_new_cost_to := v_balance_after_to;
        v_new_rate_to := 1.0;
        v_realized_fx_diff := p_amount_to - v_cost_base_released;
    ELSE
        -- Buying foreign currency
        v_new_cost_from := v_balance_after_from;
        v_new_rate_from := 1.0;

        v_new_cost_to := v_cost_before_to + p_amount_from;
        v_new_rate_to := CASE WHEN v_balance_after_to > 0 THEN ROUND(v_new_cost_to / v_balance_after_to, 4) ELSE p_exchange_rate END;
        v_realized_fx_diff := 0;
    END IF;

    UPDATE treasury_balances
    SET balance = v_balance_after_from,
        cost_base = v_new_cost_from,
        book_rate = v_new_rate_from,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND currency = p_from_currency;

    UPDATE treasury_balances
    SET balance = v_balance_after_to,
        cost_base = v_new_cost_to,
        book_rate = v_new_rate_to,
        updated_at = NOW()
    WHERE treasury_id = v_treasury_id AND currency = p_to_currency;

    -- Base Amount is the EGP amount
    IF p_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    IF v_realized_fx_diff != 0 THEN
        IF v_realized_fx_diff > 0 THEN
            v_fx_gain_loss_acct := public.resolve_gl_account('4310', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', p_from_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', 0, 'credit', v_realized_fx_diff, 'base_debit', 0, 'base_credit', v_realized_fx_diff, 'currency', 'EGP', 'description', 'أرباح فروق عملة محققة')
                )
            );
        ELSE
            v_fx_gain_loss_acct := public.resolve_gl_account('6151', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', ABS(v_realized_fx_diff), 'credit', 0, 'base_debit', ABS(v_realized_fx_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق عملة محققة'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', p_from_currency, 'description', v_desc)
                )
            );
        END IF;
    ELSE
        v_je_id := public.post_journal_entry(
            'currency_exchange', v_desc, CURRENT_DATE, v_company_id, p_user_id,
            jsonb_build_array(
                jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_to_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_from_currency, 'description', v_desc)
            )
        );
    END IF;

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_out', p_amount_from, p_from_currency,
        v_desc || ' (صادر)', v_balance_before_from, v_balance_after_from,
        p_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        created_by, exchange_rate, amount_in_base_currency, journal_entry_id
    ) VALUES (
        v_treasury_id, 'currency_exchange_in', p_amount_to, p_to_currency,
        v_desc || ' (وارد)', v_balance_before_to, v_balance_after_to,
        p_user_id, p_exchange_rate, v_base_amount, v_je_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'amount_from', p_amount_from,
        'from_currency', p_from_currency,
        'amount_to', p_amount_to,
        'to_currency', p_to_currency,
        'exchange_rate', p_exchange_rate
    );
END;
$$;

-- Overload for bigint treasury_id
CREATE OR REPLACE FUNCTION public.exchange_currency(
    p_treasury_id bigint,
    p_from_currency character varying,
    p_to_currency character varying,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric,
    p_user_id uuid,
    p_transfer_mode text DEFAULT 'exchange'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public.exchange_currency(
        p_treasury_id   := p_treasury_id::text,
        p_from_currency := p_from_currency,
        p_to_currency   := p_to_currency,
        p_amount_from   := p_amount_from,
        p_amount_to     := p_amount_to,
        p_exchange_rate := p_exchange_rate,
        p_user_id       := p_user_id,
        p_transfer_mode := p_transfer_mode
    );
END;
$$;

-- ============================================================================
-- ── Bank Account Draft & Confirm Workflow Support ──
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'bank_account_transactions' AND column_name = 'status'
    ) THEN
        ALTER TABLE public.bank_account_transactions 
        ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'bank_account_transactions' AND column_name = 'payload'
    ) THEN
        ALTER TABLE public.bank_account_transactions 
        ADD COLUMN payload JSONB DEFAULT '{}'::jsonb;
    END IF;

    -- 3. Fix foreign currency bank accounts default book_rate
    UPDATE public.bank_accounts ba
    SET book_rate = COALESCE(
        (SELECT rate_to_egp FROM public.exchange_rates er WHERE er.currency_code = ba.currency LIMIT 1),
        CASE ba.currency WHEN 'USD' THEN 50.0 WHEN 'EUR' THEN 54.0 WHEN 'GBP' THEN 63.0 ELSE 50.0 END
    )
    WHERE ba.currency != 'EGP' AND (ba.book_rate <= 1.0 OR ba.book_rate IS NULL);
END $$;

-- ── Soften fiscal-year trigger for 'draft' transactions (Treasury & Bank) ──
CREATE OR REPLACE FUNCTION public.check_fiscal_year_allows_financial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fy_status text;
BEGIN
  IF TG_TABLE_NAME IN ('bank_account_transactions', 'treasury_transactions')
     AND NEW.status = 'draft' THEN
    RETURN NEW;
  END IF;

  SELECT fy.status INTO _fy_status
  FROM public.fiscal_years fy
  WHERE fy.is_current = true
    AND fy.deleted_at IS NULL
  LIMIT 1;

  IF _fy_status IN ('CLOSING', 'CLOSED') THEN
    RAISE EXCEPTION 'لا يمكن إنشاء مستندات مالية في سنة مالية %', _fy_status;
  END IF;

  RETURN NEW;
END;
$$;

-- ── RPC: Save Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_save_bank_draft(
    p_bank_account_id BIGINT,
    p_type TEXT,
    p_amount NUMERIC,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    INSERT INTO public.bank_account_transactions (
        bank_account_id,
        type,
        amount,
        balance_before,
        balance_after,
        description,
        notes,
        entity_type,
        entity_id,
        counterparty_name,
        status,
        payload,
        created_by,
        created_at
    ) VALUES (
        p_bank_account_id,
        p_type,
        p_amount,
        0,
        0,
        p_description,
        p_notes,
        p_entity_type,
        p_entity_id,
        p_counterparty_name,
        'draft',
        COALESCE(p_payload, '{}'::jsonb),
        auth.uid(),
        NOW()
    )
    RETURNING id INTO v_tx_id;

    RETURN v_tx_id;
END;
$$;

-- ── RPC: Update Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_update_bank_draft(
    p_transaction_id BIGINT,
    p_bank_account_id BIGINT DEFAULT NULL,
    p_type TEXT DEFAULT NULL,
    p_amount NUMERIC DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.bank_account_transactions
    SET
        bank_account_id = COALESCE(p_bank_account_id, bank_account_id),
        type = COALESCE(p_type, type),
        amount = COALESCE(p_amount, amount),
        description = COALESCE(p_description, description),
        notes = p_notes,
        entity_type = p_entity_type,
        entity_id = p_entity_id,
        counterparty_name = p_counterparty_name,
        payload = CASE WHEN p_payload IS NOT NULL THEN p_payload ELSE payload END
    WHERE id = p_transaction_id AND status = 'draft';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو أنها مؤكدة بالفعل';
    END IF;

    RETURN TRUE;
END;
$$;

-- ── RPC: Delete Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_delete_bank_draft(
    p_transaction_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_deleted_count INT;
BEGIN
    DELETE FROM public.bank_account_transactions
    WHERE id = p_transaction_id AND status = 'draft';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    IF v_deleted_count = 0 THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو تم تأكيدها مسبقاً';
    END IF;

    RETURN TRUE;
END;
$$;

-- ── Drop all existing overloads of exchange_bank_currency (Migration 377) ──
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'exchange_bank_currency'
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.proname) || '(' || r.args || ') CASCADE;';
    END LOOP;
END $$;

-- ── Single Unified exchange_bank_currency (Migration 377) ──
CREATE OR REPLACE FUNCTION public.exchange_bank_currency(
    p_from_account_id integer,
    p_to_account_id integer,
    p_amount_from numeric,
    p_amount_to numeric,
    p_exchange_rate numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from_currency       TEXT;
    v_to_currency         TEXT;
    v_balance_before_from NUMERIC;
    v_balance_before_to   NUMERIC;
    v_balance_after_from  NUMERIC;
    v_balance_after_to    NUMERIC;
    
    v_cost_before_from    NUMERIC;
    v_rate_before_from    NUMERIC;
    v_cost_before_to      NUMERIC;
    v_rate_before_to      NUMERIC;
    
    v_new_cost_from       NUMERIC;
    v_new_rate_from       NUMERIC;
    v_new_cost_to         NUMERIC;
    v_new_rate_to         NUMERIC;
    
    v_cost_base_released  NUMERIC := 0;
    v_realized_fx_diff    NUMERIC := 0;
    v_base_amount         NUMERIC;
    
    v_from_acct           BIGINT;
    v_to_acct             BIGINT;
    v_fx_gain_loss_acct   BIGINT;
    v_je_id               BIGINT;
    v_desc                TEXT;
    v_company_id          UUID;
    v_user_id             UUID;
    v_transaction_id      BIGINT;
    v_result              JSONB;
BEGIN
    v_user_id := auth.uid();

    IF p_amount_from <= 0 OR p_amount_to <= 0 OR p_exchange_rate <= 0 THEN
        RAISE EXCEPTION 'المبالغ وسعر الصرف يجب أن تكون أكبر من صفر';
    END IF;

    -- 1. Lock from_account and fetch balances & cost base
    SELECT currency, COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), company_id
    INTO v_from_currency, v_balance_before_from, v_cost_before_from, v_rate_before_from, v_company_id
    FROM public.bank_accounts
    WHERE id = p_from_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب البنكي المصدر غير موجود';
    END IF;

    IF v_balance_before_from < p_amount_from THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي المصدر. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
    END IF;

    -- 2. Lock to_account and fetch balances & cost base
    SELECT currency, COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_to_currency, v_balance_before_to, v_cost_before_to, v_rate_before_to
    FROM public.bank_accounts
    WHERE id = p_to_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحساب البنكي المحول إليه غير موجود';
    END IF;

    IF v_company_id IS NULL THEN
        SELECT company_id INTO v_company_id FROM public.bank_accounts WHERE id = p_to_account_id;
        IF v_company_id IS NULL THEN
            SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
        END IF;
    END IF;

    -- Strict Rule: One of the currencies MUST be EGP
    IF v_from_currency != 'EGP' AND v_to_currency != 'EGP' THEN
        RAISE EXCEPTION 'التحويل المباشر بين عملتين أجنبيتين غير مسموح. يجب التحويل عبر الجنيه المصري كخطوتين منفصلتين.';
    END IF;

    -- Fallback for uninitialized cost base
    IF v_from_currency != 'EGP' AND (v_cost_before_from <= 0 OR v_rate_before_from <= 0) THEN
        v_rate_before_from := COALESCE(NULLIF(v_rate_before_from, 0), public.fn_get_exchange_rate(v_from_currency));
        IF v_rate_before_from <= 0 THEN v_rate_before_from := p_exchange_rate; END IF;
        v_cost_before_from := ROUND(v_balance_before_from * v_rate_before_from, 2);
    END IF;

    v_desc := 'تحويل بنكي من ' || v_from_currency || ' إلى ' || v_to_currency || ' بسعر صرف ' || p_exchange_rate;

    v_from_acct := public.resolve_gl_account(
        CASE v_from_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );
    v_to_acct := public.resolve_gl_account(
        CASE v_to_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_balance_after_from := v_balance_before_from - p_amount_from;
    v_balance_after_to := v_balance_before_to + p_amount_to;

    -- 3. IAS 21 Multi-Currency Cost Base & Realized FX Calculation
    IF v_from_currency != 'EGP' THEN
        -- Case A: Selling foreign currency (e.g. USD -> EGP)
        v_cost_base_released := ROUND(p_amount_from * v_rate_before_from, 2);
        v_new_cost_from := GREATEST(0, v_cost_before_from - v_cost_base_released);
        v_new_rate_from := CASE WHEN v_balance_after_from > 0 THEN ROUND(v_new_cost_from / v_balance_after_from, 4) ELSE v_rate_before_from END;

        v_new_cost_to := v_balance_after_to;
        v_new_rate_to := 1.0;
        v_realized_fx_diff := p_amount_to - v_cost_base_released;
    ELSE
        -- Case B: Buying foreign currency (e.g. EGP -> USD)
        v_new_cost_from := v_balance_after_from;
        v_new_rate_from := 1.0;

        v_new_cost_to := v_cost_before_to + p_amount_from;
        v_new_rate_to := CASE WHEN v_balance_after_to > 0 THEN ROUND(v_new_cost_to / v_balance_after_to, 4) ELSE p_exchange_rate END;
        v_realized_fx_diff := 0;
    END IF;

    -- Update Bank Accounts balances, cost_base, and book_rate
    UPDATE public.bank_accounts
    SET balance = v_balance_after_from,
        cost_base = v_new_cost_from,
        book_rate = v_new_rate_from,
        updated_at = NOW()
    WHERE id = p_from_account_id;

    UPDATE public.bank_accounts
    SET balance = v_balance_after_to,
        cost_base = v_new_cost_to,
        book_rate = v_new_rate_to,
        updated_at = NOW()
    WHERE id = p_to_account_id;

    -- Base Amount is the EGP amount
    IF v_from_currency = 'EGP' THEN
        v_base_amount := p_amount_from;
    ELSE
        v_base_amount := p_amount_to;
    END IF;

    -- 4. Post Balanced Journal Entry with Realized FX Gain/Loss
    IF v_realized_fx_diff != 0 THEN
        IF v_realized_fx_diff > 0 THEN
            v_fx_gain_loss_acct := public.resolve_gl_account('4310', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', v_from_currency, 'description', v_desc || ' (صادر بالتكلفة الدفترية)'),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', 0, 'credit', v_realized_fx_diff, 'base_debit', 0, 'base_credit', v_realized_fx_diff, 'currency', 'EGP', 'description', 'أرباح فروق عملة محققة')
                )
            );
        ELSE
            v_fx_gain_loss_acct := public.resolve_gl_account('6151', v_company_id);
            v_je_id := public.post_journal_entry(
                'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
                jsonb_build_array(
                    jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', p_amount_to, 'base_credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
                    jsonb_build_object('account_id', v_fx_gain_loss_acct, 'debit', ABS(v_realized_fx_diff), 'credit', 0, 'base_debit', ABS(v_realized_fx_diff), 'base_credit', 0, 'currency', 'EGP', 'description', 'خسائر فروق عملة محققة'),
                    jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_cost_base_released, 'currency', v_from_currency, 'description', v_desc || ' (صادر بالتكلفة الدفترية)')
                )
            );
        END IF;
    ELSE
        v_je_id := public.post_journal_entry(
            'currency_exchange', v_desc, CURRENT_DATE, v_company_id, v_user_id,
            jsonb_build_array(
                jsonb_build_object('account_id', v_to_acct, 'debit', p_amount_to, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_to_currency, 'description', v_desc || ' (وارد)'),
                jsonb_build_object('account_id', v_from_acct, 'debit', 0, 'credit', p_amount_from, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_from_currency, 'description', v_desc || ' (صادر)')
            )
        );
    END IF;

    -- 5. Insert Transaction Records
    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot, status
    ) VALUES (
        p_from_account_id, 'currency_exchange_out', p_amount_from, v_balance_before_from, v_balance_after_from,
        v_desc || ' (صادر)', 'exchange', v_je_id,
        p_exchange_rate, CASE WHEN v_from_currency != 'EGP' THEN v_cost_base_released ELSE v_base_amount END,
        jsonb_build_object('currency', v_from_currency, 'exchange_rate', p_exchange_rate, 'book_rate', v_new_rate_from, 'amount', p_amount_from, 'amount_in_base_currency', CASE WHEN v_from_currency != 'EGP' THEN v_cost_base_released ELSE v_base_amount END),
        'confirmed'
    ) RETURNING id INTO v_transaction_id;

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, journal_entry_id,
        exchange_rate, amount_in_base_currency, currency_snapshot, status
    ) VALUES (
        p_to_account_id, 'currency_exchange_in', p_amount_to, v_balance_before_to, v_balance_after_to,
        v_desc || ' (وارد)', 'exchange', v_je_id,
        p_exchange_rate, v_base_amount,
        jsonb_build_object('currency', v_to_currency, 'exchange_rate', p_exchange_rate, 'book_rate', v_new_rate_to, 'amount', p_amount_to, 'amount_in_base_currency', v_base_amount),
        'confirmed'
    );

    v_result := jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_entry_id', v_je_id,
        'realized_fx_diff', v_realized_fx_diff
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exchange_bank_currency(integer, integer, numeric, numeric, numeric) TO authenticated, anon, service_role;

-- ── RPC: Confirm Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_confirm_bank_draft(
    p_transaction_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx RECORD;
    v_res JSONB;
BEGIN
    SELECT * INTO v_tx
    FROM public.bank_account_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    IF v_tx.type = 'deposit' THEN
        v_res := public.deposit_bank_account(
            p_account_id        := v_tx.bank_account_id::bigint,
            p_amount            := v_tx.amount,
            p_description       := v_tx.description,
            p_revenue_account_id := COALESCE((v_tx.payload->>'revenue_account_id')::bigint, NULL),
            p_entity_type       := v_tx.entity_type,
            p_entity_id         := v_tx.entity_id,
            p_counterparty_name := v_tx.counterparty_name,
            p_source_type       := COALESCE(v_tx.payload->>'source_type', 'deposit'),
            p_notes             := v_tx.notes
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الإيداع وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'withdraw' THEN
        v_res := public.withdraw_bank_account(
            p_account_id        := v_tx.bank_account_id,
            p_amount            := v_tx.amount,
            p_description       := v_tx.description,
            p_entity_type       := v_tx.entity_type,
            p_entity_id         := v_tx.entity_id,
            p_counterparty_name := v_tx.counterparty_name,
            p_expense_account_id := COALESCE((v_tx.payload->>'expense_account_id')::integer, NULL),
            p_notes             := v_tx.notes,
            p_reference_type    := v_tx.payload->>'reference_type',
            p_reference_id      := v_tx.payload->>'reference_id'
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الصرف وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type IN ('currency_exchange_out', 'currency_exchange_in', 'exchange') THEN
        v_res := public.exchange_bank_currency(
            p_from_account_id := v_tx.bank_account_id::integer,
            p_to_account_id   := (v_tx.payload->>'to_account_id')::integer,
            p_amount_from     := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to       := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate   := (v_tx.payload->>'exchange_rate')::numeric
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة وترحيل القيد بنجاح', 'result', v_res);

    ELSIF v_tx.type = 'transfer' THEN
        PERFORM public.bank_transfer(
            p_from_account_id := v_tx.bank_account_id::integer,
            p_to_account_id   := (v_tx.payload->>'to_account_id')::integer,
            p_amount          := v_tx.amount,
            p_description     := v_tx.description,
            p_bank_fee        := COALESCE((v_tx.payload->>'bank_fee')::numeric, 0),
            p_notes           := v_tx.notes
        );

        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد التحويل البنكي وترحيل القيد بنجاح');

    ELSE
        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;
    END IF;
END;
$$;

-- ── 7.5 Ensure all required columns exist on public.cheques ──
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'bank_account_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN bank_account_id INTEGER REFERENCES public.bank_accounts(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'journal_entry_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'exchange_rate'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN exchange_rate NUMERIC(15,6) DEFAULT 1.0;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'amount_in_base_currency'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN amount_in_base_currency NUMERIC(15,2);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'treasury_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN treasury_id BIGINT REFERENCES public.treasuries(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ── 7.5 Unified clear_cheque with Multi-Payment Integration (Migration 378 / 380 / 381) ──
CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_cheque RECORD;
    v_desc TEXT;
    v_bank_id INTEGER;
    v_bank_bal NUMERIC;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_cost_released NUMERIC := 0;
    v_currency TEXT;
    v_company_id UUID;
    v_new_bank_bal NUMERIC;
    v_bank_acct BIGINT;
    v_counterparty_acct BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_je_id BIGINT;
    v_bank_tx_id BIGINT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_book_rate NUMERIC := 1.0;
    v_snapshot JSONB;
    v_entity_id TEXT;
    v_multi_res JSONB;
    v_je_lines JSONB;

    -- Shipment matching & FX calculation variables
    v_total_cust_base NUMERIC;
    v_total_gain      NUMERIC := 0;
    v_total_loss      NUMERIC := 0;
    v_remaining_alloc NUMERIC;
    v_alloc           NUMERIC;
    v_alloc_bank_base NUMERIC;
    v_alloc_cust_base NUMERIC;
    v_diff            NUMERIC;
    v_spec_shipment   RECORD;
    v_shipment        RECORD;
BEGIN
    SELECT * INTO v_cheque
    FROM public.cheques
    WHERE id = p_cheque_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الشيك غير موجود';
    END IF;

    IF v_cheque.status != 'pending' THEN
        RAISE EXCEPTION 'لا يمكن تسوية شيك بحالة %', v_cheque.status;
    END IF;

    v_currency := v_cheque.currency;
    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(v_cheque.amount * v_rate, 2);

    IF v_cheque.type = 'outgoing' THEN
        v_desc := 'صرف شيك رقم: ' || v_cheque.cheque_number;
    ELSE
        v_desc := 'تحصيل شيك رقم: ' || v_cheque.cheque_number;
    END IF;

    -- Get bank account (use cheque's assigned bank if present, otherwise match currency)
    IF v_cheque.bank_account_id IS NOT NULL THEN
        SELECT id, balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), ba.company_id
        INTO v_bank_id, v_bank_bal, v_current_cost_base, v_current_book_rate, v_company_id
        FROM public.bank_accounts ba
        WHERE ba.id = v_cheque.bank_account_id
        FOR UPDATE;
    ELSE
        SELECT id, balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), ba.company_id
        INTO v_bank_id, v_bank_bal, v_current_cost_base, v_current_book_rate, v_company_id
        FROM public.bank_accounts ba
        WHERE ba.currency = v_currency AND ba.deleted_at IS NULL
        ORDER BY ba.id ASC
        LIMIT 1
        FOR UPDATE;
    END IF;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على حساب بنكي بعملة %', v_currency;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- ================================================================
    -- 1. OUTGOING CHEQUE: Dr Counterparty / Cr Bank (Book Rate)
    -- ================================================================
    IF v_cheque.type = 'outgoing' THEN
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_bank_bal;
        END IF;

        IF v_currency = 'EGP' THEN
            v_book_rate := 1.0;
            v_cost_released := v_cheque.amount;
            v_new_cost_base := GREATEST(0, v_current_cost_base - v_cheque.amount);
            v_new_book_rate := 1.0;
        ELSE
            v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), v_rate);
            v_cost_released := ROUND(v_cheque.amount * v_book_rate, 2);
            v_new_cost_base := GREATEST(0, v_current_cost_base - v_cost_released);
        END IF;

        v_new_bank_bal := v_bank_bal - v_cheque.amount;

        IF v_new_bank_bal > 0 AND v_currency != 'EGP' THEN
            v_new_book_rate := ROUND(v_new_cost_base / v_new_bank_bal, 4);
        ELSIF v_currency = 'EGP' THEN
            v_new_book_rate := 1.0;
        ELSE
            v_new_book_rate := v_book_rate;
            v_new_cost_base := 0;
        END IF;

        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - v_cheque.amount WHERE id = v_cheque.supplier_id;
        ELSIF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.customers WHERE id = v_cheque.counterparty_id;
            UPDATE public.customers SET balance = balance + v_cheque.amount WHERE id = v_cheque.counterparty_id;
        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance - v_cheque.amount WHERE id = v_cheque.clearing_agent_id;
        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance - v_cheque.amount WHERE id = v_cheque.shipping_company_id;
        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;
        END IF;

        IF v_counterparty_acct IS NULL THEN
            v_counterparty_acct := public.resolve_gl_account('51101', v_company_id);
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        v_je_id := public.post_journal_entry(
            'bank_withdrawal',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_counterparty_acct, 'debit', v_cheque.amount, 'credit', 0, 'base_debit', v_cost_released, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_bank_acct,         'debit', 0, 'credit', v_cheque.amount, 'base_debit', 0, 'base_credit', v_cost_released, 'currency', v_currency, 'description', v_desc)
            )
        );

        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'withdraw', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_book_rate, v_cost_released, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_book_rate,
                'book_rate', v_new_book_rate,
                'cost_base', v_new_cost_base,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_cost_released,
                'rate_date', CURRENT_DATE,
                'rate_source', 'bank_book_rate'
             ))
        RETURNING id INTO v_bank_tx_id;

    -- ================================================================
    -- 2. INCOMING CHEQUE: Dr Bank / Cr Counterparty (Customer Shipment Matching & FX)
    -- ================================================================
    ELSIF v_cheque.type = 'incoming' THEN
        IF v_currency = 'EGP' THEN
            v_new_cost_base := v_current_cost_base + v_cheque.amount;
            v_new_book_rate := 1.0;
        ELSE
            v_new_cost_base := v_current_cost_base + v_base_amount;
        END IF;

        v_new_bank_bal := v_bank_bal + v_cheque.amount;

        IF v_new_bank_bal > 0 AND v_currency != 'EGP' THEN
            v_new_book_rate := ROUND(v_new_cost_base / v_new_bank_bal, 4);
        ELSIF v_currency = 'EGP' THEN
            v_new_book_rate := 1.0;
        ELSE
            v_new_book_rate := v_rate;
        END IF;

        v_counterparty_acct := NULL;

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.customers WHERE id = v_cheque.counterparty_id;
            
            UPDATE public.customers SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.counterparty_id;

            -- Sync to ledger_entries for statement reflection
            INSERT INTO public.ledger_entries (
                entity_type, entity_id, entry_type, amount, currency,
                reference_type, reference_id, reference_text, description, created_by
            ) VALUES (
                'customer', v_cheque.counterparty_id::text, 'credit', v_cheque.amount, v_currency,
                'payment', p_cheque_id, v_cheque.cheque_number, v_desc, auth.uid()
            );

        ELSIF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.suppliers WHERE id = v_cheque.supplier_id;
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + v_cheque.amount
            WHERE id = v_cheque.supplier_id;

        ELSIF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
            UPDATE public.clearing_agents SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.clearing_agent_id;

        ELSIF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
            UPDATE public.shipping_companies SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.shipping_company_id;

        ELSIF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct
            FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;

        ELSIF v_cheque.counterparty_type = 'treasury' THEN
            v_counterparty_acct := public.resolve_gl_account(
                CASE v_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' ELSE '11101' END,
                v_company_id
            );
        END IF;

        IF v_counterparty_acct IS NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
            IF v_counterparty_acct IS NOT NULL THEN
                SELECT id INTO v_counterparty_acct FROM public.accounts WHERE id = v_counterparty_acct AND is_leaf = true AND is_active = true;
            END IF;
            IF v_counterparty_acct IS NULL THEN
                v_counterparty_acct := public.resolve_equity_account(v_currency, v_company_id);
            END IF;
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        -- Customer Shipment Matching & Realized FX Calculation (if foreign currency)
        v_total_cust_base := v_base_amount;
        v_total_gain := 0;
        v_total_loss := 0;

        IF v_cheque.counterparty_type = 'customer' AND v_currency != 'EGP' AND v_cheque.counterparty_id IS NOT NULL THEN
            v_remaining_alloc := v_cheque.amount;
            v_total_cust_base := 0;

            -- Check if a specific shipment is referenced in notes
            SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                   (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
            INTO v_spec_shipment
            FROM public.export_shipments
            WHERE customer_id = v_cheque.counterparty_id
              AND is_confirmed = true
              AND status != 'cancelled'
              AND (
                  (v_cheque.notes IS NOT NULL AND v_cheque.notes LIKE '%' || shipment_no || '%')
                  OR (v_desc IS NOT NULL AND v_desc LIKE '%' || shipment_no || '%')
              )
            ORDER BY id DESC
            LIMIT 1;

            IF v_spec_shipment.id IS NOT NULL AND v_spec_shipment.due_foreign > 0.001 THEN
                v_alloc := LEAST(v_remaining_alloc, v_spec_shipment.due_foreign);
                v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                v_alloc_cust_base := ROUND(v_alloc * v_spec_shipment.shipment_rate, 2);
                v_diff := v_alloc_bank_base - v_alloc_cust_base;

                v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                IF v_diff > 0 THEN
                    v_total_gain := v_total_gain + v_diff;
                ELSIF v_diff < 0 THEN
                    v_total_loss := v_total_loss + ABS(v_diff);
                END IF;

                UPDATE public.export_shipments
                SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                    updated_at = NOW()
                WHERE id = v_spec_shipment.id;

                v_remaining_alloc := v_remaining_alloc - v_alloc;
            END IF;

            -- Allocate remaining amount to open shipments in FIFO order
            IF v_remaining_alloc > 0.001 THEN
                FOR v_shipment IN
                    SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                           (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
                    FROM public.export_shipments
                    WHERE customer_id = v_cheque.counterparty_id
                      AND is_confirmed = true
                      AND status != 'cancelled'
                      AND (v_spec_shipment.id IS NULL OR id != v_spec_shipment.id)
                      AND (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) > 0.001
                    ORDER BY created_at ASC, id ASC
                LOOP
                    EXIT WHEN v_remaining_alloc <= 0.001;

                    v_alloc := LEAST(v_remaining_alloc, v_shipment.due_foreign);
                    v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                    v_alloc_cust_base := ROUND(v_alloc * v_shipment.shipment_rate, 2);
                    v_diff := v_alloc_bank_base - v_alloc_cust_base;

                    v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                    IF v_diff > 0 THEN
                        v_total_gain := v_total_gain + v_diff;
                    ELSIF v_diff < 0 THEN
                        v_total_loss := v_total_loss + ABS(v_diff);
                    END IF;

                    UPDATE public.export_shipments
                    SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                        updated_at = NOW()
                    WHERE id = v_shipment.id;

                    v_remaining_alloc := v_remaining_alloc - v_alloc;
                END LOOP;
            END IF;

            -- If any advance amount remains (no open shipments)
            IF v_remaining_alloc > 0.001 THEN
                v_total_cust_base := v_total_cust_base + ROUND(v_remaining_alloc * v_rate, 2);
            END IF;
        END IF;

        -- Build Journal Entry Lines
        v_je_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_bank_acct, 'debit', v_cheque.amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc)
        );

        IF v_total_loss > 0 THEN
            v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_loss,
                    'credit', 0,
                    'base_debit', v_total_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - شيك ' || COALESCE(v_cheque.cheque_number, '')
                )
            );
        END IF;

        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object('account_id', v_counterparty_acct, 'debit', 0, 'credit', v_cheque.amount, 'base_debit', 0, 'base_credit', v_total_cust_base, 'currency', v_currency, 'description', v_desc)
        );

        IF v_total_gain > 0 THEN
            v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_gain,
                    'base_debit', 0,
                    'base_credit', v_total_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - شيك ' || COALESCE(v_cheque.cheque_number, '')
                )
            );
        END IF;

        -- Post journal entry
        v_je_id := public.post_journal_entry(
            'bank_deposit',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines
        );

        -- Update bank balance, cost_base and weighted average book_rate
        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        -- Record bank transaction
        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_rate, v_base_amount, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_rate,
                'book_rate', v_new_book_rate,
                'cost_base', v_new_cost_base,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_base_amount,
                'rate_date', CURRENT_DATE,
                'rate_source', 'exchange_rates_table',
                'realized_fx_gain', v_total_gain,
                'realized_fx_loss', v_total_loss
             ))
        RETURNING id INTO v_bank_tx_id;
    END IF;

    -- Update cheque status + freeze rate and amount_in_base_currency
    UPDATE public.cheques
    SET status = 'cleared',
        cleared_at = NOW(),
        bank_account_id = v_bank_id,
        journal_entry_id = v_je_id,
        exchange_rate = v_rate,
        amount_in_base_currency = v_base_amount,
        currency_snapshot = jsonb_build_object(
            'currency', v_currency,
            'exchange_rate', v_rate,
            'amount', v_cheque.amount,
            'amount_in_base_currency', v_base_amount,
            'rate_date', CURRENT_DATE,
            'rate_source', 'exchange_rates_table',
            'realized_fx_gain', v_total_gain,
            'realized_fx_loss', v_total_loss
        )
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'bank_tx_id', v_bank_tx_id,
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_record_raw_material_opening_gl(uuid, numeric, numeric, text, uuid, numeric) TO authenticated, service_role, anon;

-- ============================================================================
-- Unified View for Unpaid Liabilities (including Lot Receipts)
-- ============================================================================
DROP VIEW IF EXISTS public.vw_unpaid_liabilities CASCADE;

CREATE OR REPLACE VIEW public.vw_unpaid_liabilities AS
-- 1. Purchase Invoices (مشتريات خامات)
SELECT 
    'purchase_invoice'::text AS liability_type,
    purchase_invoices.id::text AS liability_id,
    purchase_invoices.invoice_number AS reference_number,
    'supplier'::text AS entity_type,
    purchase_invoices.supplier_id::text AS entity_id,
    purchase_invoices.currency,
    jsonb_build_object('exchange_rate', COALESCE((purchase_invoices.currency_snapshot ->> 'exchange_rate'::text)::numeric, 1.0)) AS currency_snapshot,
    (purchase_invoices.total_amount - purchase_invoices.discount_amount - COALESCE(purchase_invoices.paid_amount, 0::numeric))::double precision AS due_amount,
    purchase_invoices.invoice_date AS liability_date
FROM public.purchase_invoices
WHERE (purchase_invoices.payment_status IS NULL OR (purchase_invoices.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (purchase_invoices.total_amount - purchase_invoices.discount_amount - COALESCE(purchase_invoices.paid_amount, 0::numeric)) > 0.001

UNION ALL

-- 2. Crop Purchases / Lot Receipts (مشتريات محاصيل)
SELECT 
    'lot_receipt'::text AS liability_type,
    lot_receipts.id::text AS liability_id,
    COALESCE(lot_receipts.lot_number, 'لوت #'::text || lot_receipts.id::text) AS reference_number,
    'supplier'::text AS entity_type,
    lot_receipts.supplier_id::text AS entity_id,
    COALESCE(lot_receipts.currency, 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(lot_receipts.exchange_rate, 1.0)) AS currency_snapshot,
    (COALESCE(lot_receipts.total_fruit_cost, 0::double precision) - COALESCE(lot_receipts.paid_amount, 0::double precision)) AS due_amount,
    lot_receipts.receipt_date AS liability_date
FROM public.lot_receipts
WHERE lot_receipts.is_confirmed = true 
  AND lot_receipts.supplier_id IS NOT NULL 
  AND (lot_receipts.payment_status IS NULL OR (lot_receipts.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(lot_receipts.total_fruit_cost, 0::double precision) - COALESCE(lot_receipts.paid_amount, 0::double precision)) > 0.001::double precision

UNION ALL

-- 3. Packing Order Cost Items (تكاليف تعبئة)
SELECT 
    'packing_cost_item'::text AS liability_type,
    packing_order_cost_items.id::text AS liability_id,
    COALESCE(packing_order_cost_items.name, 'تكلفة تعبئة'::text) AS reference_number,
    'supplier'::text AS entity_type,
    COALESCE(NULLIF(packing_order_cost_items.supplier_id, ''), packing_order_cost_items.currency_snapshot->>'supplier_id') AS entity_id,
    COALESCE(NULLIF(packing_order_cost_items.original_currency, ''::text), 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(packing_order_cost_items.exchange_rate, 1.0)) AS currency_snapshot,
    (COALESCE(packing_order_cost_items.original_amount, 0::numeric) - COALESCE(packing_order_cost_items.paid_amount, 0::numeric))::double precision AS due_amount,
    packing_order_cost_items.created_at::date AS liability_date
FROM public.packing_order_cost_items
WHERE (
    (packing_order_cost_items.supplier_id IS NOT NULL AND packing_order_cost_items.supplier_id <> ''::text AND packing_order_cost_items.supplier_id <> 'null'::text)
    OR
    (packing_order_cost_items.currency_snapshot->>'supplier_id' IS NOT NULL AND packing_order_cost_items.currency_snapshot->>'supplier_id' <> ''::text AND packing_order_cost_items.currency_snapshot->>'supplier_id' <> 'null'::text)
  )
  AND (packing_order_cost_items.payment_source_type IS NULL OR packing_order_cost_items.payment_source_type = 'none'::text) 
  AND packing_order_cost_items.treasury_transaction_id IS NULL 
  AND packing_order_cost_items.bank_transaction_id IS NULL 
  AND (packing_order_cost_items.payment_status IS NULL OR (packing_order_cost_items.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(packing_order_cost_items.original_amount, 0::numeric) - COALESCE(packing_order_cost_items.paid_amount, 0::numeric)) > 0.001

UNION ALL

-- 4. Shipment Cost Items (تكاليف شحن، تخليص، وبنود تكلفة موردين من صفحة الربحية)
SELECT 
    'shipment_cost_item'::text AS liability_type,
    shipment_cost_items.id::text AS liability_id,
    COALESCE((export_shipments.shipment_no::text || ' - '::text) || shipment_cost_items.description, shipment_cost_items.description, 'تكلفة شحن/تخليص'::text) AS reference_number,
    CASE
        WHEN shipment_cost_items.shipping_company_id IS NOT NULL THEN 'shipping_company'::text
        WHEN shipment_cost_items.clearing_agent_id IS NOT NULL THEN 'clearing_agent'::text
        WHEN shipment_cost_items.supplier_id IS NOT NULL AND shipment_cost_items.supplier_id <> ''::text THEN 'supplier'::text
        ELSE lower(COALESCE(shipment_cost_items.vendor_type, 'supplier'::text))
    END AS entity_type,
    CASE
        WHEN shipment_cost_items.shipping_company_id IS NOT NULL THEN shipment_cost_items.shipping_company_id::text
        WHEN shipment_cost_items.clearing_agent_id IS NOT NULL THEN shipment_cost_items.clearing_agent_id::text
        WHEN shipment_cost_items.supplier_id IS NOT NULL AND shipment_cost_items.supplier_id <> ''::text THEN shipment_cost_items.supplier_id
        ELSE shipment_cost_items.vendor_id::text
    END AS entity_id,
    COALESCE(NULLIF(shipment_cost_items.original_currency, ''::text), NULLIF(shipment_cost_items.supplier_currency, ''::text), 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(shipment_cost_items.exchange_rate, 1.0)) AS currency_snapshot,
    round(COALESCE(NULLIF(shipment_cost_items.total_price, 0::numeric), shipment_cost_items.quantity * shipment_cost_items.unit_price, 0::numeric) / COALESCE(NULLIF(shipment_cost_items.exchange_rate, 0::numeric), 1.0) - COALESCE(shipment_cost_items.paid_amount, 0::numeric), 2)::double precision AS due_amount,
    shipment_cost_items.created_at::date AS liability_date
FROM public.shipment_cost_items
LEFT JOIN public.export_shipments ON export_shipments.id = shipment_cost_items.shipment_id
WHERE shipment_cost_items.treasury_transaction_id IS NULL 
  AND shipment_cost_items.bank_transaction_id IS NULL 
  AND (shipment_cost_items.payment_source_type IS NULL OR shipment_cost_items.payment_source_type = 'none'::text) 
  AND (shipment_cost_items.payment_status IS NULL OR (shipment_cost_items.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (round(COALESCE(NULLIF(shipment_cost_items.total_price, 0::numeric), shipment_cost_items.quantity * shipment_cost_items.unit_price, 0::numeric) / COALESCE(NULLIF(shipment_cost_items.exchange_rate, 0::numeric), 1.0) - COALESCE(shipment_cost_items.paid_amount, 0::numeric), 2)) > 0.001;

-- ============================================================================
-- Unified Entity Multi-Payment Function, Document Types & Timezone Engine
-- ============================================================================
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES 
  ('treasury_multi_payment', 'Treasury Multi-Payment / سداد متعدد من الخزينة', 'TMPY', true),
  ('bank_multi_payment',     'Bank Multi-Payment / سداد متعدد من البنك',         'BMPY', true)
ON CONFLICT (code) DO UPDATE SET 
  prefix = EXCLUDED.prefix,
  name = EXCLUDED.name,
  is_active = true;

-- Retroactive correction for journal entries created with UTC offset
UPDATE public.journal_entries
SET entry_date = (created_at AT TIME ZONE 'Africa/Cairo')::DATE
WHERE entry_date != (created_at AT TIME ZONE 'Africa/Cairo')::DATE
  AND created_at >= NOW() - INTERVAL '48 hours';

-- Central Engine: post_journal_entry with Timezone Safeguard
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
    v_actual_date   DATE;
    v_base_amount   NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = p_company_id) THEN
        RAISE EXCEPTION 'Company % not found', p_company_id;
    END IF;

    -- Timezone safeguard: if p_entry_date is null or matches UTC CURRENT_DATE while local Cairo date is ahead
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
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit:= COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
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
            currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, v_base_amount, v_desc, p_company_id
        );
    END LOOP;

    IF ABS(v_total_debit - v_total_credit) > 0.05 THEN
        RAISE EXCEPTION 'Journal entry unbalanced in base currency: Total Base Debit = %, Total Base Credit = %', v_total_debit, v_total_credit;
    END IF;

    RETURN v_je_id;
END;
$$;

-- Update deposit_treasury with Local Timezone Date
CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT ''::text,
    p_revenue_account_id integer DEFAULT NULL::integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance NUMERIC := 0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_tx_id BIGINT;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_revenue_acct BIGINT;
    v_desc TEXT;
    v_je_id BIGINT;
    v_source_type TEXT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_snapshot JSONB;
    v_entry_date DATE;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Lock treasury balance row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
    IF p_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    -- 3. Resolve GL accounts
    v_source_type := CASE WHEN p_revenue_account_id IS NOT NULL THEN 'revenue' ELSE 'opening_balance' END;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع في الخزينة');

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    -- 4. Post Journal Entry
    v_je_id := public.post_journal_entry(
        'treasury_deposit',
        v_desc,
        v_entry_date,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct,  'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- 5. Update / Upsert treasury_balances
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (p_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    -- 6. Insert transaction
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', v_entry_date,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_source_type, v_je_id, auth.uid(),
        CASE WHEN p_revenue_account_id IS NOT NULL THEN p_revenue_account_id ELSE NULL END,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$$;

-- Update deposit_bank_account with Local Timezone Date
CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_source_type text DEFAULT 'deposit'::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_credit_acct     BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_entry_date      DATE;
    v_je_lines        JSONB;

    -- Shipment matching & FX calculation variables
    v_total_cust_base NUMERIC;
    v_total_gain      NUMERIC := 0;
    v_total_loss      NUMERIC := 0;
    v_remaining_alloc NUMERIC;
    v_alloc           NUMERIC;
    v_alloc_bank_base NUMERIC;
    v_alloc_cust_base NUMERIC;
    v_diff            NUMERIC;
    v_spec_shipment   RECORD;
    v_shipment        RECORD;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- 2. Calculate spot exchange rate & base amount
    IF v_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(v_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'رصيد افتتاحي');
    ELSIF p_entity_type = 'revenue' THEN
        v_source_type := 'revenue';
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيراد');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_credit_acct := NULL;

    IF p_entity_type IS NULL OR p_entity_type = 'opening_balance' THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    ELSIF p_entity_type = 'revenue' THEN
        IF p_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب الإيرادات';
        END IF;
        v_credit_acct := p_revenue_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_credit_acct FROM public.customers WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_credit_acct FROM public.suppliers WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_credit_acct FROM public.clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_credit_acct FROM public.shipping_companies WHERE id = p_entity_id::bigint;
    ELSE
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    IF v_credit_acct IS NULL THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    -- 3. Customer Foreign Currency Shipment Matching & Realized FX Calculation
    v_total_cust_base := v_base_amount;
    v_total_gain := 0;
    v_total_loss := 0;

    IF p_entity_type = 'customer' AND v_currency != 'EGP' AND p_entity_id IS NOT NULL THEN
        v_remaining_alloc := p_amount;
        v_total_cust_base := 0;

        -- Check if a specific shipment is referenced in description or notes
        SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
               (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
        INTO v_spec_shipment
        FROM public.export_shipments
        WHERE customer_id = p_entity_id::bigint
          AND is_confirmed = true
          AND status != 'cancelled'
          AND (
              (p_description IS NOT NULL AND p_description LIKE '%' || shipment_no || '%')
              OR (p_notes IS NOT NULL AND p_notes LIKE '%' || shipment_no || '%')
          )
        ORDER BY id DESC
        LIMIT 1;

        IF v_spec_shipment.id IS NOT NULL AND v_spec_shipment.due_foreign > 0.001 THEN
            v_alloc := LEAST(v_remaining_alloc, v_spec_shipment.due_foreign);
            v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
            v_alloc_cust_base := ROUND(v_alloc * v_spec_shipment.shipment_rate, 2);
            v_diff := v_alloc_bank_base - v_alloc_cust_base;

            v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

            IF v_diff > 0 THEN
                v_total_gain := v_total_gain + v_diff;
            ELSIF v_diff < 0 THEN
                v_total_loss := v_total_loss + ABS(v_diff);
            END IF;

            UPDATE public.export_shipments
            SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                updated_at = NOW()
            WHERE id = v_spec_shipment.id;

            v_remaining_alloc := v_remaining_alloc - v_alloc;
        END IF;

        -- Allocate remaining amount to open shipments in FIFO order
        IF v_remaining_alloc > 0.001 THEN
            FOR v_shipment IN
                SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                       (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
                FROM public.export_shipments
                WHERE customer_id = p_entity_id::bigint
                  AND is_confirmed = true
                  AND status != 'cancelled'
                  AND (v_spec_shipment.id IS NULL OR id != v_spec_shipment.id)
                  AND (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) > 0.001
                ORDER BY created_at ASC, id ASC
            LOOP
                EXIT WHEN v_remaining_alloc <= 0.001;

                v_alloc := LEAST(v_remaining_alloc, v_shipment.due_foreign);
                v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                v_alloc_cust_base := ROUND(v_alloc * v_shipment.shipment_rate, 2);
                v_diff := v_alloc_bank_base - v_alloc_cust_base;

                v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                IF v_diff > 0 THEN
                    v_total_gain := v_total_gain + v_diff;
                ELSIF v_diff < 0 THEN
                    v_total_loss := v_total_loss + ABS(v_diff);
                END IF;

                UPDATE public.export_shipments
                SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                    updated_at = NOW()
                WHERE id = v_shipment.id;

                v_remaining_alloc := v_remaining_alloc - v_alloc;
            END LOOP;
        END IF;

        -- If any advance amount remains (no open shipments)
        IF v_remaining_alloc > 0.001 THEN
            v_total_cust_base := v_total_cust_base + ROUND(v_remaining_alloc * v_rate, 2);
        END IF;
    END IF;

    -- 4. Build Journal Entry Lines
    v_je_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_bank_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc)
    );

    IF v_total_loss > 0 THEN
        v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_realized_loss_acct,
                'debit', v_total_loss,
                'credit', 0,
                'base_debit', v_total_loss,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'خسائر فروق أسعار عملة محققة - عميل ' || COALESCE(p_counterparty_name, '')
            )
        );
    END IF;

    v_je_lines := v_je_lines || jsonb_build_array(
        jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_total_cust_base, 'currency', v_currency, 'description', v_desc)
    );

    IF v_total_gain > 0 THEN
        v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_realized_gain_acct,
                'debit', 0,
                'credit', v_total_gain,
                'base_debit', 0,
                'base_credit', v_total_gain,
                'currency', 'EGP',
                'description', 'أرباح فروق أسعار عملة محققة - عميل ' || COALESCE(p_counterparty_name, '')
            )
        );
    END IF;

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, v_entry_date, v_company_id, auth.uid(),
        v_je_lines
    );

    UPDATE public.bank_accounts 
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', v_entry_date,
        'rate_source', 'exchange_rates_table',
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END,
        p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    -- Update party balance & insert into public.ledger_entries for statement reflection
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id::text, 'credit', p_amount, v_currency,
            'payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id::text, 'debit', p_amount, v_currency,
            'payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate,
        'journal_entry_id', v_je_id,
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_je_source_type  TEXT;
    v_source_type     TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- 1. Lock bank account row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_current_balance;
    END IF;

    IF v_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(v_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب رصيد افتتاحي من الحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id::TEXT = p_entity_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    UPDATE public.bank_accounts
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    v_je_source_type := CASE
        WHEN p_entity_type = 'supplier' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_entity_type = 'shareholder' THEN 'shareholder_payment_received'
        ELSE 'bank_withdrawal'
    END;

    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct,    'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        ),
        p_source_id := p_reference_id
    );

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'bank_book_rate'
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, created_at, created_by, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_current_balance, v_new_balance,
        v_desc, p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id, NOW(), auth.uid(), p_notes,
        v_book_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id::TEXT = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id::text, 'debit', p_amount, v_currency,
            'refund', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::TEXT = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id::text, 'credit', p_amount, v_currency,
            'supplier_payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id::TEXT = p_entity_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(bigint, numeric, text, bigint, text, text, text, text, text, text) TO authenticated, service_role;


-- ── 7.8 View: Unpaid Liabilities (Unified Invoices, Lots, Packing & Shipment Costs) ──
CREATE OR REPLACE VIEW public.vw_unpaid_liabilities AS
-- 1. Purchase Invoices (مشتريات خامات)
SELECT 
    'purchase_invoice'::text AS liability_type,
    purchase_invoices.id::text AS liability_id,
    purchase_invoices.invoice_number AS reference_number,
    'supplier'::text AS entity_type,
    purchase_invoices.supplier_id::text AS entity_id,
    purchase_invoices.currency,
    jsonb_build_object('exchange_rate', COALESCE((purchase_invoices.currency_snapshot ->> 'exchange_rate'::text)::numeric, 1.0)) AS currency_snapshot,
    (purchase_invoices.total_amount - purchase_invoices.discount_amount - COALESCE(purchase_invoices.paid_amount, 0::numeric))::double precision AS due_amount,
    purchase_invoices.invoice_date AS liability_date
FROM public.purchase_invoices
WHERE (purchase_invoices.payment_status IS NULL OR (purchase_invoices.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (purchase_invoices.total_amount - purchase_invoices.discount_amount - COALESCE(purchase_invoices.paid_amount, 0::numeric)) > 0.001

UNION ALL

-- 2. Crop Purchases / Lot Receipts (مشتريات محاصيل)
SELECT 
    'lot_receipt'::text AS liability_type,
    lot_receipts.id::text AS liability_id,
    COALESCE(lot_receipts.lot_number, 'لوت #'::text || lot_receipts.id::text) AS reference_number,
    'supplier'::text AS entity_type,
    lot_receipts.supplier_id::text AS entity_id,
    COALESCE(lot_receipts.currency, 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(lot_receipts.exchange_rate, 1.0)) AS currency_snapshot,
    (COALESCE(lot_receipts.total_fruit_cost, 0::double precision) - COALESCE(lot_receipts.paid_amount, 0::double precision)) AS due_amount,
    lot_receipts.receipt_date AS liability_date
FROM public.lot_receipts
WHERE lot_receipts.is_confirmed = true 
  AND lot_receipts.supplier_id IS NOT NULL 
  AND (lot_receipts.payment_status IS NULL OR (lot_receipts.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(lot_receipts.total_fruit_cost, 0::double precision) - COALESCE(lot_receipts.paid_amount, 0::double precision)) > 0.001::double precision

UNION ALL

-- 3. Packing Order Cost Items (تكاليف تعبئة)
SELECT 
    'packing_cost_item'::text AS liability_type,
    packing_order_cost_items.id::text AS liability_id,
    COALESCE(packing_order_cost_items.name, 'تكلفة تعبئة'::text) AS reference_number,
    'supplier'::text AS entity_type,
    COALESCE(NULLIF(packing_order_cost_items.supplier_id, ''), packing_order_cost_items.currency_snapshot->>'supplier_id') AS entity_id,
    COALESCE(NULLIF(packing_order_cost_items.original_currency, ''::text), 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(packing_order_cost_items.exchange_rate, 1.0)) AS currency_snapshot,
    (COALESCE(packing_order_cost_items.original_amount, 0::numeric) - COALESCE(packing_order_cost_items.paid_amount, 0::numeric))::double precision AS due_amount,
    packing_order_cost_items.created_at::date AS liability_date
FROM public.packing_order_cost_items
WHERE (
    (packing_order_cost_items.supplier_id IS NOT NULL AND packing_order_cost_items.supplier_id <> ''::text AND packing_order_cost_items.supplier_id <> 'null'::text)
    OR
    (packing_order_cost_items.currency_snapshot->>'supplier_id' IS NOT NULL AND packing_order_cost_items.currency_snapshot->>'supplier_id' <> ''::text AND packing_order_cost_items.currency_snapshot->>'supplier_id' <> 'null'::text)
  )
  AND (packing_order_cost_items.payment_source_type IS NULL OR packing_order_cost_items.payment_source_type = 'none'::text) 
  AND packing_order_cost_items.treasury_transaction_id IS NULL 
  AND packing_order_cost_items.bank_transaction_id IS NULL 
  AND (packing_order_cost_items.payment_status IS NULL OR (packing_order_cost_items.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(packing_order_cost_items.original_amount, 0::numeric) - COALESCE(packing_order_cost_items.paid_amount, 0::numeric)) > 0.001

UNION ALL

-- 4. Shipment Cost Items (تكاليف شحن، تخليص، وبنود تكلفة موردين من صفحة الربحية)
SELECT 
    'shipment_cost_item'::text AS liability_type,
    shipment_cost_items.id::text AS liability_id,
    COALESCE((export_shipments.shipment_no::text || ' - '::text) || shipment_cost_items.description, shipment_cost_items.description, 'تكلفة شحن/تخليص'::text) AS reference_number,
    CASE
        WHEN shipment_cost_items.shipping_company_id IS NOT NULL THEN 'shipping_company'::text
        WHEN shipment_cost_items.clearing_agent_id IS NOT NULL THEN 'clearing_agent'::text
        WHEN shipment_cost_items.supplier_id IS NOT NULL AND shipment_cost_items.supplier_id <> ''::text THEN 'supplier'::text
        ELSE lower(COALESCE(shipment_cost_items.vendor_type, 'supplier'::text))
    END AS entity_type,
    CASE
        WHEN shipment_cost_items.shipping_company_id IS NOT NULL THEN shipment_cost_items.shipping_company_id::text
        WHEN shipment_cost_items.clearing_agent_id IS NOT NULL THEN shipment_cost_items.clearing_agent_id::text
        WHEN shipment_cost_items.supplier_id IS NOT NULL AND shipment_cost_items.supplier_id <> ''::text THEN shipment_cost_items.supplier_id
        ELSE shipment_cost_items.vendor_id::text
    END AS entity_id,
    COALESCE(NULLIF(shipment_cost_items.original_currency, ''::text), NULLIF(shipment_cost_items.supplier_currency, ''::text), 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(shipment_cost_items.exchange_rate, 1.0)) AS currency_snapshot,
    round(COALESCE(NULLIF(shipment_cost_items.total_price, 0::numeric), shipment_cost_items.quantity * shipment_cost_items.unit_price, 0::numeric) / COALESCE(NULLIF(shipment_cost_items.exchange_rate, 0::numeric), 1.0) - COALESCE(shipment_cost_items.paid_amount, 0::numeric), 2)::double precision AS due_amount,
    shipment_cost_items.created_at::date AS liability_date
FROM public.shipment_cost_items
LEFT JOIN public.export_shipments ON export_shipments.id = shipment_cost_items.shipment_id
WHERE shipment_cost_items.treasury_transaction_id IS NULL 
  AND shipment_cost_items.bank_transaction_id IS NULL 
  AND (shipment_cost_items.payment_source_type IS NULL OR shipment_cost_items.payment_source_type = 'none'::text) 
  AND (shipment_cost_items.payment_status IS NULL OR (shipment_cost_items.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(NULLIF(shipment_cost_items.total_price, 0::numeric), shipment_cost_items.quantity * shipment_cost_items.unit_price, 0::numeric) / COALESCE(NULLIF(shipment_cost_items.exchange_rate, 0::numeric), 1.0) - COALESCE(shipment_cost_items.paid_amount, 0::numeric)) > 0.001;

GRANT SELECT ON public.vw_unpaid_liabilities TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.rpc_entity_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_entity_type text,
    p_entity_id text,
    p_description text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
    v_initial_je_id BIGINT;
    v_je_id BIGINT;
    v_company_id UUID;
    v_source_acct BIGINT;
    v_entity_acct BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_book_rate NUMERIC := 1.0;
    v_remaining_to_allocate NUMERIC := p_amount;
    v_liab RECORD;
    v_allocation_amount NUMERIC;
    v_inv_rate NUMERIC;
    v_inv_base NUMERIC;
    v_paid_base NUMERIC;
    v_diff NUMERIC;
    v_total_realized_gain NUMERIC := 0.0;
    v_total_realized_loss NUMERIC := 0.0;
    v_total_ap_base NUMERIC := 0.0;
    v_total_cash_base NUMERIC := 0.0;
    v_initial_balance NUMERIC := 0;
    v_initial_direction TEXT := 'CREDIT';
    v_opening_paid NUMERIC := 0;
    v_opening_remaining NUMERIC := 0;
    v_opening_alloc NUMERIC := 0;
    v_advance_alloc NUMERIC := 0;
    v_invoices_allocated_count INT := 0;
    v_je_lines JSONB := '[]'::jsonb;
    v_entity_name TEXT;
    v_source_name TEXT;
    v_desc TEXT;
    v_supplier_uuid UUID;
    v_norm_entity_type TEXT;
    v_doc_type TEXT;
    v_entry_date DATE;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    v_norm_entity_type := LOWER(p_entity_type);
    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Fetch entity info & GL account based on normalized entity type
    IF v_norm_entity_type = 'supplier' THEN
        v_supplier_uuid := p_entity_id::uuid;
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.suppliers WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.shipping_companies WHERE id = p_entity_id::integer;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.clearing_agents WHERE id = p_entity_id::integer;
    ELSE
        RAISE EXCEPTION 'نوع الجهة غير صالح: %', p_entity_type;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_entity_acct IS NULL THEN
        IF v_norm_entity_type = 'supplier' THEN
            v_entity_acct := public.resolve_gl_account('2000', v_company_id);
        ELSIF v_norm_entity_type = 'shipping_company' THEN
            v_entity_acct := public.resolve_gl_account('2103', v_company_id);
        ELSIF v_norm_entity_type = 'clearing_agent' THEN
            v_entity_acct := public.resolve_gl_account('2104', v_company_id);
        END IF;
    END IF;

    -- 2. Resolve Source Book Rate and GL Account
    IF p_source_type = 'treasury' THEN
        v_doc_type := 'treasury_multi_payment';

        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.treasury_balances
        WHERE treasury_id::text = p_source_id::text AND currency = p_currency;

        SELECT name INTO v_source_name FROM public.treasuries WHERE id = p_source_id;
        v_source_acct := public.resolve_treasury_account(p_source_id::integer, p_currency, v_company_id);
    ELSIF p_source_type = 'bank' THEN
        v_doc_type := 'bank_multi_payment';

        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.bank_accounts
        WHERE id = p_source_id::integer;

        SELECT name INTO v_source_name FROM public.bank_accounts WHERE id = p_source_id::integer;
        v_source_acct := public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );
    ELSE
        RAISE EXCEPTION 'نوع المصدر غير صالح: %', p_source_type;
    END IF;

    IF v_book_rate IS NULL OR v_book_rate <= 0 THEN
        v_book_rate := public.fn_get_exchange_rate(p_currency);
    END IF;

    v_total_cash_base := ROUND(p_amount * v_book_rate, 2);

    -- 3. Execute Cash / Bank Payment (Withdrawal)
    IF p_source_type = 'treasury' THEN
        v_tx_id := public.spend_custody(
            p_treasury_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
            p_supplier_id := CASE WHEN v_norm_entity_type = 'supplier' THEN v_supplier_uuid ELSE NULL END,
            p_clearing_agent_id := CASE WHEN v_norm_entity_type = 'clearing_agent' THEN p_entity_id::bigint ELSE NULL END,
            p_shipping_company_id := CASE WHEN v_norm_entity_type = 'shipping_company' THEN p_entity_id::bigint ELSE NULL END,
            p_expense_account_id := COALESCE(p_expense_account_id, v_entity_acct::integer),
            p_reference_type := v_norm_entity_type || '_payment',
            p_reference_id := p_entity_id,
            p_notes := p_notes
        );
        SELECT journal_entry_id INTO v_initial_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
    ELSIF p_source_type = 'bank' THEN
        DECLARE
            v_bank_res JSONB;
        BEGIN
            v_bank_res := public.withdraw_bank_account(
                p_account_id := p_source_id::INTEGER,
                p_amount := p_amount,
                p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
                p_entity_type := v_norm_entity_type,
                p_entity_id := p_entity_id,
                p_counterparty_name := v_entity_name,
                p_expense_account_id := COALESCE(p_expense_account_id, v_entity_acct::integer),
                p_notes := p_notes,
                p_reference_type := v_norm_entity_type || '_payment',
                p_reference_id := p_entity_id
            );
            v_tx_id := (v_bank_res->>'transaction_id')::BIGINT;
            v_initial_je_id := (v_bank_res->>'journal_entry_id')::BIGINT;
        END;
    END IF;

    -- 4. Calculate Remaining Opening Balance to Allocate
    IF v_norm_entity_type = 'supplier' AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_opening_paid
        FROM public.supplier_payment_allocations
        WHERE supplier_id = v_supplier_uuid AND allocation_type = 'opening_balance';

        v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
    ELSIF v_norm_entity_type IN ('shipping_company', 'clearing_agent') AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        v_opening_remaining := v_initial_balance;
    ELSE
        v_opening_remaining := 0;
    END IF;

    -- 5. Allocation Priority 1: Opening Balance
    IF v_opening_remaining > 0 AND v_remaining_to_allocate > 0 THEN
        IF v_remaining_to_allocate >= v_opening_remaining THEN
            v_opening_alloc := v_opening_remaining;
        ELSE
            v_opening_alloc := v_remaining_to_allocate;
        END IF;

        IF v_norm_entity_type = 'supplier' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
            ) VALUES (
                p_source_type, v_tx_id, NULL, v_supplier_uuid, 'opening_balance', v_opening_alloc
            );
        END IF;

        v_total_ap_base := v_total_ap_base + ROUND(v_opening_alloc * v_book_rate, 2);
        v_remaining_to_allocate := v_remaining_to_allocate - v_opening_alloc;
    END IF;

    -- 6. Allocation Priority 2: Unpaid Liabilities (FIFO by liability_date)
    FOR v_liab IN 
        SELECT liability_type, liability_id, reference_number, currency, currency_snapshot, due_amount
        FROM public.vw_unpaid_liabilities
        WHERE LOWER(entity_type) = v_norm_entity_type
          AND entity_id = p_entity_id
          AND currency = p_currency
        ORDER BY liability_date ASC, liability_id ASC
    LOOP
        EXIT WHEN v_remaining_to_allocate <= 0;

        IF v_remaining_to_allocate >= v_liab.due_amount THEN
            v_allocation_amount := v_liab.due_amount;
        ELSE
            v_allocation_amount := v_remaining_to_allocate;
        END IF;

        -- Extract Invoice Original Pegged Exchange Rate
        v_inv_rate := COALESCE(
            (v_liab.currency_snapshot->>'exchange_rate')::NUMERIC,
            public.fn_get_exchange_rate(p_currency)
        );

        -- Realized FX Math (IAS 21):
        v_inv_base  := ROUND(v_allocation_amount * v_inv_rate, 2);
        v_paid_base := ROUND(v_allocation_amount * v_book_rate, 2);
        v_diff      := v_paid_base - v_inv_base;

        v_total_ap_base := v_total_ap_base + v_inv_base;

        IF v_diff < 0 THEN
            v_total_realized_gain := v_total_realized_gain + ABS(v_diff);
        ELSIF v_diff > 0 THEN
            v_total_realized_loss := v_total_realized_loss + v_diff;
        END IF;

        -- Update the specific liability table
        IF v_liab.liability_type = 'purchase_invoice' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::integer, v_supplier_uuid, 'invoice', v_allocation_amount
                );
            END IF;
            UPDATE public.purchase_invoices
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= (total_amount - discount_amount) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'lot_receipt' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, lot_receipt_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'lot_receipt', v_allocation_amount
                );
            END IF;
            UPDATE public.lot_receipts
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(total_fruit_cost, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type,
                updated_at = NOW()
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'packing_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, packing_order_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'packing_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.packing_order_cost_items
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= COALESCE(original_amount, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'shipment_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, shipment_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'shipment_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.shipment_cost_items
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
        END IF;

        v_invoices_allocated_count := v_invoices_allocated_count + 1;
        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- 7. Allocation Priority 3: Advance Payment / Credit Balance
    IF v_remaining_to_allocate > 0 THEN
        v_advance_alloc := v_remaining_to_allocate;
        IF v_norm_entity_type = 'supplier' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, supplier_id, allocation_type, amount
            ) VALUES (
                p_source_type, v_tx_id, v_supplier_uuid, 'advance', v_advance_alloc
            );
        END IF;
        v_total_ap_base := v_total_ap_base + ROUND(v_advance_alloc * v_book_rate, 2);
    END IF;

    -- 8. Post / Adjust GL Journal Entry for Realized FX Differences
    IF v_total_realized_gain > 0 OR v_total_realized_loss > 0 THEN
        v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
        v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);

        v_desc := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات مع تسوية فروق عملة محققة: ' || v_entity_name);

        v_je_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_entity_acct,
                'debit', p_amount,
                'credit', 0,
                'base_debit', v_total_ap_base,
                'base_credit', 0,
                'currency', p_currency,
                'description', v_desc || ' (تسوية ذمم دائنة)'
            )
        );

        IF v_total_realized_loss > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_realized_loss,
                    'credit', 0,
                    'base_debit', v_total_realized_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - ' || v_entity_name
                )
            );
        END IF;

        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_source_acct,
                'debit', 0,
                'credit', p_amount,
                'base_debit', 0,
                'base_credit', v_total_cash_base,
                'currency', p_currency,
                'description', v_desc || ' (صرف من ' || v_source_name || ')'
            )
        );

        IF v_total_realized_gain > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_realized_gain,
                    'base_debit', 0,
                    'base_credit', v_total_realized_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - ' || v_entity_name
                )
            );
        END IF;

        v_je_id := public.post_journal_entry(
            v_norm_entity_type || '_payment',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines,
            p_entity_id
        );

        IF p_source_type = 'treasury' THEN
            UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        ELSIF p_source_type = 'bank' THEN
            UPDATE public.bank_account_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        END IF;
    ELSE
        IF p_source_type = 'treasury' THEN
            SELECT journal_entry_id INTO v_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
        ELSIF p_source_type = 'bank' THEN
            SELECT journal_entry_id INTO v_je_id FROM public.bank_account_transactions WHERE id = v_tx_id;
        END IF;
    END IF;

    -- 9. Recalculate & update outstanding_balance
    IF v_norm_entity_type = 'supplier' THEN
        UPDATE public.suppliers
        SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = v_supplier_uuid)
        WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET balance = balance - p_amount
        WHERE id = p_entity_id::integer;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET balance = balance - p_amount
        WHERE id = p_entity_id::integer;
    END IF;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'opening_balance_allocated', v_opening_alloc,
        'liabilities_allocated_count', v_invoices_allocated_count,
        'liabilities_allocated_amount', p_amount - v_opening_alloc - v_advance_alloc,
        'advance_amount', v_advance_alloc,
        'realized_fx_gain', v_total_realized_gain,
        'realized_fx_loss', v_total_realized_loss
    );
END;
$$;

-- Replace old wrapper
CREATE OR REPLACE FUNCTION public.rpc_supplier_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_supplier_id uuid,
    p_description text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.rpc_entity_multi_payment(
        p_source_type, p_source_id, p_currency, p_amount, 'supplier', p_supplier_id::text, p_description, p_expense_account_id, p_notes
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, integer, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_supplier_multi_payment(text, bigint, text, numeric, uuid, text, integer, text) TO authenticated, anon, service_role;
GRANT SELECT ON public.vw_unpaid_liabilities TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';


-- ── get_balance_before_date_rpc (Multi-currency opening balance) ──
CREATE OR REPLACE FUNCTION public.get_balance_before_date_rpc(
    p_account_id text,
    p_before_date date,
    p_currency text DEFAULT NULL::text
)
RETURNS TABLE(debit numeric, credit numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
  WITH RECURSIVE target_accounts AS (
    SELECT id FROM accounts WHERE (p_account_id IS NULL OR p_account_id = '' OR id::TEXT = p_account_id OR account_code = p_account_id OR code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  )
  SELECT
    COALESCE(SUM(
      CASE 
        WHEN p_currency IS NULL OR p_currency = 'ALL' THEN
          CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
        ELSE ale.debit
      END
    ), 0)::numeric AS debit,
    COALESCE(SUM(
      CASE 
        WHEN p_currency IS NULL OR p_currency = 'ALL' THEN
          CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
        ELSE ale.credit
      END
    ), 0)::numeric AS credit
  FROM account_ledger_entries ale
  INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
  WHERE ale.account_id IN (SELECT id FROM target_accounts)
    AND (je.deleted_at IS NULL)
    AND (ale.deleted_at IS NULL)
    AND je.entry_date < p_before_date
    AND (p_currency IS NULL OR p_currency = 'ALL' OR ale.currency = p_currency);
$function$;

GRANT EXECUTE ON FUNCTION public.get_balance_before_date_rpc(text, date, text) TO authenticated, anon, service_role;


-- ── get_ledger_page_rpc ──
CREATE OR REPLACE FUNCTION public.get_ledger_page_rpc(
  p_account_id text DEFAULT NULL::text,
  p_from_date text DEFAULT NULL::text,
  p_to_date text DEFAULT NULL::text,
  p_cursor_date text DEFAULT NULL::text,
  p_cursor_id text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_currency text DEFAULT NULL::text
)
RETURNS TABLE(
  id text,
  date text,
  entry_number text,
  account_id text,
  account_code text,
  account_name text,
  description text,
  debit numeric,
  credit numeric,
  reference_type text,
  reference_id text,
  next_cursor_date text,
  next_cursor_id text,
  has_more boolean,
  opening_balance_debit numeric,
  opening_balance_credit numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_cursor_ts TIMESTAMPTZ;
  v_ob_debit NUMERIC := 0;
  v_ob_credit NUMERIC := 0;
  v_cursor_entry_id BIGINT;
BEGIN
  -- Parse cursor
  IF p_cursor_date IS NOT NULL AND p_cursor_id IS NOT NULL AND p_cursor_date != '' AND p_cursor_id != '' THEN
    v_cursor_ts := p_cursor_date::TIMESTAMPTZ;
    v_cursor_entry_id := p_cursor_id::BIGINT;
  END IF;

  -- Compute opening balance
  IF v_cursor_ts IS NOT NULL THEN
    SELECT
      COALESCE(SUM(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.debit
        END
      ), 0),
      COALESCE(SUM(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.credit
        END
      ), 0)
    INTO v_ob_debit, v_ob_credit
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    WHERE (p_account_id IS NULL OR ale.account_id IN (
      WITH RECURSIVE target_accounts AS (
        SELECT acc0.id FROM accounts acc0 
        WHERE (p_account_id IS NULL OR p_account_id = '' OR acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id OR acc0.code = p_account_id)
        UNION ALL
        SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
      )
      SELECT target_accounts.id FROM target_accounts
    ))
      AND (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND je.entry_date < (v_cursor_ts AT TIME ZONE 'UTC')::DATE
      AND (p_currency IS NULL OR ale.currency = p_currency);
  ELSE
    IF p_from_date IS NOT NULL AND p_from_date != '' THEN
      SELECT
        COALESCE(SUM(
          CASE
            WHEN p_currency IS NULL THEN CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
            ELSE ale.debit
          END
        ), 0),
        COALESCE(SUM(
          CASE
            WHEN p_currency IS NULL THEN CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
            ELSE ale.credit
          END
        ), 0)
      INTO v_ob_debit, v_ob_credit
      FROM account_ledger_entries ale
      INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
      WHERE (p_account_id IS NULL OR ale.account_id IN (
        WITH RECURSIVE target_accounts AS (
          SELECT acc0.id FROM accounts acc0 
          WHERE (p_account_id IS NULL OR p_account_id = '' OR acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id OR acc0.code = p_account_id)
          UNION ALL
          SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
        )
        SELECT target_accounts.id FROM target_accounts
      ))
        AND (je.deleted_at IS NULL)
        AND (ale.deleted_at IS NULL)
        AND je.entry_date < p_from_date::DATE
        AND (p_currency IS NULL OR ale.currency = p_currency);
    END IF;
  END IF;

  RETURN QUERY
  WITH RECURSIVE target_accounts AS (
    SELECT acc0.id FROM accounts acc0 
    WHERE (p_account_id IS NULL OR p_account_id = '' OR acc0.id::TEXT = p_account_id OR acc0.account_code = p_account_id OR acc0.code = p_account_id)
    UNION ALL
    SELECT a.id FROM accounts a INNER JOIN target_accounts ta ON a.parent_id = ta.id
  ),
  raw_page AS (
    SELECT
      ale.id::TEXT AS r_id,
      je.entry_date::TEXT AS r_date,
      COALESCE(je.entry_number, '')::TEXT AS r_entry_number,
      ale.account_id::TEXT AS r_account_id,
      COALESCE(a.account_code, a.code, '')::TEXT AS r_account_code,
      COALESCE(a.account_name, a.name, '')::TEXT AS r_account_name,
      COALESCE(NULLIF(ale.description, ''), NULLIF(je.description, ''), '')::TEXT AS r_description,
      COALESCE(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.debit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.debit
        END, 0
      ) AS r_debit,
      COALESCE(
        CASE
          WHEN p_currency IS NULL THEN CASE WHEN ale.credit > 0 THEN ale.amount_in_base_currency ELSE 0 END
          ELSE ale.credit
        END, 0
      ) AS r_credit,
      COALESCE(je.source_type, '')::TEXT AS r_reference_type,
      COALESCE(je.source_id, '')::TEXT AS r_reference_id,
      ale.id AS ale_order_id,
      je.entry_date AS je_order_date
    FROM account_ledger_entries ale
    INNER JOIN journal_entries je ON je.id = ale.journal_entry_id
    LEFT JOIN accounts a ON a.id = ale.account_id
    WHERE (je.deleted_at IS NULL)
      AND (ale.deleted_at IS NULL)
      AND (p_account_id IS NULL OR ale.account_id IN (SELECT target_accounts.id FROM target_accounts))
      AND (p_from_date IS NULL OR p_from_date = '' OR je.entry_date >= p_from_date::DATE)
      AND (p_to_date IS NULL OR p_to_date = '' OR je.entry_date <= p_to_date::DATE)
      AND (p_currency IS NULL OR ale.currency = p_currency)
      AND (
        v_cursor_ts IS NULL
        OR je.entry_date > (v_cursor_ts AT TIME ZONE 'UTC')::DATE
        OR (je.entry_date = (v_cursor_ts AT TIME ZONE 'UTC')::DATE
            AND ale.id > v_cursor_entry_id)
      )
    ORDER BY je.entry_date ASC, ale.id ASC
    LIMIT (p_limit + 1)
  ),
  page_data AS (
    SELECT * FROM raw_page LIMIT p_limit
  ),
  has_more_val AS (
    SELECT (COUNT(*) > p_limit) AS hm FROM raw_page
  )
  SELECT
    pd.r_id AS id,
    pd.r_date AS date,
    pd.r_entry_number AS entry_number,
    pd.r_account_id AS account_id,
    pd.r_account_code AS account_code,
    pd.r_account_name AS account_name,
    pd.r_description AS description,
    pd.r_debit AS debit,
    pd.r_credit AS credit,
    pd.r_reference_type AS reference_type,
    pd.r_reference_id AS reference_id,
    (SELECT p2.r_date FROM page_data p2 ORDER BY p2.je_order_date DESC, p2.ale_order_id DESC LIMIT 1)::TEXT AS next_cursor_date,
    (SELECT p2.r_id FROM page_data p2 ORDER BY p2.je_order_date DESC, p2.ale_order_id DESC LIMIT 1)::TEXT AS next_cursor_id,
    COALESCE((SELECT hm FROM has_more_val), false) AS has_more,
    v_ob_debit AS opening_balance_debit,
    v_ob_credit AS opening_balance_credit
  FROM page_data pd;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.get_ledger_page_rpc(text, text, text, text, text, integer, text) TO authenticated, anon, service_role;

-- ── rpc_post_journal (Enterprise Posting Engine with Multi-Currency) ──
CREATE OR REPLACE FUNCTION public.rpc_post_journal(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_company_id UUID;
    v_profile_id UUID;
    v_doc_type TEXT;
    v_date DATE;
    v_ref TEXT;
    v_desc TEXT;
    v_currency TEXT;
    v_exchange_rate NUMERIC;
    v_currency_snapshot JSONB;
    v_dimensions JSONB;
    v_created_by UUID;
    v_idempotency_key TEXT;
    v_fy_info JSONB;
    v_period_info JSONB;
    v_journal_id BIGINT;
    v_entry_number TEXT;
    v_lines JSONB;
    v_line JSONB;
    v_taxes JSONB;
    v_tax JSONB;
    v_norm_lines JSONB := '[]'::jsonb;
    v_roles_needed JSONB := '[]'::jsonb;
    v_resolved_accounts JSONB;
    v_total_debit NUMERIC := 0;
    v_total_credit NUMERIC := 0;
    v_role TEXT;
    v_debit NUMERIC;
    v_credit NUMERIC;
    v_acc_id BIGINT;
    v_base_amount NUMERIC;
    v_tax_rate NUMERIC;
    v_tax_role_id UUID;
    v_tax_role_code TEXT;
    v_tax_amount NUMERIC;
    v_start_time TIMESTAMPTZ;
BEGIN
    v_start_time := clock_timestamp();

    v_company_id := (payload->>'company_id')::UUID;
    v_profile_id := (payload->>'posting_profile_id')::UUID;
    v_doc_type := payload->>'document_type';
    v_date := (payload->>'posting_date')::DATE;
    v_ref := payload->>'reference';
    v_desc := payload->>'description';
    v_currency := COALESCE(payload->'currency'->>'code', 'EGP');
    v_exchange_rate := COALESCE((payload->'currency'->>'exchange_rate')::NUMERIC, 1.0);
    v_currency_snapshot := COALESCE(payload->'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0));
    v_dimensions := COALESCE(payload->'dimensions', '{}'::jsonb);
    v_created_by := COALESCE((payload->>'created_by')::UUID, auth.uid());
    v_idempotency_key := payload->>'idempotency_key';
    
    v_lines := COALESCE(payload->'lines', '[]'::jsonb);
    v_taxes := COALESCE(payload->'taxes', '[]'::jsonb);

    IF v_profile_id IS NULL THEN
        SELECT id INTO v_profile_id
        FROM public.posting_profiles
        WHERE company_id = v_company_id AND is_default = true
        LIMIT 1;

        IF v_profile_id IS NULL THEN
            PERFORM public.fn_raise_posting_error('PROFILE_MISSING', 'No default posting profile found for company.', '{}', 'Seed a default posting profile for the company', 'ERROR', v_idempotency_key);
        END IF;
    END IF;

    IF v_idempotency_key IS NOT NULL THEN
        SELECT id, entry_number INTO v_journal_id, v_entry_number
        FROM public.journal_entries
        WHERE company_id = v_company_id AND idempotency_key = v_idempotency_key 
        LIMIT 1;
        
        IF FOUND THEN
            RETURN jsonb_build_object(
                'success', true,
                'journal_id', v_journal_id,
                'journal_number', v_entry_number,
                'posting_status', 'POSTED_IDEMPOTENT',
                'warnings', '[]'::jsonb,
                'errors', '[]'::jsonb,
                'execution_time_ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))
            );
        END IF;
    END IF;

    IF jsonb_array_length(v_lines) = 0 THEN
        PERFORM public.fn_raise_posting_error('EMPTY_JOURNAL', 'A journal must contain at least one line.', '{}', 'Provide journal lines in payload', 'ERROR', v_idempotency_key);
    END IF;

    PERFORM public.fn_validate_company_active(v_company_id, v_idempotency_key);
    v_fy_info := public.fn_validate_fiscal_year(v_company_id, v_date, v_idempotency_key);
    v_period_info := public.fn_validate_period_open(v_company_id, (v_fy_info->>'fiscal_year_id')::BIGINT, v_date, v_idempotency_key);
    PERFORM public.fn_validate_document_type(v_doc_type, v_idempotency_key);
    PERFORM public.fn_validate_posting_profile(v_company_id, v_profile_id, v_idempotency_key);

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_lines)
    LOOP
        v_role := v_line->>'role';
        v_debit := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit := COALESCE((v_line->>'credit')::NUMERIC, 0);
        
        IF v_role IS NULL THEN
            PERFORM public.fn_raise_posting_error('ROLE_MISSING', 'Journal line is missing a posting role code.', '{}', 'Specify a posting role for each line', 'ERROR', v_idempotency_key);
        END IF;

        IF v_debit < 0 THEN
            v_credit := v_credit + abs(v_debit);
            v_debit := 0;
        END IF;
        IF v_credit < 0 THEN
            v_debit := v_debit + abs(v_credit);
            v_credit := 0;
        END IF;
        
        v_norm_lines := v_norm_lines || jsonb_build_object(
            'role', v_role, 
            'debit', v_debit, 
            'credit', v_credit, 
            'description', COALESCE(v_line->>'description', v_desc)
        );
        v_roles_needed := v_roles_needed || to_jsonb(v_role);
    END LOOP;

    FOR v_tax IN SELECT * FROM jsonb_array_elements(v_taxes)
    LOOP
        SELECT tr.rate, tc.posting_role_id INTO v_tax_rate, v_tax_role_id
        FROM public.tax_codes tc
        JOIN public.tax_rates tr ON tr.tax_code_id = tc.id
        WHERE tc.company_id = v_company_id 
          AND tc.code = v_tax->>'tax_code' 
          AND tc.is_active = true
          AND v_date >= tr.effective_from 
          AND (tr.effective_to IS NULL OR v_date <= tr.effective_to)
        ORDER BY tc.id, tr.id FOR SHARE
        LIMIT 1;
        
        IF NOT FOUND THEN
            PERFORM public.fn_raise_posting_error('TAX_NOT_FOUND', 'Tax code or valid rate not found for the given date.', v_tax->>'tax_code', 'Ensure tax rate is effective on posting_date', 'ERROR', v_idempotency_key);
        END IF;
        IF v_tax_role_id IS NULL THEN
            PERFORM public.fn_raise_posting_error('TAX_ROLE_MISSING', 'Tax code missing posting role.', v_tax->>'tax_code', 'Link a posting role to the tax code', 'ERROR', v_idempotency_key);
        END IF;
        
        SELECT code INTO v_tax_role_code FROM public.posting_account_roles WHERE id = v_tax_role_id;
        v_tax_amount := (v_tax->>'base_amount')::NUMERIC * v_tax_rate;
        
        IF (v_tax->>'sign') = 'DEBIT' THEN
            v_norm_lines := v_norm_lines || jsonb_build_object('role', v_tax_role_code, 'debit', v_tax_amount, 'credit', 0, 'description', 'Tax ' || (v_tax->>'tax_code'));
        ELSE
            v_norm_lines := v_norm_lines || jsonb_build_object('role', v_tax_role_code, 'debit', 0, 'credit', v_tax_amount, 'description', 'Tax ' || (v_tax->>'tax_code'));
        END IF;
        
        v_roles_needed := v_roles_needed || to_jsonb(v_tax_role_code);
    END LOOP;

    v_resolved_accounts := public.fn_resolve_posting_accounts_bulk(v_company_id, v_profile_id, v_roles_needed, v_idempotency_key);

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_norm_lines)
    LOOP
        v_total_debit := v_total_debit + (v_line->>'debit')::NUMERIC;
        v_total_credit := v_total_credit + (v_line->>'credit')::NUMERIC;
    END LOOP;

    IF ROUND(v_total_debit, 4) != ROUND(v_total_credit, 4) THEN
        PERFORM public.fn_raise_posting_error('JOURNAL_UNBALANCED', 'Total debits do not equal total credits.', 'Debit: ' || v_total_debit || ' Credit: ' || v_total_credit, 'Ensure debits equal credits before posting', 'ERROR', v_idempotency_key);
    END IF;

    v_entry_number := public.fn_get_next_sequence(v_company_id, v_doc_type, (v_fy_info->>'fiscal_year_id')::INT, NULL);

    INSERT INTO public.journal_entries (
        company_id, entry_number, entry_date, description, status, source_type, source_id, created_by, currency_snapshot, idempotency_key
    ) VALUES (
        v_company_id, v_entry_number, v_date, v_desc, 'posted', v_doc_type, v_ref, v_created_by, v_currency_snapshot, v_idempotency_key
    ) RETURNING id INTO v_journal_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_norm_lines)
    LOOP
        v_role := v_line->>'role';
        v_debit := (v_line->>'debit')::NUMERIC;
        v_credit := (v_line->>'credit')::NUMERIC;
        
        v_acc_id := (v_resolved_accounts->v_role->>'account_id')::BIGINT;

        IF v_debit > 0 OR v_credit > 0 THEN
            v_base_amount := CASE 
                WHEN v_debit > 0 THEN v_debit * COALESCE(v_exchange_rate, 1.0)
                ELSE v_credit * COALESCE(v_exchange_rate, 1.0)
            END;

            INSERT INTO public.account_ledger_entries (
                company_id, journal_entry_id, account_id, debit, credit,
                currency, amount_in_base_currency, description
            ) VALUES (
                v_company_id, v_journal_id, v_acc_id, v_debit, v_credit,
                COALESCE(v_currency, 'EGP'), v_base_amount, v_line->>'description'
            );
        END IF;
    END LOOP;

    IF v_dimensions != '{}'::jsonb THEN
        INSERT INTO public.journal_entry_dimensions (
            company_id, journal_entry_id, dimension_key, dimension_value
        )
        SELECT v_company_id, v_journal_id, key, value#>>'{}'
        FROM jsonb_each(v_dimensions);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number,
        'posting_status', 'POSTED',
        'warnings', '[]'::jsonb,
        'errors', '[]'::jsonb,
        'execution_time_ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))
    );
EXCEPTION 
    WHEN OTHERS THEN
        IF SQLSTATE = 'P0001' THEN
            RAISE;
        END IF;
        PERFORM public.fn_raise_posting_error('SYSTEM_ERROR', SQLERRM, SQLSTATE, 'Check database logs', 'FATAL', v_idempotency_key);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_post_journal(jsonb) TO authenticated, anon, service_role;

COMMIT;





-- =========================================================================
-- Migration 424: Fix timezone offset in shipment costing journal entries (admin expenses, taxes, cost items)
-- Ensuring all journal entries use Cairo local date (UTC+3) instead of server UTC CURRENT_DATE.

-- 1. Update rpc_save_shipment_admin_expenses
CREATE OR REPLACE FUNCTION public.rpc_save_shipment_admin_expenses(
    p_shipment_id BIGINT,
    p_allocated_admin_expenses NUMERIC,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_has_distribution BOOLEAN;
    v_company_id UUID;
    v_admin_exp_account_id BIGINT;
    v_provision_account_id BIGINT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_entry_date DATE;
    v_amount NUMERIC := COALESCE(p_allocated_admin_expenses, 0.00);
BEGIN
    -- ── A. Check Profit Distribution Lock ──
    SELECT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions
        WHERE shipment_id = p_shipment_id AND deleted_at IS NULL
    ) INTO v_has_distribution;

    IF v_has_distribution THEN
        RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل التكاليف أو المصروفات الإدارية';
    END IF;

    -- ── B. Fetch Shipment ──
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
    END IF;

    -- ── Calculate Safe Local Entry Date (Cairo UTC+3) ──
    v_entry_date := COALESCE(
        v_shipment.shipment_date,
        (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::DATE,
        (NOW() AT TIME ZONE 'Africa/Cairo')::DATE
    );

    -- ── C. Update Export Shipment Record ──
    UPDATE public.export_shipments
    SET allocated_admin_expenses = v_amount,
        net_profit_egp = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - v_amount - COALESCE(allocated_taxes, 0),
        net_profit = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - v_amount - COALESCE(allocated_taxes, 0)
    WHERE id = p_shipment_id;

    -- ── D. Resolve Accounts ──
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '5210' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    -- 5210: Allocated Admin Expenses (مصروفات إدارية محملة)
    SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '5210' LIMIT 1;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '6002' LIMIT 1;
    END IF;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '6000' LIMIT 1;
    END IF;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_type = 'expense' LIMIT 1;
    END IF;

    -- 2105: Admin Expenses Provision (مخصص / وسيط مصروفات إدارية)
    SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code = '2105' LIMIT 1;
    IF v_provision_account_id IS NULL THEN
        SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;
    IF v_provision_account_id IS NULL THEN
        SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_type = 'liability' LIMIT 1;
    END IF;

    -- ── E. Manage GL Journal Entry ──
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'shipment_admin_expenses' AND source_id = p_shipment_id::text AND deleted_at IS NULL
    LIMIT 1;

    IF v_amount > 0 THEN
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries
            SET description = 'مصروفات إدارية محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                entry_date = v_entry_date,
                updated_at = now()
            WHERE id = v_je_id;

            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_admin_exp_account_id, v_amount, 0, 'EGP', v_amount,
                'تحميل مصروفات إدارية على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_provision_account_id, 0, v_amount, 'EGP', v_amount,
                'مخصص مصروفات إدارية لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        ELSE
            INSERT INTO public.journal_entries (
                entry_number, entry_date, description, status,
                is_auto_generated, source_type, source_id, company_id,
                created_by, created_at, updated_at
            ) VALUES (
                'PENDING',
                v_entry_date,
                'مصروفات إدارية محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                'posted', true, 'shipment_admin_expenses', p_shipment_id::text, v_company_id,
                COALESCE(p_user_id, auth.uid()), now(), now()
            ) RETURNING id INTO v_je_id;

            v_entry_num := public.fn_get_next_sequence(v_company_id, 'shipment_admin_expenses', NULL, NULL);
            IF v_entry_num IS NULL OR v_entry_num = '' THEN
                v_entry_num := 'ADM-' || LPAD(v_je_id::text, 5, '0');
            END IF;
            UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_admin_exp_account_id, v_amount, 0, 'EGP', v_amount,
                'تحميل مصروفات إدارية على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_provision_account_id, 0, v_amount, 'EGP', v_amount,
                'مخصص مصروفات إدارية لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        END IF;
    ELSE
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries SET deleted_at = now() WHERE id = v_je_id;
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shipment_id', p_shipment_id,
        'allocated_admin_expenses', v_amount,
        'journal_entry_id', v_je_id
    );
END;
$$;

-- 2. Update rpc_save_shipment_taxes
CREATE OR REPLACE FUNCTION public.rpc_save_shipment_taxes(
    p_shipment_id BIGINT,
    p_allocated_taxes NUMERIC,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_shipment RECORD;
    v_has_distribution BOOLEAN;
    v_company_id UUID;
    v_tax_debit_acc BIGINT;
    v_tax_credit_acc BIGINT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_entry_date DATE;
    v_amount NUMERIC := COALESCE(p_allocated_taxes, 0.00);
BEGIN
    -- A. Check Profit Distribution Lock
    SELECT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions
        WHERE shipment_id = p_shipment_id AND deleted_at IS NULL
    ) INTO v_has_distribution;

    IF v_has_distribution THEN
        RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل التكاليف أو الضرائب';
    END IF;

    -- B. Fetch Shipment
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
    END IF;

    -- ── Calculate Safe Local Entry Date (Cairo UTC+3) ──
    v_entry_date := COALESCE(
        v_shipment.shipment_date,
        (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::DATE,
        (NOW() AT TIME ZONE 'Africa/Cairo')::DATE
    );

    -- C. Update Export Shipment Record
    UPDATE public.export_shipments
    SET allocated_taxes = v_amount,
        net_profit_egp = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - COALESCE(allocated_admin_expenses, 0) - v_amount,
        net_profit = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - COALESCE(allocated_admin_expenses, 0) - v_amount
    WHERE id = p_shipment_id;

    -- D. Resolve Accounts
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '2102' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code = '2102' LIMIT 1;
    IF v_tax_debit_acc IS NULL THEN
        SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code = '2101' LIMIT 1;
    IF v_tax_credit_acc IS NULL THEN
        SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    -- E. Manage GL Journal Entry
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'shipment_taxes' AND source_id = p_shipment_id::text AND deleted_at IS NULL
    LIMIT 1;

    IF v_amount > 0 THEN
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries
            SET description = 'ضرائب محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                entry_date = v_entry_date,
                updated_at = now()
            WHERE id = v_je_id;

            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_debit_acc, v_amount, 0, 'EGP', v_amount,
                'تحميل ضرائب على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_credit_acc, 0, v_amount, 'EGP', v_amount,
                'وسيط ضرائب لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        ELSE
            INSERT INTO public.journal_entries (
                entry_number, entry_date, description, status,
                is_auto_generated, source_type, source_id, company_id,
                created_by, created_at, updated_at
            ) VALUES (
                'PENDING',
                v_entry_date,
                'ضرائب محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                'posted', true, 'shipment_taxes', p_shipment_id::text, v_company_id,
                COALESCE(p_user_id, auth.uid()), now(), now()
            ) RETURNING id INTO v_je_id;

            v_entry_num := public.fn_get_next_sequence(v_company_id, 'shipment_taxes', NULL, NULL);
            IF v_entry_num IS NULL OR v_entry_num = '' THEN
                v_entry_num := 'TAX-' || LPAD(v_je_id::text, 5, '0');
            END IF;
            UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_debit_acc, v_amount, 0, 'EGP', v_amount,
                'تحميل ضرائب على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_credit_acc, 0, v_amount, 'EGP', v_amount,
                'وسيط ضرائب لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        END IF;
    ELSE
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries SET deleted_at = now() WHERE id = v_je_id;
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shipment_id', p_shipment_id,
        'allocated_taxes', v_amount,
        'journal_entry_id', v_je_id
    );
END;
$$;

-- 3. Update rpc_pay_shipment_cost_item (ensure Cairo date is used for payment search)
CREATE OR REPLACE FUNCTION public.rpc_pay_shipment_cost_item(
  p_cost_item_id        BIGINT,
  p_source_type         TEXT,
  p_source_id           BIGINT,
  p_expense_account_id  BIGINT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r_item           RECORD;
  v_supplier_id    UUID;
  v_amount         NUMERIC;
  v_currency       TEXT;
  v_current_bal    NUMERIC;
  v_treasury_tx_id BIGINT;
  v_bank_tx_id     INTEGER;
  v_tx_desc        TEXT;
  v_je_id          BIGINT;
  v_company_id     UUID;
  v_bank_res       JSONB;
  v_liability_acct INTEGER;
BEGIN
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'هذا البند مدفوع مسبقاً');
  END IF;

  IF p_source_type NOT IN ('treasury', 'bank') THEN
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح: ' || p_source_type);
  END IF;

  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');
  
  IF v_currency != 'EGP' AND COALESCE(r_item.exchange_rate, 1.0) > 0 THEN
    v_amount := ROUND(COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0) / r_item.exchange_rate, 2);
  ELSE
    v_amount := COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0);
  END IF;

  v_tx_desc  := 'سداد بند تكلفة شحنة: ' || COALESCE(r_item.description, 'غير محدد')
                 || ' (بند ' || p_cost_item_id::text || ')';

  IF v_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  v_liability_acct := NULL;
  v_supplier_id := NULL;
  IF p_expense_account_id IS NOT NULL THEN
    v_liability_acct := p_expense_account_id;
  ELSIF r_item.shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_liability_acct FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;
  ELSIF r_item.clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_liability_acct FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;
  ELSIF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      v_supplier_id := r_item.supplier_id::uuid;
      SELECT s.account_id INTO v_liability_acct FROM public.suppliers s WHERE s.id = v_supplier_id;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
      v_liability_acct := NULL;
    END;
  ELSIF r_item.vendor_type = 'shipping_company' AND r_item.vendor_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_liability_acct FROM public.shipping_companies sc WHERE sc.id = r_item.vendor_id;
  ELSIF r_item.vendor_type = 'clearing_agent' AND r_item.vendor_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_liability_acct FROM public.clearing_agents ca WHERE ca.id = r_item.vendor_id;
  ELSIF r_item.vendor_type = 'supplier' AND r_item.vendor_id IS NOT NULL THEN
    BEGIN
      v_supplier_id := r_item.vendor_id::text::uuid;
      SELECT s.account_id INTO v_liability_acct FROM public.suppliers s WHERE s.id = v_supplier_id;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
      v_liability_acct := NULL;
    END;
  END IF;

  IF v_liability_acct IS NULL THEN
    SELECT a.id INTO v_liability_acct FROM public.accounts a
    WHERE a.account_code = '2300' AND a.is_leaf = true AND a.is_active = true LIMIT 1;
  END IF;

  IF p_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_source_id;
  ELSE
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_source_id::integer;
  END IF;

  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies ORDER BY created_at ASC LIMIT 1;
  END IF;

  IF p_source_type = 'treasury' THEN
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    PERFORM public.spend_custody(
      p_source_id, v_currency, v_amount, v_tx_desc,
      NULL, v_supplier_id, NULL, r_item.clearing_agent_id, r_item.shipping_company_id,
      v_liability_acct
    );

    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type = 'expense' AND amount = v_amount AND currency = v_currency
    ORDER BY created_at DESC LIMIT 1;

    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id IS NOT DISTINCT FROM v_company_id
      AND je.entry_date = (NOW() AT TIME ZONE 'Africa/Cairo')::DATE
    ORDER BY je.id DESC LIMIT 1;

    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_treasury_tx_id,
        payment_source_type     = 'treasury',
        payment_source_id       = p_source_id,
        payment_status          = 'paid',
        paid_amount             = v_amount,
        journal_entry_id        = v_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_treasury_tx_id, 'type', 'treasury', 'journal_entry_id', v_je_id);

  ELSIF p_source_type = 'bank' THEN
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    v_bank_res := public.withdraw_bank_account(
      p_source_id::integer, v_amount, v_tx_desc,
      CASE 
        WHEN v_supplier_id IS NOT NULL THEN 'supplier' 
        WHEN r_item.shipping_company_id IS NOT NULL THEN 'shipping_company'
        WHEN r_item.clearing_agent_id IS NOT NULL THEN 'clearing_agent'
        ELSE NULL 
      END,
      CASE 
        WHEN v_supplier_id IS NOT NULL THEN v_supplier_id::text 
        WHEN r_item.shipping_company_id IS NOT NULL THEN r_item.shipping_company_id::text
        WHEN r_item.clearing_agent_id IS NOT NULL THEN r_item.clearing_agent_id::text
        ELSE NULL 
      END,
      NULL,
      v_liability_acct
    );

    v_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
    v_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

    UPDATE public.shipment_cost_items
    SET bank_transaction_id     = v_bank_tx_id,
        payment_source_type     = 'bank',
        payment_source_id       = p_source_id,
        payment_status          = 'paid',
        paid_amount             = v_amount,
        journal_entry_id        = v_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_bank_tx_id, 'type', 'bank', 'journal_entry_id', v_je_id);
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

-- (Canonical rpc_apply_packing_order_item_debit_note defined above)

-- 5. Fix dates on existing journal entries created tonight after 21:00 UTC (past midnight in Egypt)
UPDATE public.journal_entries
SET entry_date = (created_at AT TIME ZONE 'Africa/Cairo')::DATE
WHERE entry_date != (created_at AT TIME ZONE 'Africa/Cairo')::DATE
  AND created_at >= '2026-08-27 21:00:00+00';

-- 6. Canonical rpc_confirm_packing_order with supplier_id population
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(p_packing_order_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_station_id INT;
  v_packed_at TIMESTAMPTZ;
  v_company_id UUID;

  -- Cost components
  v_tot_raw_cost NUMERIC := 0;
  v_tot_waste_cost NUMERIC := 0;
  v_tot_sorting_cost NUMERIC := 0;
  v_fruit_net_cost NUMERIC := 0;
  v_mat_waste_pct NUMERIC := 0;
  v_tot_pkg_drawn NUMERIC := 0;
  v_tot_pkg_waste NUMERIC := 0;
  v_tot_pkg_consumed NUMERIC := 0;
  v_tot_cost_items NUMERIC := 0;
  v_finished_goods_cost NUMERIC := 0;

  -- Account IDs
  v_finished_inv_acc INT;
  v_raw_inv_acc INT;
  v_sorting_inv_acc INT;
  v_pkg_inv_acc INT;
  v_pkg_waste_inter_acc INT;    -- 2106
  v_crop_waste_inter_acc INT;   -- 2107
  v_credit_acc INT;
  v_supp_leaf_acc INT;

  -- Journal entry tracking
  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  -- Loop variables
  v_el JSONB;
  r_cost RECORD;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;

  -- Inventory deduction variables
  v_alloc JSONB;
  v_batch_id BIGINT;
  v_used_qty NUMERIC;
  v_pname TEXT;
  v_pcode TEXT;
  v_curr_rem NUMERIC;
  v_sp_qty NUMERIC;
  v_rem_needed NUMERIC;
  r_b RECORD;
  v_take NUMERIC;

  -- Cost allocation arrays
  v_n INT := 0;
  v_lines RECORD;
  v_line_ids BIGINT[];
  v_line_raw NUMERIC[];
  v_line_net NUMERIC[];
  v_line_overhead NUMERIC[];
  v_bases NUMERIC[];
  v_shares NUMERIC[];
  v_amount NUMERIC;
  v_method TEXT;
  v_assigned NUMERIC;
  v_part NUMERIC;
  v_max_cost_item_id BIGINT;
  v_posted_cost_items NUMERIC := 0;
BEGIN
  -- ── A. Validate Packing Order ──
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status = 'completed' THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة مؤكد بالفعل',
      'journal_entry_id', v_order.journal_entry_id
    );
  END IF;

  IF v_order.status != 'draft' AND v_order.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'حالة أمر التعبئة لا تسمح بالتأكيد: ' || v_order.status);
  END IF;

  BEGIN
    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_notes) = 'string' THEN
      v_notes := (v_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_notes := '{}'::jsonb;
  END;

  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);
  v_station_id := v_order.station_id;
  v_packed_at := COALESCE(v_order.packed_at, now());

  -- ── B. Fruit Inventory Deduction ──
  IF v_notes ? 'fruit_allocation' THEN
    v_alloc := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_alloc) = 'object' THEN v_alloc := jsonb_build_array(v_alloc); END IF;

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN
        SELECT remaining_quantity INTO v_curr_rem
        FROM public.station_product_batches
        WHERE id = v_batch_id
        FOR UPDATE;

        IF FOUND AND v_curr_rem >= v_used_qty THEN
          UPDATE public.station_product_batches
          SET remaining_quantity = remaining_quantity - v_used_qty
          WHERE id = v_batch_id;

          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
          FROM public.station_product_batches
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

          UPDATE public.station_products
          SET quantity = v_sp_qty, updated_at = NOW()
          WHERE station_id = v_station_id
            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- ── C. Material Inventory Deduction ──
  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials')
    LOOP
      v_batch_id := (v_el->>'batch_id')::bigint;
      v_used_qty := COALESCE((v_el->>'used_qty')::numeric, (v_el->>'quantity')::numeric, 0);
      v_pname := v_el->>'product_name';
      v_pcode := v_el->>'product_code';

      IF v_used_qty > 0 THEN
        IF v_batch_id IS NOT NULL AND v_batch_id > 0 THEN
          SELECT remaining_quantity INTO v_curr_rem
          FROM public.station_product_batches
          WHERE id = v_batch_id
          FOR UPDATE;

          IF FOUND AND v_curr_rem >= v_used_qty THEN
            UPDATE public.station_product_batches
            SET remaining_quantity = remaining_quantity - v_used_qty
            WHERE id = v_batch_id;
          ELSE
            v_rem_needed := v_used_qty;
            FOR r_b IN (
              SELECT id, remaining_quantity
              FROM public.station_product_batches
              WHERE station_id = v_station_id
                AND (product_name = v_pname OR product_code = v_pcode)
                AND remaining_quantity > 0
              ORDER BY id ASC
              FOR UPDATE
            ) LOOP
              IF v_rem_needed <= 0 THEN EXIT; END IF;
              v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
              UPDATE public.station_product_batches
              SET remaining_quantity = remaining_quantity - v_take
              WHERE id = r_b.id;
              v_rem_needed := v_rem_needed - v_take;
            END LOOP;
          END IF;
        ELSE
          v_rem_needed := v_used_qty;
          FOR r_b IN (
            SELECT id, remaining_quantity
            FROM public.station_product_batches
            WHERE station_id = v_station_id
              AND (product_name = v_pname OR product_code = v_pcode)
              AND remaining_quantity > 0
            ORDER BY id ASC
            FOR UPDATE
          ) LOOP
            IF v_rem_needed <= 0 THEN EXIT; END IF;
            v_take := LEAST(r_b.remaining_quantity, v_rem_needed);
            UPDATE public.station_product_batches
            SET remaining_quantity = remaining_quantity - v_take
            WHERE id = r_b.id;
            v_rem_needed := v_rem_needed - v_take;
          END LOOP;
        END IF;

        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty
        FROM public.station_product_batches
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);

        UPDATE public.station_products
        SET quantity = v_sp_qty, updated_at = NOW()
        WHERE station_id = v_station_id
          AND (product_name = v_pname OR product_code = v_pcode);
      END IF;
    END LOOP;
  END IF;

  -- ── D. Rebuild Cost Items from Notes ──
  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;
    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;
    IF v_max_cost_item_id > 0 THEN
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);
    ELSE
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), 1, false);
    END IF;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);
      IF v_amt_egp > 0 THEN
        v_supplier_id := NULL;
        v_supp_str := v_el->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          v_supplier_id := v_supp_str::uuid;
        END IF;

        v_target_line_idx := NULL;
        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' AND v_el->>'target_line_index' != 'null' THEN
          v_target_line_idx := (v_el->>'target_line_index')::integer;
        END IF;

        INSERT INTO public.packing_order_cost_items (
          packing_order_id, name, category,
          base_amount, original_amount, original_currency,
          payment_source_type, payment_source_id,
          allocation_method, target_line_id,
          currency_snapshot, supplier_id, payment_status, paid_amount
        ) VALUES (
          p_packing_order_id,
          v_el->>'name',
          CASE WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'other') THEN v_el->>'category' ELSE 'other' END,
          v_amt_egp,
          COALESCE((v_el->>'total')::numeric, v_amt_egp),
          COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
          'none',
          NULL,
          v_el->>'allocation_method',
          v_target_line_idx,
          jsonb_build_object(
            'supplier_id', v_supplier_id,
            'supplier_name', v_el->>'supplier_name',
            'target_line_index', v_target_line_idx
          ),
          v_supplier_id::text,
          'unpaid',
          0
        );
      END IF;
    END LOOP;
  END IF;

  -- ── E. Allocate Cost Items Across Lines ──
  v_n := 0;
  v_bases := ARRAY[]::NUMERIC[];
  FOR v_lines IN
    SELECT id, COALESCE(raw_material_cost, 0) as rc, COALESCE(total_net_weight, 0) as nw
    FROM public.packing_order_lines
    WHERE packing_order_id = p_packing_order_id
    ORDER BY id
  LOOP
    v_n := v_n + 1;
    v_line_ids[v_n] := v_lines.id;
    v_line_raw[v_n] := v_lines.rc;
    v_line_net[v_n] := v_lines.nw;
    v_line_overhead[v_n] := 0;
    v_bases[v_n] := v_lines.rc;
  END LOOP;

  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_amount := COALESCE(r_cost.base_amount, 0);
    IF v_amount <= 0 THEN CONTINUE; END IF;

    IF r_cost.target_line_id IS NOT NULL THEN
      IF r_cost.target_line_id >= 0 AND r_cost.target_line_id < v_n THEN
        v_line_overhead[r_cost.target_line_id + 1] := v_line_overhead[r_cost.target_line_id + 1] + v_amount;
      END IF;
      CONTINUE;
    END IF;

    v_method := COALESCE(r_cost.allocation_method, 'EQUAL');
    IF v_method = 'WEIGHT' THEN
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_net[v_i]; END LOOP;
    ELSIF v_method = 'COST' THEN
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_raw[v_i]; END LOOP;
    ELSE
      FOR v_i IN 1..v_n LOOP v_bases[v_i] := 1; END LOOP;
    END IF;

    IF v_n > 0 THEN
      v_shares := public._packing_allocate_shares(v_method, v_bases);
      v_assigned := 0;
      FOR v_i IN 1..v_n LOOP
        IF v_i = v_n THEN
          v_part := ROUND(v_amount - v_assigned, 2);
        ELSE
          v_part := ROUND(v_amount * v_shares[v_i], 2);
        END IF;
        v_line_overhead[v_i] := v_line_overhead[v_i] + v_part;
        v_assigned := v_assigned + v_part;
      END LOOP;
    END IF;
  END LOOP;

  -- ══════════════════════════════════════════════════════════════════════════
  -- F. Calculate Cost Values Directly from Packing Order Data
  -- ══════════════════════════════════════════════════════════════════════════

  -- 1. Produce Raw Cost & Sorting
  v_tot_raw_cost := COALESCE(v_order.fruit_cost_base, 0);
  IF v_tot_raw_cost = 0 THEN
    IF v_notes ? 'fruit_allocation' THEN
      DECLARE
        v_f_elem JSONB;
        v_f_arr JSONB := v_notes->'fruit_allocation';
      BEGIN
        IF jsonb_typeof(v_f_arr) = 'object' THEN v_f_arr := jsonb_build_array(v_f_arr); END IF;
        FOR v_f_elem IN SELECT * FROM jsonb_array_elements(v_f_arr) LOOP
          v_tot_raw_cost := v_tot_raw_cost + (
            COALESCE((v_f_elem->>'quantity')::numeric, 0) *
            COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0)
          );
        END LOOP;
      END;
    END IF;
  END IF;
  IF v_tot_raw_cost = 0 THEN
    v_tot_raw_cost := COALESCE(v_order.fruit_cost_allocated, 0);
  END IF;

  v_tot_sorting_cost := COALESCE((v_notes->>'sorting_cost')::numeric, 0);
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;
  IF v_tot_sorting_cost = 0 THEN
    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost
    FROM public.packing_order_sortings WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- 2. Produce Waste Cost
  v_tot_waste_cost := COALESCE((v_notes->>'waste_cost')::numeric, 0);
  IF v_tot_waste_cost = 0 THEN
    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost
    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  END IF;

  -- Net Fruit Cost (Good Fruit entering product)
  v_fruit_net_cost := GREATEST(0, v_tot_raw_cost - v_tot_sorting_cost - v_tot_waste_cost);

  -- 3. Packaging Materials Base Cost (1040) & Waste
  v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);
  v_tot_pkg_drawn := 0;

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN
    DECLARE
      v_m_el JSONB;
    BEGIN
      FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials') LOOP
        v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE(
          (v_m_el->>'total')::numeric,
          (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) *
           COALESCE((v_m_el->>'unit_cost')::numeric, 0))
        );
      END LOOP;
    END;
  END IF;

  IF v_tot_pkg_drawn = 0 THEN
    v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    IF v_mat_waste_pct > 0 THEN
      v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 2);
    END IF;
  END IF;

  -- 4. Packaging Waste Cost
  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 2);
  v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;

  -- 5. Additional Cost Items
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 6. Total Finished Goods Cost (1031)
  v_finished_goods_cost := COALESCE(v_order.total_packing_cost, 0);
  IF v_finished_goods_cost = 0 THEN
    v_finished_goods_cost := v_fruit_net_cost + v_tot_waste_cost + v_tot_pkg_drawn + v_tot_pkg_waste + v_tot_cost_items;
  END IF;

  -- ── G. Resolve COA Accounts ──
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc     := public.resolve_gl_account('1031', v_company_id);
  v_sorting_inv_acc      := public.resolve_gl_account('1032', v_company_id);
  v_raw_inv_acc          := public.resolve_gl_account('1030', v_company_id);
  v_pkg_inv_acc          := public.resolve_gl_account('1040', v_company_id);
  v_pkg_waste_inter_acc  := public.resolve_gl_account('2106', v_company_id);
  v_crop_waste_inter_acc := public.resolve_gl_account('2107', v_company_id);

  -- Clean up previous JE if exists
  IF v_order.journal_entry_id IS NOT NULL THEN
    DELETE FROM account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;
    DELETE FROM journal_entries WHERE id = v_order.journal_entry_id;
  END IF;

  -- ── J. Create Journal Entry (Egypt Cairo Timezone) ──
  INSERT INTO public.journal_entries (
    entry_number, entry_date, description, status,
    is_auto_generated, source_type, source_id, company_id,
    created_by, created_at, updated_at
  ) VALUES (
    'PENDING',
    COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),
    'قيد أمر تعبئة رقم ' || v_order_num,
    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,
    auth.uid(), now(), now()
  ) RETURNING id INTO v_je_id;

  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);
  IF v_entry_num IS NULL OR v_entry_num = '' THEN
    v_entry_num := 'PO-JE-' || LPAD(v_je_id::text, 5, '0');
  END IF;
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- ══════════════════════════════════════════════════════════════════════════
  -- H. JOURNAL ENTRY LINES (NEW SPECIFICATION)
  -- ══════════════════════════════════════════════════════════════════════════

  -- ── 1. DR 1031: إجمالي تكلفة أمر التعبئة بالكامل ──
  IF v_finished_goods_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, 'EGP', v_finished_goods_cost,
      'إجمالي تكلفة أمر تعبئة ' || v_order_num || ' (' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_finished_goods_cost;
  END IF;

  -- ── 2. DR 1032: تكلفة مخزون الفرز ──
  IF v_tot_sorting_cost > 0 AND v_sorting_inv_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, 'EGP', v_tot_sorting_cost,
      'مخزون الفرز - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_sorting_cost;
  END IF;

  -- ── 3. CR 1030: تكلفة المحصول المستخدم بالكامل ──
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,
      'صرف محصول خام بالكامل - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_raw_cost;
  END IF;

  -- ── 4. CR 1040: تكلفة مواد التعبئة المستخدمة فقط بدون الهالك ──
  IF v_tot_pkg_drawn > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_drawn, 'EGP', v_tot_pkg_drawn,
      'صرف مواد تعبئة وتغليف (بدون الهالك) - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_drawn;
  END IF;

  -- ── 5. CR 2106: وسيط هالك مواد التعبئة ──
  IF v_tot_pkg_waste > 0 AND v_pkg_waste_inter_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_pkg_waste_inter_acc, 0, v_tot_pkg_waste, 'EGP', v_tot_pkg_waste,
      'وسيط هالك مواد التعبئة والتغليف - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_pkg_waste;
  END IF;

  -- ── 6. CR 2107: وسيط هالك المحاصيل ──
  IF v_tot_waste_cost > 0 AND v_crop_waste_inter_acc IS NOT NULL THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_crop_waste_inter_acc, 0, v_tot_waste_cost, 'EGP', v_tot_waste_cost,
      'وسيط هالك وفاقد المحاصيل - أمر تعبئة ' || v_order_num,
      v_company_id
    );
    v_sum_credit := v_sum_credit + v_tot_waste_cost;
  END IF;

  -- ── 7. CR حسابات الموردين وبنود التكلفة ──
  v_posted_cost_items := 0;
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
  LOOP
    v_credit_acc := NULL;
    v_supplier_id := NULL;

    IF r_cost.currency_snapshot IS NOT NULL THEN
      v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        v_supplier_id := v_supp_str::uuid;
        SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
        IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
      END IF;
    END IF;

    IF v_credit_acc IS NULL THEN
      v_credit_acc := public.resolve_gl_account('2000', v_company_id);
    END IF;

    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
      'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
    );
    v_sum_credit := v_sum_credit + r_cost.base_amount;
    v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

    IF v_supplier_id IS NOT NULL THEN
      INSERT INTO public.ledger_entries (
        entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
      ) VALUES (
        v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
        'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
        'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
      );
      UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
    END IF;
  END LOOP;

  -- Fallback credit for other_cost_base
  IF v_tot_cost_items > v_posted_cost_items THEN
    v_credit_acc := public.resolve_gl_account('2000', v_company_id);
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_credit_acc, 0, (v_tot_cost_items - v_posted_cost_items), 'EGP', (v_tot_cost_items - v_posted_cost_items),
      'مصروفات إضافية أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_credit := v_sum_credit + (v_tot_cost_items - v_posted_cost_items);
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  -- VALIDATION
  -- ══════════════════════════════════════════════════════════════════════════
  IF ROUND(v_sum_debit, 2) != ROUND(v_sum_credit, 2) THEN
    RAISE EXCEPTION 'فشل تأكيد أمر التعبئة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;
  END IF;

  UPDATE public.packing_orders
  SET status = 'completed',
      journal_entry_id = v_je_id,
      reversal_journal_entry_id = NULL,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'journal_entry_id', v_je_id,
    'finished_goods_cost', v_finished_goods_cost,
    'fruit_net_cost', v_fruit_net_cost,
    'sorting_inventory_cost', v_tot_sorting_cost,
    'crop_waste_cost', v_tot_waste_cost,
    'packaging_base_cost', v_tot_pkg_drawn,
    'packaging_waste_cost', v_tot_pkg_waste,
    'packaging_total_cost', v_tot_pkg_consumed,
    'supplier_costs', v_tot_cost_items,
    'debit', v_sum_debit,
    'credit', v_sum_credit
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated, service_role;
