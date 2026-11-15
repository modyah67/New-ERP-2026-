import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // Query triggers on suppliers via RPC or check if any trigger is active
  try {
    // Let's test what RPCs exist or query information_schema.triggers
    final res = await c.from('information_schema.triggers').select().eq('event_object_table', 'suppliers');
    print('Triggers on suppliers: $res');
  } catch (e) {
    print('Failed direct select: $e');
  }

  // Let's test inserting a row into shipping_companies to see if shipping_companies creates a JE!
  print('\nTesting shipping_companies trigger:');
  try {
    final sc = await c.from('shipping_companies').insert({
      'code': '99998',
      'name': 'شركة شحن اختبارية',
      'initial_balance': 1000.0,
      'initial_balance_direction': 'CREDIT',
      'currency': 'EGP',
      'account_id': 5106,
      'company_id': '9aae4cab-8ee3-4bc1-8e05-990894869c2e',
    }).select().single();
    final scId = sc['id'];
    print('Inserted shipping company: $scId');

    final jes = await c.from('journal_entries').select().eq('source_id', 'shipping_companies_$scId');
    print('JEs for shipping company: ${jes.length}');
    if (jes.isNotEmpty) {
      print('JE: ${jes.first}');
      final lines = await c.from('account_ledger_entries').select().eq('journal_entry_id', jes.first['id']);
      print('Lines in account_ledger_entries: ${lines.length}');
    }

    // Cleanup
    await c.from('account_ledger_entries').delete().eq('journal_entry_id', jes.isNotEmpty ? jes.first['id'] : -1);
    await c.from('journal_entries').delete().eq('source_id', 'shipping_companies_$scId');
    await c.from('shipping_companies').delete().eq('id', scId);
    print('Cleaned up shipping company test.');
  } catch (e) {
    print('Error testing shipping company: $e');
  }
}
