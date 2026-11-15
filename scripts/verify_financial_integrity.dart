import 'package:supabase/supabase.dart';

void main() async {
  print('====================================================');
  print('FINANCIAL INTEGRITY & HIERARCHY VERIFICATION');
  print('====================================================');

  final c = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  await c.auth.signInWithPassword(email: 'eslam@gmail.com', password: '123456');

  // 1. Ledger Entries
  final ledger = await c.from('account_ledger_entries').select('id, account_id, debit, credit, currency');
  double totalDebit = 0;
  double totalCredit = 0;
  for (final l in (ledger as List)) {
    totalDebit += (l['debit'] as num?)?.toDouble() ?? 0.0;
    totalCredit += (l['credit'] as num?)?.toDouble() ?? 0.0;
  }
  print('✓ Ledger Entries: ${ledger.length}');
  print('✓ Total Debits:  $totalDebit');
  print('✓ Total Credits: $totalCredit');
  print('✓ Balance Equality: ${totalDebit == totalCredit ? "BALANCED ✅" : "IMBALANCE ❌"}');

  // 2. Journal Entry Lines View
  final vLines = await c.from('v_journal_entry_lines').select('id, account_id, account_code, account_name, debit, credit').limit(10);
  print('\nSample v_journal_entry_lines:');
  for (final v in (vLines as List)) {
    print('  Line ID ${v['id']}: Acc ID ${v['account_id']} | Code: ${v['account_code']} | Name: ${v['account_name']} | Dr: ${v['debit']} | Cr: ${v['credit']}');
  }

  // 3. Level Breakdown
  final accounts = await c.from('accounts').select('id, account_code, name, account_name, level, is_leaf, allow_posting, parent_id').order('account_code');
  final byLevel = <int, int>{};
  for (final a in (accounts as List)) {
    final lvl = a['level'] as int? ?? 0;
    byLevel[lvl] = (byLevel[lvl] ?? 0) + 1;
  }
  print('\nAccounts count by level:');
  for (final entry in (byLevel.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
    print('  Level ${entry.key}: ${entry.value} accounts');
  }

  // 4. Roots
  final roots = accounts.where((a) => a['parent_id'] == null).toList();
  print('\nRoot Accounts (Level 1):');
  for (final r in roots) {
    print('  [${r['account_code']}] ${r['account_name']} (ID: ${r['id']})');
  }

  // 5. Level 2 Major Groups
  final l2 = accounts.where((a) => a['level'] == 2).toList();
  print('\nLevel 2 Major Groups:');
  for (final g in l2) {
    print('  [${g['account_code']}] ${g['account_name']} (parent ID: ${g['parent_id']})');
  }
}
