import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // Let's see if we can query pg_proc directly
  try {
    final procs = await c.from('pg_proc').select('proname, prosrc').eq('proname', 'rpc_confirm_packing_crops');
    print('prosrc of rpc_confirm_packing_crops:');
    if (procs.isNotEmpty) {
      print(procs.first['prosrc']);
    } else {
      print('Not found in pg_proc');
    }
  } catch (e) {
    print('pg_proc error: $e');
  }
}
