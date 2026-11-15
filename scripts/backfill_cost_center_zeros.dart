import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
  print('=== Starting Backfill of Cost Center Zeros (Authenticated) ===\n');

  // 1. Backfill packing_order_lines line #2
  try {
    final lines = await client.from('packing_order_lines').select().eq('id', 2);
    if (lines.isNotEmpty) {
      final line = lines.first;
      print('Current packing_order_line #2: $line');
      final wasteCost = (line['waste_cost'] as num?)?.toDouble() ?? 0.0;
      final wasteWeight = (line['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
      final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
      final wastePct = (line['expected_loss_percent'] as num?)?.toDouble() ?? 0.0;

      double targetWeight = wasteWeight;
      if (targetWeight <= 0) {
        if (wastePct > 0 && qty > 0) {
          targetWeight = qty * (wastePct / 100.0);
        } else {
          targetWeight = 25.0; // 500 * 5% = 25
        }
      }

      print('Updating packing_order_lines id=2 with waste_weight_kg=$targetWeight...');
      await client.from('packing_order_lines').update({
        'waste_weight_kg': targetWeight,
      }).eq('id', 2);
      print('✅ Updated packing_order_lines id=2');
    }
  } catch (e) {
    print('❌ Error updating packing_order_lines: $e');
  }

  // 2. Backfill packing_orders id=1 notes
  try {
    final poList = await client.from('packing_orders').select('id, notes').eq('id', 1);
    if (poList.isNotEmpty) {
      final po = poList.first;
      final rawNotes = po['notes']?.toString() ?? '';
      if (rawNotes.trim().startsWith('{')) {
        final Map<String, dynamic> notesMap = jsonDecode(rawNotes);
        final wasteData = notesMap['waste_data'];
        if (wasteData is List) {
          for (final item in wasteData) {
            if (item is Map) {
              final wWeight = (item['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
              final wCost = (item['waste_cost'] as num?)?.toDouble() ?? 0.0;
              final wPct = (item['waste_percent'] as num?)?.toDouble() ?? 0.0;
              if (wWeight <= 0 && wCost > 0) {
                // Set to 25.0
                item['waste_weight_kg'] = 25.0;
                item['quantity'] = 25.0;
                item['unit_price'] = wCost / 25.0;
              }
            }
          }
          final updatedNotes = jsonEncode(notesMap);
          print('Updating packing_orders id=1 notes...');
          await client.from('packing_orders').update({'notes': updatedNotes}).eq('id', 1);
          print('✅ Updated packing_orders id=1 notes');
        }
      }
    }
  } catch (e) {
    print('❌ Error updating packing_orders notes: $e');
  }

  // 3. Backfill cost_center_transactions where qty=0 and amount!=0
  try {
    final cctRows = await client.from('cost_center_transactions').select().eq('quantity', 0);
    print('Found ${cctRows.length} CCT rows with quantity=0:');
    for (final r in cctRows) {
      final id = r['id'];
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      print('Updating CCT id=$id (amount=$amt, current unit_price=$unitPrice)...');
      
      double newQty = 1.0;
      double newUnitPrice = amt.abs();
      if (unitPrice > 0) {
        newUnitPrice = unitPrice;
        newQty = amt / unitPrice;
      } else {
        newQty = amt < 0 ? -1.0 : 1.0;
        newUnitPrice = amt.abs();
      }

      await client.from('cost_center_transactions').update({
        'quantity': newQty,
        'unit_price': newUnitPrice,
      }).eq('id', id);
      print('✅ Updated CCT id=$id with qty=$newQty, unit_price=$newUnitPrice');
    }
  } catch (e) {
    print('❌ Error updating cost_center_transactions: $e');
  }

  print('\n=== Backfill Completed Successfully ===');
}
