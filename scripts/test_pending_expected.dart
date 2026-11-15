import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    print('Testing pending expected costs fetch...');
    final rows = await client
        .from('packing_order_cost_items')
        .select('supplier_id, expected_amount, base_amount, original_amount, currency_snapshot, cost_status, actual_amount')
        .or('cost_status.eq.expected,actual_amount.is.null');

    print('Fetched ${rows.length} pending rows:');
    for (final r in rows) {
      final sid = r['supplier_id']?.toString() ??
          (r['currency_snapshot'] is Map ? (r['currency_snapshot']['supplier_id']?.toString()) : null);
      final exp = (r['expected_amount'] as num?)?.toDouble() ?? 0.0;
      final base = (r['base_amount'] as num?)?.toDouble() ?? 0.0;
      print('  sid=$sid, exp=$exp, base=$base, status=${r['cost_status']}, actual=${r['actual_amount']}');
    }
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}
