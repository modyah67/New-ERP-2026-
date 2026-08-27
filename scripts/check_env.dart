import 'dart:io';

void main() {
  print('SUPABASE_DB_PASSWORD: ${Platform.environment['SUPABASE_DB_PASSWORD'] != null}');
  print('SUPABASE_ACCESS_TOKEN: ${Platform.environment['SUPABASE_ACCESS_TOKEN'] != null}');
  print('All keys: ${Platform.environment.keys.where((k) => k.toLowerCase().contains('supabase') || k.toLowerCase().contains('db') || k.toLowerCase().contains('pass'))}');
}
