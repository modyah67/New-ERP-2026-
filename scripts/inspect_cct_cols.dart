import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final rows = await client.from('cost_center_transactions').select().limit(1);
  if (rows.isNotEmpty) {
    print('cost_center_transactions columns:');
    rows.first.forEach((k, v) => print('  $k: $v (${v.runtimeType})'));
  } else {
    print('No rows found in cost_center_transactions');
  }
}
