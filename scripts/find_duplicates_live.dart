import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final host = 'aws-0-eu-north-1.pooler.supabase.com';
  final username = 'postgres.pjkhdnoeyyvraclomepx';
  final database = 'postgres';
  final port = 5432;

  stdout.write('Enter your Supabase database password: ');
  stdin.echoMode = false;
  final password = stdin.readLineSync()?.trim();
  stdin.echoMode = true;
  stdout.writeln();

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

    print('Querying live database for all foreign keys...');
    final results = await conn.execute(
      '''
      SELECT
        tc.table_name,
        tc.constraint_name,
        kcu.column_name,
        ccu.table_name AS referenced_table_name,
        ccu.column_name AS referenced_column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public'
      ORDER BY tc.table_name, kcu.column_name;
      '''
    );

    print('\n--- ALL LIVE FOREIGN KEYS ---');
    final Map<String, List<Map<String, String>>> groups = {};
    for (final row in results) {
      final table = row[0] as String;
      final constraint = row[1] as String;
      final column = row[2] as String;
      final refTable = row[3] as String;
      final refColumn = row[4] as String;

      final key = '$table($column) -> $refTable($refColumn)';
      if (!groups.containsKey(key)) {
        groups[key] = [];
      }
      groups[key]!.add({
        'constraint': constraint,
        'table': table,
      });
    }

    bool hasDuplicates = false;
    groups.forEach((key, fks) {
      if (fks.length > 1) {
        print('\n⚠️ DUPLICATE RELATIONSHIP DETECTED: $key');
        for (final fk in fks) {
          print('  - Constraint: ${fk['constraint']}');
        }
        hasDuplicates = true;
      } else {
        print('  Unique: $key (${fks.first['constraint']})');
      }
    });

    if (!hasDuplicates) {
      print('\n🎉 No duplicate relationships found on the live database!');
    }

    await conn.close();
  } catch (e) {
    print('Error: $e');
  }
}
