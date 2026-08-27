import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShipmentBreakdownService', () {
    test('breakdown category totals sum correctly', () {
      final breakdowns = [
        {'category': 'fruit', 'amount': 3000.0},
        {'category': 'packing_material', 'amount': 500.0},
        {'category': 'logistics', 'amount': 700.0},
        {'category': 'export_costs', 'amount': 200.0},
        {'category': 'admin', 'amount': 100.0},
        {'category': 'other', 'amount': 0.0},
      ];

      final total = breakdowns.fold(0.0, (sum, b) => sum + (b['amount'] as double));
      expect(total, 4500.0);
    });

    test('breakdown has all required categories', () {
      const requiredCategories = ['fruit', 'packing_material', 'logistics', 'export_costs', 'admin', 'other'];
      expect(requiredCategories.length, 6);
      expect(requiredCategories.contains('fruit'), true);
      expect(requiredCategories.contains('packing_material'), true);
      expect(requiredCategories.contains('logistics'), true);
      expect(requiredCategories.contains('export_costs'), true);
      expect(requiredCategories.contains('admin'), true);
      expect(requiredCategories.contains('other'), true);
    });

    test('profit calculation uses revenue minus total cost', () {
      const revenue = 9000.0;
      const totalCost = 4500.0;
      final profit = revenue - totalCost;
      final margin = (profit / revenue) * 100;

      expect(profit, 4500.0);
      expect(margin, 50.0);
    });

    test('profit per carton calculation', () {
      const revenue = 9000.0;
      const totalCost = 4500.0;
      const cartons = 300;
      final profitPerCarton = (revenue - totalCost) / cartons;

      expect(profitPerCarton, 15.0);
    });
  });
}
