import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );
  final sql = File('supabase/migrations/20260806000004_082_fix_journal_entry_view_and_ledger_rpc.sql').readAsStringSync();
  try {
    await client.rpc('exec_sql', params: {'sql': sql});
    print('Migration 082 executed successfully');
  } catch (e) {
    print('exec_sql failed: $e');
  }
}
