import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== 1. Inspecting Account 3 and 34 ===');
  final root3 = await c.from('accounts').select('id, account_code').eq('account_code', '3').single();
  final acct34 = await c.from('accounts').select('id, account_code, company_id').eq('account_code', '34').single();
  final companyId = acct34['company_id'];

  print('Root 3 id: ${root3['id']}, Account 34 id: ${acct34['id']}, company_id: $companyId');

  // Update 34: parent_id = root3['id'], level = 2, is_leaf = false, allow_posting = false
  await c.from('accounts').update({
    'parent_id': root3['id'],
    'level': 2,
    'is_leaf': false,
    'allow_posting': false,
    'account_type': 'expense',
    'normal_balance': 'Debit',
    'account_name': 'تكاليف المبيعات',
    'name': 'Cost of Sales',
  }).eq('id', acct34['id']);
  print('Updated account 34.');

  // 2. Ensure 341 exists and parented to 34
  final existing341 = await c.from('accounts').select('id').eq('account_code', '341').maybeSingle();
  int id341;
  if (existing341 == null) {
    final ins341 = await c.from('accounts').insert({
      'account_code': '341',
      'code': '341',
      'name': 'Cost of Sales',
      'account_name': 'تكاليف المبيعات',
      'account_type': 'expense',
      'normal_balance': 'Debit',
      'level': 3,
      'is_leaf': false,
      'allow_posting': false,
      'parent_id': acct34['id'],
      'company_id': companyId,
      'sort_order': 3410,
    }).select('id').single();
    id341 = ins341['id'];
    print('Created account 341 with id $id341');
  } else {
    id341 = existing341['id'];
    await c.from('accounts').update({
      'parent_id': acct34['id'],
      'level': 3,
      'is_leaf': false,
      'allow_posting': false,
      'account_type': 'expense',
      'normal_balance': 'Debit',
      'account_name': 'تكاليف المبيعات',
      'name': 'Cost of Sales',
    }).eq('id', id341);
    print('Updated account 341 (id: $id341) to parent 34 (id: ${acct34['id']})');
  }

  // 3. Ensure 3411 exists and parented to 341
  final existing3411 = await c.from('accounts').select('id').eq('account_code', '3411').maybeSingle();
  int id3411;
  if (existing3411 == null) {
    final ins3411 = await c.from('accounts').insert({
      'account_code': '3411',
      'code': '3411',
      'name': 'Cost of Sales Control',
      'account_name': 'تكاليف المبيعات',
      'account_type': 'expense',
      'normal_balance': 'Debit',
      'level': 4,
      'is_leaf': false,
      'allow_posting': false,
      'parent_id': id341,
      'company_id': companyId,
      'sort_order': 3411,
    }).select('id').single();
    id3411 = ins3411['id'];
    print('Created account 3411 with id $id3411');
  } else {
    id3411 = existing3411['id'];
    await c.from('accounts').update({
      'parent_id': id341,
      'level': 4,
      'is_leaf': false,
      'allow_posting': false,
      'account_type': 'expense',
      'normal_balance': 'Debit',
      'account_name': 'تكاليف المبيعات',
      'name': 'Cost of Sales Control',
    }).eq('id', id3411);
    print('Updated account 3411 (id: $id3411) to parent 341 (id: $id341)');
  }

  // 4. Delete stale 3412 if present and has no entries
  final stale3412 = await c.from('accounts').select('id').eq('account_code', '3412').maybeSingle();
  if (stale3412 != null) {
    final entries = await c.from('account_ledger_entries').select('id').eq('account_id', stale3412['id']);
    if (entries.isEmpty) {
      await c.from('accounts').delete().eq('id', stale3412['id']);
      print('Deleted stale account 3412 (id: ${stale3412['id']})');
    }
  }

  // 5. Seed all 10 Level 5 accounts under 3411
  final level5Accounts = [
    {
      'account_code': '34111',
      'code': '34111',
      'name': 'Raw Material Purchase Costs - Sales Cost',
      'account_name': 'تكاليف مشتريات خام - تكلفه بيع',
      'sort_order': 34111,
    },
    {
      'account_code': '34112',
      'code': '34112',
      'name': 'Tips & Gratuities - Sales Cost',
      'account_name': 'مصروفات اكراميات - تكلفه بيع',
      'sort_order': 34112,
    },
    {
      'account_code': '34113',
      'code': '34113',
      'name': 'Labor Expenses - Sales Cost',
      'account_name': 'مصروفات عماله - تكلفه بيع',
      'sort_order': 34113,
    },
    {
      'account_code': '34114',
      'code': '34114',
      'name': 'Transport & Handling - Sales Cost',
      'account_name': 'مصروفات نقل ومشال - تكلفه بيع',
      'sort_order': 34114,
    },
    {
      'account_code': '34115',
      'code': '34115',
      'name': 'Royalty Expenses - Sales Cost',
      'account_name': 'مصروفات رويالتي - تكلفه بيع',
      'sort_order': 34115,
    },
    {
      'account_code': '34116',
      'code': '34116',
      'name': 'Reefer Rental - Sales Cost',
      'account_name': 'مصروفات ايجار برادات - تكلفه بيع',
      'sort_order': 34116,
    },
    {
      'account_code': '34117',
      'code': '34117',
      'name': 'Clearance Expenses - Sales Cost',
      'account_name': 'مصروفات تخليص - تكلفه بيع',
      'sort_order': 34117,
    },
    {
      'account_code': '34118',
      'code': '34118',
      'name': 'Freight / Ocean Freight - Sales Cost',
      'account_name': 'مصروفات شحن (نولون) - تكلفه بيع',
      'sort_order': 34118,
    },
    {
      'account_code': '34119',
      'code': '34119',
      'name': 'Sample Analysis - Sales Cost',
      'account_name': 'مصروفات تحاليل عينات - تكلفه بيع',
      'sort_order': 34119,
    },
    {
      'account_code': '34110',
      'code': '34110',
      'name': 'Other Miscellaneous - Sales Cost',
      'account_name': 'مصروفات متنوعه اخرى - تكلفه بيع',
      'sort_order': 34110,
    },
  ];

  for (final a in level5Accounts) {
    final existing = await c.from('accounts').select('id').eq('account_code', a['account_code']!).maybeSingle();
    if (existing == null) {
      final ins = await c.from('accounts').insert({
        'account_code': a['account_code'],
        'name': a['name'],
        'account_name': a['account_name'],
        'account_type': 'expense',
        'normal_balance': 'Debit',
        'level': 5,
        'is_leaf': true,
        'allow_posting': true,
        'parent_id': id3411,
        'company_id': companyId,
        'sort_order': a['sort_order'],
      }).select('id').single();
      print('Inserted ${a['account_code']} -> ${a['account_name']} (id: ${ins['id']})');
    } else {
      await c.from('accounts').update({
        'name': a['name'],
        'account_name': a['account_name'],
        'account_type': 'expense',
        'normal_balance': 'Debit',
        'level': 5,
        'is_leaf': true,
        'allow_posting': true,
        'parent_id': id3411,
        'sort_order': a['sort_order'],
      }).eq('id', existing['id']);
      print('Updated ${a['account_code']} -> ${a['account_name']} (id: ${existing['id']})');
    }
  }

  // 6. Rebuild hierarchy
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('rebuild_chart_of_accounts_hierarchy completed successfully.');
  } catch (e) {
    print('Hierarchy rebuild note: $e');
  }

  // 7. Verification
  print('\n=== Verification: Accounts under 34 ===');
  final tree34 = await c
      .from('accounts')
      .select('id, account_code, account_name, level, parent_id, is_leaf, allow_posting')
      .like('account_code', '34%')
      .order('account_code');
  for (final row in tree34) {
    print('${row['account_code']} | L${row['level']} | Leaf: ${row['is_leaf']} | Posting: ${row['allow_posting']} | Parent: ${row['parent_id']} | ${row['account_name']}');
  }
}
