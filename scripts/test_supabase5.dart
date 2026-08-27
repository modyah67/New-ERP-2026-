import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final pii = await client.from('purchase_invoice_items').select('*').eq('invoice_id', 97);
    print('items for 97: $pii');
  } catch (e) {
    print('error: $e');
  }
}
