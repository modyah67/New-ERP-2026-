import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  String? password = Platform.environment['DB_PASS'];
  if (password == null || password.isEmpty) {
    print('Password is required.');
    exit(1);
  }

  final conn = await Connection.open(
    Endpoint(
      host: 'aws-0-eu-north-1.pooler.supabase.com',
      database: 'postgres',
      username: 'postgres.pjkhdnoeyyvraclomepx',
      password: password,
      port: 5432,
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );

  try {
    final migrationCode = await File('supabase/migrations/20260809000006_132_fix_exchange_journal_entry.sql').readAsString();
    await conn.execute(migrationCode);
    print('Migration 132 applied successfully!');
  } catch (e) {
    print('Migration failed: $e');
  } finally {
    await conn.close();
  }
}
