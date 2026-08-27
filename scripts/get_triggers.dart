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
    final result = await conn.execute("SELECT trigger_name, action_statement FROM information_schema.triggers WHERE event_object_table = 'clearing_agents'");
    for (final row in result) {
      print('TRIGGER: ${row[0]}');
      print('ACTION: ${row[1]}');
      print('---------------------------');
    }
  } catch (e) {
    print('Failed: $e');
  } finally {
    await conn.close();
  }
}
