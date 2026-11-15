import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('================================================================');
  print('1. INSPECT CUSTOMER "mohamed" / "12511" IN TABLE customers');
  print('================================================================');

  final customers = await c
      .from('customers')
      .select()
      .limit(10);
  print('Sample customer fields: ${customers.isNotEmpty ? customers.first.keys : "None"}');
  
  final matchedCustomers = await c
      .from('customers')
      .select()
      .or('name.ilike.%mohamed%,code.ilike.%12511%');
  print('Matched customers count: ${matchedCustomers.length}');
  for (final cust in matchedCustomers) {
    print('Customer Record:');
    cust.forEach((k, v) => print('  $k: $v'));
  }

  // Also search in accounts table for 12511
  print('\n----------------------------------------------------------------');
  print('Check account 12511 in accounts table:');
  final accounts = await c
      .from('accounts')
      .select('id, account_code, name, account_name, parent_id, level, is_leaf, allow_posting, created_at')
      .or('account_code.eq.12511,account_code.like.12511%');
  for (final a in accounts) {
    print('  $a');
  }

  print('\n================================================================');
  print('2. QUERY JOURNAL ENTRIES & LEDGER FOR CUSTOMER');
  print('================================================================');

  final jes = await c
      .from('journal_entries')
      .select('id, entry_number, entry_date, description, source_type, source_id, status, created_at')
      .or('source_type.ilike.%customer%,source_type.ilike.%opening%,source_id.ilike.%12511%,description.ilike.%mohamed%,description.ilike.%12511%')
      .order('id', ascending: false)
      .limit(20);

  print('Journal entries found (${jes.length}):');
  for (final je in jes) {
    print('  $je');
  }

  // If customer found, search by customer ID as source_id
  if (matchedCustomers.isNotEmpty) {
    final custId = matchedCustomers.first['id'];
    print('\nSearching journal_entries specifically for customer ID: $custId');
    final custJes = await c
        .from('journal_entries')
        .select()
        .or('source_id.eq.$custId,source_id.eq.customers_$custId,source_id.eq.customer_$custId');
    print('Found ${custJes.length} journal entries for customer ID $custId:');
    for (final j in custJes) {
      print('  $j');
    }

    // Check account_ledger_entries for customer account_id
    final custAccId = matchedCustomers.first['account_id'];
    print('\nCustomer account_id is: $custAccId');
    if (custAccId != null) {
      final ales = await c
          .from('account_ledger_entries')
          .select('id, journal_entry_id, account_id, debit, credit, currency, description, created_at')
          .eq('account_id', custAccId);
      print('Found ${ales.length} ledger entries for customer account_id $custAccId:');
      for (final l in ales) {
        print('  $l');
      }
    }
  }
}
