import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_model.dart';
import 'package:accounting_system/data/models/packing_order_line_model.dart';
import 'package:accounting_system/data/models/packing_cost_variance_model.dart';

void main() {
  group('Packing Cost Variance Stage Sync Tests', () {
    test('1. Pre-stage 1 order indicates crops are unconfirmed', () {
      final order = PackingOrderModel(
        id: '1001',
        orderNumber: 'PO-2026-001',
        lotId: '1',
        grade: 'A',
        status: 'pending',
        fruitCostBase: 50000.0,
      );

      expect(order.isCropsConfirmed, isFalse);
      expect(order.cropsJournalEntryId, isNull);
    });

    test('2. Stage 1 confirmation reflects isCropsConfirmed and enables journal linking', () {
      final now = DateTime.now();
      final order = PackingOrderModel(
        id: '1002',
        orderNumber: 'PO-2026-002',
        lotId: '1',
        grade: 'A',
        status: 'crops_confirmed',
        fruitCostBase: 50000.0,
        fruitCostAllocated: 48000.0,
        cropsConfirmedAt: now,
        cropsJournalEntryId: '2001',
      );

      expect(order.isCropsConfirmed, isTrue);
      expect(order.cropsJournalEntryId, equals('2001'));
      expect(order.cropsConfirmedAt, equals(now));
    });

    test('3. Variance item model properly reflects fullyActual status and non-null actualCost', () {
      final item = PackingCostItemComparison(
        name: 'خام: برتقال صيفي',
        category: 'fruit',
        estimatedCost: 50000.0,
        actualCost: 50000.0,
        variance: 0.0,
        variancePercent: 0.0,
        status: PackingCostStatus.fullyActual,
        source: 'قيد صرف المحاصيل #POC-00001 (مخزون الخام 12412)',
        journalEntryId: 2001,
        sourceType: 'packing_order_crops',
        sourceId: '1002',
        unit: 'كجم',
      );

      expect(item.hasActualCost, isTrue);
      expect(item.actualCost, equals(50000.0));
      expect(item.status, equals(PackingCostStatus.fullyActual));
      expect(item.status.labelAr, equals('مكتمل فعلياً'));
      expect(item.reasonNotAvailable, isNull);
      expect(item.journalEntryId, equals(2001));
    });

    test('4. Multi-line packing order lines retain actual costs', () {
      final lines = [
        const PackingOrderLineModel(
          packingOrderId: 1002,
          productName: 'برتقال صيفي كرتون 15 كجم',
          quantity: 2500,
          unitCost: 10.0,
          rawMaterialCost: 25000.0,
          finalCost: 25000.0,
        ),
        const PackingOrderLineModel(
          packingOrderId: 1002,
          productName: 'برتقال صيفي كرتون 10 كجم',
          quantity: 2500,
          unitCost: 10.0,
          rawMaterialCost: 25000.0,
          finalCost: 25000.0,
        ),
      ];

      expect(lines.length, equals(2));
      expect(lines.fold<double>(0.0, (sum, l) => sum + l.rawMaterialCost), equals(50000.0));
    });
  });
}
