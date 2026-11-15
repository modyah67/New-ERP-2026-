import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final pos = await client.from('packing_orders').select('*').eq('id', 1);
  final po = pos.first;
  final lines = await client.from('packing_order_lines').select('*').eq('packing_order_id', 1);
  print('Lines count: ${lines.length}');
  for (final l in lines) {
    print('Line: prod=${l['product_name']}, qty=${l['quantity']}, unit_cost=${l['unit_cost']}, raw_cost=${l['raw_material_cost']}, waste_cost=${l['waste_cost']}, sorting_cost=${l['sorting_cost']}');
  }

  final rawNotes = po['notes']?.toString() ?? '';
  final dec = jsonDecode(rawNotes);
  print('waste_data type: ${dec['waste_data'].runtimeType}');
  print('waste_data: ${dec['waste_data']}');
  print('sorting_data: ${dec['sorting_data']}');
  print('materials: ${dec['materials']}');
}
