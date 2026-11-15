import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final ccs = await client.from('cost_centers').select('*');
  print('Cost centers count: ${ccs.length}');
  for (final c in ccs) {
    print('CC: id=${c['id']}, code=${c['code']}, nameAr=${c['name_ar']}, nameEn=${c['name_en']}, cropCode=${c['crop_code']}, prodId=${c['product_id']}, isClosed=${c['is_closed']}');
  }
}
