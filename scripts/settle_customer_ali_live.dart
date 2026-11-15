import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== SETTLING CUSTOMER ALI OPENING BALANCE ON LIVE ===');

  final cust = await c.from('customers').select().eq('id', 1).single();
  final companyId = cust['company_id'] ?? '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
  final accountId = cust['account_id'] ?? 3614;
  final currency = cust['currency'] ?? 'USD';
  final amount = (cust['initial_balance'] as num).toDouble();
  final name = cust['name'] ?? 'ali';
  final desc = 'رصيد افتتاحي - $name';
  final sourceId = 'customers_${cust['id']}';

  // Get equity account 23421
  final eqAcc = await c.from('accounts').select('id').eq('account_code', '23421').single();
  final equityAccountId = eqAcc['id'] as int;

  // Get exchange rate
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

  print('Customer: ID=${cust['id']}, Name=$name, Acc=$accountId, EquityAcc=$equityAccountId, Amt=$amount $currency, Rate=$rate, BaseAmt=$baseAmount');

  // Check if journal entry exists
  final existingJe = await c.from('journal_entries').select().or('source_id.eq.$sourceId,source_id.eq.${cust['id']}').maybeSingle();
  int jeId;
  if (existingJe != null) {
    jeId = existingJe['id'] as int;
    print('Journal entry already exists: ID=$jeId');
    await c.from('account_ledger_entries').delete().eq('journal_entry_id', jeId);
    await c.from('journal_entries').update({
      'description': desc,
      'source_id': sourceId,
      'status': 'posted',
      'entry_date': DateTime.now().toIso8601String().split('T').first,
    }).eq('id', jeId);
  } else {
    // Generate next entry number
    String entryNumber = 'OB-00001';
    try {
      final seqRes = await c.rpc('fn_get_next_sequence', params: {
        'p_company_id': companyId,
        'p_document_type_code': 'opening_balance',
      });
      if (seqRes != null && seqRes.toString().isNotEmpty) {
        entryNumber = seqRes.toString();
      }
    } catch (_) {
      entryNumber = 'OB-00001';
    }

    final newJe = await c.from('journal_entries').insert({
      'source_type': 'opening_balance',
      'source_id': sourceId,
      'entry_number': entryNumber,
      'entry_date': DateTime.now().toIso8601String().split('T').first,
      'description': desc,
      'status': 'posted',
      'company_id': companyId,
    }).select().single();
    jeId = newJe['id'] as int;
    print('Created new journal entry: ID=$jeId, Number=$entryNumber');
  }

  // Insert ledger entries
  // Line 1: Customer Account (Debit)
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

  // Line 2: Equity Account 23421 (Credit)
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

  print('✅ Successfully created double-entry ledger lines for customer $name!');

  // Verify accounts
  final check12511 = await c.from('account_ledger_entries').select().eq('account_id', accountId);
  final check23421 = await c.from('account_ledger_entries').select().eq('account_id', equityAccountId);
  print('Verification:');
  print('  Lines in 12511 (Export Customers): ${check12511.length}');
  print('  Lines in 23421 (Opening Balance Suspense): ${check23421.length}');
}
