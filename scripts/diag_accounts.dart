import 'package:supabase/supabase.dart';

void main() async {
  final c = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  final accounts = await c
      .from('accounts')
      .select('id, account_code, account_name, account_type, parent_id, is_leaf, allow_posting')
      .order('id');
  print('=== All accounts ===');
  for (final a in accounts) {
    print(a);
  }

  final targetAccounts = await c.from('accounts').select('id, account_code, account_name, parent_id').inFilter('id', [1401, 1402, 1405, 1406]);
  print('\n=== Target Accounts ===');
  for (final a in targetAccounts) {
    print(a);
  }

  // Check what accounts RPC would pick
  final revenue = await c
      .from('accounts')
      .select('id, account_code, account_name, is_leaf, allow_posting')
      .eq('account_type', 'revenue')
      .order('account_code')
      .limit(3);
  print('\n=== Revenue accounts ===');
  print(revenue);

  final discount = await c
      .from('accounts')
      .select('id, account_code, account_name, is_leaf, allow_posting')
      .or('account_code.eq.4105,account_name.ilike.%خصم%')
      .limit(3);
  print('\n=== Discount accounts ===');
  print(discount);
}
