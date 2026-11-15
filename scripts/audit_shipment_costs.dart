import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== 1. Checking shipment_cost_items table ===');
  final items = await c.from('shipment_cost_items').select('*').limit(10);
  print('Sample shipment_cost_items count: ${items.length}');
  for (final it in items) {
    print('Item: id=${it['id']}, cat=${it['category']}, report_cat=${it['report_category_id']}, desc=${it['description']}, exp_acct=${it['expense_account_id']}, supp=${it['supplier_id']}, total=${it['total_price']}, je_id=${it['journal_entry_id']}, status=${it['payment_status']}');
  }

  print('\n=== 2. Testing rpc_sync_shipment_cost_accruals ===');
  try {
    final res = await c.rpc('rpc_sync_shipment_cost_accruals', params: {'p_shipment_id': 1});
    print('rpc_sync_shipment_cost_accruals result: $res');
  } catch (e) {
    print('rpc_sync_shipment_cost_accruals error: $e');
  }

  print('\n=== 3. Checking Journal Entries for shipment_cost_item or shipment_cost_accrual ===');
  final jes = await c.from('journal_entries').select('id, source_type, source_id, description').inFilter('source_type', ['shipment_cost_accrual', 'expense_payment', 'export_shipment']).limit(10);
  print('Found JEs: ${jes.length}');
  for (final j in jes) {
    print('JE: id=${j['id']}, type=${j['source_type']}, source_id=${j['source_id']}, desc=${j['description']}');
  }

  print('\n=== 4. Checking 341 accounts in accounts table ===');
  final accts = await c.from('accounts').select('id, account_code, account_name, is_leaf, allow_posting').like('account_code', '341%');
  for (final a in accts) {
    print('Account: code=${a['account_code']}, id=${a['id']}, name=${a['account_name']}, leaf=${a['is_leaf']}, posting=${a['allow_posting']}');
  }
}
