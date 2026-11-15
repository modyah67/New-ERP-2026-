import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  print('=== Inspecting Packing Orders ===');
  final pos = await client.from('packing_orders').select('*');
  print('Total packing orders: ${pos.length}');
  for (final po in pos) {
    print('\n----------------------------------------');
    print('PO ID: ${po['id']}, Number: ${po['order_number']}, Status: ${po['status']}');
    print('Product: ${po['product_name']}, NetWeight: ${po['total_net_weight']}, FruitCost: ${po['fruit_cost_base']}');
    print('MaterialCost: actual=${po['actual_material_cost']}, base=${po['material_cost_base']}');
    print('CostItems: actual=${po['actual_other_cost']}, other_cost_base=${po['other_cost_base']}');
    print('TotalPackingCost: ${po['total_packing_cost']}');
    print('ShipmentID: ${po['export_shipment_id']}');
    final rawNotes = po['notes']?.toString() ?? '';
    if (rawNotes.startsWith('{')) {
      try {
        final dec = jsonDecode(rawNotes);
        print('Notes keys: ${dec.keys.toList()}');
        print('Materials in notes: ${dec['materials']}');
        print('Waste data in notes: ${dec['waste_data']}');
        print('Sorting data in notes: ${dec['sorting_data']}');
        print('Fruit allocation in notes: ${dec['fruit_allocation']}');
      } catch (e) {
        print('Notes json error: $e');
      }
    } else {
      print('Notes raw: $rawNotes');
    }
  }

  print('\n=== Inspecting cost_center_transactions for waste and materials ===');
  final cct = await client.from('cost_center_transactions').select().limit(20);
  print('CCT total count (sample): ${cct.length}');
  for (final c in cct) {
    print('CCT: id=${c['id']}, cc_id=${c['cost_center_id']}, src=${c['source_type']}, item=${c['item_name']}, amt=${c['amount']}');
  }
}
