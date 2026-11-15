import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final compId = '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
  print('=== SEEDING PACKAGING AND SHARED SUPPLIERS & SYNCING TO GL ===');

  // 1. Packaging Supplier (70000) -> 21112
  final packSupplier = await c.from('suppliers').upsert({
    'code': '70000',
    'supplier_code': '70000',
    'name': 'مورد مواد تعبئة وتغليف',
    'supplier_type': 'packaging',

    'account_id': 5103, // 21112
    'is_multi_currency': true,
    'initial_balance': 17100.0,
    'currency': 'MULTI',
    'company_id': compId,
    'initial_balances_by_currency': {
      'EGP': {'amount': 100.0, 'currency': 'EGP', 'direction': 'CREDIT', 'exchange_rate': 1.0},
      'USD': {'amount': 100.0, 'currency': 'USD', 'direction': 'CREDIT', 'exchange_rate': 50.0},
      'EUR': {'amount': 100.0, 'currency': 'EUR', 'direction': 'CREDIT', 'exchange_rate': 55.0},
      'GBP': {'amount': 100.0, 'currency': 'GBP', 'direction': 'CREDIT', 'exchange_rate': 65.0},
    },
  }, onConflict: 'code').select('id').single();

  print('✅ Packaging supplier ready: ${packSupplier['id']}');

  // 2. Shared Supplier (75000) -> 21114
  final sharedSupplier = await c.from('suppliers').upsert({
    'code': '75000',
    'supplier_code': '75000',
    'name': 'مورد مشترك محاصيل وتعبئة',
    'supplier_type': 'shared',
    'category': 'shared',
    'account_id': 5105, // 21114
    'is_multi_currency': true,
    'initial_balance': 17100.0,
    'currency': 'MULTI',
    'company_id': compId,
    'initial_balances_by_currency': {
      'EGP': {'amount': 100.0, 'currency': 'EGP', 'direction': 'CREDIT', 'exchange_rate': 1.0},
      'USD': {'amount': 100.0, 'currency': 'USD', 'direction': 'CREDIT', 'exchange_rate': 50.0},
      'EUR': {'amount': 100.0, 'currency': 'EUR', 'direction': 'CREDIT', 'exchange_rate': 55.0},
      'GBP': {'amount': 100.0, 'currency': 'GBP', 'direction': 'CREDIT', 'exchange_rate': 65.0},
    },
  }, onConflict: 'code').select('id').single();

  print('✅ Shared supplier ready: ${sharedSupplier['id']}');

  // Now sync both to GL
  final items = [
    {
      'id': packSupplier['id'],
      'name': 'مورد مواد تعبئة وتغليف',
      'code': '70000',
      'type': 'packaging',
      'acc': 5103, // 21112
    },
    {
      'id': sharedSupplier['id'],
      'name': 'مورد مشترك محاصيل وتعبئة',
      'code': '75000',
      'type': 'shared',
      'acc': 5105, // 21114
    },
  ];

  for (final it in items) {
    final supId = it['id'];
    final sourceId = 'suppliers_$supId';
    final desc = 'رصيد أول المدة للمورد: ${it['name']}';
    final jeNum = 'OB-${it['code']}';

    final existing = await c.from('journal_entries').select('id').eq('source_id', sourceId).eq('company_id', compId).maybeSingle();
    final int jeId;
    if (existing != null) {
      jeId = (existing['id'] as num).toInt();
      await c.from('journal_entries').update({'description': desc}).eq('id', jeId);
      await c.from('account_ledger_entries').delete().eq('journal_entry_id', jeId);
    } else {
      final ins = await c.from('journal_entries').insert({
        'entry_number': jeNum,
        'entry_date': DateTime.now().toIso8601String().substring(0, 10),
        'description': desc,
        'source_id': sourceId,
        'company_id': compId,
        'status': 'POSTED',
      }).select('id').single();
      jeId = (ins['id'] as num).toInt();
    }

    final currencies = [
      {'cur': 'EGP', 'amt': 100.0, 'rate': 1.0},
      {'cur': 'USD', 'amt': 100.0, 'rate': 50.0},
      {'cur': 'EUR', 'amt': 100.0, 'rate': 55.0},
      {'cur': 'GBP', 'amt': 100.0, 'rate': 65.0},
    ];

    for (final curr in currencies) {
      final cur = curr['cur'] as String;
      final amt = curr['amt'] as double;
      final rate = curr['rate'] as double;
      final baseAmt = amt * rate;

      // Credit: Sub-ledger (21112 or 21114)
      await c.from('account_ledger_entries').insert({
        'journal_entry_id': jeId,
        'account_id': it['acc'],
        'debit': 0.0,
        'credit': amt,
        'currency': cur,
        'amount_in_base_currency': baseAmt,
        'description': '$desc ($cur)',
        'company_id': compId,
      });

      // Debit: Equity 23421
      await c.from('account_ledger_entries').insert({
        'journal_entry_id': jeId,
        'account_id': 5109,
        'debit': amt,
        'credit': 0.0,
        'currency': cur,
        'amount_in_base_currency': baseAmt,
        'description': '$desc ($cur)',
        'company_id': compId,
      });
    }

    print('✅ Synced 4 multi-currency lines for ${it['name']} to Acc ${it['acc']} & Equity 5109');
  }

  print('\n=== VERIFYING FINAL BALANCES ===');
  for (final code in ['21112', '21113', '21114', '23421']) {
    final lines = await c.from('v_journal_entry_lines').select().eq('account_code', code);
    print('Account $code has ${lines.length} lines in General Ledger.');
  }
}
