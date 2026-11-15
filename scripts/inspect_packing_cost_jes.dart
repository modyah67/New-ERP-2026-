import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  // 1. Check resolve_gl_account for 2000 and 2112 and 21111
  final r2000 = await c.rpc('resolve_gl_account', params: {'p_account_code': '2000'});
  final r2112 = await c.rpc('resolve_gl_account', params: {'p_account_code': '2112'});
  final r21111 = await c.rpc('resolve_gl_account', params: {'p_account_code': '21111'});
  print('resolve_gl_account(2000): $r2000');
  print('resolve_gl_account(2112): $r2112');
  print('resolve_gl_account(21111): $r21111');

  // Check account rows for these IDs
  final accRows = await c.from('accounts').select('id, account_code, account_name').inFilter('id', [r2000, r2112, r21111].where((x) => x != null).toList());
  print('Resolved Accounts: $accRows');

  // 2. Check packing_order_cost_items
  final costItems = await c.from('packing_order_cost_items').select('*').limit(20);
  print('\n=== packing_order_cost_items (${costItems.length}) ===');
  for (var ci in costItems) {
    print('${ci["id"]} | name:${ci["name"]} | cat:${ci["category"]} | supp_id:${ci["supplier_id"]} | trans_id:${ci["transport_supplier_id"]} | amount:${ci["base_amount"]}');
  }

  // 3. Check existing journal entries for packing_order_costs
  final jes = await c.from('journal_entries').select('id, entry_number, description, source_type, source_id').eq('source_type', 'packing_order_costs').limit(10);
  print('\n=== journal_entries for packing_order_costs (${jes.length}) ===');
  for (var je in jes) {
    print('${je["id"]} | ${je["entry_number"]} | ${je["description"]} | source_id:${je["source_id"]}');
    final lines = await c.from('account_ledger_entries').select('account_id, debit, credit, description').eq('journal_entry_id', je["id"]);
    for (var l in lines) {
      final acc = await c.from('accounts').select('account_code, account_name').eq('id', l['account_id']).maybeSingle();
      print('   -> Acc: ${acc?["account_code"]} (${acc?["account_name"]}) | debit: ${l["debit"]} | credit: ${l["credit"]} | desc: ${l["description"]}');
    }
  }
}
