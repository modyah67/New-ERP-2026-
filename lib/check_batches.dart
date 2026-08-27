import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  final client = Supabase.instance.client;
  final batches = await client.from('station_product_batches').select('*');
  for (var b in batches) {
    print('Batch: id=${b['id']} qty=${b['quantity']} rem=${b['remaining_quantity']} src=${b['source_type']} item_type=${b['item_type']} fruit_id=${b['fruit_type_id']} code=${b['product_code']} name=${b['product_name']}');
  }
}
