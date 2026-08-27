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
    final result = await conn.execute("""
      SELECT n.nspname as schema,
             p.proname as name,
             pg_catalog.pg_get_function_arguments(p.oid) as args
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE p.proname = 'post_journal_entry'
    """);
    for (final row in result) {
      print('${row[0]}.${row[1]}(${row[2]})');
    }
  } catch (e) {
    print('Query failed: $e');
  } finally {
    await conn.close();
  }
}
