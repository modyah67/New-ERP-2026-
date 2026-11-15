import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Inspecting Accounts for Waste & Clearing ===');
  final accs = await client.from('accounts').select('id, account_code, account_name, account_type').inFilter('account_code', ['9111', '3213', '2106', '12411', '12413', '51104', '33111', '34110']);
  for (final a in accs) {
    print('Account: $a');
  }
  final returns = await client.from('export_shipment_returns').select();
  print('Total returns: ${returns.length}');
  for (final r in returns) {
    print('Return ID: ${r['id']}, No: ${r['return_number']}, ShipmentId: ${r['shipment_id']}, CostCenter: ${r['cost_center_id']}, Date: ${r['return_date']}');
    print('  - crop_waste_cost: ${r['crop_waste_cost']}, damaged_crop_weight: ${r['damaged_crop_weight']}');
    print('  - material_waste_cost: ${r['material_waste_cost']}, damaged_cartons: ${r['damaged_cartons']}');
    print('  - extra_expenses_cost: ${r['extra_expenses_cost']}');
    print('  - raw_data: ${r['raw_data']}');
  }

  print('\n=== Inspecting export_shipments with status returned_from_airport ===');
  final shipments = await client.from('export_shipments').select().eq('status', 'returned_from_airport');
  print('Total returned shipments: ${shipments.length}');
  for (final s in shipments) {
    print('Shipment ID: ${s['id']}, No: ${s['shipment_no']}, Status: ${s['status']}, ReturnJE: ${s['return_journal_entry_id']}');
  }

  print('\n=== Inspecting export_shipment_items for shipment 1 ===');
  final items = await client.from('export_shipment_items').select().eq('shipment_id', 1);
  for (final it in items) {
    print('Item: $it');
  }

  print('\n=== Testing packaging waste from returns for PO 8 ===');
  final allReturns = await client.from('export_shipment_returns').select('*, export_shipments(shipment_no)');
  double totalReturnWaste = 0.0;
  int totalDamagedCartons = 0;
  final details = <Map<String, dynamic>>[];

  for (final ret in allReturns) {
    final rawData = ret['raw_data'] as Map<String, dynamic>?;
    final itemsList = rawData?['items'] as List<dynamic>? ?? [];
    final shipNo = (ret['export_shipments'] as Map<String, dynamic>?)?['shipment_no'] ?? '';
    final retNo = ret['return_number'] ?? '';
    final retDate = ret['return_date'] ?? '';

    for (final itm in itemsList) {
      final poId = int.tryParse(itm['packing_order_id']?.toString() ?? '');
      if (poId == 8) {
        final dmgCartons = (itm['damaged_cartons'] as num?)?.toInt() ?? 0;
        final cartonCost = (itm['carton_unit_cost'] as num?)?.toDouble() ?? 0.0;
        final wasteCost = dmgCartons * cartonCost;
        totalReturnWaste += wasteCost;
        totalDamagedCartons += dmgCartons;
        details.add({
          'return_id': ret['id'],
          'return_number': retNo,
          'return_date': retDate,
          'shipment_no': shipNo,
          'damaged_cartons': dmgCartons,
          'carton_unit_cost': cartonCost,
          'waste_cost': wasteCost,
          'product_name': itm['product_name'],
          'carton_product_name': itm['carton_product_name'],
        });
      }
    }
  }

  print('Total return packaging waste for PO 8: $totalReturnWaste');
  print('Total damaged cartons: $totalDamagedCartons');
  print('Details: $details');
}
