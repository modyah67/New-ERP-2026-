import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final url = 'https://pjkhdnoeyyvraclomepx.supabase.co';
  final key = 'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12';
  
  final client = SupabaseClient(url, key);
  
  final sql = '''
    ALTER TABLE public.cheques ADD COLUMN IF NOT EXISTS treasury_id INTEGER;
    NOTIFY pgrst, 'reload schema';
  ''';
  
  try {
    await client.rpc('exec_sql', params: {'sql': sql});
    print('SQL executed successfully!');
  } catch (e) {
    print('exec_sql failed: ' + e.toString());
  }
  exit(0);
}
