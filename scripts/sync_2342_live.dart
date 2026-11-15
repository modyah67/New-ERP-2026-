import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Syncing 2342 and 23421 to Live DB ===');

  // 1. Get parent 234
  final p234 = await c.from('accounts').select('id, company_id').eq('account_code', '234').single();
  final p234Id = p234['id'] as int;
  final companyId = p234['company_id'];
  print('Parent 234 ID: $p234Id, company: $companyId');

  // 2. Ensure 2342 (Control Account - Level 4)
  final existing2342 = await c.from('accounts').select('id').eq('account_code', '2342').maybeSingle();
  int p2342Id;
  if (existing2342 == null) {
    final inserted = await c.from('accounts').insert({
      'account_code': '2342',
      'name': 'Opening Balance Suspense Control',
      'account_name': 'فروق أرصدة افتتاحية',
      'account_type': 'equity',
      'normal_balance': 'Credit',
      'level': 4,
      'is_leaf': false,
      'allow_posting': false,
      'parent_id': p234Id,
      'company_id': companyId,
      'sort_order': 23420,
      'is_active': true,
      'is_system': true,
    }).select().single();
    p2342Id = inserted['id'] as int;
    print('Inserted 2342: $p2342Id');
  } else {
    p2342Id = existing2342['id'] as int;
    print('2342 already exists: $p2342Id');
  }

  // 3. Ensure 23421 (Posting Account - Level 5)
  final existing23421 = await c.from('accounts').select('id').eq('account_code', '23421').maybeSingle();
  if (existing23421 == null) {
    final inserted = await c.from('accounts').insert({
      'account_code': '23421',
      'name': 'Opening Balance Suspense Account',
      'account_name': 'رصيد افتتاحي',
      'account_type': 'equity',
      'normal_balance': 'Credit',
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
      'parent_id': p2342Id,
      'company_id': companyId,
      'sort_order': 23421,
      'is_active': true,
      'is_system': true,
    }).select().single();
    print('Inserted 23421: ${inserted['id']}');
  } else {
    print('23421 already exists: ${existing23421['id']}');
  }

  // 4. Verify live accounts under 234
  final liveTree = await c.from('accounts')
      .select('id, account_code, account_name, level, parent_id, is_leaf, allow_posting')
      .like('account_code', '234%')
      .order('account_code');

  print('\n=== Final Live Tree under 234 ===');
  for (final a in liveTree) {
    print('  ${a['account_code']} | ${a['account_name']} (id: ${a['id']}, parent: ${a['parent_id']}, level: ${a['level']}, postable: ${a['allow_posting']})');
  }
}
