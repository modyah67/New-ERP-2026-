import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final a2000 = await c.from('accounts').select('*').or('account_code.eq.2000,code.eq.2000');
  print('Accounts with code 2000: $a2000');

  final a2112 = await c.from('accounts').select('*').or('account_code.eq.2112,code.eq.2112');
  print('Accounts with code 2112: $a2112');

  final a21111 = await c.from('accounts').select('*').or('account_code.eq.21111,code.eq.21111');
  print('Accounts with code 21111: $a21111');
}
