import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  String? password = Platform.environment['DB_PASS'];
  
  final conn = await Connection.open(
    Endpoint(
      host: 'aws-0-eu-north-1.pooler.supabase.com',
      database: 'postgres',
      username: 'postgres.pjkhdnoeyyvraclomepx',
      password: password,
      port: 5432,
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );

  try {
    // Check journal_entries schema
    final cols = await conn.execute('''
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns 
      WHERE table_name = 'journal_entries'
      ORDER BY ordinal_position;
    ''');
    print('=== journal_entries columns ===');
    for (var row in cols) {
      print(row[0].toString().padRight(25) + row[1].toString().padRight(20) + 'nullable=' + row[2].toString() + '  default=' + (row[3] ?? 'NONE').toString());
    }

    // Check how entry_number is typically generated
    final maxNum = await conn.execute('''
      SELECT entry_number FROM journal_entries ORDER BY id DESC LIMIT 5;
    ''');
    print('\n=== Recent entry_numbers ===');
    for (var row in maxNum) {
      print('  ' + row[0].toString());
    }
  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
