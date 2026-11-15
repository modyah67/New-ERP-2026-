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
  final host = 'aws-0-eu-central-1.pooler.supabase.com';
  final username = 'postgres.rakdzuvlauphupkywoik';
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

  print('====================================================');
  print(' Fix: packing_order child tables UUID → BIGINT');
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
    print('✅ Connected successfully.');
  } catch (e) {
    print('❌ Connection failed: $e');
    exit(1);
  }

  // Check current column types BEFORE migration
  print('\n=== BEFORE: Column types ===');
  try {
    final res = await conn.execute('''
      SELECT table_name, column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND column_name = 'packing_order_id'
        AND table_name IN ('packing_order_cost_items', 'packing_order_lines', 'packing_order_sortings', 'packing_wastes')
      ORDER BY table_name;
    ''');
    for (final row in res) {
      print('  ${row[0]}.${row[1]} → ${row[2]}');
    }
  } catch (e) {
    print('⚠️ Check failed: $e');
  }

  // Apply migration
  print('\n=== Applying migration ===');
  try {
    final migrationFile = File('supabase/migrations/sql/fix_packing_order_uuid_to_bigint.sql');
    if (!await migrationFile.exists()) {
      print('❌ Migration file not found');
      await conn.close();
      exit(1);
    }
    final sql = decodeFile(migrationFile);
    print('Executing SQL (${sql.length} chars)...');
    await conn.execute(sql);
    print('✅ Migration applied successfully!');
  } catch (e) {
    print('❌ Migration failed: $e');
    await conn.close();
    exit(1);
  }

  // Check column types AFTER migration
  print('\n=== AFTER: Column types ===');
  try {
    final res = await conn.execute('''
      SELECT table_name, column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND column_name = 'packing_order_id'
        AND table_name IN ('packing_order_cost_items', 'packing_order_lines', 'packing_order_sortings', 'packing_wastes')
      ORDER BY table_name;
    ''');
    for (final row in res) {
      print('  ${row[0]}.${row[1]} → ${row[2]}');
    }
  } catch (e) {
    print('⚠️ Check failed: $e');
  }

  // Verify rpc_confirm_packing_order function exists
  print('\n=== Verifying RPC function ===');
  try {
    final fn = await conn.execute(
      "SELECT proname FROM pg_proc WHERE proname = 'rpc_confirm_packing_order';"
    );
    if (fn.isNotEmpty) {
      print('✅ rpc_confirm_packing_order function exists');
    } else {
      print('⚠️ rpc_confirm_packing_order function NOT found');
    }
  } catch (e) {
    print('⚠️ Verification failed: $e');
  }

  await conn.close();
  print('\n🎉 Done! You can now click "تأكيد" in the app.');
}
