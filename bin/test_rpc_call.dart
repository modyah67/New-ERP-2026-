import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  try {
    final client = SupabaseClient(
      'https://pjkhdnoeyyvraclomepx.supabase.co',
      'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
    );

    // Test calling rpc_supplier_multi_payment with invalid amount 0 to check signature and error response
    try {
      final res = await client.rpc('rpc_supplier_multi_payment', params: {
        'p_source_type': 'treasury',
        'p_source_id': 1,
        'p_currency': 'USD',
        'p_amount': 0,
        'p_supplier_id': '34c0ab81-f4ee-48c4-9d0b-bf01bebd0bbb',
        'p_description': 'Test',
        'p_notes': '',
      });
      print('rpc_supplier_multi_payment result: $res');
    } catch (e) {
      print('rpc_supplier_multi_payment expected response: $e');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    exit(0);
  }
}
