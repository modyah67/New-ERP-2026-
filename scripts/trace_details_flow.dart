import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

// Let's replicate CostReportDao().getDetails logic in a quick diagnostic script to see exact rows
void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  // 1. Fetch packing_orders
  final orders = await client.from('packing_orders').select('id, order_number, status, packed_at, created_at, fruit_cost_base, fruit_cost_allocated, total_packing_cost, total_net_weight, total_gross_weight, product_name, notes, export_shipment_id, export_shipments(id, shipment_no, customer_name)');
  print('Packing orders: ${orders.length}');
  for (final o in orders) {
    print('PO: id=${o['id']}, num=${o['order_number']}, status=${o['status']}, prod=${o['product_name']}');
  }

  // 2. Fetch packing_order_lines
  final lines = await client.from('packing_order_lines').select('*');
  print('Packing lines: ${lines.length}');
  for (final l in lines) {
    print('Line: po=${l['packing_order_id']}, prod=${l['product_name']}, raw=${l['raw_material_cost']}, waste=${l['waste_cost']}, sorting=${l['sorting_cost']}');
  }

  // 3. Fetch cost_centers
  final ccs = await client.from('cost_centers').select('*');
  print('Cost centers:');
  for (final c in ccs) {
    print('CC: id=${c['id']}, code=${c['code']}, name=${c['name_ar']}');
  }

  // 4. Fetch cost_center_transactions
  final cct = await client.from('cost_center_transactions').select();
  print('\nCCT count: ${cct.length}');
  for (final c in cct) {
    print('CCT: id=${c['id']}, cc_id=${c['cost_center_id']}, src=${c['source_type']}, item=${c['item_name']}, amt=${c['amount']}');
  }
}
