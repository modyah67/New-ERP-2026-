import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final targetCodes = ['2322', '2330', '2332', '2333', '2334', '2342'];

  print('Deleting accounts: $targetCodes...');

  // 1. Check existing
  final existing = await c
      .from('accounts')
      .select('id, account_code, name, account_name')
      .inFilter('account_code', targetCodes);

  print('Found ${existing.length} accounts to delete:');
  for (var a in existing) {
    print('  ${a['account_code']} (ID: ${a['id']}) - ${a['account_name']}');
  }

  if (existing.isEmpty) {
    print('No accounts found to delete.');
    return;
  }

  // 2. Delete the accounts
  final deleteRes = await c
      .from('accounts')
      .delete()
      .inFilter('account_code', targetCodes)
      .select('id, account_code');

  print('Deleted ${deleteRes.length} accounts: $deleteRes');

  // 3. Rebuild hierarchy
  print('Rebuilding COA hierarchy...');
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('Hierarchy rebuild RPC completed successfully.');
  } catch (e) {
    print('Error rebuilding hierarchy: $e');
  }

  // 4. Verify deletion
  final remaining = await c
      .from('accounts')
      .select('id, account_code')
      .inFilter('account_code', targetCodes);

  print('Remaining accounts with codes $targetCodes: ${remaining.length}');
}
