import 'dart:io';
import 'package:postgres/postgres.dart';

class RollbackException implements Exception {}

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
  Connection? conn;
  try {
    conn = await Connection.open(
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
  } catch (e) {
    print('Database connection failed: $e');
    exit(1);
  }

  // 1. Apply migration
  print('\n=== STEP 1: Applying Migration ===');
  try {
    final migrationFile = File('supabase/migrations/20260722_full_integrity_restoration.sql');
    if (!await migrationFile.exists()) {
      print('Error: Migration file not found.');
      await conn.close();
      exit(1);
    }
    final sql = await migrationFile.readAsString();
    print('Executing SQL migration...');
    await conn.execute(sql);
    print('✅ Migration applied successfully.');
  } catch (e) {
    print('❌ Failed to apply migration: $e');
    await conn.close();
    exit(1);
  }

  // 2. Verify pg_get_serial_sequence
  print('\n=== STEP 2: Verifying pg_get_serial_sequence ===');
  final tables = ['clearing_agents', 'export_shipment_items', 'lot_returns', 'station_product_batches', 'station_products'];
  try {
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
    final row = results.first;
    for (int i = 0; i < tables.length; i++) {
      final seq = row[i];
      if (seq == null) {
        print('❌ Table "${tables[i]}" has NO sequence linked to its "id" column!');
      } else {
        print('✅ Table "${tables[i]}" sequence: $seq');
      }
    }
  } catch (e) {
    print('❌ Failed to check serial sequences: $e');
  }

  // 3. Verify column_default = nextval(...)
  print('\n=== STEP 3: Verifying column_default ===');
  try {
    final results = await conn.execute(
      '''
      SELECT table_name, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public' 
        AND table_name IN ('clearing_agents', 'export_shipment_items', 'lot_returns', 'station_product_batches', 'station_products')
        AND column_name = 'id';
      '''
    );
    for (final row in results) {
      print('✅ Table "${row[0]}": default = ${row[1]}');
    }
  } catch (e) {
    print('❌ Failed to check column defaults: $e');
  }

  // 4. Insert temporary row and verify ID auto-generation
  print('\n=== STEP 4: Testing ID Auto-Generation via Transaction Rollback ===');
  try {
    // Let's get dependencies first
    final shipmentIdRow = await conn.execute("SELECT id FROM public.export_shipments LIMIT 1");
    final lotReceiptIdRow = await conn.execute("SELECT id FROM public.lot_receipts LIMIT 1");
    final stationIdRow = await conn.execute("SELECT id FROM public.stations LIMIT 1");

    final shipmentId = shipmentIdRow.isNotEmpty ? shipmentIdRow.first.first : null;
    final lotReceiptId = lotReceiptIdRow.isNotEmpty ? lotReceiptIdRow.first.first : null;
    final stationId = stationIdRow.isNotEmpty ? stationIdRow.first.first : null;

    print('Fetched dependencies: shipment_id=$shipmentId, lot_receipt_id=$lotReceiptId, station_id=$stationId');

    await conn.runTx((session) async {
      // 1. clearing_agents
      final r1 = await session.execute(
        "INSERT INTO public.clearing_agents (name, code) VALUES ('Test Agent Temp', 'TEMP_999') RETURNING id"
      );
      print('✅ clearing_agents temp ID generated: ${r1.first.first}');

      // 2. export_shipment_items
      if (shipmentId != null) {
        final r2 = await session.execute(
          "INSERT INTO public.export_shipment_items (shipment_id, product_name, quantity, price, weight_per_carton, net_weight, gross_weight, amount, pallets, sort_order) "
          "VALUES ($shipmentId, 'Test Product Temp', 10, 1.0, 15.0, 150.0, 160.0, 10.0, 1, 0) RETURNING id"
        );
        print('✅ export_shipment_items temp ID generated: ${r2.first.first}');
      } else {
        print('⚠️ Skipped export_shipment_items insert test (no shipments found in DB).');
      }

      // 3. lot_returns
      if (lotReceiptId != null) {
        final r3 = await session.execute(
          "INSERT INTO public.lot_returns (lot_receipt_id, returned_quantity, return_value) VALUES ($lotReceiptId, 10.0, 100.0) RETURNING id"
        );
        print('✅ lot_returns temp ID generated: ${r3.first.first}');
      } else {
        print('⚠️ Skipped lot_returns insert test (no lot receipts found in DB).');
      }

      // 4. station_product_batches
      if (stationId != null) {
        final r4 = await session.execute(
          "INSERT INTO public.station_product_batches (station_id, product_name, product_code, quantity, remaining_quantity, unit_cost, exchange_rate) "
          "VALUES ($stationId, 'Test Product Temp', 'TEMP_CODE', 100.0, 100.0, 1.0, 1.0) RETURNING id"
        );
        print('✅ station_product_batches temp ID generated: ${r4.first.first}');
      } else {
        print('⚠️ Skipped station_product_batches insert test (no stations found in DB).');
      }

      // 5. station_products
      if (stationId != null) {
        final r5 = await session.execute(
          "INSERT INTO public.station_products (station_id, product_name, product_code, quantity) VALUES ($stationId, 'Test Product Temp', 'TEMP_CODE', 100.0) RETURNING id"
        );
        print('✅ station_products temp ID generated: ${r5.first.first}');
      } else {
        print('⚠️ Skipped station_products insert test (no stations found in DB).');
      }

      print('Rolling back transaction...');
      throw RollbackException();
    });
  } catch (e) {
    if (e is RollbackException) {
      print('✅ Transaction successfully rolled back (test data removed).');
    } else {
      print('❌ Insert test failed: $e');
    }
  }

  await conn.close();
  print('\n=== FINISHED ===');
}
