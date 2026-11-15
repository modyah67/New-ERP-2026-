import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
  final cats = await c.from('cost_report_categories').select('id, name, scope, supplier_type, account_id, cost_center_id').order('id');
  for (final cat in cats) {
    print('${cat['id']} | ${cat['name']} | supp_type: ${cat['supplier_type']} | scope: ${cat['scope']} | acc: ${cat['account_id']} | cc: ${cat['cost_center_id']}');
  }

  // Also test what list_cost_report_categories RPC returns
  try {
    final rpcRes = await c.rpc('list_cost_report_categories');
    print('\nRPC list_cost_report_categories first 3:');
    for (final r in (rpcRes as List).take(3)) {
      print(r);
    }
  } catch (e) {
    print('\nRPC error: $e');
  }
}
