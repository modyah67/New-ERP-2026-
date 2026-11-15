import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final all = await client.from('cost_centers').select().order('id');
  print('Total cost centers: ${all.length}');
  for (final c in all) {
    print('CC #${c['id']}: code=${c['code']}, name=${c['name_ar']}, status=${c['status']}, season_status=${c['season_status']}, is_active=${c['is_active']}, is_closed=${c['is_closed']}, season_number=${c['season_number']}, closure_count=${c['closure_count']}, rollover_id=${c['rollover_cost_center_id']}');
  }
}
