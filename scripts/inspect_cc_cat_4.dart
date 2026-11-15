import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final allShipping = await client.from('cost_centers').select().or('code.ilike.%CC-CAT-4%,name_ar.ilike.%شركات الشحن%,id.eq.19');
  for (final c in allShipping) {
    print('CC #${c['id']}: code=${c['code']}, name=${c['name_ar']}, status=${c['status']}, season_status=${c['season_status']}, is_active=${c['is_active']}, is_closed=${c['is_closed']}, season_number=${c['season_number']}, closure_count=${c['closure_count']}, rollover_id=${c['rollover_cost_center_id']}');
  }
}
