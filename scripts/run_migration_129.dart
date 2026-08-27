import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final host = 'aws-0-eu-north-1.pooler.supabase.com';
  final username = 'postgres.pjkhdnoeyyvraclomepx';
  final database = 'postgres';
  final port = 5432;

  String? password = Platform.environment['DB_PASS'];
  
  if (password == null || password.isEmpty) {
    stdout.write('Enter DB Password: ');
    password = stdin.readLineSync();
  }

  if (password == null || password.isEmpty) {
    print('Password is required.');
    exit(1);
  }

  print('Connecting to Supabase PostgreSQL...');
  final conn = await Connection.open(
    Endpoint(
      host: host,
      database: database,
      username: username,
      password: password,
      port: port,
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );

  print('✅ Connected!');

  final migrationFiles = [
    'supabase/migrations/20260809000003_129_sync_entity_opening_balances_gl.sql',
  ];

  for (final path in migrationFiles) {
    final file = File(path);
    if (!await file.exists()) {
      print('❌ File not found: $path');
      continue;
    }

    print('\\nApplying: ${file.path.split('/').last}');
    try {
      final sql = await file.readAsString();
      print('Executing SQL...');
      await conn.execute(sql);
      print('✅ Applied successfully.');
    } catch (e) {
      print('❌ Failed: $e');
    }
  }

  await conn.close();
  print('\\nDone.');
  exit(0);
}
