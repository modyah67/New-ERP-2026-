import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/services/custody_service.dart';

void main() {
  group('CustodyExpensePoolSummary Tests', () {
    test('1. Calculates remaining pool correctly', () {
      const summary = CustodyExpensePoolSummary(
        totalSpent: 5000.0,
        totalAllocated: 2000.0,
        remainingPool: 3000.0,
        mealsSpent: 1000.0,
        laborSpent: 2000.0,
        transportSpent: 2000.0,
      );

      expect(summary.remainingPool, 3000.0);
      expect(summary.remainingAfter(1000.0), 2000.0);
      expect(summary.remainingAfter(3500.0), 0.0);
    });

    test('2. Calculates cash amount from percentage correctly', () {
      const summary = CustodyExpensePoolSummary(
        totalSpent: 10000.0,
        totalAllocated: 2000.0,
        remainingPool: 8000.0,
      );

      // 50% of 8000 = 4000
      final amt50 = summary.calculateAmount(isPercentage: true, inputValue: 50.0);
      expect(amt50, 4000.0);

      // 100% of 8000 = 8000
      final amt100 = summary.calculateAmount(isPercentage: true, inputValue: 100.0);
      expect(amt100, 8000.0);

      // 25% of 8000 = 2000
      final amt25 = summary.calculateAmount(isPercentage: true, inputValue: 25.0);
      expect(amt25, 2000.0);
    });

    test('3. Direct cash amount mode returns inputValue directly', () {
      const summary = CustodyExpensePoolSummary(
        totalSpent: 5000.0,
        totalAllocated: 1000.0,
        remainingPool: 4000.0,
      );

      final directAmt = summary.calculateAmount(isPercentage: false, inputValue: 1500.0);
      expect(directAmt, 1500.0);
    });

    test('4. CustodyExpensePoolSummary stores and preserves fromDate and toDate range', () {
      final from = DateTime(2026, 11, 1);
      final to = DateTime(2026, 11, 30);
      final summary = CustodyExpensePoolSummary(
        totalSpent: 12000.0,
        totalAllocated: 4000.0,
        remainingPool: 8000.0,
        mealsSpent: 3000.0,
        laborSpent: 5000.0,
        transportSpent: 4000.0,
        transactionsCount: 15,
        allocatedOrdersCount: 3,
        fromDate: from,
        toDate: to,
      );

      expect(summary.fromDate, equals(from));
      expect(summary.toDate, equals(to));
      expect(summary.totalSpent, equals(12000.0));
      expect(summary.remainingPool, equals(8000.0));
    });

    test('5. In-memory date range evaluation logic accurately filters transactions', () {
      final from = DateTime.utc(2026, 11, 1, 0, 0, 0);
      final to = DateTime.utc(2026, 11, 10, 23, 59, 59, 999);

      final transactions = [
        {'id': 1, 'amount': 1000.0, 'created_at': '2026-10-31T12:00:00Z'}, // Before
        {'id': 2, 'amount': 2500.0, 'created_at': '2026-11-01T10:00:00Z'}, // Inside
        {'id': 3, 'amount': 1500.0, 'created_at': '2026-11-08T14:30:00Z'}, // Inside
        {'id': 4, 'amount': 3000.0, 'created_at': '2026-11-15T09:00:00Z'}, // After
      ];

      final filtered = transactions.where((tx) {
        final txDate = DateTime.tryParse(tx['created_at'].toString())?.toUtc();
        if (txDate == null) return false;
        if (txDate.isBefore(from)) return false;
        if (txDate.isAfter(to)) return false;
        return true;
      }).toList();

      expect(filtered.length, equals(2));
      final totalFiltered = filtered.fold<double>(0.0, (sum, tx) => sum + (tx['amount'] as double));
      expect(totalFiltered, equals(4000.0));
    });
  });
}
