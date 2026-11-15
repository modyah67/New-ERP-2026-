import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  const companyId = 'a0000000-0000-0000-0000-000000000001';

  print('=== STEP 1: Deleting existing Root 4 accounts ===');
  // 1. Fetch all existing accounts under 4% ordered by level descending
  final oldAccounts = await c
      .from('accounts')
      .select('id, account_code, level')
      .like('account_code', '4%')
      .order('level', ascending: false);

  print('Found ${oldAccounts.length} existing accounts under 4% to delete.');

  for (var a in oldAccounts) {
    // Unlink any parent references if any
    await c.from('accounts').delete().eq('id', a['id']);
  }
  print('Deleted old accounts under 4%.');

  print('\n=== STEP 2: Inserting exact requested Revenues tree (16 accounts) ===');

  final accountsData = [
    // ── Level 1 ──
    {
      'account_code': '4',
      'account_name': 'الإيرادات',
      'name': 'Revenues',
      'level': 1,
      'parent_code': null,
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4000,
    },

    // ── Level 2 (under 4) ──
    {
      'account_code': '41',
      'account_name': 'إيرادات النشاط',
      'name': 'Operating Revenues',
      'level': 2,
      'parent_code': '4',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4100,
    },
    {
      'account_code': '42',
      'account_name': 'إيرادات اخرى',
      'name': 'Other Revenues',
      'level': 2,
      'parent_code': '4',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4200,
    },

    // ── Level 3 (under 41 & 42) ──
    {
      'account_code': '411',
      'account_name': 'إيرادات النشاط',
      'name': 'Operating Revenues',
      'level': 3,
      'parent_code': '41',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4110,
    },
    {
      'account_code': '421',
      'account_name': 'إيرادات اخرى',
      'name': 'Other Revenues',
      'level': 3,
      'parent_code': '42',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4210,
    },

    // ── Level 4 (under 411 & 421) ──
    {
      'account_code': '4111',
      'account_name': 'مبيعات محاصيل',
      'name': 'Crop Sales',
      'level': 4,
      'parent_code': '411',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4111,
    },
    {
      'account_code': '4112',
      'account_name': 'مبيعات اخرى',
      'name': 'Other Sales',
      'level': 4,
      'parent_code': '411',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4112,
    },
    {
      'account_code': '4211',
      'account_name': 'فوائد دائنه',
      'name': 'Credit Interest',
      'level': 4,
      'parent_code': '421',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4211,
    },
    {
      'account_code': '4212',
      'account_name': 'عمولات',
      'name': 'Commissions',
      'level': 4,
      'parent_code': '421',
      'is_leaf': false,
      'allow_posting': false,
      'sort_order': 4212,
    },

    // ── Level 5 (Leaf analytical accounts) ──
    {
      'account_code': '41111',
      'account_name': 'مبيعات فراوله',
      'name': 'Strawberry Sales',
      'level': 5,
      'parent_code': '4111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 41111,
    },
    {
      'account_code': '41112',
      'account_name': 'مبيعات مانجو',
      'name': 'Mango Sales',
      'level': 5,
      'parent_code': '4111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 41112,
    },
    {
      'account_code': '41113',
      'account_name': 'مبيعات بلح',
      'name': 'Dates Sales',
      'level': 5,
      'parent_code': '4111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 41113,
    },
    {
      'account_code': '41114',
      'account_name': 'مبيعات بلوبيرى',
      'name': 'Blueberry Sales',
      'level': 5,
      'parent_code': '4111',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 41114,
    },
    {
      'account_code': '41121',
      'account_name': 'مبيعات فرزه محلي',
      'name': 'Local Sorting Sales',
      'level': 5,
      'parent_code': '4112',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 41121,
    },
    {
      'account_code': '42111',
      'account_name': 'فوائد دائنه - بنك التجارى الدولى CIB',
      'name': 'Credit Interest - CIB',
      'level': 5,
      'parent_code': '4211',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 42111,
    },
    {
      'account_code': '42121',
      'account_name': 'عمولات',
      'name': 'Commissions',
      'level': 5,
      'parent_code': '4212',
      'is_leaf': true,
      'allow_posting': true,
      'sort_order': 42121,
    },
  ];

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
        'account_type': 'revenue',
        'normal_balance': 'Credit',
        'level': acc['level'],
        'parent_id': parentId,
        'is_leaf': acc['is_leaf'],
        'allow_posting': acc['allow_posting'],
        'is_active': true,
        'is_system': false,
        'sort_order': acc['sort_order'],
        'company_id': companyId,
      };

      final inserted = await c
          .from('accounts')
          .insert(insertData)
          .select('id, account_code')
          .single();
      codeToId[code] = inserted['id'];
      print('  Inserted: $code (${acc['account_name']}) -> id: ${inserted['id']}');
    }
  }

  print('\n=== STEP 3: Rebuilding hierarchy ===');
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('Hierarchy rebuilt successfully.');
  } catch (e) {
    print('Hierarchy rebuild error: $e');
  }

  print('\n=== STEP 4: Verification ===');
  final tree = await c
      .from('accounts')
      .select('id, account_code, account_name, level, parent_id, is_leaf, allow_posting')
      .like('account_code', '4%')
      .order('account_code');

  print('Total accounts in Root 4: ${tree.length}');
  for (var a in tree) {
    print('  L${a['level']} | ${a['account_code']} | ${a['account_name']} | parent_id: ${a['parent_id']} | leaf: ${a['is_leaf']} | posting: ${a['allow_posting']}');
  }
}
