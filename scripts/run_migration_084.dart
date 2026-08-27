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
        'supabase/migrations/20260806000006_084_fix_packing_order_enterprise_gl_and_allocation.sql');
    if (!await migrationFile.exists()) {
      print('Error: Migration file not found at ${migrationFile.path}');
      await conn.close();
      exit(1);
    }
    final sql = decodeFile(migrationFile);
    print('Migration SQL loaded (${sql.length} chars)');
    print('Executing migration 084...');
    await conn.execute(sql);
    print('Migration 084 applied successfully.');

    print('\n=== Verification ===');
    final acc = await conn.execute(
      "SELECT account_code, account_name FROM accounts WHERE account_code IN ('1030','1031','1040') ORDER BY account_code;",
    );
    print('Inventory accounts:');
    for (final row in acc) {
      print('  ${row[0]} — ${row[1]}');
    }

    final col = await conn.execute(
      "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='packing_orders' AND column_name='reversal_journal_entry_id';",
    );
    print('reversal_journal_entry_id exists: ${col.first.first == 1}');

    final fn = await conn.execute(
      "SELECT proname FROM pg_proc WHERE proname IN ('rpc_confirm_packing_order','rpc_cancel_packing_order','_packing_allocate_shares');",
    );
    print('Functions:');
    for (final row in fn) {
      print('  ${row[0]}');
    }

    await conn.close();
    print('\nDone.');
  } catch (e, st) {
    print('Error applying migration: $e\n$st');
    await conn.close();
    exit(1);
  }
}
