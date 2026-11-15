import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);

  print('=== 1. Checking cost_center_transactions ===');
  try {
    final cctRows = await client.from('cost_center_transactions').select().order('id', ascending: false).limit(100);
    print('Total cct rows found: ${cctRows.length}');
    for (final r in cctRows) {
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      print('CCT [id=${r['id']}, source_type=${r['source_type']}, source_id=${r['source_id']}, cat=${r['category']}, item=${r['item_name']}, cc_id=${r['cost_center_id']}, qty=$qty, unit_price=$price, amount=$amt]');
    }
  } catch (e) {
    print('cct query error: $e');
  }

  print('\n=== 2. Checking packing_wastes table ===');
  try {
    final pwRows = await client.from('packing_wastes').select().limit(50);
    print('packing_wastes rows (${pwRows.length}):');
    for (final r in pwRows) {
      print('PW: $r');
    }
  } catch (e) {
    print('packing_wastes error: $e');
  }

  print('\n=== 3. Checking packing_orders with waste/loss data ===');
  try {
    final poRows = await client.from('packing_orders').select('id, order_number, status, notes').limit(10);
    for (final po in poRows) {
      final rawNotes = po['notes']?.toString() ?? '';
      if (rawNotes.contains('waste') || rawNotes.contains('sorting') || rawNotes.contains('هالك') || rawNotes.contains('فرز')) {
        print('PO #${po['order_number']} (id=${po['id']}) has waste/sorting in notes!');
        try {
          final dec = jsonDecode(rawNotes);
          print('  waste_data: ${dec['waste_data']}');
          print('  sorting_data: ${dec['sorting_data']}');
          print('  loss: ${dec['loss']}');
        } catch (_) {
          print('  notes snippet: ${rawNotes.substring(0, rawNotes.length > 200 ? 200 : rawNotes.length)}');
        }
      }
    }
  } catch (e) {
    print('po query error: $e');
  }

  print('\n=== 4. Checking vw_cost_details_live for waste/sorting ===');
  try {
    final liveWaste = await client.from('vw_cost_details_live').select().ilike('item_name', '%هالك%');
    print('vw_cost_details_live rows with هالك (${liveWaste.length}):');
    for (final r in liveWaste) {
      print('LIVE WASTE: $r');
    }
  } catch (e) {
    print('live waste error: $e');
  }

  try {
    final liveSorting = await client.from('vw_cost_details_live').select().ilike('item_name', '%فرز%');
    print('vw_cost_details_live rows with فرز (${liveSorting.length}):');
    for (final r in liveSorting) {
      print('LIVE SORTING: $r');
    }
  } catch (e) {
    print('live sorting error: $e');
  }

  print('\n=== 5. Checking packing_order_lines ===');
  try {
    final lines = await client.from('packing_order_lines').select().limit(20);
    print('packing_order_lines count: ${lines.length}');
    for (final l in lines) {
      print('LINE: id=${l['id']}, po_id=${l['packing_order_id']}, prod=${l['product_name']}, qty=${l['quantity']}, unit_cost=${l['unit_cost']}, raw_cost=${l['raw_material_cost']}, waste_cost=${l['waste_cost']}, waste_weight=${l['waste_weight_kg']}, sorting_cost=${l['sorting_cost']}, sorted_weight=${l['sorted_weight_kg']}');
    }
  } catch (e) {
    print('lines error: $e');
  }
}
