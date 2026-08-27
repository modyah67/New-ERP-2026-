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
    
    // Insert an item with null
    final res = await client.from('shipment_cost_items').insert({
      'shipment_id': shipmentId,
      'description': 'test null insert',
      'quantity': 1,
      'unit_price': 1,
      'report_category_id': null,
      'category': 'other'
    }).select();
    
    final id = res[0]['id'];
    print('Inserted with null successfully');
    
    // Update the item with null again
    final resUpdate = await client.from('shipment_cost_items').update({
      'report_category_id': null
    }).eq('id', id).select();
    
    print('Updated with null successfully: $resUpdate');
    
    await client.from('shipment_cost_items').delete().eq('id', id);
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
