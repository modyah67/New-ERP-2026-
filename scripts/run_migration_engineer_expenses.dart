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
  print(' Engineer Expenses & Custody Settlement Migration');
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
      ),
    );
    print('✅ Connected to database successfully.\n');
  } catch (e) {
    print('❌ Connection failed: $e');
    exit(1);
  }

  try {
    final file = File('supabase/migrations/20261005000001_add_engineer_expenses_cost_type_and_custody_settlement.sql');
    if (!file.existsSync()) {
      print('❌ Error: Migration file not found.');
      exit(1);
    }

    final sql = decodeFile(file);
    print('Executing migration SQL...');
    await conn.execute(sql);
    print('✅ Migration executed successfully!\n');
  } catch (e, st) {
    print('❌ Error applying migration: $e\n$st');
  } finally {
    await conn.close();
    print('Connection closed.');
  }
}
