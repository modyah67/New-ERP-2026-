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
    final result = await conn.execute("SELECT id, code, name FROM clearing_agents");
    for (final row in result) {
      print('${row[0]} | ${row[1]} | ${row[2]}');
    }
  } catch (e) {
    print('Failed: $e');
  } finally {
    await conn.close();
  }
}
