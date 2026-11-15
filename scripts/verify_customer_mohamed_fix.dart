import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('================================================================');
  print('VERIFYING CUSTOMER MOHAMED FIX ON LIVE');
  print('================================================================');

  // 1. Fetch current mohamed record
  final existing = await c.from('customers').select().eq('id', 1).maybeSingle();
  if (existing != null) {
    print('Found existing customer: id=${existing['id']}, name=${existing['name']}, code=${existing['code']}');
    print('Deleting customer id=1 to ensure fresh trigger recreation...');
    await c.from('customers').delete().eq('id', 1);
    print('Customer id=1 deleted.');
  }

  // 2. Re-insert customer mohamed (100 USD, DEBIT)
  print('\nRe-inserting customer mohamed with 100 USD DEBIT...');
  final inserted = await c.from('customers').insert({
    'name': 'mohamed',
    'code': '12000',
    'company_type': 'export',
    'currency': 'USD',
    'initial_balance': 100.0,
    'initial_balance_direction': 'DEBIT',
    'company_id': '9aae4cab-8ee3-4bc1-8e05-990894869c2e',
    'city': 'uhkj',
    'country': 'jvgjh',
  }).select().single();

  final newId = inserted['id'];
  print('Customer re-created successfully: id=$newId, account_id=${inserted['account_id']}');

  // 3. Check for generated journal entry
  final sourceId = 'customers_$newId';
  print('\nQuerying journal_entries for source_id: $sourceId or $newId...');
  final jes = await c
      .from('journal_entries')
      .select('id, entry_number, entry_date, source_type, source_id, description, status, company_id')
      .or('source_id.eq.$sourceId,source_id.eq.$newId')
      .order('id', ascending: false);

  if (jes.isEmpty) {
    print('⚠️ No journal entry found yet. The trigger may not have been executed on the live DB yet.');
    return;
  }

  print('✅ Found ${jes.length} Journal Entry:');
  final je = jes.first;
  final jeId = je['id'];
  print('  JE ID: $jeId | Number: ${je['entry_number']} | Date: ${je['entry_date']} | Desc: ${je['description']} | Status: ${je['status']}');

  // 4. Query ledger entries
  final lines = await c
      .from('account_ledger_entries')
      .select('id, account_id, debit, credit, currency, amount_in_base_currency, description')
      .eq('journal_entry_id', jeId)
      .order('id', ascending: true);

  print('\n✅ Found ${lines.length} Account Ledger Entries:');
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    print('  Line ${i + 1}: Account=${line['account_id']} | Debit=${line['debit']} | Credit=${line['credit']} | Cur=${line['currency']} | BaseAmt=${line['amount_in_base_currency']} | Desc=${line['description']}');
  }

  print('\n================================================================');
  print('VERIFICATION COMPLETE');
  print('================================================================');
}
