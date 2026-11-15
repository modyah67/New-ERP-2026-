import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final ccs = await client.from('cost_centers').select().ilike('code', '%MANGO%');
  print('All Mango Cost Centers:');
  for (final c in ccs) {
    print('  - id: ${c['id']}, code: ${c['code']}, name: ${c['name_ar']}, season: ${c['season']}, period: ${c['season_number']}, closures: ${c['closure_count']}, active: ${c['is_active']}, closed: ${c['is_closed']}, status: ${c['status']}');
  }
}
