import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  String? password = Platform.environment['DB_PASS'];
  
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
    print('Testing rpc_sync_vendor_balances_and_ledger...');
    final result = await conn.execute('''
      SELECT public.rpc_sync_vendor_balances_and_ledger();
    ''');
    print('Success: ' + result.toString());
  } catch (e) {
    print('Error executing RPC: ' + e.toString());
  } finally {
    await conn.close();
  }
}
