import 'package:postgres/postgres.dart';

void main() async {
  Connection? connection;
  try {
    connection = await Connection.open(Endpoint(
      host: 'localhost',
      port: 5432,
      database: 'erp',
      username: 'postgres',
      password: 'postgres',
    ));

    final results = await connection.execute(
      Sql('SELECT id, station_id, product_name, product_code, quantity, remaining_quantity FROM station_product_batches ORDER BY id DESC LIMIT 20'),
    );
    for (final row in results) {
      print(row);
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    await connection?.close();
  }
}
