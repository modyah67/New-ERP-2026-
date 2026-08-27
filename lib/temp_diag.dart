import 'package:supabase_flutter/supabase_flutter.dart';

/// Temporary script to diagnose packing_order_lines vs export_shipment_items
void main() async {
  await Supabase.initialize(
    url: 'https://YOUR_PROJECT.supabase.co',
    anonKey: 'YOUR_ANON_KEY',
  );
  final client = Supabase.instance.client;

  // 1. Get latest packing_order
  final poResult = await client
      .from('packing_orders')
      .select('id, order_number, status')
      .order('id', ascending: false)
      .limit(1)
      .maybeSingle();

  if (poResult == null) {
    print('No packing orders found');
    return;
  }

  final poId = poResult['id'];
  print('=== LATEST PACKING ORDER: #$poId (${poResult["order_number"]}) ===\n');

  // 2. Get packing_order_lines
  final lines = await client
      .from('packing_order_lines')
      .select('id, packing_order_id, product_name, fruit_type_id, carton_count, raw_material_cost, specific_packaging_cost, allocated_shared_packaging, allocated_cost_items, final_cost, final_unit_cost, total_net_weight, net_weight_per_carton')
      .eq('packing_order_id', poId)
      .order('id');

  print('=== PACKING_ORDER_LINES (${lines.length} rows) ===');
  for (final l in lines) {
    print('  line_id=${l["id"]} | product=${l["product_name"]} | fruit_type_id=${l["fruit_type_id"]}');
    print('    carton_count=${l["carton_count"]} | final_cost=${l["final_cost"]} | final_unit_cost=${l["final_unit_cost"]}');
    print('    raw_material_cost=${l["raw_material_cost"]} | specific_packaging=${l["specific_packaging_cost"]}');
    print('    allocated_shared=${l["allocated_shared_packaging"]} | allocated_cost_items=${l["allocated_cost_items"]}');
    print('    total_net_weight=${l["total_net_weight"]} | net_wt_per_carton=${l["net_weight_per_carton"]}');
    final perCarton = (l["final_cost"] as num?) != null && (l["carton_count"] as num?) != null && (l["carton_count"] as num)! > 0
        ? (l["final_cost"] as num).toDouble() / (l["carton_count"] as num).toInt()
        : 0.0;
    print('    ** final_cost / carton_count = ${perCarton.toStringAsFixed(2)} **');
    print('');
  }

  // 3. Get export_shipment_items linked to this packing order
  final items = await client
      .from('export_shipment_items')
      .select('id, packing_order_id, packing_order_line_id, product_name, quantity, price')
      .eq('packing_order_id', poId)
      .order('id');

  print('=== EXPORT_SHIPMENT_ITEMS (${items.length} rows) ===');
  for (final i in items) {
    print('  item_id=${i["id"]} | line_id=${i["packing_order_line_id"]} | product=${i["product_name"]} | qty=${i["quantity"]} | price=${i["price"]}');
  }
}
