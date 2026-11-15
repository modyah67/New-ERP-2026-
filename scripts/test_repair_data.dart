import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
  print('Auth as: ${c.auth.currentUser?.email}');

  // Test update on account_ledger_entries where journal_entry_id = 36 and account_id = 58
  try {
    final res = await c
        .from('account_ledger_entries')
        .update({'account_id': 5396, 'description': 'عهدة موظف - مصاريف مهندسين وإشراف تقديرية (أمر 1)'})
        .eq('journal_entry_id', 36)
        .eq('account_id', 58)
        .select();
    print('Updated ALE for JE 36: $res');
  } catch (e) {
    print('Error updating ALE for JE 36: $e');
  }

  // Check lines of JE 36
  final lines36 = await c.from('v_journal_entry_lines').select('*').eq('journal_entry_id', 36);
  print('JE 36 lines:');
  for (var l in lines36) {
    print('  ${l["account_code"]} (${l["account_name"]}) | Dr=${l["debit"]} | Cr=${l["credit"]} | ${l["description"]}');
  }
}
