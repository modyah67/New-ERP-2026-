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
    final result = await conn.execute('''
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'shipment_cost_items' 
        AND column_name = 'vendor_id';
    ''');
    print('shipment_cost_items vendor_id type: ' + result[0][1].toString());

    final result2 = await conn.execute('''
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'ledger_entries' 
        AND column_name = 'reference_id';
    ''');
    print('ledger_entries reference_id type: ' + result2[0][1].toString());
    
    final result3 = await conn.execute('''
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'clearing_agents' 
        AND column_name = 'id';
    ''');
    print('clearing_agents id type: ' + result3[0][1].toString());

    final result4 = await conn.execute('''
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'shipment_cost_items' 
        AND column_name = 'id';
    ''');
    print('shipment_cost_items id type: ' + result4[0][1].toString());
    
  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
