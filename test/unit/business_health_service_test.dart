import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessHealthService', () {
    test('gross profit margin calculation', () {
      const revenue = 100000.0;
      const cogs = 60000.0;
      final grossProfit = revenue - cogs;
      final grossMargin = (grossProfit / revenue) * 100;

      expect(grossProfit, 40000.0);
      expect(grossMargin, 40.0);
    });

    test('net profit margin after expenses', () {
      const revenue = 100000.0;
      const cogs = 60000.0;
      const operatingExpenses = 15000.0;
      final netProfit = revenue - cogs - operatingExpenses;
      final netMargin = (netProfit / revenue) * 100;

      expect(netProfit, 25000.0);
      expect(netMargin, 25.0);
    });

    test('inventory turnover ratio', () {
      const cogs = 60000.0;
      const avgInventory = 15000.0;
      final turnover = cogs / avgInventory;

      expect(turnover, 4.0);
    });

    test('average carton cost', () {
      const totalCost = 45000.0;
      const totalCartons = 3000;
      final avgCartonCost = totalCost / totalCartons;

      expect(avgCartonCost, 15.0);
    });

    test('average carton revenue', () {
      const totalRevenue = 90000.0;
      const totalCartons = 3000;
      final avgCartonRevenue = totalRevenue / totalCartons;

      expect(avgCartonRevenue, 30.0);
    });
  });
}
