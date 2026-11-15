import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== TOTAL ROWS IN v_journal_entry_lines ===');
  final allLines = await c.from('v_journal_entry_lines').select();
  print('Total rows in v_journal_entry_lines: ${allLines.length}');
  for (final l in allLines) {
    print('  Line: id=${l['id']}, acc=${l['account_id']}, code=${l['account_code']}, dr=${l['debit']}, cr=${l['credit']}, cur=${l['currency']}, status=${l['status']}');
  }

  print('\n=== TOTAL ROWS IN account_ledger_entries ===');
  final allAle = await c.from('account_ledger_entries').select();
  print('Total rows in account_ledger_entries: ${allAle.length}');
  for (final a in allAle) {
    print('  ALE: id=${a['id']}, je=${a['journal_entry_id']}, acc=${a['account_id']}, dr=${a['debit']}, cr=${a['credit']}, cur=${a['currency']}, del=${a['deleted_at']}');
  }

  print('\n=== TOTAL ROWS IN journal_entries ===');
  final allJe = await c.from('journal_entries').select();
  print('Total rows in journal_entries: ${allJe.length}');
  for (final j in allJe) {
    print('  JE: id=${j['id']}, num=${j['entry_number']}, del=${j['deleted_at']}, stat=${j['status']}');
  }
}
