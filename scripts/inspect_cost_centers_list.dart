import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Inspecting cost_centers table ===');
  final centers = await client.from('cost_centers').select();
  for (final c in centers) {
    print('CC: id=${c['id']}, code=${c['code']}, name_ar=${c['name_ar']}, name_en=${c['name_en']}, type=${c['type']}, product_id=${c['product_id']}');
  }
}
