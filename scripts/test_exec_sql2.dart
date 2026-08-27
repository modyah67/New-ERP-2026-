import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );
  
  try {
    print('Testing exec_sql with query param...');
    final res = await client.rpc('exec_sql', params: {
      'query': "SELECT 1 as val;"
    });
    print('exec_sql result: $res');
  } catch (e) {
    print('exec_sql failed: $e');
  }
  exit(0);
}
