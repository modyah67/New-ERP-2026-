import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final host = 'aws-0-eu-north-1.pooler.supabase.com';
  final username = 'postgres.pjkhdnoeyyvraclomepx';
  final database = 'postgres';
  final port = 5432;

  String? password = Platform.environment['SUPABASE_DB_PASSWORD'];
  if (password == null || password.isEmpty) {
    stdout.write('Enter your Supabase database password: ');
    password = stdin.readLineSync()?.trim();
    stdout.writeln();
  }
  if (password == null || password.isEmpty) { print('Error: password required.'); exit(1); }

  print('Connecting...');
  Connection? conn;
  try {
    conn = await Connection.open(
      Endpoint(host: host, database: database, username: username, password: password, port: port),
      settings: ConnectionSettings(sslMode: SslMode.require),
    );
  } catch (e) { print('Connection failed: $e'); exit(1); }

  print('Applying migration: 20260724000000_add_rpc_pay_shipment_cost_item.sql');
  try {
    final sql = File('supabase/migrations/20260724000000_add_rpc_pay_shipment_cost_item.sql')
        .readAsStringSync();
    await conn.execute(sql);
    print('✅ Migration applied successfully.');
  } catch (e) {
    print('❌ Migration failed: $e');
  }

  // Verify function exists
  print('\nVerifying function...');
  try {
    final rows = await conn.execute(
      "SELECT proname FROM pg_proc WHERE proname = 'rpc_pay_shipment_cost_item'"
    );
    if (rows.isNotEmpty) {
      print('✅ Function rpc_pay_shipment_cost_item exists in database.');
    } else {
      print('❌ Function NOT found in database.');
    }
  } catch (e) {
    print('⚠️ Verification query failed: $e');
  }

  await conn.close();
}
