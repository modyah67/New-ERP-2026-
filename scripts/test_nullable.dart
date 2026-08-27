import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  try {
    final shipmentRes = await client.from('export_shipments').select('id').limit(1);
    final shipmentId = shipmentRes[0]['id'];
    print('Using shipment_id: $shipmentId');
    
    final res = await client.from('shipment_cost_items').insert({
      'shipment_id': shipmentId,
      'description': 'test null',
      'quantity': 1,
      'unit_price': 1,
      'report_category_id': null
    }).select();
    print('Inserted successfully: $res');
    
    if (res.isNotEmpty) {
      await client.from('shipment_cost_items').delete().eq('id', res[0]['id']);
    }
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
