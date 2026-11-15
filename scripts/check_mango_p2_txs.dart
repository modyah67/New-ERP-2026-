import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final p2Txs = await client.from('cost_center_transactions').select().eq('cost_center_id', 'CC-MANGO-2026-2027-P2');
  print('Txs for CC-MANGO-2026-2027-P2: ${p2Txs.length}');
  for (final t in p2Txs) {
    print('  - id: ${t['id']}, source_type: ${t['source_type']}, source_id: ${t['source_id']}, amount: ${t['amount']}, item: ${t['item_name']}');
  }

  final y2Txs = await client.from('cost_center_transactions').select().eq('cost_center_id', 'CC-MANGO-2027-2028');
  print('Txs for CC-MANGO-2027-2028: ${y2Txs.length}');
  for (final t in y2Txs) {
    print('  - id: ${t['id']}, source_type: ${t['source_type']}, source_id: ${t['source_id']}, amount: ${t['amount']}, item: ${t['item_name']}');
  }

  final ft = await client.from('fruit_types').select('id, name, cost_center_id').ilike('name', '%مانج%');
  print('Fruit types for mango: $ft');
}
