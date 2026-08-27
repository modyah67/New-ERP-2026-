import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  final sql = File('supabase/migrations/20260808000031_126_fix_receive_payment_clearing_agent_account.sql').readAsStringSync();
  try {
    await client.rpc('exec_sql', params: {'sql': sql});
    print('Migration 126 executed successfully');
  } catch (e) {
    print('Failed to execute migration 126 via exec_sql: $e');
  }
  exit(0);
}
