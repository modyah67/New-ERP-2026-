import 'package:erpa/core/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  final client = SupabaseService.client;
  
  try {
    final res = await client.from('packing_orders').select('id, carton_count, total_packing_cost, packing_cost_per_carton, notes').eq('carton_count', 280);
    print('PACKING ORDERS:');
    print(jsonEncode(res));
    
    if (res.isNotEmpty) {
      final notes = res.first['notes'];
      if (notes != null) {
        final notesMap = jsonDecode(notes);
        final fruitAlloc = notesMap['fruit_allocation'];
        print('FRUIT ALLOC: \$fruitAlloc');
        
        if (fruitAlloc is Map) {
          final batchId = fruitAlloc['batch_id'];
          final batchRes = await client.from('stock_batches').select('id, average_cost, exchange_rate, quantity').eq('id', batchId);
          print('BATCH: \$batchRes');
        } else if (fruitAlloc is List && fruitAlloc.isNotEmpty) {
          final batchId = fruitAlloc.first['batch_id'];
          final batchRes = await client.from('stock_batches').select('id, average_cost, exchange_rate, quantity').eq('id', batchId);
          print('BATCH: \$batchRes');
        }
      }
    }
  } catch (e, st) {
    print('ERROR: \$e');
    print(st);
  }
}
