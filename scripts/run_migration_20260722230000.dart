import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  
  final sqlPath = 'supabase/migrations/20260722230000_add_payment_source_columns.sql';
  final sql = File(sqlPath).readAsStringSync();
  
  print('Applying migration: $sqlPath');
  try {
    final response = await client.rpc('exec_sql', params: {'query': sql});
    print('Migration executed successfully: $response');
  } catch (e) {
    print('exec_sql failed: $e');
  }
}
