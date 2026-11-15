import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final ccs = await client.from('cost_centers').select().limit(1);
  if (ccs.isNotEmpty) {
    print('COST_CENTERS COLUMNS: ${ccs.first.keys.toList()}');
    print('ROW 1: ${ccs.first}');
  } else {
    print('cost_centers is empty');
  }
}
