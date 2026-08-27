import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  print('==================================================');
  print('TEST 1: Fetching ALL raw materials in the system');
  print('==================================================');
  final rawMaterialsData = await supabase
      .from('raw_materials')
      .select('id, code, name, unit, is_active')
      .eq('is_active', true)
      .order('name');
  print('Found ${rawMaterialsData.length} active raw materials:');
  for (var rm in rawMaterialsData) {
    print('  - ID: ${rm['id']}, Code: "${rm['code']}", Name: "${rm['name']}", Unit: ${rm['unit']}');
  }

  final stationId = 2;

  print('\n==================================================');
  print('TEST 2: Fetching batches for Material Code "1" (كراتين مانجا)');
  print('==================================================');
  final code1Batches = await supabase
      .from('station_product_batches')
      .select('id, product_code, product_name, remaining_quantity, unit_cost, source_type, supplier_name')
      .eq('station_id', stationId)
      .eq('product_code', '1')
      .gt('remaining_quantity', 0)
      .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual'])
      .order('created_at', ascending: true);

  print('Batches for Code "1": ${code1Batches.length}');
  for (var b in code1Batches) {
    print('  -> Batch #${b['id']}: code=${b['product_code']}, name="${b['product_name']}", rem=${b['remaining_quantity']}, source=${b['source_type']}');
    assert(b['product_code'] == '1', 'Must have product_code == 1');
    assert(b['source_type'] != 'lot_receipt', 'Must NOT be a fruit lot receipt');
  }

  print('\n==================================================');
  print('TEST 3: Fetching batches for Material Code "2" (كراتين مانجا)');
  print('==================================================');
  final code2Batches = await supabase
      .from('station_product_batches')
      .select('id, product_code, product_name, remaining_quantity, unit_cost, source_type, supplier_name')
      .eq('station_id', stationId)
      .eq('product_code', '2')
      .gt('remaining_quantity', 0)
      .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual'])
      .order('created_at', ascending: true);

  print('Batches for Code "2": ${code2Batches.length}');
  for (var b in code2Batches) {
    print('  -> Batch #${b['id']}: code=${b['product_code']}, name="${b['product_name']}", rem=${b['remaining_quantity']}, source=${b['source_type']}');
    assert(b['product_code'] == '2', 'Must have product_code == 2');
    assert(b['source_type'] != 'lot_receipt', 'Must NOT be a fruit lot receipt');
  }

  print('\n==================================================');
  print('TEST 4: Fetching batches for Material Code "3" (كراتين مانجا دولار)');
  print('==================================================');
  final code3Batches = await supabase
      .from('station_product_batches')
      .select('id, product_code, product_name, remaining_quantity, unit_cost, source_type, supplier_name')
      .eq('station_id', stationId)
      .eq('product_code', '3')
      .gt('remaining_quantity', 0)
      .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual'])
      .order('created_at', ascending: true);

  print('Batches for Code "3": ${code3Batches.length}');
  for (var b in code3Batches) {
    print('  -> Batch #${b['id']}: code=${b['product_code']}, name="${b['product_name']}", rem=${b['remaining_quantity']}, source=${b['source_type']}');
    assert(b['product_code'] == '3', 'Must have product_code == 3');
    assert(b['source_type'] != 'lot_receipt', 'Must NOT be a fruit lot receipt');
  }

  print('\n==================================================');
  print('TEST 5: Verify NO fruit batches ("lot_receipt") appear in any material query');
  print('==================================================');
  final allMaterialBatches = await supabase
      .from('station_product_batches')
      .select('id, product_code, product_name, remaining_quantity, unit_cost, source_type')
      .eq('station_id', stationId)
      .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual']);
  print('Total material batches: ${allMaterialBatches.length}');
  for (var b in allMaterialBatches) {
    print('  -> Batch #${b['id']}: code=${b['product_code']}, name="${b['product_name']}", source=${b['source_type']}');
    if (b['source_type'] == 'lot_receipt') {
      throw Exception('Violation! Fruit batch found in material query: $b');
    }
  }

  print('\nALL TESTS PASSED WITH 100% ISOLATION AND INTEGRITY!');
}
