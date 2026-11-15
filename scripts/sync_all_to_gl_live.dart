import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== AUTO-SYNCING ALL ENTITIES OPENING BALANCES TO GL ===');

  // Resolve Equity Account 23421
  final eqAcc = await c.from('accounts').select('id').eq('account_code', '23421').maybeSingle();
  final equityAccountId = (eqAcc?['id'] as num?)?.toInt() ?? 5109;

  // 1. SYNC CUSTOMERS
  final customers = await c.from('customers').select().gt('initial_balance', 0);
  print('\nFound ${customers.length} customer(s) with initial_balance > 0');

  for (final cust in customers) {
    final id = cust['id'];
    final name = cust['name'] ?? 'عميل';
    final amount = (cust['initial_balance'] as num).toDouble();
    final currency = (cust['currency']?.toString() ?? 'EGP').toUpperCase();
    final companyId = cust['company_id'] ?? '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
    final direction = (cust['initial_balance_direction']?.toString() ?? 'DEBIT').toUpperCase();
    final compType = cust['company_type']?.toString();
    
    // Resolve account_id
    int? accountId = (cust['account_id'] as num?)?.toInt();
    if (accountId == null) {
      final isLocal = (compType ?? '').contains('local') || (compType ?? '').contains('محلي');
      final targetCode = isLocal ? '12512' : '12511';
      final accRes = await c.from('accounts').select('id').eq('account_code', targetCode).limit(1).maybeSingle();
      accountId = (accRes?['id'] as num?)?.toInt() ?? (isLocal ? 3615 : 3614);
    }

    // Exchange rate
    double rate = 1.0;
    if (currency != 'EGP' && currency != 'ج.م') {
      final erList = await c.from('exchange_rates').select('rate_to_egp').eq('currency_code', currency).order('id', ascending: false).limit(1);
      if (erList.isNotEmpty) {
        rate = (erList.first['rate_to_egp'] as num).toDouble();
      } else {
        rate = (currency == 'USD') ? 50.0 : (currency == 'EUR' ? 55.0 : 1.0);
      }
    }
    final baseAmount = amount * rate;
    final sourceId = 'customers_$id';
    final desc = 'رصيد افتتاحي - $name';
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    // Check existing JE
    final existingJe = await c.from('journal_entries').select('id').eq('source_type', 'opening_balance').eq('source_id', sourceId).maybeSingle();
    int jeId;

    if (existingJe != null) {
      jeId = (existingJe['id'] as num).toInt();
      print('Updating existing JE $jeId for customer $name');
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
      } catch (_) {
        entryNumber = 'OB-${id.toString().padLeft(5, '0')}';
      }

      final newJe = await c.from('journal_entries').insert({
        'source_type': 'opening_balance',
        'source_id': sourceId,
        'entry_number': entryNumber,
        'entry_date': todayStr,
        'description': desc,
        'status': 'posted',
        'company_id': companyId,
      }).select('id').single();
      jeId = (newJe['id'] as num).toInt();
      print('Created JE $jeId ($entryNumber) for customer $name');
    }

    final bool isDebit = direction == 'DEBIT';

    // Line 1: Customer Account
    await c.from('account_ledger_entries').insert({
      'journal_entry_id': jeId,
      'account_id': accountId,
      'debit': isDebit ? amount : 0,
      'credit': isDebit ? 0 : amount,
      'currency': currency,
      'amount_in_base_currency': baseAmount,
      'description': desc,
      'company_id': companyId,
    });

    // Line 2: Equity Account 23421
    await c.from('account_ledger_entries').insert({
      'journal_entry_id': jeId,
      'account_id': equityAccountId,
      'debit': isDebit ? 0 : amount,
      'credit': isDebit ? amount : 0,
      'currency': currency,
      'amount_in_base_currency': baseAmount,
      'description': desc,
      'company_id': companyId,
    });

    print('✅ Synced customer $name: $amount $currency ($baseAmount EGP) to Account $accountId & Equity $equityAccountId');
  }

  print('\n=== VERIFYING FINAL LEDGER ENTRIES ON LIVE ===');
  final ales = await c.from('account_ledger_entries').select();
  print('Total account_ledger_entries: ${ales.length}');
  for (final a in ales) {
    print('  ALE: id=${a['id']}, je=${a['journal_entry_id']}, acc=${a['account_id']}, dr=${a['debit']}, cr=${a['credit']}, cur=${a['currency']}, base=${a['amount_in_base_currency']}, desc=${a['description']}');
  }

  final jes = await c.from('journal_entries').select();
  print('\nTotal journal_entries: ${jes.length}');
  for (final j in jes) {
    print('  JE: id=${j['id']}, num=${j['entry_number']}, source=${j['source_id']}, date=${j['entry_date']}, desc=${j['description']}');
  }
}
