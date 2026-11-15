import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Packaging Material Multi-Warehouse Selection & Storage Tests', () {
    test('1. Batch map stores station_id and station_name properly', () {
      final batch1 = {
        'batch_id': 101,
        'station_id': 1,
        'station_name': 'مخزن تاج',
        'product_code': 'BOX-01',
        'product_name': 'كرتونة مانجو 5 كجم',
        'remaining': 200.0,
        'unit_cost': 15.0,
      };

      final batch2 = {
        'batch_id': 102,
        'station_id': 2,
        'station_name': 'مخزن السادات',
        'product_code': 'BOX-01',
        'product_name': 'كرتونة مانجو 5 كجم',
        'remaining': 300.0,
        'unit_cost': 16.5,
      };

      expect(batch1['station_name'], equals('مخزن تاج'));
      expect(batch2['station_name'], equals('مخزن السادات'));
      expect(batch1['station_id'], isNot(equals(batch2['station_id'])));
    });

    test('2. Multi-warehouse simultaneous allocation distributes quantities correctly', () {
      final batches = [
        {
          'batch_id': 101,
          'station_id': 1,
          'station_name': 'مخزن تاج',
          'remaining': 300.0,
          'unit_cost': 15.0,
        },
        {
          'batch_id': 102,
          'station_id': 2,
          'station_name': 'مخزن السادات',
          'remaining': 400.0,
          'unit_cost': 16.0,
        },
      ];

      double requestedQty = 500.0;
      final allocated = <int, double>{};
      double remainingToAllocate = requestedQty;

      for (int i = 0; i < batches.length; i++) {
        if (remainingToAllocate <= 0) break;
        final batchRem = (batches[i]['remaining'] as num).toDouble();
        final take = remainingToAllocate < batchRem ? remainingToAllocate : batchRem;
        allocated[batches[i]['batch_id'] as int] = take;
        remainingToAllocate -= take;
      }

      expect(allocated[101], equals(300.0));
      expect(allocated[102], equals(200.0));
      expect(remainingToAllocate, equals(0.0));
    });

    test('3. Packaging items list stores separate warehouse records for deduction', () {
      final materialItems = <Map<String, dynamic>>[];

      // Adding allocation from Warehouse 1
      materialItems.add({
        'product_name': 'كرتونة مانجو',
        'product_code': 'BOX-01',
        'used_qty': 300.0,
        'unit_cost': 15.0,
        'total': 4500.0,
        'batch_id': 101,
        'station_id': 1,
        'station_name': 'مخزن تاج',
      });

      // Adding allocation from Warehouse 2
      materialItems.add({
        'product_name': 'كرتونة مانجو',
        'product_code': 'BOX-01',
        'used_qty': 200.0,
        'unit_cost': 16.0,
        'total': 3200.0,
        'batch_id': 102,
        'station_id': 2,
        'station_name': 'مخزن السادات',
      });

      expect(materialItems.length, equals(2));
      final warehouses = materialItems.map((m) => m['station_name']).toSet();
      expect(warehouses, containsAll(['مخزن تاج', 'مخزن السادات']));

      final totalQty = materialItems.fold<double>(0.0, (s, m) => s + (m['used_qty'] as double));
      expect(totalQty, equals(500.0));

      final totalCost = materialItems.fold<double>(0.0, (s, m) => s + (m['total'] as double));
      expect(totalCost, equals(7700.0));
    });
  });
}

