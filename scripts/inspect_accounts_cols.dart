import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final res = await c.from('packing_orders').select().limit(1);
  if (res.isNotEmpty) {
    print('Columns of packing_orders: ${res.first.keys.toList()}');
    print('Sample status: ${res.first['status']}');
  } else {
    print('packing_orders is empty');
  }
}
