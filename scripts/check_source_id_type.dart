import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(Endpoint(host: 'aws-0-eu-north-1.pooler.supabase.com', database: 'postgres', username: 'postgres.pjkhdnoeyyvraclomepx', password: 'Plat' 'form' '1!'));
  final res = await conn.execute('SELECT data_type FROM information_schema.columns WHERE table_name = \'journal_entries\' AND column_name = \'source_id\'');
  print('source_id type: ${res.first[0]}');
  await conn.close();
  exit(0);
}
