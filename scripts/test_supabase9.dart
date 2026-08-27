import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final result = await client.from('stock_batches').insert({
      'batch_number': 'TEST-999',
      'product_id': '0426f5b8-6b4d-4868-b6e5-ec7cb27d1936',
      'purchase_invoice_id': 97,
      'quantity': 1,
      'remaining_quantity': 1,
      'purchase_cost': 1,
      'average_cost': 1
    }).select();
    print('result: $result');
  } catch (e) {
    print('error: $e');
  }
}
