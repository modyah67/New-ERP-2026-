import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  try {
    final client = SupabaseClient(
      'https://pjkhdnoeyyvraclomepx.supabase.co',
      'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
    );

    // Try inserting a test record into supplier_payment_allocations to check columns
    try {
      final testInsert = await client.from('supplier_payment_allocations').insert({
        'source_type': 'treasury',
        'source_id': 1,
        'amount': 1.0,
      }).select();
      print('Insert without purchase_invoice_id: $testInsert');
      // clean up test record
      if (testInsert.isNotEmpty) {
        await client.from('supplier_payment_allocations').delete().eq('id', testInsert.first['id']);
      }
    } catch (e) {
      print('Insert test error: $e');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    exit(0);
  }
}
