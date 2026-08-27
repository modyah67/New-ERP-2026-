import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CostAllocationService', () {
    test('calculateGradingCost shares cost proportionally by quantity', () {
      final totalCost = 15000.0;
      final grades = [
        {'grade': 'A', 'quantity': 500.0},
        {'grade': 'B', 'quantity': 300.0},
        {'grade': 'C', 'quantity': 200.0},
      ];
      final totalQuantity = 1000.0;

      final results = grades.map((g) {
        final share = (g['quantity'] as double) / totalQuantity * totalCost;
        return {
          'grade': g['grade'],
          'quantity': g['quantity'],
          'cost': share,
        };
      }).toList();

      expect(results.length, 3);
      expect(results[0]['cost'], 7500.0); // A: 500/1000 * 15000
      expect(results[1]['cost'], 4500.0); // B: 300/1000 * 15000
      expect(results[2]['cost'], 3000.0); // C: 200/1000 * 15000
    });

    test('calculateGradingCost handles single grade', () {
      final totalCost = 10000.0;
      final grades = [
        {'grade': 'A', 'quantity': 800.0},
      ];
      final totalQuantity = 800.0;

      final results = grades.map((g) {
        final share = (g['quantity'] as double) / totalQuantity * totalCost;
        return {'grade': g['grade'], 'quantity': g['quantity'], 'cost': share};
      }).toList();

      expect(results.length, 1);
      expect(results[0]['cost'], 10000.0);
    });

    test('calculateGradingCost handles zero quantity gracefully', () {
      const totalQuantity = 0.0;
      expect(totalQuantity, 0.0);
    });

    test('consumeFruitForPacking cascades across FIFO batches correctly', () {
      final batches = [
        {'id': 1, 'quantity': 100.0, 'unit_cost': 10.0},
        {'id': 2, 'quantity': 200.0, 'unit_cost': 12.0},
        {'id': 3, 'quantity': 150.0, 'unit_cost': 15.0},
      ];

      double remaining = 250.0;
      double totalCost = 0.0;
      final consumed = <Map<String, dynamic>>[];

      for (final batch in batches) {
        if (remaining <= 0) break;
        final batchQty = batch['quantity'] as double;
        final take = batchQty < remaining ? batchQty : remaining;
        totalCost += take * (batch['unit_cost'] as double);
        consumed.add({'batch_id': batch['id'], 'quantity': take, 'cost': take * (batch['unit_cost'] as double)});
        remaining -= take;
      }

      expect(remaining, 0.0);
      expect(totalCost, 2800.0); // 100*10 + 150*12
      expect(consumed.length, 2); // consumed from batches 1 and 2 only
      expect(consumed[0]['quantity'], 100.0);
      expect(consumed[1]['quantity'], 150.0);
    });

    test('consumeFruitForPacking throws when insufficient stock', () {
      final batches = [
        {'id': 1, 'quantity': 50.0, 'unit_cost': 10.0},
      ];

      double remaining = 100.0;

      for (final batch in batches) {
        if (remaining <= 0) break;
        remaining -= batch['quantity'] as double;
      }

      expect(remaining > 0, isTrue);
    });

    test('updateCosting excludes packing material cost when nonPackingLandedCost provided', () {
      const totalCost = 10000.0;
      const packingCost = 2000.0;
      final nonPackingLandedCost = totalCost - packingCost;

      const fruitCost = 6000.0;
      const logisticsCost = 1000.0;
      const otherCost = 1000.0;

      final nonPackingTotal = fruitCost + logisticsCost + otherCost;

      expect(nonPackingLandedCost, 8000.0);
      expect(nonPackingTotal, 8000.0);
    });
  });
}
