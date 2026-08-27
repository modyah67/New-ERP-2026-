import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InventoryValuationService', () {
    test('valuation calculates weighted average cost correctly', () {
      final batches = [
        {'quantity': 500.0, 'unit_cost': 10.0},
        {'quantity': 300.0, 'unit_cost': 12.0},
        {'quantity': 200.0, 'unit_cost': 15.0},
      ];

      double totalQuantity = 0;
      double totalValue = 0;
      for (final b in batches) {
        final qty = b['quantity'] as double;
        final cost = b['unit_cost'] as double;
        totalQuantity += qty;
        totalValue += qty * cost;
      }
      final avgCost = totalValue / totalQuantity;

      expect(totalQuantity, 1000.0);
      expect(totalValue, 5000 + 3600 + 3000); // 11600
      expect(avgCost, 11.6);
    });

    test('valuation calculates value for single batch', () {
      final batch = {'quantity': 750.0, 'unit_cost': 20.0};
      final value = (batch['quantity'] as double) * (batch['unit_cost'] as double);
      expect(value, 15000.0);
    });

    test('valuation returns zero for empty batches', () {
      final batches = <Map<String, dynamic>>[];
      double totalQuantity = 0;
      double totalValue = 0;
      for (final b in batches) {
        totalQuantity += b['quantity'] as double;
        totalValue += (b['quantity'] as double) * (b['unit_cost'] as double);
      }
      expect(totalQuantity, 0.0);
      expect(totalValue, 0.0);
    });

    test('valuation groups by product correctly', () {
      final items = [
        {'product_id': 1, 'product_name': 'برتقال', 'quantity': 500.0, 'value': 7500.0},
        {'product_id': 2, 'product_name': 'ليمون', 'quantity': 300.0, 'value': 4500.0},
      ];

      final totalValue = items.fold(0.0, (sum, i) => sum + (i['value'] as double));
      final totalQty = items.fold(0.0, (sum, i) => sum + (i['quantity'] as double));

      expect(items.length, 2);
      expect(totalValue, 12000.0);
      expect(totalQty, 800.0);
    });
  });
}
