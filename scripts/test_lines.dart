import 'package:erpa/core/services/supabase_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  final client = SupabaseService.client;
  
  try {
    final res = await client.from('packing_order_lines').select().limit(1);
    print(res);
  } catch (e, st) {
    print('ERROR: \');
  }
}
