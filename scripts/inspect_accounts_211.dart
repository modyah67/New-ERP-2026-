import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final res = await c
      .from('accounts')
      .select('id, account_code, account_name, parent_id, level, is_leaf, is_active')
      .like('account_code', '211%')
      .order('account_code');
  print('=== Accounts under 211% (${res.length}) ===');
  for (var a in res) {
    print('${a["account_code"]} | ${a["account_name"]} | level:${a["level"]} | leaf:${a["is_leaf"]} | active:${a["is_active"]} | id:${a["id"]}');
  }

  final transSuppliers = await c.from('transport_suppliers').select('id, code, name, account_id, balance, truck_balance').limit(10);
  print('\n=== transport_suppliers (${transSuppliers.length}) ===');
  for (var ts in transSuppliers) {
    print('${ts["id"]} | ${ts["code"]} | ${ts["name"]} | account_id:${ts["account_id"]} | bal:${ts["balance"]} | trucks:${ts["truck_balance"]}');
  }
}
