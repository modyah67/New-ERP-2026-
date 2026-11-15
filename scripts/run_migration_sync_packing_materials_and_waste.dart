import 'dart:io';
import 'dart:convert';
import 'package:postgres/postgres.dart';

String decodeFile(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final codeUnits = <int>[];
    for (int i = 2; i < bytes.length - 1; i += 2) {
      codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }
  try {
    return utf8.decode(bytes);
  } catch (e) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

void main(List<String> args) async {
  final host = 'aws-0-eu-central-1.pooler.supabase.com';
  final username = 'postgres.rakdzuvlauphupkywoik';
  final database = 'postgres';
  final port = 5432;

  String? password = Platform.environment['SUPABASE_DB_PASSWORD'];
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--password' && i + 1 < args.length) {
      password = args[i + 1];
    }
  }

  if (password == null || password.isEmpty) {
    stdout.write('Enter your Supabase database password for $username: ');
    password = stdin.readLineSync()?.trim();
    stdout.writeln();
  }

  if (password == null || password.isEmpty) {
    print('❌ Error: Password cannot be empty.');
    exit(1);
  }

  print('====================================================');
  print(' Sync Packing Materials & Waste To Cost Centers');
  print(' Target: $username @ $host:$port');
  print('====================================================\n');

  print('Connecting to database...');
  Connection conn;
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
        connectTimeout: const Duration(seconds: 30),
        queryTimeout: const Duration(minutes: 5),
      ),
    );
    print('✅ Connected successfully to PostgreSQL.');
  } catch (e) {
    print('❌ Connection failed: $e');
    exit(1);
  }

  // Apply migration
  print('\n=== Applying Migration ===');
  try {
    final migrationFile = File('supabase/migrations/20261025000001_sync_packing_materials_and_waste_to_cost_centers.sql');
    if (!await migrationFile.exists()) {
      print('❌ Migration file not found: supabase/migrations/20261025000001_sync_packing_materials_and_waste_to_cost_centers.sql');
      await conn.close();
      exit(1);
    }
    final sql = decodeFile(migrationFile);
    print('Executing SQL (${sql.length} characters)...');
    await conn.execute(sql);
    print('✅ Migration applied successfully!');
  } catch (e) {
    print('❌ Migration execution failed: $e');
    await conn.close();
    exit(1);
  }

  // Verify RPCs exist in schema
  print('\n=== Verifying Stored Procedures ===');
  final rpcs = [
    'rpc_confirm_packing_crops',
    'rpc_confirm_packing_packaging',
  ];

  for (final rpc in rpcs) {
    try {
      final res = await conn.execute(
        Sql.named('SELECT proname FROM pg_proc WHERE proname = @name;'),
        parameters: {'name': rpc},
      );
      if (res.isNotEmpty) {
        print('  ✅ Found function: public.$rpc');
      } else {
        print('  ❌ Missing function: public.$rpc');
      }
    } catch (e) {
      print('  ⚠️ Could not verify $rpc: $e');
    }
  }

  // Verify backfilled cost center transactions
  print('\n=== Verifying Cost Center Transactions ===');
  try {
    final res = await conn.execute(
      Sql.named('''
        SELECT id, cost_center_name, category, item_name, amount, source_type, source_id
        FROM public.cost_center_transactions
        WHERE source_type IN ('packing_material', 'packing_material_waste', 'packing_crop_waste')
        ORDER BY id DESC
        LIMIT 10;
      '''),
    );
    for (final row in res) {
      print('  Row: CC="${row[1]}" | Cat="${row[2]}" | Item="${row[3]}" | Amt=${row[4]} | Src=${row[5]}');
    }
  } catch (e) {
    print('  ⚠️ Could not query cost_center_transactions: $e');
  }

  await conn.close();
  print('\n🎉 Done! Migration 20261025000001 has been applied and verified.');
}
