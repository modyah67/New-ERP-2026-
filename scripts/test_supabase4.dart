import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final results = await client.from('purchase_invoices').select('id, invoice_number').limit(1);
    print('purchase_invoices: $results');
    final pii = await client.from('purchase_invoice_items').select('id, invoice_id').limit(1);
    print('purchase_invoice_items: $pii');
  } catch (e) {
    print('error: $e');
  }
}
