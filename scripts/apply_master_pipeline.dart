import 'dart:io';
import 'package:postgres/postgres.dart';

Future<void> main(List<String> args) async {
  final host = 'aws-0-eu-central-1.pooler.supabase.com';
  final username = 'postgres.rakdzuvlauphupkywoik';
  final database = 'postgres';
  final port = 5432; // session pooler for DDL support

  String? password = Platform.environment['SUPABASE_DB_PASSWORD'];
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--password' && i + 1 < args.length) {
      password = args[i + 1];
    }
  }

  if (password == null || password.isEmpty) {
    stdout.write('Enter database password for $username: ');
    password = stdin.readLineSync()?.trim();
    stdout.writeln();
  }

  if (password == null || password.isEmpty) {
    print('❌ Error: Password cannot be empty.');
    exit(1);
  }

  print('====================================================');
  print(' Fruity Farms ERP — Master Database Migration');
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
        queryTimeout: const Duration(minutes: 10),
      ),
    );
    print('✅ Connected successfully to PostgreSQL.');
  } catch (e) {
    print('❌ Connection failed: $e');
    exit(1);
  }

  final files = [
    'supabase/migrations/20260721000000_initial_schema.sql',
    'supabase/scripts/master_split/01_master_reset_cleanup_and_coa.sql',
    'supabase/scripts/master_split/02_master_suppliers_and_operations.sql',
    'supabase/scripts/master_split/03_master_cost_centers_and_rpcs.sql',
  ];

  for (int i = 0; i < files.length; i++) {
    final path = files[i];
    print('\n[${i + 1}/${files.length}] Executing $path ...');
    final file = File(path);
    if (!await file.exists()) {
      print('❌ File not found: $path');
      await conn.close();
      exit(1);
    }

    final stopwatch = Stopwatch()..start();
    final sql = await file.readAsString();
    print('  Read ${sql.length} characters. Executing on server...');

    try {
      await conn.execute(sql);
      stopwatch.stop();
      print('  ✅ Success in ${stopwatch.elapsed.inSeconds}s (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      stopwatch.stop();
      print('  ❌ Migration failed on $path: $e');
      await conn.close();
      exit(1);
    }
  }

  print('\n====================================================');
  print(' Verifying Installed Schema and RPCs...');
  print('====================================================');
  try {
    final countRes = await conn.execute(
      "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'"
    );
    print('✅ Public tables count: ${countRes.first.first}');

    final rpcRes = await conn.execute(
      "SELECT count(*) FROM information_schema.routines WHERE routine_schema = 'public'"
    );
    print('✅ Public functions/RPCs count: ${rpcRes.first.first}');
  } catch (e) {
    print('⚠️ Verification query note: $e');
  }

  await conn.close();
  print('\n🎉 All 4 migration stages applied cleanly with zero errors!');
}
