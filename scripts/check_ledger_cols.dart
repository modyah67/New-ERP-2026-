import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final cols = await c.from('account_ledger_entries').select('*').limit(1);
  if (cols.isNotEmpty) {
    print('account_ledger_entries columns: ${cols.first.keys.toList()}');
  }
}
