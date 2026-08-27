import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final host = 'aws-0-eu-north-1.pooler.supabase.com';
  final username = 'postgres.pjkhdnoeyyvraclomepx';
  final database = 'postgres';
  final port = 5432;

  String? password = Platform.environment['SUPABASE_DB_PASSWORD'];
  if (password == null || password.isEmpty) {
    stdout.write('Enter your Supabase database password: ');
    password = stdin.readLineSync()?.trim();
    stdout.writeln();
  }

  if (password == null || password.isEmpty) {
    print('Error: Password cannot be empty.');
    exit(1);
  }

  print('Connecting to database...');
  Connection? conn;
  try {
    conn = await Connection.open(
      Endpoint(
        host: host,
        database: database,
        username: username,
        password: password,
        port: port,
      ),
      settings: ConnectionSettings(
        sslMode: SslMode.require,
      ),
    );
  } catch (e) {
    print('Database connection failed: $e');
    exit(1);
  }

  // Apply migrations 126, 127 & 128
  final migrations = [
    'supabase/migrations/20260808000031_126_fix_receive_payment_clearing_agent_account.sql',
    'supabase/migrations/20260809000001_127_fix_spend_custody_all_entities.sql',
    'supabase/migrations/20260809000002_128_add_missing_payment_doc_types.sql',
  ];

  for (final path in migrations) {
    print('\n=== Applying: $path ===');
    try {
      final file = File(path);
      if (!await file.exists()) {
        print('Error: File not found: $path');
        continue;
      }
      final sql = await file.readAsString();
      print('Executing SQL...');
      await conn.execute(sql);
      print('✅ Applied successfully.');
    } catch (e) {
      print('❌ Failed: $e');
    }
  }

  await conn.close();
  print('\nDone.');
  exit(0);
}
