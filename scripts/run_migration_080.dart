import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  
  final sql = File('supabase/migrations/20260806000002_080_lot_receipt_enterprise_journal_entries.sql').readAsStringSync();
  try {
    print('Applying 080 migration via exec_sql_text...');
    final res = await client.rpc('exec_sql_text', params: {'sql': sql});
    print('Success: $res');
  } catch (e) {
    print('exec_sql_text error: $e');
  }
  exit(0);
}
