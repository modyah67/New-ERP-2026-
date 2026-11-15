import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // 1. Update 2115
  final res = await c
      .from('accounts')
      .update({
        'account_name': 'موردو مواد التعبئة',
        'name': 'Packaging Materials Suppliers',
      })
      .eq('account_code', '2115')
      .select('id, account_code, account_name, name');

  print('Updated 2115: $res');

  // 2. Check and update 21151 if present
  final res21151 = await c
      .from('accounts')
      .update({
        'account_name': 'موردو مواد التعبئة - فرعي',
        'name': 'Packaging Materials Suppliers Sub-ledger',
      })
      .eq('account_code', '21151')
      .select('id, account_code, account_name, name');

  print('Updated 21151: $res21151');

  // Rebuild hierarchy
  try {
    await c.rpc('rebuild_chart_of_accounts_hierarchy');
    print('Hierarchy rebuilt successfully.');
  } catch (e) {
    print('Hierarchy rebuild error: $e');
  }

  // Verify
  final verify = await c
      .from('accounts')
      .select('id, account_code, account_name, name')
      .like('account_code', '2115%');
  print('Verified 2115 accounts: $verify');
}
