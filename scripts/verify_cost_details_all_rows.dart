import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
  print('=== Verifying Cost Center Transactions & Packing Rows (Authenticated) ===\n');

  final lines = await client.from('packing_order_lines').select().order('id');
  print('Packing Order Lines:');
  for (final l in lines) {
    print('Line #${l['id']}: prod=${l['product_name']}, qty=${l['quantity']}, unit_cost=${l['unit_cost']}, waste_weight_kg=${l['waste_weight_kg']}, waste_cost=${l['waste_cost']}, sorting_cost=${l['sorting_cost']}, sorted_weight=${l['sorted_weight_kg']}');
  }

  final cctRows = await client.from('cost_center_transactions').select().order('id');
  print('\nCost Center Transactions:');
  for (final c in cctRows) {
    print('CCT #${c['id']}: item=${c['item_name']}, qty=${c['quantity']}, unit_price=${c['unit_price']}, amount=${c['amount']}');
  }

  print('\nChecking for any 0 qty or 0 unit_price in rows with amount != 0:');
  int zeroCount = 0;
  for (final c in cctRows) {
    final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
    final q = (c['quantity'] as num?)?.toDouble() ?? 0.0;
    final up = (c['unit_price'] as num?)?.toDouble() ?? 0.0;
    if (amt != 0 && (q == 0 || up == 0)) {
      print('⚠️ Found zero CCT: #${c['id']} [qty=$q, unit_price=$up, amt=$amt]');
      zeroCount++;
    }
  }

  for (final l in lines) {
    final wasteCost = (l['waste_cost'] as num?)?.toDouble() ?? 0.0;
    final wasteWeight = (l['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
    if (wasteCost > 0 && wasteWeight == 0) {
      print('⚠️ Found zero waste line: #${l['id']} [wasteCost=$wasteCost, wasteWeight=$wasteWeight]');
      zeroCount++;
    }
  }

  if (zeroCount == 0) {
    print('🎉 SUCCESS: Zero problematic rows found in database!');
  } else {
    print('❌ Warning: $zeroCount problematic rows remain.');
  }
}
