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
  print('VERIFICATION 1: FULL 211 CHART OF ACCOUNTS TREE (LEVELS 3, 4, 5)');
  print('================================================================');
  final accounts = await c
      .from('accounts')
      .select('id, account_code, name, account_name, parent_id, level, is_leaf, allow_posting, company_id')
      .or('account_code.eq.211,account_code.like.211%')
      .isFilter('deleted_at', null)
      .order('account_code');

  print('Found ${accounts.length} accounts under 211:\n');
  for (final a in accounts) {
    print('  [Level ${a['level']}] Code=${a['account_code']} | ID=${a['id']} | ParentID=${a['parent_id']} | Leaf=${a['is_leaf']} | Posting=${a['allow_posting']} | Name=${a['account_name']} (${a['name']}) | Company=${a['company_id']}');
  }

  print('\n================================================================');
  print('VERIFICATION 2: OPERATIONAL CODES IN suppliers TABLE (UNCHANGED)');
  print('================================================================');
  final supps = await c
      .from('suppliers')
      .select('id, name, code, supplier_code, account_id, supplier_type, company_id')
      .isFilter('deleted_at', null)
      .order('supplier_code');
  for (final s in supps) {
    print('  Supplier: name=${s['name']} | code=${s['code']} | supplier_code=${s['supplier_code']} | account_id=${s['account_id']} | type=${s['supplier_type']}');
  }

  print('\n================================================================');
  print('VERIFICATION 3: OPERATIONAL CODES IN transport_suppliers (UNCHANGED)');
  print('================================================================');
  final trans = await c
      .from('transport_suppliers')
      .select('id, code, name, account_id, company_id, balance, truck_balance')
      .isFilter('deleted_at', null);
  for (final t in trans) {
    print('  Transporter: ID=${t['id']} | name=${t['name']} | code=${t['code']} | account_id=${t['account_id']} | company_id=${t['company_id']} | balance=${t['balance']}');
  }

  print('\n================================================================');
  print('VERIFICATION 4: CHECK NULL company_id ACROSS FIXED TABLES');
  print('================================================================');
  for (final table in ['transport_suppliers', 'shipping_companies', 'clearing_agents']) {
    final nullRows = await c.from(table).select('id, name').isFilter('company_id', null);
    print('  Table $table -> NULL company_id count: ${nullRows.length}');
  }
  final nullAccs = await c.from('accounts').select('id, account_code, name').isFilter('company_id', null);
  print('  Table accounts -> NULL company_id count: ${nullAccs.length}');

  print('\n=== ALL VERIFICATION CHECKS COMPLETE ===');
}
