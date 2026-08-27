import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://pjkhdnoeyyvraclomepx.supabase.co',
    publishableKey: 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
  );

  final client = Supabase.instance.client;

  // Try exec_sql with 'sql'
  try {
    print('Trying exec_sql with sql parameter...');
    final res = await client.rpc('exec_sql', params: {
      'sql': 'SELECT 1 as val'
    });
    print('exec_sql SUCCESS: $res');
  } catch (e) {
    print('exec_sql FAILED: $e');
  }

  // Try exec_sql_text with 'sql'
  try {
    print('Trying exec_sql_text with sql parameter...');
    final res = await client.rpc('exec_sql_text', params: {
      'sql': 'SELECT 1 as val'
    });
    print('exec_sql_text SUCCESS: $res');
  } catch (e) {
    print('exec_sql_text FAILED: $e');
  }
}
