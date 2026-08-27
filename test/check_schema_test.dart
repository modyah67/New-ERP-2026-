import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  test('fetch shipment_cost_items', () async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://localhost:54321', // Dummy URL, we'll replace if needed, wait no this is a desktop app
      anonKey: 'dummy',
    );
    final res = await Supabase.instance.client.from('shipment_cost_items').select().limit(1);
    print(res);
  }, skip: 'Requires running Supabase instance');
}
