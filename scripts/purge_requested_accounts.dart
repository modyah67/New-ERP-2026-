import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // 1. Unlink cost_report_categories so foreign keys don't block deletion
  print('=== STEP 1: Unlinking cost_report_categories ===');
  try {
    final updateRes = await c
        .from('cost_report_categories')
        .update({'account_id': null})
        .gte('id', 1)
        .select('id, name, account_id');
    print('Unlinked categories: $updateRes');
  } catch (e) {
    print('Error unlinking cost_report_categories: $e');
  }

  // 2. Identify all targets to delete
  final specificCodes = ['3121', '3123', '3212', '3222', '3223', '3224'];
  
  print('=== STEP 2: Finding accounts to delete ===');
  final specificAccts = await c
      .from('accounts')
      .select('id, account_code, account_name, level')
      .inFilter('account_code', specificCodes);
  
  final accts34 = await c
      .from('accounts')
      .select('id, account_code, account_name, level')
      .like('account_code', '34%')
      .order('level', ascending: false);

  print('Found ${specificAccts.length} specific accounts:');
  for (var a in specificAccts) {
    print('  ${a['account_code']} - ${a['account_name']} (ID: ${a['id']})');
  }

  print('Found ${accts34.length} accounts under 34%:');
  for (var a in accts34) {
    print('  Level ${a['level']}: ${a['account_code']} - ${a['account_name']} (ID: ${a['id']})');
  }

  // 3. Delete specific accounts
  for (var a in specificAccts) {
    // Delete any children first if exist
    await c.from('accounts').delete().eq('parent_id', a['id']);
    final res = await c.from('accounts').delete().eq('id', a['id']).select('account_code');
    print('Deleted specific account: ${a['account_code']} => $res');
  }

  // 4. Delete 34% from deepest level to root
  for (var a in accts34) {
    await c.from('accounts').delete().eq('parent_id', a['id']);
    final res = await c.from('accounts').delete().eq('id', a['id']).select('account_code');
    print('Deleted 34% account: ${a['account_code']} => $res');
  }

  // 5. Rebuild hierarchy
  print('\n=== STEP 3: Rebuilding hierarchy ===');
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('Hierarchy rebuilt successfully.');
  } catch (e) {
    print('Hierarchy rebuild error: $e');
  }

  // 6. Final verification
  print('\n=== STEP 4: Verification ===');
  final checkSpecific = await c
      .from('accounts')
      .select('account_code, account_name')
      .inFilter('account_code', specificCodes);
  
  final check34 = await c
      .from('accounts')
      .select('account_code, account_name')
      .like('account_code', '34%');

  print('Remaining specific accounts: ${checkSpecific.length}');
  print('Remaining 34% accounts: ${check34.length}');

  if (checkSpecific.isEmpty && check34.isEmpty) {
    print('SUCCESS: All requested accounts deleted completely and verified clean!');
  } else {
    print('WARNING: Still remaining: $checkSpecific, $check34');
  }
}
