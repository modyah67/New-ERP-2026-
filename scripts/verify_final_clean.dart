import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final checkCodes = ['3121', '3123', '3212', '3222', '3223', '3224', '3412', '34', '341', '3411'];
  final res = await c
      .from('accounts')
      .select('account_code, account_name')
      .inFilter('account_code', checkCodes);

  final res34 = await c
      .from('accounts')
      .select('account_code, account_name')
      .like('account_code', '34%');

  print('=== RESULTS ===');
  print('Matches in checkCodes: ${res.length}');
  print('Matches in 34%: ${res34.length}');
}
