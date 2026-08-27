-- ============================================================================
-- SEED_MASTER_DATA.sql — Enterprise ERP Master Data Initialization
-- ============================================================================
-- Purpose: Seed ALL reference/master data for first-run database setup.
-- Safe:    Idempotent — can be run multiple times without duplicates.
-- Scope:   Reference data ONLY — no schema changes, no DDL.
-- Order:   FK-safe seeding order (parents before children).
--
-- Usage:   Run AFTER all migrations are applied.
--          SELECT * FROM verify_database();  -- confirm all PASS first
--          Then run this file.
--
-- Returns: Verification report via RAISE NOTICE at the end.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. CURRENCIES
-- ============================================================================

INSERT INTO public.currencies (code, name, name_ar, symbol, is_base, is_active)
SELECT v.code, v.name, v.name_ar, v.symbol, v.is_base, v.is_active
FROM (VALUES
  ('EGP', 'Egyptian Pound',       'جنيه مصري',           'ج.م',  true,  true),
  ('USD', 'US Dollar',            'دولار أمريكي',         '$',    false, true),
  ('EUR', 'Euro',                 'يورو',                '€',    false, true),
  ('GBP', 'British Pound',        'جنيه إسترليني',       '£',    false, true),
  ('SAR', 'Saudi Riyal',          'ريال سعودي',          'ر.س',  false, true),
  ('AED', 'UAE Dirham',           'درهم إماراتي',        'د.إ',  false, true)
) AS v(code, name, name_ar, symbol, is_base, is_active)
WHERE NOT EXISTS (SELECT 1 FROM public.currencies c WHERE c.code = v.code);

-- ============================================================================
-- 2. EXCHANGE RATES
-- ============================================================================

INSERT INTO public.exchange_rates (currency_code, currency_name, rate_to_egp, updated_at)
SELECT v.currency_code, v.currency_name, v.rate_to_egp, NOW()
FROM (VALUES
  ('USD', 'الدولار الأمريكي',   50.00),
  ('EUR', 'اليورو الأوروبي',    50.00),
  ('GBP', 'الجنيه الاسترليني',  60.00),
  ('SAR', 'الريال السعودي',    13.50),
  ('AED', 'الدرهم الإماراتي',   13.70)
) AS v(currency_code, currency_name, rate_to_egp)
WHERE NOT EXISTS (SELECT 1 FROM public.exchange_rates er WHERE er.currency_code = v.currency_code);

-- ============================================================================
-- 3. CHART OF ACCOUNTS (18 accounts — canonical from migration 284)
-- ============================================================================

INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, sort_order)
SELECT v.account_code, v.name, v.account_name, v.account_type, true, v.sort_order
FROM (VALUES
  -- Assets
  ('1000',  'Cash',                         'الصندوق',                         'asset',     1000),
  ('1010',  'Bank',                         'البنك',                           'asset',     1010),
  ('1020',  'Accounts Receivable',          'العملاء (مدينون)',                'asset',     1020),
  ('1030',  'Inventory',                    'المخزون',                         'asset',     1030),
  ('1040',  'Packing Materials Inventory',  'مخزون التعبئة',                  'asset',     1040),
  ('1050',  'Export Expenses',              'مصروفات التصدير',                'expense',   1050),
  ('11101', 'Main Treasury - EGP',          'الخزينة الرئيسية - جنيه',        'asset',     11101),
  ('11102', 'Main Treasury - USD',          'الخزينة الرئيسية - دولار',       'asset',     11102),
  ('11103', 'Main Treasury - EUR',          'الخزينة الرئيسية - يورو',        'asset',     11103),
  ('11104', 'Main Treasury - GBP',          'الخزينة الرئيسية - جنيه إسترليني','asset',    11104),
  -- Liabilities
  ('2000',  'Accounts Payable',             'الموردون (دائنون)',               'liability', 2000),
  -- Equity
  ('3000',  'Owner Equity',                 'رأس مال المالك',                 'equity',    3000),
  ('3100',  'Retained Earnings',            'الأرباح المحتجزة',               'equity',    3100),
  ('3200',  'Current Year Earnings',        'أرباح السنة الجارية',            'equity',    3200),
  -- Revenue
  ('4000',  'Sales Revenue',                'إيرادات المبيعات',               'revenue',   4000),
  -- Expenses
  ('5000',  'Cost of Goods Sold',           'تكلفة البضاعة المباعة',          'expense',   5000),
  ('6000',  'Expenses',                     'المصروفات',                      'expense',   6000),
  ('7000',  'Purchase Account',             'حساب المشتريات',                 'expense',   7000)
) AS v(account_code, name, account_name, account_type, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.account_code = v.account_code);

-- ============================================================================
-- 4. BANK ACCOUNTS (one per currency)
-- ============================================================================

INSERT INTO public.bank_accounts (name, name_en, currency)
SELECT v.name, v.name_en, v.currency
FROM (VALUES
  ('الجنيه المصري',       'Egyptian Pound',  'EGP'),
  ('الدولار الأمريكي',     'US Dollar',       'USD'),
  ('اليورو',               'Euro',            'EUR'),
  ('الجنيه الإسترليني',    'British Pound',   'GBP')
) AS v(name, name_en, currency)
WHERE NOT EXISTS (SELECT 1 FROM public.bank_accounts ba WHERE ba.currency = v.currency);

-- ============================================================================
-- 5. WAREHOUSES
-- ============================================================================

INSERT INTO public.warehouses (name, name_en, address, city, country, is_active)
SELECT v.name, v.name_en, v.address, v.city, v.country, true
FROM (VALUES
  ('المستودع الرئيسي',  'Main Warehouse',  'المنطقة الصناعية', 'القاهرة',    'Egypt'),
  ('مستودع التصدير',     'Export Warehouse', 'ميناء الإسكندرية', 'الإسكندرية', 'Egypt'),
  ('مستودع التجميد',     'Cold Storage',     'المنطقة الصناعية', 'القاهرة',    'Egypt')
) AS v(name, name_en, address, city, country)
WHERE NOT EXISTS (SELECT 1 FROM public.warehouses w WHERE w.name = v.name);

-- ============================================================================
-- 6. PRODUCT CATEGORIES (main categories + subcategories)
-- ============================================================================

-- 6a. Main categories (parent_id = NULL)
INSERT INTO public.product_categories (id, name, name_en, icon, color, sort_order, category_type, is_active)
SELECT v.id::uuid, v.name, v.name_en, v.icon, v.color, v.sort_order, 'material', true
FROM (VALUES
  ('a1000000-0000-0000-0000-000000000001', 'فواكه طازجة',      'Fresh Fruits',          'eco',              '#66BB6A', 1),
  ('a1000000-0000-0000-0000-000000000002', 'مواد تغليف',        'Packaging Materials',   'inventory_2',      '#42A5F5', 2),
  ('a1000000-0000-0000-0000-000000000003', 'خامات',              'Raw Materials',         'science',          '#AB47BC', 3),
  ('a1000000-0000-0000-0000-000000000004', 'منتجات تصديرية',     'Export Products',       'local_shipping',   '#FF7043', 4),
  ('a1000000-0000-0000-0000-000000000005', 'مواد استهلاكية',     'Consumables',           'shopping_bag',     '#FFCA28', 5)
) AS v(id, name, name_en, icon, color, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.product_categories pc WHERE pc.id = v.id::uuid);

-- 6b. Fruit subcategories
INSERT INTO public.product_categories (id, name, name_en, parent_id, icon, color, sort_order, category_type, is_active)
SELECT v.id::uuid, v.name, v.name_en, 'a1000000-0000-0000-0000-000000000001'::uuid, v.icon, v.color, v.sort_order, 'fruit', true
FROM (VALUES
  ('b1000000-0000-0000-0000-000000000001', 'مانجو',    'Mango',        'eco', '#FFA726', 1),
  ('b1000000-0000-0000-0000-000000000002', 'برتقال',    'Orange',       'eco', '#FF9800', 2),
  ('b1000000-0000-0000-0000-000000000003', 'عنب',       'Grapes',       'eco', '#7B1FA2', 3),
  ('b1000000-0000-0000-0000-000000000004', 'رمان',      'Pomegranate',  'eco', '#C62828', 4),
  ('b1000000-0000-0000-0000-000000000005', 'موز',       'Banana',       'eco', '#FDD835', 5),
  ('b1000000-0000-0000-0000-000000000006', 'فراولة',    'Strawberry',   'eco', '#E53935', 6),
  ('b1000000-0000-0000-0000-000000000007', 'كيوي',      'Kiwi',         'eco', '#689F38', 7),
  ('b1000000-0000-0000-0000-000000000008', 'جوافة',     'Guava',        'eco', '#8BC34A', 8),
  ('b1000000-0000-0000-0000-000000000009', 'ليمون',     'Lemon',        'eco', '#FDD835', 9),
  ('b1000000-0000-0000-0000-000000000010', 'خوخ',       'Peach',        'eco', '#FF8F00', 10),
  ('b1000000-0000-0000-0000-000000000011', 'مشمش',      'Apricot',      'eco', '#FF6F00', 11),
  ('b1000000-0000-0000-0000-000000000012', 'بطيخ',      'Watermelon',   'eco', '#43A047', 12)
) AS v(id, name, name_en, icon, color, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.product_categories pc WHERE pc.id = v.id::uuid);

-- 6c. Packaging subcategories
INSERT INTO public.product_categories (id, name, name_en, parent_id, icon, color, sort_order, category_type, is_active)
SELECT v.id::uuid, v.name, v.name_en, 'a1000000-0000-0000-0000-000000000002'::uuid, v.icon, v.color, v.sort_order, 'material', true
FROM (VALUES
  ('c1000000-0000-0000-0000-000000000001', 'كراتين',           'Cartons',       'inventory_2', '#42A5F5', 1),
  ('c1000000-0000-0000-0000-000000000002', 'لفافات بلاستيك',   'Plastic Wrap',  'inventory_2', '#26C6DA', 2),
  ('c1000000-0000-0000-0000-000000000003', 'ملصقات',            'Stickers',      'inventory_2', '#7E57C2', 3),
  ('c1000000-0000-0000-0000-000000000004', 'فوم',               'Foam',          'inventory_2', '#78909C', 4),
  ('c1000000-0000-0000-0000-000000000005', 'شريط لاصق',         'Tape',          'inventory_2', '#8D6E63', 5)
) AS v(id, name, name_en, icon, color, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.product_categories pc WHERE pc.id = v.id::uuid);

-- 6d. Raw Materials subcategories
INSERT INTO public.product_categories (id, name, name_en, parent_id, sort_order, category_type, is_active)
SELECT v.id::uuid, v.name, v.name_en, 'a1000000-0000-0000-0000-000000000003'::uuid, v.sort_order, 'material', true
FROM (VALUES
  ('d1000000-0000-0000-0000-000000000001', 'مبيدات',           'Pesticides',           1),
  ('d1000000-0000-0000-0000-000000000002', 'سماد',             'Fertilizer',           2),
  ('d1000000-0000-0000-0000-000000000003', 'مواد تنظيف',        'Cleaning Materials',   3)
) AS v(id, name, name_en, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.product_categories pc WHERE pc.id = v.id::uuid);

-- ============================================================================
-- 7. RAW MATERIAL CATEGORIES
-- ============================================================================

INSERT INTO public.raw_material_categories (name)
SELECT v.name
FROM (VALUES
  ('مواد تعبئة'),
  ('مواد أولية'),
  ('مواد كيميائية'),
  ('قطع غيار')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM public.raw_material_categories rmc WHERE rmc.name = v.name);

-- ============================================================================
-- 8. EXPENSE CATEGORIES
-- ============================================================================

INSERT INTO public.expense_categories (name, color, is_active)
SELECT v.name, v.color, true
FROM (VALUES
  ('مصروفات إدارية',   '#F59E0B', true),
  ('مصروفات نقل',       '#448AFF', true),
  ('مصروفات صيانة',     '#EC4899', true),
  ('مصروفات إنتاج',     '#10B981', true),
  ('مصروفات تسويق',     '#8B5CF6', true),
  ('مصروفات متنوعة',    '#6B7280', true)
) AS v(name, color)
WHERE NOT EXISTS (SELECT 1 FROM public.expense_categories ec WHERE ec.name = v.name);

-- ============================================================================
-- 9. COST REPORT CATEGORIES
-- ============================================================================

INSERT INTO public.cost_report_categories (name, type)
SELECT v.name, v.type
FROM (VALUES
  ('محاصيل',              'direct'),
  ('تعبئة وتغليف',       'direct'),
  ('لوجستيك ونقل',       'direct'),
  ('مصاريف إدارية',       'indirect')
) AS v(name, type)
WHERE NOT EXISTS (SELECT 1 FROM public.cost_report_categories crc WHERE crc.name = v.name);

-- ============================================================================
-- 10. UNIT CONVERSIONS (global — product_id is NULL)
-- ============================================================================

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
  WHERE uc.from_unit = v.from_unit
    AND uc.to_unit = v.to_unit
    AND uc.product_id IS NULL
);

-- ============================================================================
-- 11. INVOICE NUMBERING (auto-numbering templates)
-- ============================================================================

INSERT INTO public.invoice_numbering (entity_type, prefix, next_number, pad_length)
SELECT v.entity_type, v.prefix, v.next_number, v.pad_length
FROM (VALUES
  ('sales_invoice',    'INV-', 1, 4),
  ('purchase_invoice', 'PUR-', 1, 4),
  ('export_shipment',  'EXP-', 1, 4)
) AS v(entity_type, prefix, next_number, pad_length)
WHERE NOT EXISTS (SELECT 1 FROM public.invoice_numbering inv WHERE inv.entity_type = v.entity_type);

-- ============================================================================
-- 12. COMPANY PROFILE (single row)
-- ============================================================================

INSERT INTO public.company_profile (company_name, base_currency)
SELECT 'شركتي', 'EGP'
WHERE NOT EXISTS (SELECT 1 FROM public.company_profile);

-- ============================================================================
-- 13. FISCAL YEAR (current year)
-- ============================================================================

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

-- ============================================================================
-- 14. SUBSCRIPTION PLANS
-- ============================================================================

INSERT INTO public.subscription_plans (name, price_egp, duration_months, max_users, period)
SELECT v.name, v.price_egp, v.duration_months, v.max_users, v.period
FROM (VALUES
  ('تجريبي',   0,     1,  3,  'monthly'),
  ('أساسي',    500,   1,  5,  'monthly'),
  ('متقدم',    1500,  1,  15, 'monthly'),
  ('مؤسسي',    8000,  12, 50, 'yearly')
) AS v(name, price_egp, duration_months, max_users, period)
WHERE NOT EXISTS (SELECT 1 FROM public.subscription_plans sp WHERE sp.name = v.name);

-- ============================================================================
-- 15. DEFAULT TENANT
-- ============================================================================

INSERT INTO public.tenants (name, email, tenant_type, is_active, max_users)
SELECT 'الحساب الرئيسي', 'admin@erp.local', 'erp', true, 50
WHERE NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.email = 'admin@erp.local');

-- ============================================================================
-- 16. SYSTEM SETTINGS (comprehensive defaults)
-- ============================================================================

INSERT INTO public.system_settings (setting_key, setting_value, description)
SELECT v.key, v.value, v.description
FROM (VALUES
  -- Company
  ('company_name',        'Fruity Farms ERP',         'اسم النظام'),
  ('company_name_ar',     'فروتي فارمز',              'اسم النظام بالعربية'),
  -- Currency
  ('currency',            'EGP',                      'العملة الافتراضية'),
  ('base_currency',       'EGP',                      'العملة الأساسية'),
  -- Fiscal Year
  ('fiscal_year_start',   '1',                        'شهر بداية السنة المالية'),
  -- Localization
  ('language',            'ar',                       'اللغة الافتراضية'),
  ('theme',               'light',                    'المظهر الافتراضي'),
  ('timezone',            'Africa/Cairo',             'المنطقة الزمنية'),
  ('date_format',         'dd/MM/yyyy',               'تنسيق التاريخ'),
  ('currency_format',     '#,##0.00',                 'تنسيق العملة'),
  ('decimals',            '2',                        'عدد الكسور العشرية'),
  -- Trial
  ('trial_days',          '7',                        'عدد أيام الفترة التجريبية'),
  ('trial_minutes',       '0',                        'عدد دقائق الفترة التجريبية'),
  -- Inventory
  ('inventory_method',    'weighted_average',         'طريقة تقييم المخزون'),
  -- Auto Numbering
  ('auto_numbering',      'true',                     'تفعيل الترقيم التلقائي'),
  -- Backup
  ('backup_enabled',      'true',                     'تفعيل النسخ الاحتياطي'),
  ('backup_frequency',    'daily',                    'تكرار النسخ الاحتياطي'),
  -- Notifications
  ('notifications_enabled', 'true',                   'تفعيل الإشعارات'),
  -- Tax
  ('tax_enabled',         'false',                    'تفعيل الضرائب'),
  ('tax_rate',            '14',                       'نسبة ضريبة القيمة المضافة'),
  -- Exchange Rate
  ('exchange_rate_auto',  'true',                     'تحديث أسعار الصرف تلقائياً'),
  -- Dashboard
  ('dashboard_refresh',   '300',                      'فترة تحديث Dashboard بالثواني'),
  -- Security
  ('session_timeout',     '60',                       'مدة انتهاء الجلسة بالدقائق'),
  ('max_login_attempts',  '5',                        'عدد محاولات تسجيل الدخول القصوى')
) AS v(key, value, description)
WHERE NOT EXISTS (SELECT 1 FROM public.system_settings ss WHERE ss.setting_key = v.key);

-- ============================================================================
-- 17. TREASURIES (default main treasury)
-- ============================================================================

INSERT INTO public.treasuries (name, type, notes)
SELECT 'الخزينة الرئيسية', 'main', 'الخزينة الافتراضية للنظام'
WHERE NOT EXISTS (SELECT 1 FROM public.treasuries t WHERE t.name = 'الخزينة الرئيسية' AND t.type = 'main');

-- ============================================================================
-- 18. TREASURY BALANCES (one row per currency for main treasury)
-- ============================================================================

INSERT INTO public.treasury_balances (treasury_id, currency, balance)
SELECT t.id, v.currency, 0.00
FROM (VALUES ('EGP'), ('USD'), ('EUR'), ('GBP')) AS v(currency)
CROSS JOIN public.treasuries t
WHERE t.name = 'الخزينة الرئيسية' AND t.type = 'main'
  AND NOT EXISTS (
    SELECT 1 FROM public.treasury_balances tb
    WHERE tb.treasury_id = t.id AND tb.currency = v.currency
  );

-- ============================================================================
-- 19. TREASURY-ACCOUNT LINKS
-- ============================================================================
-- NOTE: treasury_balances.account_id (added in migration 041) already links
-- each treasury balance row to a GL account. No separate treasury_accounts
-- table exists in the schema. The account_id is set when the treasury is
-- created via the create_treasury() RPC, which links to the correct GL
-- account code (11101-11104) based on currency.

-- ============================================================================
-- 20. BACKFILL PUBLIC.USERS FROM AUTH.USERS (if any users exist)
-- ============================================================================

INSERT INTO public.users (id, full_name, email, username, is_admin)
SELECT
  au.id,
  COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.email, '@', 1)),
  au.email,
  split_part(au.email, '@', 1),
  false
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
WHERE pu.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- COMMIT
-- ============================================================================

COMMIT;

-- ============================================================================
-- VERIFICATION REPORT
-- ============================================================================

DO $$
DECLARE
  v_accounts INT;
  v_currencies INT;
  v_exchange_rates INT;
  v_bank_accounts INT;
  v_warehouses INT;
  v_categories INT;
  v_expense_cats INT;
  v_cost_cats INT;
  v_unit_conv INT;
  v_invoice_num INT;
  v_company INT;
  v_fiscal_years INT;
  v_plans INT;
  v_tenants INT;
  v_settings INT;
  v_treasuries INT;
  v_treasury_balances INT;
  v_raw_mat_cats INT;
BEGIN
  SELECT COUNT(*) INTO v_accounts FROM public.accounts;
  SELECT COUNT(*) INTO v_currencies FROM public.currencies;
  SELECT COUNT(*) INTO v_exchange_rates FROM public.exchange_rates;
  SELECT COUNT(*) INTO v_bank_accounts FROM public.bank_accounts;
  SELECT COUNT(*) INTO v_warehouses FROM public.warehouses;
  SELECT COUNT(*) INTO v_categories FROM public.product_categories;
  SELECT COUNT(*) INTO v_expense_cats FROM public.expense_categories;
  SELECT COUNT(*) INTO v_cost_cats FROM public.cost_report_categories;
  SELECT COUNT(*) INTO v_unit_conv FROM public.unit_conversions WHERE product_id IS NULL;
  SELECT COUNT(*) INTO v_invoice_num FROM public.invoice_numbering;
  SELECT COUNT(*) INTO v_company FROM public.company_profile;
  SELECT COUNT(*) INTO v_fiscal_years FROM public.fiscal_years;
  SELECT COUNT(*) INTO v_plans FROM public.subscription_plans;
  SELECT COUNT(*) INTO v_tenants FROM public.tenants;
  SELECT COUNT(*) INTO v_settings FROM public.system_settings;
  SELECT COUNT(*) INTO v_treasuries FROM public.treasuries;
  SELECT COUNT(*) INTO v_treasury_balances FROM public.treasury_balances;
  SELECT COUNT(*) INTO v_raw_mat_cats FROM public.raw_material_categories;

  RAISE NOTICE '';
  RAISE NOTICE '================================================================';
  RAISE NOTICE '          MASTER DATA SEEDING REPORT';
  RAISE NOTICE '================================================================';
  RAISE NOTICE '  %-30s %s rows', 'Accounts (Chart of Accounts):', v_accounts;
  RAISE NOTICE '  %-30s %s rows', 'Currencies:', v_currencies;
  RAISE NOTICE '  %-30s %s rows', 'Exchange Rates:', v_exchange_rates;
  RAISE NOTICE '  %-30s %s rows', 'Bank Accounts:', v_bank_accounts;
  RAISE NOTICE '  %-30s %s rows', 'Warehouses:', v_warehouses;
  RAISE NOTICE '  %-30s %s rows', 'Product Categories:', v_categories;
  RAISE NOTICE '  %-30s %s rows', 'Raw Material Categories:', v_raw_mat_cats;
  RAISE NOTICE '  %-30s %s rows', 'Expense Categories:', v_expense_cats;
  RAISE NOTICE '  %-30s %s rows', 'Cost Report Categories:', v_cost_cats;
  RAISE NOTICE '  %-30s %s rows', 'Unit Conversions:', v_unit_conv;
  RAISE NOTICE '  %-30s %s rows', 'Invoice Numbering:', v_invoice_num;
  RAISE NOTICE '  %-30s %s rows', 'Company Profile:', v_company;
  RAISE NOTICE '  %-30s %s rows', 'Fiscal Years:', v_fiscal_years;
  RAISE NOTICE '  %-30s %s rows', 'Subscription Plans:', v_plans;
  RAISE NOTICE '  %-30s %s rows', 'Tenants:', v_tenants;
  RAISE NOTICE '  %-30s %s rows', 'System Settings:', v_settings;
  RAISE NOTICE '  %-30s %s rows', 'Treasuries:', v_treasuries;
  RAISE NOTICE '  %-30s %s rows', 'Treasury Balances:', v_treasury_balances;
  RAISE NOTICE '================================================================';

  IF v_accounts >= 18 AND v_currencies >= 4 AND v_settings >= 10 THEN
    RAISE NOTICE '  MASTER DATA READY';
  ELSE
    RAISE NOTICE '  WARNING: Some master data may be incomplete';
  END IF;

  RAISE NOTICE '================================================================';
  RAISE NOTICE '';
END $$;
