import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );

  try {
    final users = await client.from('users').select('id, full_name, email');
    print('Users in DB:');
    for (var u in users) {
      print('- ID: ${u['id']}, Name: ${u['full_name']}, Email: ${u['email']}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
