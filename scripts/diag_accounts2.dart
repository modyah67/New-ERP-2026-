import 'package:supabase/supabase.dart';

void main() async {
  final c = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  final acct469 = await c
      .from('accounts')
      .select('id, account_code, account_name, is_leaf, allow_posting, is_active')
      .eq('id', 469)
      .maybeSingle();
  print('Customer AR account 469: $acct469');

  final discountSearch = await c
      .from('accounts')
      .select('id, account_code, account_name, is_leaf, allow_posting')
      .or('account_code.eq.4105,account_code.eq.41101,account_name.ilike.%خصم%,account_name.ilike.%discount%');
  print('Discount search: $discountSearch');

  final exportRev = await c
      .from('accounts')
      .select('id, account_code, account_name, is_leaf, allow_posting')
      .eq('account_code', '4200')
      .maybeSingle();
  print('Export Revenue 4200: $exportRev');
}
