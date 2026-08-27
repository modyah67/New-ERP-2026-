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
      settings: ConnectionSettings(sslMode: SslMode.require),
    );
    print('Connected successfully.');
  } catch (e) {
    print('Database connection failed: $e');
    exit(1);
  }

  try {
    final migrationFile = File(
        'supabase/migrations/20260808000026_122_fix_export_shipment_leaf_accounts.sql');
    if (!await migrationFile.exists()) {
      print('Error: Migration file not found at ${migrationFile.path}');
      await conn.close();
      exit(1);
    }
    final sql = decodeFile(migrationFile);
    print('Migration SQL loaded (${sql.length} chars)');
    print('Executing migration 122...');
    await conn.execute(sql);
    print('Migration 122 applied successfully.');

    print('\n=== Backfill export shipment journal entries ===');
    for (final sid in [1, 2]) {
      final result = await conn.execute(
        "SELECT public.rpc_process_export_shipment_ledger($sid);",
      );
      print('Shipment $sid: ${result.first.first}');
    }

    print('\n=== Verification ===');
    final jes = await conn.execute('''
      SELECT je.id, je.entry_number, je.source_type, je.source_id, je.description
      FROM journal_entries je
      WHERE je.source_type IN ('export_shipment', 'export_discount')
      ORDER BY je.id;
    ''');
    print('Export shipment journal entries:');
    for (final row in jes) {
      print('  $row');
    }

    await conn.close();
    print('\nDone.');
  } catch (e, st) {
    print('Error applying migration: $e\n$st');
    await conn.close();
    exit(1);
  }
}
