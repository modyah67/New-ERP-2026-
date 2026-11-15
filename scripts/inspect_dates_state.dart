import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final txs = await client.from('cost_center_transactions').select().eq('cost_center_id', 'CC-DATES-2026-2027');
  print('Transactions for CC-DATES-2026-2027: ${txs.length}');
  for (final t in txs) {
    print('  ID: ${t['id']}, Date: ${t['transaction_date']}, SourceType: ${t['source_type']}, SourceId: ${t['source_id']}, Item: ${t['item_name']}, Amount: ${t['amount']}');
  }

  final cc = await client.from('cost_centers').select().eq('code', 'CC-DATES-2026-2027').single();
  print('CC Dates: season_number=${cc['season_number']}, closure_count=${cc['closure_count']}, status=${cc['status']}');
}
