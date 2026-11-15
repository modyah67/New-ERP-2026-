import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
    final res = await client.from('packing_order_cost_items').select('*').limit(1);
    print('Cost items sample row keys: ${res.isNotEmpty ? res.first.keys.toList() : "empty table"}');
    if (res.isNotEmpty) {
      print('First row: ${res.first}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
