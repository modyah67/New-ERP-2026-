import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/cost_report_dao.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: SupabaseOptions.url,
      anonKey: SupabaseOptions.anonKey,
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'mahmoud@gmail.com',
      password: '123456',
    );
  });

  test('CostReportDao.getDetails returns non-zero quantity and unit_price for all non-zero rows', () async {
    final dao = CostReportDao();
    final rows = await dao.getDetails(costCenter: 'CC-MANGO-2026-2027');

    print('Fetched ${rows.length} rows for CC-MANGO-2026-2027:');
    for (final r in rows) {
      final item = r['item_name'];
      final cat = r['category'];
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final up = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      print('Row: cat=$cat | item=$item | qty=$qty | unit_price=$up | amt=$amt');

      if (amt != 0) {
        expect(qty, isNot(0.0), reason: 'Row "$item" with amount $amt should not have quantity 0.0');
        expect(up, isNot(0.0), reason: 'Row "$item" with amount $amt should not have unit_price 0.0');
      }
    }
  });
}
