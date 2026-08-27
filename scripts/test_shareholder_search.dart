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
    final result = await conn.execute("SELECT * FROM v_shareholders WHERE name ILIKE '%اسلام%' LIMIT 5;");
    print('Results: ${result.length}');
    for (final row in result) {
      print(row);
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    await conn.close();
  }
}
