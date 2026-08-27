import 'package:postgres/postgres.dart';
import 'dart:io';

void main() async {
  try {
    final conn = await Connection.open(
      Endpoint(
        host: 'localhost',
        database: 'postgres',
        username: 'postgres',
        password: '123456',
        port: 5432
      ),
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );
    print('Connected successfully!');
    
    final results = await conn.execute("SELECT datname FROM pg_database;");
    print('Databases:');
    for (final row in results) {
      print(row[0]);
    }
    
    await conn.close();
  } catch (e) {
    print('Error: $e');
  }
}
