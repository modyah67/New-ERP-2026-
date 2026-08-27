import 'package:postgres/postgres.dart';
import 'dart:io';
void main() async {
  final conn = await Connection.open(Endpoint(host: 'localhost', database: 'postgres', username: 'postgres', password: 'postgres_password', port: 5432));
  final res = await conn.execute("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'packing_orders_status_check'");
  print('Constraint definition:');
  for (final row in res) {
    print(row[0]);
  }
  await conn.close();
}
