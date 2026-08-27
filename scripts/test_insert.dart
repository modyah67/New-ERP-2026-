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
    print('Inserting clearing agent...');
    final res = await conn.execute("""
      INSERT INTO clearing_agents (code, name, broker_type, currency) 
      VALUES ('9999', 'Test Agent', 'بحري', 'EGP')
      RETURNING id;
    """);
    print('Inserted! ID: ${res[0][0]}');
  } catch (e) {
    print('Error: $e');
  }

  await conn.close();
  exit(0);
}
