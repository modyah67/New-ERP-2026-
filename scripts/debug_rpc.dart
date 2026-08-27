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
    // Get the actual function source from database
    final result = await conn.execute('''
      SELECT prosrc FROM pg_proc WHERE proname = 'rpc_sync_vendor_balances_and_ledger';
    ''');
    print('=== FUNCTION SOURCE ===');
    print(result[0][0].toString());
    print('=== END ===');

    // Check all triggers on clearing_agents
    final triggers = await conn.execute('''
      SELECT trigger_name, event_manipulation, action_statement 
      FROM information_schema.triggers 
      WHERE event_object_table = 'clearing_agents';
    ''');
    print('\n=== TRIGGERS ON clearing_agents ===');
    for (var row in triggers) {
      print('Trigger: ' + row[0].toString() + ' | Event: ' + row[1].toString());
      print('  Action: ' + row[2].toString());
    }

    // Check all triggers on shipping_companies
    final triggers2 = await conn.execute('''
      SELECT trigger_name, event_manipulation, action_statement 
      FROM information_schema.triggers 
      WHERE event_object_table = 'shipping_companies';
    ''');
    print('\n=== TRIGGERS ON shipping_companies ===');
    for (var row in triggers2) {
      print('Trigger: ' + row[0].toString() + ' | Event: ' + row[1].toString());
      print('  Action: ' + row[2].toString());
    }
  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
