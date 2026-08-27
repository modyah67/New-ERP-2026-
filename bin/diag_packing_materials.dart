import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  print('=== RAW MATERIALS TABLE ===');
  final rawMaterials = await supabase.from('raw_materials').select();
  print('Count: ${rawMaterials.length}');
  for (var rm in rawMaterials) {
    print('  -> RawMaterial id=${rm['id']}, code=${rm['code']}, name="${rm['name']}", unit=${rm['unit']}');
  }

  print('\n=== STATION PRODUCT BATCHES FOR STATION 2 ===');
  final batches = await supabase.from('station_product_batches').select().eq('station_id', 2);
  print('Count: ${batches.length}');
  for (var b in batches) {
    print('  -> Batch #${b['id']}: code=${b['product_code']}, name="${b['product_name']}", qty=${b['quantity']}, rem=${b['remaining_quantity']}, source=${b['source_type']}');
  }

  print('\n=== STATION PRODUCTS FOR STATION 2 ===');
  final sp = await supabase.from('station_products').select().eq('station_id', 2);
  print('Count: ${sp.length}');
  for (var p in sp) {
    print('  -> StationProduct id=${p['id']}, code=${p['product_code']}, name="${p['product_name']}", qty=${p['quantity']}');
  }
}
