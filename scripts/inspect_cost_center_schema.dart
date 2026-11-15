import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final row = await client.from('cost_centers').select().limit(1).maybeSingle();
  if (row != null) {
    print('Cost Centers columns:');
    for (final k in row.keys) {
      print('  - $k: ${row[k]} (${row[k].runtimeType})');
    }
  } else {
    print('No rows in cost_centers');
  }
}
