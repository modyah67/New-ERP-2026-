import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final compId = '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
  print('=== DIAGNOSING ACCOUNT_LEDGER_ENTRIES INSERTION ===');

  try {
    print('Testing insert into account_ledger_entries for JE 1...');
    final res = await c.from('account_ledger_entries').insert({
      'journal_entry_id': 1,
      'account_id': 5104, // 21113
      'debit': 0.0,
      'credit': 17100.0,
      'currency': 'EGP',
      'amount_in_base_currency': 17100.0,
      'description': 'اختبار ترحيل سطر',
      'company_id': compId,
    }).select();
    print('✅ Insert SUCCESS! Result: $res');
  } catch (e, st) {
    print('❌ Insert FAILED with error: $e');
    print(st);
  }
}
