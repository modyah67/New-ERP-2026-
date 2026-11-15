import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  try {
    final pos = await client.from('packing_orders').select('id, order_number');
    print('pjkhdnoeyyvraclomepx packing orders: $pos');

    final shipments = await client.from('export_shipments').select('id, shipment_no');
    print('pjkhdnoeyyvraclomepx shipments: $shipments');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
