import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  try {
    final client = SupabaseClient(
      'https://pjkhdnoeyyvraclomepx.supabase.co',
      'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
    );

    final res = await client.rpc('exec_sql', params: {'sql': 'SELECT 1 as test;'});
    print('exec_sql with sql param: $res');
  } catch (e) {
    print('exec_sql error: $e');
    try {
      final client = SupabaseClient(
        'https://pjkhdnoeyyvraclomepx.supabase.co',
        'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
      );
      final res = await client.rpc('exec_sql', params: {'query': 'SELECT 1 as test;'});
      print('exec_sql with query param: $res');
    } catch (e2) {
      print('exec_sql query error: $e2');
    }
  } finally {
    exit(0);
  }
}
