import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Inspecting Shipment #1 ===');
  final s = await client.from('export_shipments').select().eq('id', 1).single();
  print('Shipment: ${s['shipment_no']}, status: ${s['status']}, notes: ${s['internal_notes']}');

  print('\n=== Inspecting Shipment #1 Items ===');
  final items = await client.from('export_shipment_items').select().eq('shipment_id', 1);
  for (final i in items) {
    print('Item: id=${i['id']}, prod=${i['product_name']}, qty=${i['quantity']}, amount=${i['amount']}');
  }

  print('\n=== Inspecting Journal Entry #36 ===');
  final je = await client.from('journal_entries').select().eq('id', 36).maybeSingle();
  print('JE #36: $je');

  final jeLines = await client.from('journal_entry_lines').select('*').eq('journal_entry_id', 36);
  print('JE #36 Lines (${jeLines.length}):');
  for (final l in jeLines) {
    print('Line: acct_id=${l['account_id']}, debit=${l['debit']}, credit=${l['credit']}, cost_center=${l['cost_center_id']}, desc=${l['description']}');
  }
}
