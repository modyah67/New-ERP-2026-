import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  // Let's check what CostReportDao does:
  final orders = await client.from('packing_orders').select('id, order_number, status, packed_at, created_at, fruit_cost_base, fruit_cost_allocated, total_packing_cost, total_net_weight, total_gross_weight, product_name, notes, export_shipment_id, export_shipments(id, shipment_no, customer_name)');
  
  final po = orders.first;
  final notesMap = jsonDecode(po['notes']);
  final lines = await client.from('packing_order_lines').select('*').eq('packing_order_id', 1);
  final line = lines.first;

  print('po product_name: "${po['product_name']}"');
  print('line product_name: "${line['product_name']}"');
  print('line waste_cost: ${line['waste_cost']}');
  print('line sorting_cost: ${line['sorting_cost']}');
  print('line raw_cost: ${line['raw_material_cost']}');
  print('notes materials: ${notesMap['materials']}');
  print('notes waste_data: ${notesMap['waste_data']}');
}
