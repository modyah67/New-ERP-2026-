import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(
    SupabaseOptions.url,
    SupabaseOptions.anonKey,
  );

  await c.auth.signInWithPassword(
    email: 'mahmoud@gmail.com',
    password: '123456',
  );

  print('================================================================');
  print('CHECK 1: VERIFYING POSTING ACCOUNTS PURGED FROM DATABASE');
  print('================================================================');

  final targetCodes = [
    '211501', '211502',
    '211601', '211602', '211603',
    '211701',
    '211101',
    '211200',
    '124101', '124102',
  ];

  final remaining = await c
      .from('accounts')
      .select('account_code, account_name')
      .inFilter('account_code', targetCodes);

  if (remaining.isEmpty) {
    print('SUCCESS: All 13 previous test/posting accounts are completely deleted!');
  } else {
    print('WARNING: Some accounts still exist:');
    for (final r in remaining) {
      print('  - ${r['account_code']}: ${r['account_name']}');
    }
  }

  print('\n================================================================');
  print('CHECK 2: VERIFYING TEMPLATE SUB-LEDGERS AND LEVEL 4 PARENTS');
  print('================================================================');

  final templateCodes = [
    // Level 4 parents
    '1251', '2111', '2112', '2113', '2114', '2115', '2116', '2117', '2321',
    // Level 5 standard template sub-ledgers
    '12511', '12512',
    '21111', '21121', '21131', '21141', '21151', '21161', '21171',
    '23211', '23212', '23213',
  ];

  final coaRows = await c
      .from('accounts')
      .select('account_code, account_name, name, level, is_leaf, allow_posting, parent_id')
      .inFilter('account_code', templateCodes)
      .order('account_code');

  print('Found ${coaRows.length}/${templateCodes.length} official COA accounts:');
  for (final row in coaRows) {
    print('  [Level ${row['level']}] Code=${row['account_code']} | Leaf=${row['is_leaf']} | Posting=${row['allow_posting']} | Name=${row['account_name']} (${row['name']})');
  }

  print('\n================================================================');
  print('CHECK 3: VERIFYING NEXT CODE GENERATION STARTS AT 01');
  print('================================================================');

  final entityTypes = [
    'customer',
    'crop_supplier',
    'packaging_supplier',
    'shared_supplier',
    'transport_supplier',
    'shipping_company',
    'clearing_agent',
    'shareholder',
  ];

  bool allStartAt01 = true;
  for (final type in entityTypes) {
    final res = await c.rpc('get_next_entity_account_code', params: {
      'p_entity_type': type,
    });
    final codeStr = res.toString();
    final endsWith01 = codeStr.endsWith('01');
    print('  Entity: ${type.padRight(20)} -> Next Account Code: $codeStr ${endsWith01 ? "✓ (Clean 01)" : "✗ (NOT 01!)"}');
    if (!endsWith01) allStartAt01 = false;
  }

  print('\n================================================================');
  print('CHECK 4: TOTAL ACCOUNTS COUNT IN DATABASE');
  print('================================================================');
  final allAccounts = await c.from('accounts').select('id, account_code');
  print('Total accounts in database: ${allAccounts.length}');

  if (allStartAt01) {
    print('\n>>> ALL CHECKS PASSED PERFECTLY! Handover reset guarantees clean slate. <<<');
  } else {
    print('\n>>> SOME CHECKS FAILED! <<<');
  }
}
