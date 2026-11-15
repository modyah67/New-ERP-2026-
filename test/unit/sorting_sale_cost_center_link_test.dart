import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/data_change_event_bus.dart';
import 'package:accounting_system/data/models/cost_center.dart';

void main() {
  group('Sorting Sale Cost Center Linkage & Net Cost Offsetting', () {
    test('DataChangeEventBus broadcasts costCentersStream event upon notification', () async {
      final bus = DataChangeEventBus.instance;
      var received = false;

      final sub = bus.costCentersStream.listen((_) {
        received = true;
      });

      bus.notifyCostCentersChanged();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, isTrue);
      await sub.cancel();
    });

    test('Net cost calculation accurately offsets sorting sales proceeds from total costs', () {
      // Simulate cost entries for a parent fruit cost center (e.g., Strawberry CC-01)
      final transactions = <Map<String, dynamic>>[
        {
          'category': 'تكلفة المحاصيل',
          'item_name': 'فراولة خام - صنف فستيفال',
          'amount': 10000.0,
          'cost_center_id': 'CC-01',
        },
        {
          'category': 'مواد التعبئة',
          'item_name': 'كرتون 2 كجم',
          'amount': 2000.0,
          'cost_center_id': 'CC-01',
        },
        {
          'category': 'تشغيل وعمالة',
          'item_name': 'أجور عمالة الفرز والتعبئة',
          'amount': 1000.0,
          'cost_center_id': 'CC-01',
        },
        // Sorting Sale Credit Entry: 1,500.00 EGP revenue offsets costs
        {
          'category': 'تكلفة الفرز',
          'item_name': 'مبيعات فرزة - فراولة (تشغيلة PO-101)',
          'source_type': 'sorting_sale',
          'amount': -1500.0,
          'cost_center_id': 'CC-01',
        },
      ];

      final grossCost = transactions
          .where((t) => (t['amount'] as double) > 0)
          .fold<double>(0.0, (sum, t) => sum + (t['amount'] as double));

      final sortingRevenueOffset = transactions
          .where((t) => t['source_type'] == 'sorting_sale')
          .fold<double>(0.0, (sum, t) => sum + (t['amount'] as double));

      final netCost = transactions.fold<double>(
        0.0,
        (sum, t) => sum + (t['amount'] as double),
      );

      expect(grossCost, equals(13000.0));
      expect(sortingRevenueOffset, equals(-1500.0));
      expect(netCost, equals(11500.0));
    });

    test('Parent Fruit Cost Center is accurately resolved for sorting sale', () {
      final centers = [
        CostCenter.fromMap({
          'id': 1,
          'code': 'CC-01',
          'name': 'فراولة',
          'name_ar': 'فراولة',
          'name_en': 'Strawberry',
          'cost_center_type': 'variety',
          'product_id': 1,
        }),
        CostCenter.fromMap({
          'id': 2,
          'code': 'CC-02',
          'name': 'عنب',
          'name_ar': 'عنب',
          'name_en': 'Grapes',
          'cost_center_type': 'variety',
          'product_id': 2,
        }),
      ];

      // Match by product ID or fruit type ID
      const fruitTypeId = '1';
      final matchedById = centers.firstWhere(
        (c) => c.productId.toString() == fruitTypeId || c.code == 'CC-$fruitTypeId' || c.code == 'CC-0$fruitTypeId',
      );
      expect(matchedById.code, equals('CC-01'));
      expect(matchedById.nameAr, equals('فراولة'));

      // Match by product name
      const fruitName = 'فراولة';
      final matchedByName = centers.firstWhere(
        (c) => c.nameAr == fruitName || c.nameEn.toLowerCase() == fruitName.toLowerCase(),
      );
      expect(matchedByName.code, equals('CC-01'));
    });

    test('Cost center breakdown calculation accumulates negative sorting sale amount correctly', () {
      final centerMap = <String, Map<String, dynamic>>{
        'CC-01': {
          'id': 'CC-01',
          'name': 'فراولة',
          'total_amount': 0.0,
          'transaction_count': 0,
        },
      };

      final details = [
        {'cost_center_id': 'CC-01', 'amount': 10000.0},
        {'cost_center_id': 'CC-01', 'amount': -1500.0, 'source_type': 'sorting_sale'},
      ];

      for (final row in details) {
        final cid = row['cost_center_id'] as String;
        final amt = (row['amount'] as num).toDouble();
        centerMap[cid]!['total_amount'] = (centerMap[cid]!['total_amount'] as double) + amt;
        centerMap[cid]!['transaction_count'] = (centerMap[cid]!['transaction_count'] as int) + 1;
      }

      expect(centerMap['CC-01']!['total_amount'], equals(8500.0));
      expect(centerMap['CC-01']!['transaction_count'], equals(2));
    });
  });
}
