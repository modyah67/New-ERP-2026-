import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final results = await client.from('stock_batches').select('id, product_id, batch_number, quantity').order('created_at', ascending: false).limit(5);
    print('stock_batches: $results');
    final purchases = await client.from('purchase_invoices').select('id, status').order('created_at', ascending: false).limit(5);
    print('purchase_invoices: $purchases');
  } catch (e) {
    print('error: $e');
  }
}
