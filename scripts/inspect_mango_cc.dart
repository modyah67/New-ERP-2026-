import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // Let's inspect Mango cost center currently
  final mango = await client.from('cost_centers').select().eq('code', 'CC-MANGO-2026-2027').maybeSingle();
  print('Mango Cost Center:');
  print('  - id: ${mango?['id']}');
  print('  - code: ${mango?['code']}');
  print('  - name_ar: ${mango?['name_ar']}');
  print('  - season: ${mango?['season']}');
  print('  - season_number: ${mango?['season_number']}');
  print('  - closure_count: ${mango?['closure_count']}');
  print('  - status: ${mango?['status']}');
  print('  - season_status: ${mango?['season_status']}');
  print('  - is_active: ${mango?['is_active']}');
  print('  - is_closed: ${mango?['is_closed']}');
}
