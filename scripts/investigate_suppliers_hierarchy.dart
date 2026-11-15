import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(
    SupabaseOptions.url,
    SupabaseOptions.anonKey,
  );

  await c.auth.signInWithPassword(
    email: 'mahmoud@gmail.com',
    password: '123456',
  );

  print('================================================================');
  print('1. ALL SUPPLIERS IN public.suppliers');
  print('================================================================');
  final suppliers = await c.from('suppliers').select('*').isFilter('deleted_at', null);
  print('Found ${suppliers.length} active suppliers:');
  for (final s in suppliers) {
    print('  ID=${s['id']} | Name=${s['name']} | Code=${s['code']} | supplier_type=${s['supplier_type']} | category=${s['supplier_category']} | account_id=${s['account_id']}');
  }

  print('\n================================================================');
  print('2. ALL TRANSPORT SUPPLIERS IN public.transport_suppliers');
  print('================================================================');
  final trans = await c.from('transport_suppliers').select('*').isFilter('deleted_at', null);
  print('Found ${trans.length} active transport_suppliers:');
  for (final t in trans) {
    print('  ID=${t['id']} | Name=${t['name']} | Code=${t['code']} | account_id=${t['account_id']}');
  }

  print('\n================================================================');
  print('3. ALL ACCOUNTS CURRENTLY UNDER 211 (LEVEL 3, 4, 5)');
  print('================================================================');
  final accounts = await c
      .from('accounts')
      .select('id, account_code, code, name, account_name, parent_id, level, is_leaf, allow_posting, company_id')
      .or('account_code.eq.211,account_code.like.211%')
      .isFilter('deleted_at', null)
      .order('account_code');

  print('Found ${accounts.length} accounts under 211:');
  for (final a in accounts) {
    print('  Code=${a['account_code']} | ID=${a['id']} | ParentID=${a['parent_id']} | Level=${a['level']} | Leaf=${a['is_leaf']} | Posting=${a['allow_posting']} | Name=${a['account_name']} (${a['name']}) | Company=${a['company_id']}');
  }

  print('\n================================================================');
  print('4. INVESTIGATING AFFECTED SUPPLIERS ACCOUNTS & LEDGER MOVEMENTS');
  print('================================================================');
  // Look for Ali, Yasser, Hamza, Galal
  final targetNames = ['علي', 'ياسر', 'حمزة', 'حمزه', 'جلال'];
  for (final name in targetNames) {
    final supp = suppliers.where((s) => (s['name'] as String? ?? '').contains(name)).toList();
    final tr = trans.where((t) => (t['name'] as String? ?? '').contains(name)).toList();
    final accs = accounts.where((a) => (a['account_name'] as String? ?? '').contains(name)).toList();
    print('\n-- Investigation for name containing "$name":');
    print('   suppliers table match: $supp');
    print('   transport_suppliers table match: $tr');
    print('   accounts table match: $accs');

    for (final a in accs) {
      final accId = a['id'];
      // Check movements in journal entries / lines
      try {
        final lines = await c.from('v_journal_entry_lines').select().eq('account_id', accId);
        print('   -> v_journal_entry_lines count for Account ID $accId (${a['account_code']}): ${lines.length}');
        for (final l in lines) {
          print('      Line: debit=${l['debit']}, credit=${l['credit']}, desc=${l['description']}');
        }
      } catch (e) {
        // try direct table if view fails
        print('   -> v_journal_entry_lines check failed: $e');
      }
    }
  }

  print('\n================================================================');
  print('5. CHECKING TRANSACTIONS & JOURNAL ENTRIES');
  print('================================================================');
  final aleLines = await c.from('account_ledger_entries').select('*').isFilter('deleted_at', null);
  print('Total active account_ledger_entries in DB: ${aleLines.length}');
  for (final l in aleLines) {
    print('  ALE: ID=${l['id']} | account_id=${l['account_id']} | debit=${l['debit']} | credit=${l['credit']} | desc=${l['description']}');
  }

  try {
    final tRows = await c.from('transport_transactions').select('*');
    print('Total transport_transactions: ${tRows.length}');
    for (final tr in tRows) {
      print('  TR: $tr');
    }
  } catch (e) {
    print('  transport_transactions error: $e');
  }

  print('\n================================================================');
  print('6. CHECKING DATABASE FUNCTIONS & TRIGGERS VIA RPC / SCHEMA');
  print('================================================================');
  // Check supplier_type enum or constraints
  print('Done data extraction.');
}
