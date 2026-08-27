import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  try {
    final res = await client.from('cost_report_categories').select('*');
    print('Raw categories: $res');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
