import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  try {
    print('Testing query...');
    final res = await client.rpc('exec_sql', params: {'query': 'SELECT 1 as val'});
    print('Result: $res');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
