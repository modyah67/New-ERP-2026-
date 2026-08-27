import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  final sql = File('supabase/migrations/124_fix_expenses_ledgers.sql').readAsStringSync();
  try {
    await client.rpc('exec_sql', params: {'sql': sql});
    print('SQL executed successfully via exec_sql');
  } catch (e) {
    print('exec_sql failed: $e');
    // If we don't have exec_sql, we can't run DDL via REST API.
    // The user will have to run it in Supabase dashboard.
  }
  exit(0);
}
