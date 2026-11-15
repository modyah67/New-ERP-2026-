import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Simulating Cost Report Details for Packing Order #1 ===\n');

  final orders = await client.from('packing_orders').select().eq('id', 1);
  final po = orders.first;
  final lines = await client.from('packing_order_lines').select().eq('packing_order_id', 1);

  final rawNotes = po['notes']?.toString() ?? '';
  Map<String, dynamic>? notesMap;
  if (rawNotes.trim().startsWith('{')) {
    try {
      notesMap = jsonDecode(rawNotes);
    } catch (_) {}
  }

  for (final line in lines) {
    final pName = line['product_name'];
    final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
    final rawCost = (line['raw_material_cost'] as num?)?.toDouble() ?? 0.0;
    final unitPrice = (line['unit_cost'] as num?)?.toDouble() ?? (qty > 0 ? rawCost / qty : 0.0);
    double wasteCost = (line['waste_cost'] as num?)?.toDouble() ?? 0.0;
    double wasteWeight = (line['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
    double wastePct = (line['expected_loss_percent'] as num?)?.toDouble() ?? 0.0;

    print('Product: $pName');
    print('  - qty: $qty');
    print('  - rawCost: $rawCost');
    print('  - unitPrice: $unitPrice');
    print('  - wasteCost: $wasteCost');
    print('  - wasteWeightKg: $wasteWeight');

    // Simulate _addOperationalEntries logic:
    if (wasteCost > 0) {
      double effectiveWasteQty = wasteWeight;
      double effectiveUnitPrice = 0.0;

      if (effectiveWasteQty <= 0) {
        if (wastePct > 0 && qty > 0) {
          effectiveWasteQty = qty * (wastePct / 100.0);
        } else if (unitPrice > 0) {
          effectiveWasteQty = wasteCost / unitPrice;
        }
      }

      if (effectiveWasteQty > 0) {
        effectiveUnitPrice = wasteCost / effectiveWasteQty;
      } else if (unitPrice > 0) {
        effectiveUnitPrice = unitPrice;
        effectiveWasteQty = wasteCost / unitPrice;
      } else {
        effectiveWasteQty = 1.0;
        effectiveUnitPrice = wasteCost;
      }

      print('  -> Operational Waste Row Generated:');
      print('     category: تكلفة الهالك');
      print('     item_name: تكلفة الهالك - $pName');
      print('     quantity: $effectiveWasteQty');
      print('     unit_price: $effectiveUnitPrice');
      print('     amount: $wasteCost EGP');

      // Simulate UI Table rendering logic:
      final rawQty = effectiveWasteQty;
      final rawUnitPriceVal = effectiveUnitPrice;
      final totalInCurrency = wasteCost;
      double uiQty = rawQty;
      double uiUnitPriceForeign = rawUnitPriceVal;
      if (uiUnitPriceForeign <= 0 && uiQty.abs() > 0 && totalInCurrency != 0) {
        uiUnitPriceForeign = (totalInCurrency / uiQty).abs();
      } else if (uiQty == 0 && uiUnitPriceForeign > 0 && totalInCurrency != 0) {
        uiQty = totalInCurrency / uiUnitPriceForeign;
      } else if (uiQty == 0 && uiUnitPriceForeign <= 0 && totalInCurrency != 0) {
        uiQty = totalInCurrency < 0 ? -1.0 : 1.0;
        uiUnitPriceForeign = totalInCurrency.abs();
      }

      print('  -> UI Table Display:');
      print('     الكمية: ${uiQty.toStringAsFixed(2)}');
      print('     سعر الوحدة: EGP ${uiUnitPriceForeign.toStringAsFixed(2)}');
      print('     الإجمالي بالمصري: ${wasteCost.toStringAsFixed(2)}');
      print('');
    }
  }
}
