import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== SYNCING SUPPLIERS OPENING BALANCES TO GL ===');

  // 1. Resolve Equity Account (23421)
  final eqRes = await c.from('accounts').select('id').eq('account_code', '23421').limit(1).maybeSingle();
  final equityAccountId = (eqRes?['id'] as num?)?.toInt() ?? 5109;
  print('Equity Account 23421 ID: $equityAccountId');

  // 2. Resolve Supplier Sub-ledger Accounts
  final accounts = await c.from('accounts').select('id, account_code, name').inFilter('account_code', ['21111', '21112', '21113', '21114', '21115', '21116']);
  final Map<String, int> codeToId = {
    for (final a in accounts) a['account_code'].toString(): (a['id'] as num).toInt(),
  };
  print('Resolved accounts: $codeToId');

  // 3. Fetch all suppliers with initial balance
  final suppliers = await c.from('suppliers').select();
  print('Found ${suppliers.length} suppliers in DB');

  for (final s in suppliers) {
    final id = s['id'].toString();
    final name = s['name']?.toString() ?? 'مورد';
    final type = (s['supplier_type']?.toString() ?? 'crop').toLowerCase();
    final code = s['code']?.toString() ?? '';
    final isMulti = s['is_multi_currency'] == true;
    final companyId = s['company_id']?.toString() ?? '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
    final sourceId = 'suppliers_$id';
    final desc = 'رصيد افتتاحي - $name';
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    // Determine target account ID
    int? targetAccountId = (s['account_id'] as num?)?.toInt();
    if (targetAccountId == null || targetAccountId == 0) {
      if (type == 'packaging' || type == 'sticker' || code.startsWith('70') || code.startsWith('71') || code.startsWith('72') || code.startsWith('73') || code.startsWith('74')) {
        targetAccountId = codeToId['21112'];
      } else if (type == 'shared' || code.startsWith('75') || code.startsWith('76') || code.startsWith('77') || code.startsWith('78') || code.startsWith('79')) {
        targetAccountId = codeToId['21114'];
      } else if (type == 'transport' || code.startsWith('6')) {
        targetAccountId = codeToId['21111'];
      } else if (type == 'shipping' || code.startsWith('9')) {
        targetAccountId = codeToId['21115'];
      } else if (type == 'clearing' || type == 'customs') {
        targetAccountId = codeToId['21116'];
      } else {
        targetAccountId = codeToId['21113'];
      }
      // Update supplier's account_id in database if needed
      if (targetAccountId != null) {
        await c.from('suppliers').update({'account_id': targetAccountId}).eq('id', id);
        print('Updated supplier $name ($code) account_id to $targetAccountId');
      }
    }

    if (targetAccountId == null) {
      print('❌ Could not resolve account for supplier $name ($type)');
      continue;
    }

    // Check existing JE
    final existingJe = await c.from('journal_entries').select('id').eq('source_type', 'opening_balance').eq('source_id', sourceId).maybeSingle();
    int jeId;
    if (existingJe != null) {
      jeId = (existingJe['id'] as num).toInt();
      print('Updating existing JE $jeId for supplier $name');
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
        entryNumber = 'OB-${code.isNotEmpty ? code : id.substring(0, 5)}';
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
      print('Created JE $jeId ($entryNumber) for supplier $name');
    }

    if (isMulti) {
      final balancesMap = s['initial_balances_by_currency'] as Map<String, dynamic>? ?? {};
      for (final entry in balancesMap.entries) {
        final cur = entry.key.toUpperCase();
        final item = entry.value as Map<String, dynamic>;
        final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final dir = (item['direction']?.toString() ?? 'CREDIT').toUpperCase();
        double rate = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        if (rate <= 0) {
          rate = (cur == 'USD') ? 50.0 : (cur == 'EUR' ? 55.0 : (cur == 'GBP' ? 65.0 : 1.0));
        }
        final baseAmt = amt * rate;

        if (amt > 0) {
          final isCredit = dir == 'CREDIT';
          // Line 1: Supplier Account (21112/21113/21114)
          await c.from('account_ledger_entries').insert({
            'journal_entry_id': jeId,
            'account_id': targetAccountId,
            'debit': isCredit ? 0 : amt,
            'credit': isCredit ? amt : 0,
            'currency': cur,
            'amount_in_base_currency': baseAmt,
            'description': '$desc ($cur)',
            'company_id': companyId,
          });

          // Line 2: Equity Account (23421)
          await c.from('account_ledger_entries').insert({
            'journal_entry_id': jeId,
            'account_id': equityAccountId,
            'debit': isCredit ? amt : 0,
            'credit': isCredit ? 0 : amt,
            'currency': cur,
            'amount_in_base_currency': baseAmt,
            'description': '$desc ($cur)',
            'company_id': companyId,
          });

          print('  -> Added $amt $cur ($baseAmt EGP) to Acc $targetAccountId & Equity $equityAccountId');
        }
      }
    } else {
      final amt = (s['initial_balance'] as num?)?.toDouble() ?? 0.0;
      final cur = (s['currency']?.toString() ?? 'EGP').toUpperCase();
      final dir = (s['initial_balance_direction']?.toString() ?? 'CREDIT').toUpperCase();
      if (amt > 0) {
        double rate = 1.0;
        if (cur == 'USD') rate = 50.0;
        else if (cur == 'EUR') rate = 55.0;
        else if (cur == 'GBP') rate = 65.0;
        final baseAmt = amt * rate;
        final isCredit = dir == 'CREDIT';

        // Line 1: Supplier Account
        await c.from('account_ledger_entries').insert({
          'journal_entry_id': jeId,
          'account_id': targetAccountId,
          'debit': isCredit ? 0 : amt,
          'credit': isCredit ? amt : 0,
          'currency': cur,
          'amount_in_base_currency': baseAmt,
          'description': desc,
          'company_id': companyId,
        });

        // Line 2: Equity Account
        await c.from('account_ledger_entries').insert({
          'journal_entry_id': jeId,
          'account_id': equityAccountId,
          'debit': isCredit ? amt : 0,
          'credit': isCredit ? 0 : amt,
          'currency': cur,
          'amount_in_base_currency': baseAmt,
          'description': desc,
          'company_id': companyId,
        });

        print('  -> Added $amt $cur ($baseAmt EGP) to Acc $targetAccountId & Equity $equityAccountId');
      }
    }
  }

  print('\n=== CHECKING ENTRIES IN v_journal_entry_lines ===');
  for (final code in ['21112', '21113', '21114', '23421']) {
    final accId = (code == '23421') ? equityAccountId : codeToId[code];
    if (accId != null) {
      final lines = await c.from('v_journal_entry_lines').select().eq('account_id', accId);
      print('Account $code (ID: $accId): ${lines.length} lines');
      for (final l in lines) {
        print('   Line: dr=${l['debit']}, cr=${l['credit']}, cur=${l['currency']}, base_cr=${l['base_credit']}, desc=${l['line_description'] ?? l['description']}');
      }
    }
  }
}
