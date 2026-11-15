import 'dart:convert';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final orders = await client.from('packing_orders').select().order('id');
  print('Total orders: ${orders.length}');
  for (final o in orders) {
    print('Order #${o['id']}: order_number=${o['order_number']}, status=${o['status']}, crops_confirmed_at=${o['crops_confirmed_at']}, packaging_confirmed_at=${o['packaging_confirmed_at']}, costs_confirmed_at=${o['costs_confirmed_at']}');
    print('Notes: ${o['notes']}');
  }

  // Cost items for order 1
  final costItems = await client.from('packing_order_cost_items').select().order('id');
  print('Cost items total: ${costItems.length}');
  for (final ci in costItems) {
    print('CostItem #${ci['id']}: po_id=${ci['packing_order_id']}, name=${ci['name']}, supplier_id=${ci['supplier_id']}, transport_supplier_id=${ci['transport_supplier_id']}, category=${ci['category']}');
  }
}
