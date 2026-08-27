import 'package:supabase/supabase.dart';

void main() async {
  final c = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );

  final shipments = await c
      .from('export_shipments')
      .select(
          'id, shipment_no, discount_amount, currency_code, customer_id, is_confirmed')
      .order('id', ascending: false)
      .limit(5);
  print('=== Shipments ===');
  for (final s in shipments) {
    print(s);
    final sid = s['id'].toString();
    final items = await c
        .from('export_shipment_items')
        .select('quantity, export_price_per_carton, amount')
        .eq('shipment_id', sid);
    print('  Items: $items');
    final jes = await c
        .from('journal_entries')
        .select('id, entry_number, source_type, source_id, description')
        .or('source_id.eq.$sid,description.ilike.%${s['shipment_no']}%');
    print('  JEs: $jes');

    // Try calling sync RPC
    try {
      final result = await c.rpc('rpc_process_export_shipment_ledger', params: {
        'p_shipment_id': s['id'],
      });
      print('  RPC result: $result');
    } catch (e) {
      print('  RPC error: $e');
    }
  }
}
