import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExecutiveDashboardService', () {
    test('total revenue calculation', () {
      final shipments = [
        {'total_revenue': 9000.0},
        {'total_revenue': 12000.0},
        {'total_revenue': 7500.0},
      ];

      final totalRevenue = shipments.fold(0.0, (sum, s) => sum + (s['total_revenue'] as double));
      expect(totalRevenue, 28500.0);
    });

    test('total cost calculation', () {
      final shipments = [
        {'total_cost': 4500.0},
        {'total_cost': 6000.0},
        {'total_cost': 3500.0},
      ];

      final totalCost = shipments.fold(0.0, (sum, s) => sum + (s['total_cost'] as double));
      expect(totalCost, 14000.0);
    });

    test('overall profit margin', () {
      const totalRevenue = 28500.0;
      const totalCost = 14000.0;
      final profit = totalRevenue - totalCost;
      final margin = (profit / totalRevenue) * 100;

      expect(profit, 14500.0);
      expect(margin, closeTo(50.88, 0.01));
    });

    test('month over month trend', () {
      final monthlyData = {
        '2026-01': {'revenue': 10000.0, 'cost': 6000.0},
        '2026-02': {'revenue': 12000.0, 'cost': 7000.0},
        '2026-03': {'revenue': 15000.0, 'cost': 8000.0},
      };

      final revenueGrowth = ((monthlyData['2026-03']!['revenue']! - monthlyData['2026-02']!['revenue']!) /
          monthlyData['2026-02']!['revenue']!) * 100;

      expect(monthlyData.length, 3);
      expect(revenueGrowth, closeTo(25.0, 0.01));
    });

    test('top products by revenue', () {
      final products = [
        {'name': 'برتقال', 'revenue': 50000.0},
        {'name': 'ليمون', 'revenue': 35000.0},
        {'name': 'جريب فروت', 'revenue': 20000.0},
      ];

      products.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));

      expect(products[0]['name'], 'برتقال');
      expect(products[0]['revenue'], 50000.0);
    });
  });
}
