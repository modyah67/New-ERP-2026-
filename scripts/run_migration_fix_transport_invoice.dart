import 'dart:io';
import 'dart:convert';
import 'package:postgres/postgres.dart';

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
  print(' Fix: rpc_add_transport_invoice Overloading (PGRST203)');
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

  try {
    final migrationFile = File('supabase/migrations/20261020000001_fix_transport_invoice_numeric_overload.sql');
    if (!migrationFile.existsSync()) {
      throw Exception('Migration file not found: ${migrationFile.path}');
    }

    final sql = migrationFile.readAsStringSync();
    print('Executing SQL migration...');
    await conn.execute(sql);
    print('✅ Migration executed successfully!');
    print('PostgREST schema cache reloaded.');
  } catch (e) {
    print('❌ Error executing migration: $e');
  } finally {
    await conn.close();
    print('\nConnection closed.');
  }
}
