import 'package:postgres/postgres.dart';
import 'dart:io';

void main() async {
  final conn = await Connection.open(Endpoint(host: 'localhost', database: 'postgres', username: 'postgres', password: 'postgres_password', port: 5432));
  final results = await conn.execute('SELECT id, product_id, batch_number, quantity FROM stock_batches ORDER BY created_at DESC LIMIT 5');
  for (final row in results) {
    print(row);
  }
  await conn.close();
}
