import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);

  print('=== Inspecting packing_order_lines with waste or sorting ===');
  final polines = await client.from('packing_order_lines').select();
  for (final l in polines) {
    print('POL #${l['id']}: PO=${l['packing_order_id']}, prod=${l['product_name']}, qty=${l['quantity']}, unit_cost=${l['unit_cost']}, waste_weight_kg=${l['waste_weight_kg']}, waste_cost=${l['waste_cost']}, sorted_weight_kg=${l['sorted_weight_kg']}, sorting_cost=${l['sorting_cost']}');
  }

  print('\n=== Inspecting packing_orders notes JSON ===');
  final orders = await client.from('packing_orders').select('id, order_number, notes');
  for (final o in orders) {
    print('PO #${o['order_number']} (id=${o['id']}):');
    final raw = o['notes']?.toString() ?? '';
    if (raw.isNotEmpty) {
      try {
        final dec = jsonDecode(raw);
        print('  waste_data: ${dec['waste_data']}');
        print('  waste_weight_kg: ${dec['waste_weight_kg']}');
        print('  waste_cost: ${dec['waste_cost']}');
      } catch (e) {
        print('  notes error: $e');
      }
    }
  }

  print('\n=== Inspecting cost_center_transactions with 0 quantity or 0 unit_price ===');
  final cctZero = await client.from('cost_center_transactions').select().or('quantity.eq.0,unit_price.eq.0');
  print('Found ${cctZero.length} cct rows with 0 qty or 0 unit_price:');
  for (final r in cctZero) {
    print('  CCT #${r['id']}: source_type=${r['source_type']}, source_id=${r['source_id']}, item=${r['item_name']}, qty=${r['quantity']}, unit_price=${r['unit_price']}, amount=${r['amount']}, total_in_cur=${r['total_in_currency']}');
  }
}
