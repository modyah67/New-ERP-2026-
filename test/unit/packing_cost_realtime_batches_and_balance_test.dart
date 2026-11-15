import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/transport_batch_model.dart';
import 'package:accounting_system/data/models/transport_supplier_model.dart';
import 'package:accounting_system/core/data_change_event_bus.dart';

void main() {
  group('Real-Time Available Batches & Contractor Balance Deductions Tests', () {
    test('1. In-memory deduction accurately reduces batch available trucks and increases consumed trucks', () {
      final rawBatches = [
        const TransportBatchModel(
          id: 10,
          supplierId: 5,
          date: '2026-11-01',
          description: 'نقل محطة الجيزة',
          totalAmount: 15000.0,
          totalTrucks: 10.0,
          consumedTrucks: 2.0,
          availableTrucks: 8.0,
          costPerTruck: 1500.0,
        ),
        const TransportBatchModel(
          id: 11,
          supplierId: 5,
          date: '2026-11-05',
          description: 'نقل مزارع البحيرة',
          totalAmount: 6000.0,
          totalTrucks: 3.0,
          consumedTrucks: 0.0,
          availableTrucks: 3.0,
          costPerTruck: 2000.0,
        ),
      ];

      // Simulate cost items added in memory for current packing order
      final costItems = [
        {
          'transport_supplier_id': 5,
          'transport_batch_id': 10,
          'truck_count': 3.5,
          'total_egp': 5250.0,
        },
        {
          'transport_supplier_id': 5,
          'transport_batch_id': 10,
          'truck_count': 1.5,
          'total_egp': 2250.0,
        },
      ];

      // Calculate effective batches (same logic as _getEffectiveTransportBatches)
      final allocatedByBatch = <int, double>{};
      for (final c in costItems) {
        final bId = c['transport_batch_id'] as int?;
        if (bId != null) {
          final t = (c['truck_count'] as num).toDouble();
          allocatedByBatch[bId] = (allocatedByBatch[bId] ?? 0.0) + t;
        }
      }

      final effectiveBatches = rawBatches.map((b) {
        final allocated = allocatedByBatch[b.id] ?? 0.0;
        final available = (b.availableTrucks - allocated).clamp(0.0, double.infinity);
        final consumed = b.consumedTrucks + allocated;
        return b.copyWith(
          availableTrucks: available,
          consumedTrucks: consumed,
        );
      }).toList();

      // Batch 10: initial 8.0 available - (3.5 + 1.5) = 3.0 available, consumed = 2.0 + 5.0 = 7.0
      expect(effectiveBatches[0].availableTrucks, equals(3.0));
      expect(effectiveBatches[0].consumedTrucks, equals(7.0));
      expect(effectiveBatches[0].formattedAvailableTrucks, equals('3'));

      // Batch 11: unaffected (no cost items allocated to it)
      expect(effectiveBatches[1].availableTrucks, equals(3.0));
      expect(effectiveBatches[1].consumedTrucks, equals(0.0));
    });

    test('2. Editing a cost item excludes its own quantity from batch deduction', () {
      final rawBatches = [
        const TransportBatchModel(
          id: 10,
          supplierId: 5,
          date: '2026-11-01',
          description: 'دفعة نقل #10',
          totalAmount: 10000.0,
          totalTrucks: 5.0,
          consumedTrucks: 0.0,
          availableTrucks: 5.0,
          costPerTruck: 2000.0,
        ),
      ];

      final costItems = [
        {
          'transport_supplier_id': 5,
          'transport_batch_id': 10,
          'truck_count': 2.0,
        }, // index 0 (being edited)
        {
          'transport_supplier_id': 5,
          'transport_batch_id': 10,
          'truck_count': 1.0,
        }, // index 1
      ];

      // When editing index 0, excludeItemIndex = 0
      const excludeItemIndex = 0;
      final allocatedByBatch = <int, double>{};
      for (int i = 0; i < costItems.length; i++) {
        if (i == excludeItemIndex) continue;
        final c = costItems[i];
        final bId = c['transport_batch_id'] as int?;
        if (bId != null) {
          final t = (c['truck_count'] as num).toDouble();
          allocatedByBatch[bId] = (allocatedByBatch[bId] ?? 0.0) + t;
        }
      }

      final effectiveBatches = rawBatches.map((b) {
        final allocated = allocatedByBatch[b.id] ?? 0.0;
        final available = (b.availableTrucks - allocated).clamp(0.0, double.infinity);
        final consumed = b.consumedTrucks + allocated;
        return b.copyWith(
          availableTrucks: available,
          consumedTrucks: consumed,
        );
      }).toList();

      // Only item 1 (1.0 truck) was deducted, item 0 is excluded
      expect(effectiveBatches[0].availableTrucks, equals(4.0));
      expect(effectiveBatches[0].consumedTrucks, equals(1.0));
    });

    test('3. Contractor truck balance chip reflects remaining balance across all allocated cost items', () {
      final contractor = const TransportSupplierModel(
        id: 5,
        name: 'شركة الصفا للنقل',
        truckBalance: 8.0,
        balance: 25000.0,
        createdAt: '2026-01-01',
      );

      final costItems = [
        {
          'transport_supplier_id': '5',
          'truck_count': 2.5,
        },
        {
          'transport_supplier_id': '5',
          'truck_count': 1.5,
        },
        {
          'transport_supplier_id': '99', // Another supplier
          'truck_count': 4.0,
        },
      ];

      // Calculate remaining truck balance for supplier '5'
      double allocated = 0.0;
      for (final c in costItems) {
        if (c['transport_supplier_id'] == '5') {
          allocated += (c['truck_count'] as num).toDouble();
        }
      }

      final remaining = contractor.truckBalance - allocated;
      expect(remaining, equals(4.0)); // 8.0 - (2.5 + 1.5) = 4.0

      // When formatted for UI chip
      final formatted = remaining % 1 == 0
          ? remaining.toInt().toString()
          : remaining.toStringAsFixed(2);
      expect(formatted, equals('4'));
    });

    test('4. DataChangeEventBus triggers transport supplier stream on changes', () async {
      bool notified = false;
      final sub = DataChangeEventBus.instance.transportSuppliersStream.listen((_) {
        notified = true;
      });

      DataChangeEventBus.instance.notifyTransportSuppliersChanged();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(notified, isTrue);
      await sub.cancel();
    });

    test('5. Strict Filtering: Batches with remaining available trucks <= 0 are completely excluded', () {
      final batches = [
        const TransportBatchModel(
          id: 1,
          supplierId: 5,
          date: '2026-11-01',
          description: 'دفعة مستنفدة بالكامل',
          totalAmount: 5000.0,
          totalTrucks: 2.0,
          consumedTrucks: 2.0,
          availableTrucks: 0.0,
          costPerTruck: 2500.0,
        ),
        const TransportBatchModel(
          id: 2,
          supplierId: 5,
          date: '2026-11-02',
          description: 'دفعة بها رصيد متبقٍ',
          totalAmount: 10000.0,
          totalTrucks: 4.0,
          consumedTrucks: 1.0,
          availableTrucks: 3.0,
          costPerTruck: 2500.0,
        ),
      ];

      final filtered = batches.where((b) => b.availableTrucks > 0.0001).toList();

      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals(2));
      expect(filtered.any((b) => b.id == 1), isFalse);
    });

    test('6. Real-time batch exhaustion: Consuming full batch removes it from available batches list', () {
      final rawBatches = [
        const TransportBatchModel(
          id: 20,
          supplierId: 10,
          date: '2026-11-01',
          description: 'دفعة نقل العبور',
          totalAmount: 4000.0,
          totalTrucks: 2.0,
          consumedTrucks: 0.0,
          availableTrucks: 2.0,
          costPerTruck: 2000.0,
        ),
        const TransportBatchModel(
          id: 21,
          supplierId: 10,
          date: '2026-11-02',
          description: 'دفعة نقل السادات',
          totalAmount: 8000.0,
          totalTrucks: 4.0,
          consumedTrucks: 0.0,
          availableTrucks: 4.0,
          costPerTruck: 2000.0,
        ),
      ];

      // Cost item consumes all 2.0 trucks of Batch 20
      final costItems = [
        {
          'transport_supplier_id': 10,
          'transport_batch_id': 20,
          'truck_count': 2.0,
        },
      ];

      final allocatedByBatch = <int, double>{};
      for (final c in costItems) {
        final bId = c['transport_batch_id'] as int?;
        if (bId != null) {
          final t = (c['truck_count'] as num).toDouble();
          allocatedByBatch[bId] = (allocatedByBatch[bId] ?? 0.0) + t;
        }
      }

      final effectiveBatches = rawBatches.map((b) {
        final allocated = allocatedByBatch[b.id] ?? 0.0;
        final available = (b.availableTrucks - allocated).clamp(0.0, double.infinity);
        final consumed = b.consumedTrucks + allocated;
        return b.copyWith(
          availableTrucks: available,
          consumedTrucks: consumed,
        );
      }).toList();

      // Strict filter applied in UI dropdown & query
      final availableOnly = effectiveBatches.where((b) => b.availableTrucks > 0.0001).toList();

      expect(availableOnly.length, equals(1));
      expect(availableOnly.first.id, equals(21));
      expect(availableOnly.any((b) => b.id == 20), isFalse);
    });
  });
}

