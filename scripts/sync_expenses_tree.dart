import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  const templateCompanyId = 'a0000000-0000-0000-0000-000000000001';

  print('=== STEP 1: Deleting old accounts under 3% ===');
  // First, verify 0 ledger entries
  final oldAccounts = await c
      .from('accounts')
      .select('id, account_code')
      .like('account_code', '3%');

  print('Found ${oldAccounts.length} existing accounts under 3%');

  // Delete all old 3% accounts
  final delRes = await c
      .from('accounts')
      .delete()
      .like('account_code', '3%')
      .select('id');
  print('Deleted ${delRes.length} old accounts.');

  print('=== STEP 2: Inserting standard 64 accounts in order of levels ===');

  final accountsData = [
    // ── Level 1 ──
    {
      'account_code': '3',
      'account_name': 'التكاليف',
      'name': 'Costs & Expenses',
      'level': 1,
      'parent_code': null,
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3000,
    },

    // ── Level 2 (under 3) ──
    {
      'account_code': '31',
      'account_name': 'تكاليف نقديه',
      'name': 'Cash Costs',
      'level': 2,
      'parent_code': '3',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3100,
    },
    {
      'account_code': '32',
      'account_name': 'تكاليف محاسبيه',
      'name': 'Accounting Costs',
      'level': 2,
      'parent_code': '3',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3200,
    },
    {
      'account_code': '33',
      'account_name': 'تكاليف مخزنيه',
      'name': 'Inventory Costs',
      'level': 2,
      'parent_code': '3',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3300,
    },

    // ── Level 3 (under 31) ──
    {
      'account_code': '311',
      'account_name': 'مصروفات وأجور عاملين',
      'name': 'Salaries & Employee Wages',
      'level': 3,
      'parent_code': '31',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3110,
    },
    {
      'account_code': '312',
      'account_name': 'مصروفات تشغيل',
      'name': 'Operating Expenses',
      'level': 3,
      'parent_code': '31',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3120,
    },
    {
      'account_code': '313',
      'account_name': 'مصروفات إداريه',
      'name': 'Administrative Expenses',
      'level': 3,
      'parent_code': '31',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3130,
    },
    {
      'account_code': '314',
      'account_name': 'مصروفات اخرى',
      'name': 'Other Expenses',
      'level': 3,
      'parent_code': '31',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3140,
    },

    // ── Level 3 (under 32) ──
    {
      'account_code': '321',
      'account_name': 'إهلاك أصول ثابته',
      'name': 'Fixed Assets Depreciation',
      'level': 3,
      'parent_code': '32',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3210,
    },
    {
      'account_code': '322',
      'account_name': 'مصروفات محاسبيه اخرى',
      'name': 'Other Accounting Expenses',
      'level': 3,
      'parent_code': '32',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3220,
    },

    // ── Level 3 (under 33) ──
    {
      'account_code': '331',
      'account_name': 'تكاليف مخزنيه',
      'name': 'Inventory Costs',
      'level': 3,
      'parent_code': '33',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3310,
    },


    // ── Level 4 (under 311) ──
    {
      'account_code': '3111',
      'account_name': 'مرتبات ومافي حكمها',
      'name': 'Salaries & Benefits Control',
      'level': 4,
      'parent_code': '311',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3111,
    },
    {
      'account_code': '3112',
      'account_name': 'مصروفات عاملين اخري',
      'name': 'Other Employee Expenses Control',
      'level': 4,
      'parent_code': '311',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3112,
    },

    // ── Level 4 (under 312) ──
    {
      'account_code': '3122',
      'account_name': 'مصروفات تشغيل وبيع وتسويق',
      'name': 'Operating, Sales & Marketing Control',
      'level': 4,
      'parent_code': '312',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3122,
    },

    // ── Level 4 (under 313) ──
    {
      'account_code': '3131',
      'account_name': 'مصروفات البوفيه وخدمات للادارة',
      'name': 'Buffet & Admin Services Control',
      'level': 4,
      'parent_code': '313',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3131,
    },
    {
      'account_code': '3132',
      'account_name': 'استشارات واشتراكات ورسوم',
      'name': 'Consulting, Subscriptions & Fees Control',
      'level': 4,
      'parent_code': '313',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3132,
    },

    // ── Level 4 (under 314) ──
    {
      'account_code': '3141',
      'account_name': 'الفوائد البنكيه',
      'name': 'Bank Interest Control',
      'level': 4,
      'parent_code': '314',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3141,
    },
    {
      'account_code': '3142',
      'account_name': 'المصروفات البنكيه',
      'name': 'Bank Charges Control',
      'level': 4,
      'parent_code': '314',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3142,
    },
    {
      'account_code': '3143',
      'account_name': 'المصروفات المتنوعه الأخري',
      'name': 'Other Miscellaneous Expenses Control',
      'level': 4,
      'parent_code': '314',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3143,
    },

    // ── Level 4 (under 321) ──
    {
      'account_code': '3211',
      'account_name': 'إهلاك أصول ثابته',
      'name': 'Depreciation Control',
      'level': 4,
      'parent_code': '321',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3211,
    },

    // ── Level 4 (under 322) ──
    {
      'account_code': '3221',
      'account_name': 'فروق عمله',
      'name': 'Foreign Exchange Differences Control',
      'level': 4,
      'parent_code': '322',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3221,
    },

    // ── Level 4 (under 331) ──
    {
      'account_code': '3311',
      'account_name': 'تكاليف مخزنيه',
      'name': 'Inventory Costs Control',
      'level': 4,
      'parent_code': '331',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 3311,
    },


    // ── Level 5 (under 3111) ──
    {
      'account_code': '31111',
      'account_name': 'مصروفات مرتبات',
      'name': 'Salaries Expense',
      'level': 5,
      'parent_code': '3111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31111,
    },
    {
      'account_code': '31112',
      'account_name': 'مصروفات تامينات اجتماعيه',
      'name': 'Social Insurance Expense',
      'level': 5,
      'parent_code': '3111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31112,
    },
    {
      'account_code': '31113',
      'account_name': 'مصروفات بدلات اخري - ثابته',
      'name': 'Fixed Allowances Expense',
      'level': 5,
      'parent_code': '3111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31113,
    },
    {
      'account_code': '31114',
      'account_name': 'مصروفات بدلات اخري - متغيره',
      'name': 'Variable Allowances Expense',
      'level': 5,
      'parent_code': '3111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31114,
    },
    {
      'account_code': '31115',
      'account_name': 'مصروفات مكافآت وحوافز',
      'name': 'Bonuses & Incentives Expense',
      'level': 5,
      'parent_code': '3111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31115,
    },
    {
      'account_code': '31116',
      'account_name': 'مصروفات مكافأه نهايه الخدمه',
      'name': 'End of Service Indemnity Expense',
      'level': 5,
      'parent_code': '3111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31116,
    },

    // ── Level 5 (under 3112) ──
    {
      'account_code': '31121',
      'account_name': 'مصروفات سفر للخارج - بدلات سفر',
      'name': 'Overseas Travel & Per Diem',
      'level': 5,
      'parent_code': '3112',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31121,
    },
    {
      'account_code': '31122',
      'account_name': 'مصروفات علاج العاملين',
      'name': 'Staff Healthcare Expense',
      'level': 5,
      'parent_code': '3112',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31122,
    },
    {
      'account_code': '31123',
      'account_name': 'مصروفات انتقالات',
      'name': 'Staff Transportation Expense',
      'level': 5,
      'parent_code': '3112',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31123,
    },

    // ── Level 5 (under 3122) ──
    {
      'account_code': '31221',
      'account_name': 'مصروفات صيانه وتشغيل سيارات',
      'name': 'Vehicle Maintenance & Operations',
      'level': 5,
      'parent_code': '3122',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31221,
    },
    {
      'account_code': '31222',
      'account_name': 'مصروفات الدعايه والإعلان',
      'name': 'Advertising & Promotion Expense',
      'level': 5,
      'parent_code': '3122',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31222,
    },
    {
      'account_code': '31223',
      'account_name': 'مصروفات المعارض',
      'name': 'Exhibitions & Trade Shows',
      'level': 5,
      'parent_code': '3122',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31223,
    },
    {
      'account_code': '31224',
      'account_name': 'مصروفات طباعه كتالوجات',
      'name': 'Catalog & Print Marketing',
      'level': 5,
      'parent_code': '3122',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31224,
    },

    // ── Level 5 (under 3131) ──
    {
      'account_code': '31311',
      'account_name': 'مصروفات النظافه والبوفيه',
      'name': 'Cleaning & Buffet Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31311,
    },
    {
      'account_code': '31312',
      'account_name': 'مصروفات فواتير الكهرباء والمياه والغاز الطبيعي',
      'name': 'Utilities - Electricity, Water, Gas',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31312,
    },
    {
      'account_code': '31313',
      'account_name': 'مصروفات الضيافه',
      'name': 'Hospitality Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31313,
    },
    {
      'account_code': '31314',
      'account_name': 'مصروفات ادوات كتابيه وماكينات التصوير والفاكس',
      'name': 'Stationery & Printing Supplies',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31314,
    },
    {
      'account_code': '31315',
      'account_name': 'مصروفات الكمبيوتر والانترنت وتليفون ارضي',
      'name': 'IT, Internet & Landline Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31315,
    },
    {
      'account_code': '31316',
      'account_name': 'مصروفات الإكراميات',
      'name': 'Tips & Gratuities Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31316,
    },
    {
      'account_code': '31317',
      'account_name': 'مصروفات الهدايا',
      'name': 'Gifts Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31317,
    },
    {
      'account_code': '31318',
      'account_name': 'مصروفات الصيانه العامه',
      'name': 'General Maintenance Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31318,
    },
    {
      'account_code': '31319',
      'account_name': 'مصروفات ايجار عقارات',
      'name': 'Real Estate Rent Expense',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31319,
    },
    {
      'account_code': '31310',
      'account_name': 'المصروفات المتنوعه',
      'name': 'Miscellaneous Administrative Expenses',
      'level': 5,
      'parent_code': '3131',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31310,
    },

    // ── Level 5 (under 3132) ──
    {
      'account_code': '31321',
      'account_name': 'مصروفات أتعاب استشاريه',
      'name': 'Consulting Fees Expense',
      'level': 5,
      'parent_code': '3132',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31321,
    },
    {
      'account_code': '31322',
      'account_name': 'مصروفات أتعاب مكتب المراجعه',
      'name': 'Audit Office Fees Expense',
      'level': 5,
      'parent_code': '3132',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31322,
    },
    {
      'account_code': '31323',
      'account_name': 'مصروفات رسوم واشتراكات وتراخيص',
      'name': 'Government Subscriptions & Licenses',
      'level': 5,
      'parent_code': '3132',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31323,
    },
    {
      'account_code': '31324',
      'account_name': 'مصروفات شحن مستندات',
      'name': 'Document Courier & Shipping',
      'level': 5,
      'parent_code': '3132',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31324,
    },

    // ── Level 5 (under 3141) ──
    {
      'account_code': '31411',
      'account_name': 'مصروفات فوائد بنكيه',
      'name': 'Bank Interest Expense',
      'level': 5,
      'parent_code': '3141',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31411,
    },

    // ── Level 5 (under 3142) ──
    {
      'account_code': '31421',
      'account_name': 'مصروفات بنكيه',
      'name': 'Bank Charges Expense',
      'level': 5,
      'parent_code': '3142',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31421,
    },

    // ── Level 5 (under 3143) ──
    {
      'account_code': '31431',
      'account_name': 'فروق فحص ضريبي',
      'name': 'Tax Inspection Differences',
      'level': 5,
      'parent_code': '3143',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31431,
    },
    {
      'account_code': '31432',
      'account_name': 'مصروفات سنوات سابقه',
      'name': 'Prior Years Expenses',
      'level': 5,
      'parent_code': '3143',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 31432,
    },

    // ── Level 5 (under 3211) ──
    {
      'account_code': '32111',
      'account_name': 'إهلاك أصول ثابته أراضي',
      'name': 'Land Depreciation / Impairment',
      'level': 5,
      'parent_code': '3211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32111,
    },
    {
      'account_code': '32112',
      'account_name': 'إهلاك أصول ثابته مباني',
      'name': 'Buildings Depreciation',
      'level': 5,
      'parent_code': '3211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32112,
    },
    {
      'account_code': '32113',
      'account_name': 'إهلاك أصول ثابته آلات ومعدات مكتبيه',
      'name': 'Machinery & Office Equipment Depr.',
      'level': 5,
      'parent_code': '3211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32113,
    },
    {
      'account_code': '32114',
      'account_name': 'إهلاك أصول ثابته اجهزه كمبيوتر',
      'name': 'Computers & IT Depreciation',
      'level': 5,
      'parent_code': '3211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32114,
    },
    {
      'account_code': '32115',
      'account_name': 'إهلاك أصول ثابته سيارات ملاكي',
      'name': 'Passenger Vehicles Depreciation',
      'level': 5,
      'parent_code': '3211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32115,
    },
    {
      'account_code': '32116',
      'account_name': 'إهلاك أصول ثابته وسائل نقل المحاصيل',
      'name': 'Crop Transport Vehicles Depr.',
      'level': 5,
      'parent_code': '3211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32116,
    },

    // ── Level 5 (under 3221) ──
    {
      'account_code': '32211',
      'account_name': 'فروق تقويم عمله',
      'name': 'FX Valuation Differences',
      'level': 5,
      'parent_code': '3221',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 32211,
    },

    // ── Level 5 (under 3311) ──
    {
      'account_code': '33111',
      'account_name': 'مصروفات مخزنية تعبئة وتغليف',
      'name': 'Packaging & Storage Inventory Expense',
      'level': 5,
      'parent_code': '3311',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 33111,
    },

  ];

  print('Total accounts to insert: ${accountsData.length}');

  // Insert level by level to properly resolve parent_id
  final Map<String, dynamic> codeToId = {};

  for (int lvl = 1; lvl <= 5; lvl++) {
    final levelAccounts = accountsData.where((a) => a['level'] == lvl).toList();
    print('Inserting Level $lvl (${levelAccounts.length} accounts)...');

    for (var acc in levelAccounts) {
      final code = acc['account_code'] as String;
      final parentCode = acc['parent_code'] as String?;
      final parentId = parentCode != null ? codeToId[parentCode] : null;

      final insertData = {
        'account_code': code,
        'account_name': acc['account_name'],
        'name': acc['name'],
        'account_type': 'expense',
        'normal_balance': 'Debit',
        'level': acc['level'],
        'parent_id': parentId,
        'is_leaf': acc['is_leaf'],
        'allow_posting': acc['allow_posting'],
        'is_active': true,
        'is_system': false,
        'sort_order': acc['sort_order'],
        'company_id': templateCompanyId,
      };

      final inserted = await c.from('accounts').insert(insertData).select('id, account_code').single();
      codeToId[code] = inserted['id'];
    }
  }

  print('Successfully inserted all ${codeToId.length} accounts!');

  print('=== STEP 3: Rebuilding COA hierarchy ===');
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('rebuild_chart_of_accounts_hierarchy completed successfully.');
  } catch (e) {
    print('Hierarchy RPC error: $e');
  }

  print('=== STEP 4: Verifying new tree structure ===');
  final check = await c
      .from('accounts')
      .select('id, account_code, account_name, level, parent_id, is_leaf, allow_posting')
      .like('account_code', '3%')
      .order('account_code');

  print('Total accounts now under 3%: ${check.length}');
  for (var a in check) {
    print('L${a['level']} | ${a['account_code']} | ${a['account_name']} | parent: ${a['parent_id']} | leaf: ${a['is_leaf']} | posting: ${a['allow_posting']}');
  }
}
