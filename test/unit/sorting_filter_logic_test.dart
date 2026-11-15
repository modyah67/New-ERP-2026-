import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_sorting_model.dart';

void main() {
  group('Grading / Sorting Status Filter Logic Tests', () {
    // 1. Fully Sold Item: 30kg total, 30kg sold, 0kg remaining
    final fullySoldItem = PackingOrderSortingModel(
      id: 1,
      packingOrderId: 10,
      productName: 'فراوله - كراتين',
      weightKg: 30.0,
      remainingWeightKg: 0.0,
      costPerKg: 10.0,
      totalCost: 300.0,
      totalSaleAmount: 300.0,
      status: 'sold',
    );

    // 2. Partially Sold Item: 100kg total, 50kg sold, 50kg remaining
    final partiallySoldItem = PackingOrderSortingModel(
      id: 2,
      packingOrderId: 10,
      productName: 'فراوله - وزن',
      weightKg: 100.0,
      remainingWeightKg: 50.0,
      costPerKg: 10.0,
      totalCost: 1000.0,
      totalSaleAmount: 500.0,
      status: 'pending',
    );

    // 3. Completely Unsold / Pending Item: 80kg total, 0kg sold, 80kg remaining
    final unsoldItem = PackingOrderSortingModel(
      id: 3,
      packingOrderId: 10,
      productName: 'مانجو - عويس',
      weightKg: 80.0,
      remainingWeightKg: 80.0,
      costPerKg: 20.0,
      totalCost: 1600.0,
      totalSaleAmount: 0.0,
      status: 'pending',
    );

    final allItems = [fullySoldItem, partiallySoldItem, unsoldItem];

    double getSoldQty(PackingOrderSortingModel s) {
      final sold = s.weightKg - s.remainingWeightKg;
      return sold > 0 ? sold : 0.0;
    }

    bool isPending(PackingOrderSortingModel s) => s.remainingWeightKg > 0;
    bool isPartial(PackingOrderSortingModel s) => getSoldQty(s) > 0 && s.remainingWeightKg > 0;
    bool isSold(PackingOrderSortingModel s) => getSoldQty(s) > 0 || s.remainingWeightKg <= 0 || s.status == 'sold';
    bool isFullySold(PackingOrderSortingModel s) => s.remainingWeightKg <= 0 || s.status == 'sold';

    test('Filter "تم البيع" includes both fully sold AND partially sold items', () {
      final soldItems = allItems.where(isSold).toList();

      // Both fullySoldItem (30kg) and partiallySoldItem (50kg) must be included!
      expect(soldItems.length, 2);
      expect(soldItems.any((s) => s.id == 1), isTrue);
      expect(soldItems.any((s) => s.id == 2), isTrue);
      expect(soldItems.any((s) => s.id == 3), isFalse); // Unsold is excluded
    });

    test('Filter "مباع جزئياً" isolates only items with partial sales and remaining stock', () {
      final partialItems = allItems.where(isPartial).toList();

      expect(partialItems.length, 1);
      expect(partialItems.first.id, 2);
      expect(partialItems.first.productName, 'فراوله - وزن');
    });

    test('Filter "قيد الانتظار" includes items with available stock to sell', () {
      final pendingItems = allItems.where(isPending).toList();

      // Both partiallySoldItem (50kg remaining) and unsoldItem (80kg remaining) have available stock
      expect(pendingItems.length, 2);
      expect(pendingItems.any((s) => s.id == 2), isTrue);
      expect(pendingItems.any((s) => s.id == 3), isTrue);
      expect(pendingItems.any((s) => s.id == 1), isFalse); // Fully sold has 0kg remaining
    });

    test('Filter "تم البيع بالكامل" includes only items with zero remaining stock', () {
      final fullySoldItems = allItems.where(isFullySold).toList();

      expect(fullySoldItems.length, 1);
      expect(fullySoldItems.first.id, 1);
    });

    test('Counters accurately synchronize with filtered lists', () {
      final allCount = allItems.length;
      final pendingCount = allItems.where(isPending).length;
      final partialCount = allItems.where(isPartial).length;
      final soldCount = allItems.where(isSold).length;
      final fullySoldCount = allItems.where(isFullySold).length;

      expect(allCount, 3);
      expect(pendingCount, 2);
      expect(partialCount, 1);
      expect(soldCount, 2);
      expect(fullySoldCount, 1);
    });
  });
}
