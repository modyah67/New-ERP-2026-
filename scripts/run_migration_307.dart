import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  try {
    final sql = File('supabase/migrations/20260817000001_307_fix_edit_purchase_price_transferred_batches.sql').readAsStringSync();
    final result = await client.rpc('exec_sql', params: {'sql': sql});
    print('result: $result');
    print('✅ Migration 307 executed successfully via exec_sql');
  } catch (e) {
    print('exec_sql failed: $e');
    try {
      final sql = File('supabase/migrations/20260817000001_307_fix_edit_purchase_price_transferred_batches.sql').readAsStringSync();
      final result = await client.rpc('exec_sql_text', params: {'sql': sql});
      print('result (exec_sql_text): $result');
      print('✅ Migration 307 executed successfully via exec_sql_text');
    } catch (e2) {
      print('exec_sql_text failed: $e2');
    }
  }
}
