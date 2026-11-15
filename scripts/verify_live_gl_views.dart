import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== VERIFYING COA & GL VIEWS ON LIVE ===\n');

  // Account 12511
  final l12511 = await c.from('account_ledger_entries').select().eq('account_id', 3614);
  print('Account 12511 (Export Customers):');
  print('  Count: ${l12511.length}');
  for (final r in l12511) {
    print('  Entry: JE=${r['journal_entry_id']}, Debit=${r['debit']}, Credit=${r['credit']}, Cur=${r['currency']}, BaseAmt=${r['amount_in_base_currency']}, Desc=${r['description']}');
  }

  // Account 23421
  final l23421 = await c.from('account_ledger_entries').select().eq('account_id', 5109);
  print('\nAccount 23421 (Opening Balance Suspense):');
  print('  Count: ${l23421.length}');
  for (final r in l23421) {
    print('  Entry: JE=${r['journal_entry_id']}, Debit=${r['debit']}, Credit=${r['credit']}, Cur=${r['currency']}, BaseAmt=${r['amount_in_base_currency']}, Desc=${r['description']}');
  }

  // Journal Entry
  final je = await c.from('journal_entries').select().eq('id', 1).single();
  print('\nJournal Entry 1:');
  print('  Number: ${je['entry_number']}, Date: ${je['entry_date']}, Source: ${je['source_id']}, Status: ${je['status']}, Desc: ${je['description']}');
}
