import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final staleCodes = ['3121', '3123', '3212', '3222', '3223', '3224', '3412'];

  print('=== Step 1: Unlinking cost_report_categories from stale accounts ===');
  // Find approved replacement accounts
  final acc33111 = await c.from('accounts').select('id').eq('account_code', '33111').maybeSingle();
  final acc34111 = await c.from('accounts').select('id').eq('account_code', '34111').maybeSingle();
  final acc34114 = await c.from('accounts').select('id').eq('account_code', '34114').maybeSingle();
  final acc31310 = await c.from('accounts').select('id').eq('account_code', '31310').maybeSingle();

  final id33111 = acc33111?['id'];
  final id34111 = acc34111?['id'];
  final id34114 = acc34114?['id'];
  final id31310 = acc31310?['id'];

  if (id33111 != null) {
    await c.from('cost_report_categories').update({'account_id': id33111}).inFilter('name', ['مواد التعبئة', 'تعبئة وتغليف']);
    print('Linked مواد التعبئة and تعبئة وتغليف to 33111 ($id33111)');
  }
  if (id34111 != null) {
    await c.from('cost_report_categories').update({'account_id': id34111}).eq('name', 'تكلفة المحاصيل');
    print('Linked تكلفة المحاصيل to 34111 ($id34111)');
  }
  if (id34114 != null) {
    await c.from('cost_report_categories').update({'account_id': id34114}).inFilter('name', ['تكلفة شركات الشحن', 'تكلفة المخلصين', 'لوجستيك ونقل']);
    print('Linked shipping/logistics to 34114 ($id34114)');
  }
  if (id31310 != null) {
    await c.from('cost_report_categories').update({'account_id': id31310}).eq('name', 'أخرى');
    print('Linked أخرى to 31310 ($id31310)');
  }

  print('\n=== Step 2: Checking and deleting stale accounts ===');
  for (var code in staleCodes) {
    final accts = await c
        .from('accounts')
        .select('id, account_code, account_name, level, is_leaf, allow_posting')
        .eq('account_code', code);
    if (accts.isNotEmpty) {
      final acct = accts[0];
      print('FOUND: $code - ${acct['account_name']} (id: ${acct['id']})');

      // Unlink cost_report_categories explicitly by account_id just in case
      await c.from('cost_report_categories').update({'account_id': id33111 ?? id31310}).eq('account_id', acct['id']);

      // Check child accounts
      final children = await c.from('accounts').select('id, account_code').eq('parent_id', acct['id']);
      if (children.isNotEmpty) {
        print('  Deleting ${children.length} children...');
        await c.from('accounts').delete().eq('parent_id', acct['id']);
      }

      // Check ledger entries
      final entries = await c.from('account_ledger_entries').select('id').eq('account_id', acct['id']).limit(5);
      if (entries.isNotEmpty) {
        print('  WARNING: Account $code has ${entries.length} ledger entries! Skipping delete.');
        continue;
      }

      // Delete the account
      final res = await c.from('accounts').delete().eq('id', acct['id']).select('id, account_code');
      print('  DELETED: $code => $res');
    } else {
      print('NOT FOUND: $code (already clean)');
    }
  }

  // Rebuild hierarchy
  print('\n=== Step 3: Rebuilding hierarchy ===');
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('Hierarchy rebuilt successfully.');
  } catch (e) {
    print('Hierarchy rebuild error: $e');
  }

  // Verify
  print('\n=== Step 4: Verifying no stale accounts remain ===');
  final remaining = await c
      .from('accounts')
      .select('account_code, account_name')
      .inFilter('account_code', staleCodes);
  if (remaining.isEmpty) {
    print('SUCCESS: All stale accounts (3121, 3123, etc.) deleted successfully!');
  } else {
    print('REMAINING ACCOUNTS: $remaining');
  }
}
