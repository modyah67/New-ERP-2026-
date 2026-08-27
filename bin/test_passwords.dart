import 'package:postgres/postgres.dart';
import 'dart:io';

void main() async {
  final passwords = ['password', 'postgres', 'admin', 'root', '123456', ''];
  final ports = [5432, 54322];
  
  for (final port in ports) {
    for (final password in passwords) {
      try {
        final conn = await Connection.open(
          Endpoint(
            host: 'localhost',
            database: 'postgres',
            username: 'postgres',
            password: password,
            port: port
          ),
          settings: ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 2)),
        );
        print('SUCCESS: Connected on port $port with password "$password"');
        await conn.close();
        return;
      } catch (e) {
        print('FAILED: port $port, password "$password" -> $e');
      }
    }
  }
}
