import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Querying cost_center_transactions for CC-MANGO-2026-2027 ===\n');

  final cctData = await client
      .from('cost_center_transactions')
      .select()
      .or('cost_center_id.eq.CC-MANGO-2026-2027,cost_center_id.eq.16')
      .order('transaction_date', ascending: false);

  print('Total CCT Rows: ${cctData.length}');
  for (final c in cctData) {
    final sType = c['source_type'];
    final sId = c['source_id'];
    final item = c['item_name'];
    final cat = c['category'];
    final qty = c['quantity'];
    final unitPrice = c['unit_price'];
    final amt = c['amount'];
    final notes = c['notes'];
    final supp = c['supplier_name'];

    print('Row: source_type=$sType, source_id=$sId');
    print('  - item: $item');
    print('  - cat: $cat');
    print('  - supplier/customer: $supp');
    print('  - qty: $qty, unit_price: $unitPrice, amount: $amt');
    print('  - notes: $notes\n');
  }

  print('=== Checking JE #36 account_ledger_entries ===');
  final aleRows = await client
      .from('account_ledger_entries')
      .select('id, debit, credit, cost_center_id, description')
      .eq('journal_entry_id', 36);

  for (final ale in aleRows) {
    print('ALE #${ale['id']}: debit=${ale['debit']}, credit=${ale['credit']}, cost_center_id=${ale['cost_center_id']}, desc=${ale['description']}');
  }
}
