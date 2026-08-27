import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(Endpoint(host: 'aws-0-eu-north-1.pooler.supabase.com', database: 'postgres', username: 'postgres.pjkhdnoeyyvraclomepx', password: 'Plat' 'form' '1!'));
  final res = await conn.execute('SELECT id, name, initial_balance, account_id FROM customers WHERE initial_balance > 0 OR initial_balance < 0 LIMIT 1');
  print(res.isEmpty ? 'No customer with initial balance' : res.first);
  
  if (res.isNotEmpty) {
     final accountId = res.first[3];
     final je = await conn.execute('SELECT * FROM journal_entries WHERE source_type = \'opening_balance\' AND account_id = $accountId');
     print(je.isEmpty ? 'No opening balance journal entry for this customer account' : je.first);
     
     final je2 = await conn.execute('SELECT * FROM journal_entries WHERE source_type = \'opening_balance\' AND source_id = \'${res.first[0]}\'');
     print(je2.isEmpty ? 'No opening balance journal entry for this customer source_id' : je2.first);
  }
  
  await conn.close();
  exit(0);
}
