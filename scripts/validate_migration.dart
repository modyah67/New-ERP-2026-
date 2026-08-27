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

  if (password == null || password.isEmpty) {
    print('Error: Password cannot be empty.');
    exit(1);
  }

  print('Connecting to database...');
  try {
    final conn = await Connection.open(
      Endpoint(
        host: host,
        database: database,
        username: username,
        password: password,
        port: port,
      ),
      settings: ConnectionSettings(
        sslMode: SslMode.require,
      ),
    );

    print('Validating sequences for repaired tables...');
    final results = await conn.execute(
      '''
      SELECT 
        pg_get_serial_sequence('public.clearing_agents', 'id') AS clearing_agents,
        pg_get_serial_sequence('public.export_shipment_items', 'id') AS export_shipment_items,
        pg_get_serial_sequence('public.lot_returns', 'id') AS lot_returns,
        pg_get_serial_sequence('public.station_product_batches', 'id') AS station_product_batches,
        pg_get_serial_sequence('public.station_products', 'id') AS station_products;
      '''
    );

    // Validate the treasury relation constraint
    final fkeyResult = await conn.execute(
      '''
      SELECT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'treasury_transactions_related_treasury_id_fkey' 
          AND table_schema = 'public'
      );
      '''
    );
    final bool hasFkey = fkeyResult.first.first as bool;

    // Validate the auth trigger on auth.users
    final triggerResult = await conn.execute(
      '''
      SELECT EXISTS (
        SELECT 1 
        FROM pg_trigger 
        WHERE tgname = 'on_auth_user_created'
      );
      '''
    );
    final bool hasTrigger = triggerResult.first.first as bool;

    // Validate RLS status on a representative table (public.accounts)
    final rlsResult = await conn.execute(
      '''
      SELECT relrowsecurity 
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'accounts';
      '''
    );
    final bool hasRls = rlsResult.isNotEmpty && (rlsResult.first.first as bool);

    print('\n--- VALIDATION RESULTS ---');
    final row = results.first;
    final tables = ['clearing_agents', 'export_shipment_items', 'lot_returns', 'station_product_batches', 'station_products'];
    
    bool allValid = true;
    for (int i = 0; i < tables.length; i++) {
      final seq = row[i];
      if (seq == null) {
        print('❌ Table "${tables[i]}" has NO sequence linked to its "id" column!');
        allValid = false;
      } else {
        print('✅ Table "${tables[i]}" sequence is correctly linked: $seq');
      }
    }

    if (hasFkey) {
      print('✅ Constraint "treasury_transactions_related_treasury_id_fkey" is present in public.treasury_transactions.');
    } else {
      print('❌ Constraint "treasury_transactions_related_treasury_id_fkey" is MISSING in public.treasury_transactions!');
      allValid = false;
    }

    if (hasTrigger) {
      print('✅ Auth trigger "on_auth_user_created" is present on auth.users.');
    } else {
      print('❌ Auth trigger "on_auth_user_created" is MISSING on auth.users!');
      allValid = false;
    }

    if (hasRls) {
      print('✅ Row Level Security (RLS) is enabled on public.accounts.');
    } else {
      print('❌ Row Level Security (RLS) is disabled on public.accounts!');
      allValid = false;
    }

    if (allValid) {
      print('\n🎉 All missing sequences, constraints, triggers, and security policies have been successfully restored and linked!');
    } else {
      print('\n⚠️ Some database objects or security settings are still missing. Please make sure the compiled migration has been applied.');
    }

    await conn.close();
  } catch (e) {
    print('Database connection failed: $e');
  }
}
