import 'package:erpa/core/services/supabase_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  final client = SupabaseService.client;
  
  try {
    final res = await client.from('packing_orders').select('id, packing_cost_per_carton, total_packing_cost, fruit_cost_base').order('id', ascending: false).limit(5);
    print(res);
  } catch (e, st) {
    print('ERROR: \');
  }
}
