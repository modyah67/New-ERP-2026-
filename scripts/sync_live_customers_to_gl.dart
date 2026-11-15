import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== SYNCING LIVE CUSTOMERS TO GL ===');

  final customers = await c.from('customers').select().gt('initial_balance', 0);
  print('Found ${customers.length} customer(s) with initial balance > 0:');

  for (final cust in customers) {
    final id = cust['id'];
    final name = cust['name'];
    final amount = (cust['initial_balance'] as num).toDouble();
    final currency = cust['currency'] ?? 'USD';
    final companyId = cust['company_id'];
    final accountId = cust['account_id'] ?? 3614;
    final sourceId = 'customers_$id';
    final desc = 'رصيد افتتاحي - $name';

    print('\nSyncing customer: ID=$id, Name=$name, InitBal=$amount $currency, AccountId=$accountId');

    // Get equity account 23421
    final eqAcc = await c.from('accounts').select('id').eq('account_code', '23421').single();
    final equityAccountId = eqAcc['id'] as int;

    // Exchange rate
    double rate = 1.0;
    if (currency != 'EGP') {
      final erList = await c.from('exchange_rates').select('rate_to_egp').eq('currency_code', currency).order('id', ascending: false).limit(1);
      if (erList.isNotEmpty) {
        rate = (erList.first['rate_to_egp'] as num).toDouble();
      } else {
        rate = 50.0;
      }
    }
    final baseAmount = amount * rate;

    // Check if journal entry exists
    final existingJe = await c.from('journal_entries').select('id').eq('source_type', 'opening_balance').eq('source_id', sourceId).maybeSingle();
    int jeId;
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    if (existingJe != null) {
      jeId = existingJe['id'] as int;
      print('Updating existing JE: $jeId');
      await c.from('account_ledger_entries').delete().eq('journal_entry_id', jeId);
      await c.from('journal_entries').update({
        'description': desc,
        'status': 'posted',
        'entry_date': todayStr,
      }).eq('id', jeId);
    } else {
      String entryNumber = 'OB-00001';
      try {
        final seq = await c.rpc('fn_get_next_sequence', params: {
          'p_company_id': companyId,
          'p_document_type_code': 'opening_balance',
        });
        if (seq != null && seq.toString().isNotEmpty) {
          entryNumber = seq.toString();
        }
      } catch (_) {}

      final newJe = await c.from('journal_entries').insert({
        'source_type': 'opening_balance',
        'source_id': sourceId,
        'entry_number': entryNumber,
        'entry_date': todayStr,
        'description': desc,
        'status': 'posted',
        'company_id': companyId,
      }).select('id').single();
      jeId = newJe['id'] as int;
      print('Created new JE: $jeId, Number: $entryNumber');
    }

    // Insert 2 lines
    // Line 1: Customer Account (12511)
    await c.from('account_ledger_entries').insert({
      'journal_entry_id': jeId,
      'account_id': accountId,
      'debit': amount,
      'credit': 0,
      'currency': currency,
      'amount_in_base_currency': baseAmount,
      'description': desc,
      'company_id': companyId,
    });

    // Line 2: Equity Account (23421)
    await c.from('account_ledger_entries').insert({
      'journal_entry_id': jeId,
      'account_id': equityAccountId,
      'debit': 0,
      'credit': amount,
      'currency': currency,
      'amount_in_base_currency': baseAmount,
      'description': desc,
      'company_id': companyId,
    });

    print('✅ Synced customer $name: Debit $amount $currency ($baseAmount EGP) to Account $accountId, Credit to Equity Account $equityAccountId');
  }

  print('\n=== VERIFYING FINAL LEDGER ENTRIES ===');
  final ales = await c.from('account_ledger_entries').select();
  print('Total account_ledger_entries in DB: ${ales.length}');
  for (final a in ales) {
    print('  Line: ID=${a['id']}, JE=${a['journal_entry_id']}, Acc=${a['account_id']}, Dr=${a['debit']}, Cr=${a['credit']}, Cur=${a['currency']}, Base=${a['amount_in_base_currency']}');
  }
}
