import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Inspecting account 34 and descendants ===');
  final accts34 = await c
      .from('accounts')
      .select('id, account_code, account_name, level, is_leaf, parent_id')
      .like('account_code', '34%')
      .order('level', ascending: false);

  print('Found ${accts34.length} accounts under 34:');
  for (var a in accts34) {
    print('  ${a['account_code']} (Level ${a['level']}, ID: ${a['id']}) - ${a['account_name']}');
  }

  // Check ledger entries for any of these accounts
  final ids = accts34.map((a) => a['id']).toList();
  if (ids.isNotEmpty) {
    final entries = await c
        .from('account_ledger_entries')
        .select('account_id')
        .inFilter('account_id', ids);
    if (entries.isNotEmpty) {
      print('WARNING: Ledger entries found for some accounts! Cannot delete.');
      for (var e in entries) {
        print('  Ledger entry for account_id: ${e['account_id']}');
      }
      return;
    }
  }

  // Delete from deepest level to top level
  for (var a in accts34) {
    final res = await c.from('accounts').delete().eq('id', a['id']).select('account_code');
    print('Deleted: ${a['account_code']} - ${a['account_name']} => $res');
  }

  // Rebuild hierarchy
  print('\n=== Rebuilding hierarchy ===');
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('Hierarchy rebuilt successfully.');
  } catch (e) {
    print('Hierarchy rebuild error: $e');
  }

  // Verify
  final remaining = await c
      .from('accounts')
      .select('account_code, account_name')
      .like('account_code', '34%');
  if (remaining.isEmpty) {
    print('SUCCESS: Account 34 and all sub-accounts completely deleted!');
  } else {
    print('REMAINING: $remaining');
  }
}
