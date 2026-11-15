import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/cost_report_dao.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final dao = CostReportDao(client);
  final details = await dao.getDetails(costCenter: 'CC-MANGO-2026-2027');
  print('=== Details Count: ${details.length} ===');
  for (var r in details) {
    print('Row: id=${r['id']}, source_type=${r['source_type']}, source_id=${r['source_id']}, item=${r['item_name']}, amt=${r['amount']}, date=${r['date']}, shipment_date=${r['shipment_date']}, created_at=${r['created_at']}');
  }

  final breakdown = await dao.getCostCenterBreakdown();
  print('\n=== Breakdown Count: ${breakdown.length} ===');
  for (var b in breakdown) {
    print('Breakdown: id=${b['id']}, name=${b['name']}, total_amount=${b['total_amount']}, opening_balance=${b['opening_balance']}, carried_forward_amount=${b['carried_forward_amount']}, tx_count=${b['transaction_count']}');
  }
}
