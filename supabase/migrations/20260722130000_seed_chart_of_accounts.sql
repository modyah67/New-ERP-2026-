-- ============================================================================
-- Full Chart of Accounts — Restores all 18 accounts across all migrations
-- Source: migrations 011, 012, 041, 058, 062, 266, 281
-- Run this in Supabase SQL Editor
-- ============================================================================

INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, sort_order)
SELECT v.account_code, v.name, v.account_name, v.account_type, true, v.sort_order
FROM (VALUES
  -- ═══════════════════════════════════════
  -- الأصول (Assets)
  -- ═══════════════════════════════════════
  ('1000', 'Cash',                         'الصندوق',                       'asset',     1000),
  ('1010', 'Bank',                         'البنك',                         'asset',     1010),
  ('1020', 'Accounts Receivable',          'العملاء (مدينون)',              'asset',     1020),
  ('1030', 'Inventory',                    'المخزون',                       'asset',     1030),
  ('1040', 'Packing Materials Inventory',  'مخزون التعبئة',                'asset',     1040),
  ('1050', 'Export Expenses',              'مصروفات التصدير',              'expense',   1050),
  ('11101','Main Treasury - EGP',          'الخزينة الرئيسية - جنيه',      'asset',     11101),
  ('11102','Main Treasury - USD',          'الخزينة الرئيسية - دولار',     'asset',     11102),
  ('11103','Main Treasury - EUR',          'الخزينة الرئيسية - يورو',      'asset',     11103),
  ('11104','Main Treasury - GBP',          'الخزينة الرئيسية - جنيه إسترليني','asset',   11104),

  -- ═══════════════════════════════════════
  -- الخصوم (Liabilities)
  -- ═══════════════════════════════════════
  ('2000', 'Accounts Payable',             'الموردون (دائنون)',             'liability', 2000),

  -- ═══════════════════════════════════════
  --حقوق الملكية (Equity)
  -- ═══════════════════════════════════════
  ('3000', 'Owner Equity',                 'رأس مال المالك',               'equity',    3000),
  ('3100', 'Retained Earnings',            'الأرباح المحتجزة',             'equity',    3100),
  ('3200', 'Current Year Earnings',        'أرباح السنة الجارية',          'equity',    3200),

  -- ═══════════════════════════════════════
  -- الإيرادات (Revenue)
  -- ═══════════════════════════════════════
  ('4000', 'Sales Revenue',                'إيرادات المبيعات',             'revenue',   4000),

  -- ═══════════════════════════════════════
  -- المصروفات (Expenses)
  -- ═══════════════════════════════════════
  ('5000', 'Cost of Goods Sold',           'تكلفة البضاعة المباعة',        'expense',   5000),
  ('6000', 'Expenses',                     'المصروفات',                    'expense',   6000),
  ('7000', 'Purchase Account',             'حساب المشتريات',               'expense',   7000)
) AS v(account_code, name, account_name, account_type, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.accounts a WHERE a.account_code = v.account_code
);

-- Verify
SELECT account_code, name, account_name, account_type, balance, is_active
FROM public.accounts
ORDER BY sort_order;
