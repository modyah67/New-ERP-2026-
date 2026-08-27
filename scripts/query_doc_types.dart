import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(Endpoint(host: 'aws-0-eu-north-1.pooler.supabase.com', database: 'postgres', username: 'postgres.pjkhdnoeyyvraclomepx', password: Platform.environment['SUPABASE_DB_PASSWORD'] ?? '', port: 5432), settings: ConnectionSettings(sslMode: SslMode.require)); 
  final results = await conn.execute('SELECT code FROM document_types'); 
  for (final row in results) { print(row[0]); } 
  await conn.close();
}
