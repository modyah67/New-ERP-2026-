import 'dart:io';

void main() {
  print('SUPABASE_DB_PASSWORD: ${Platform.environment['SUPABASE_DB_PASSWORD'] != null}');
  print('DB_PASS: ${Platform.environment['DB_PASS'] != null}');
}
