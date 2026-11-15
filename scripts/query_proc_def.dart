import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    try {
      final res = await client.rpc('rpc_confirm_packing_packaging', params: {'p_packing_order_id': 2});
      print('RPC RESULT: $res');
    } on PostgrestException catch (e) {
      print('PostgrestException: message=${e.message}, details=${e.details}, hint=${e.hint}, code=${e.code}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
