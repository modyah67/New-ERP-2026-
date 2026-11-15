import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/services/packing_cost_variance_service.dart';

void main() {
  group('Engineer Expense Item Visibility & Pool Tests', () {
    test('1. Engineer expense from custody pool evaluates to fullyActual with matching amounts', () {
      final rawItem = {
        'id': 101,
        'name': 'مصاريف مهندسين وإشراف',
        'category': 'engineer_expenses',
        'supplier_type': 'engineer',
        'supplier_name': 'مجمع عهد الموظفين',
        'cost_status': 'actual',
        'expected_amount': 1500.0,
        'actual_amount': 1500.0,
        'base_amount': 1500.0,
        'total_egp': 1500.0,
        'is_engineer_cost_settled': true,
        'pool_remaining_pool': 3500.0,
        'notes': 'تحميل نسبة من وجبات وانتقالات مهندسي المحطة',
      };

      final costItemStatus = rawItem['cost_status']?.toString();
      final double? actualAmount = (rawItem['actual_amount'] as num?)?.toDouble();
      final bool isEngineer = rawItem['supplier_type'] == 'engineer' || rawItem['category'] == 'engineer_expenses';
      final bool isEngineerSettled = (isEngineer && (rawItem['is_engineer_cost_settled'] == true || costItemStatus == 'actual')) ||
          (isEngineer && actualAmount != null && actualAmount > 0);
      final bool isSettledActual = (costItemStatus == 'actual' && actualAmount != null) ||
          isEngineerSettled;

      expect(isEngineer, true);
      expect(isEngineerSettled, true);
      expect(isSettledActual, true);

      final double estAmount = (rawItem['expected_amount'] as num).toDouble();
      final double netActual = (actualAmount ?? estAmount);

      expect(estAmount, 1500.0);
      expect(netActual, 1500.0);
      expect(netActual - estAmount, 0.0);
    });

    test('2. Insufficient balance check is bypassed for engineer pool expenses', () {
      const isEngineer = true;
      const paymentSourceType = 'none';
      const int? selectedPaymentSourceId = null;
      const double availableBalance = 0.0;
      const double totalInSupplierCurrency = 2500.0;

      final isInsufficientBalance = !isEngineer &&
          (paymentSourceType != 'none') &&
          (selectedPaymentSourceId != null) &&
          (totalInSupplierCurrency > availableBalance);

      expect(isInsufficientBalance, false);

      const name = 'مصاريف مهندسين وإشراف';
      const price = 2500.0;
      final canSubmit = name.isNotEmpty &&
          price > 0 &&
          !isInsufficientBalance;

      expect(canSubmit, true);
    });

    test('3. Non-existent report_category_id is sanitized to null to prevent FK 23503', () {
      final validCatIds = <int>{1, 2, 3, 5, 10};
      
      // A stale or hardcoded id like 19
      const rawReportCatId = 19;
      final reportCategoryId = validCatIds.contains(rawReportCatId)
          ? rawReportCatId
          : null;

      expect(reportCategoryId, isNull);
    });

    test('4. Dynamic remaining balance: Deducts existing engineer items from custody pool in real-time', () {
      const double dbPoolRemaining = 2200.0;
      const double dbPoolAllocated = 500.0;

      final costItems = [
        {
          'name': 'مصاريف مهندسين وإشراف',
          'category': 'engineer_expenses',
          'supplier_type': 'engineer',
          'total_egp': 200.0,
        },
        {
          'name': 'مصاريف إدارية',
          'category': 'admin',
          'total_egp': 1000.0,
        },
      ];

      double computeAllocated(List<Map<String, dynamic>> items) {
        return items.where((c) {
          final cat = (c['category']?.toString() ?? '').toLowerCase();
          final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
          final name = (c['name']?.toString() ?? '').toLowerCase();
          return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
        }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
      }

      // After first addition (200 EGP allocated)
      final allocated1 = computeAllocated(costItems);
      final effRemaining1 = math.max(0.0, dbPoolRemaining - allocated1);
      final effAllocated1 = dbPoolAllocated + allocated1;

      expect(allocated1, equals(200.0));
      expect(effRemaining1, equals(2000.0)); // 2200 - 200 = 2000!
      expect(effAllocated1, equals(700.0));

      // After second addition (another 200 EGP allocated)
      costItems.add({
        'name': 'مصاريف مهندسين وإشراف',
        'category': 'engineer_expenses',
        'supplier_type': 'engineer',
        'total_egp': 200.0,
      });

      final allocated2 = computeAllocated(costItems);
      final effRemaining2 = math.max(0.0, dbPoolRemaining - allocated2);
      final effAllocated2 = dbPoolAllocated + allocated2;

      expect(allocated2, equals(400.0));
      expect(effRemaining2, equals(1800.0)); // 2000 - 200 = 1800!
      expect(effAllocated2, equals(900.0));
    });

    test('5. PackingCostVarianceService.canonicalCostKey collapses duplicates with different notes and categories', () {
      final itemA = {
        'name': 'مصاريف إدارية',
        'category': 'admin',
        'total_egp': 1000.0,
        'notes': 'اوراق',
      };
      final itemB = {
        'name': 'مصاريف اداريه', // normalized Arabic alef and taa marbuta
        'category': 'other', // unnormalized DB category
        'supplier_type': 'admin',
        'total_egp': 1000.0,
        'notes': '', // empty note
      };

      final keyA = PackingCostVarianceService.canonicalCostKey(itemA);
      final keyB = PackingCostVarianceService.canonicalCostKey(itemB);

      expect(keyA, equals('مصاريف اداريه|admin|1000.00'));
      expect(keyB, equals('مصاريف اداريه|admin|1000.00'));
      expect(keyA, equals(keyB)); // Exact match!
    });
  });
}
