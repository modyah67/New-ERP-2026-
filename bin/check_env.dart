import 'dart:io';

void main() {
  print('SUPABASE_DB_PASSWORD: ${Platform.environment['SUPABASE_DB_PASSWORD'] != null}');
}
