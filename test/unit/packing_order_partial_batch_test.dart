import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/station_product_batch.dart';

/// Unit tests for Partial Batch Quantity Tracking & Remaining Balance in Packing Orders
void main() {
  group('Packing Order Partial Batch Quantity Tracking Tests', () {
    test('1. Batch remaining balance calculation across multiple crop entries in same order', () {
      final batch1 = StationProductBatch(
        id: 101,
        stationId: 1,
        productName: 'Orange Valencia',
        productCode: 'LOT-ORG-001',
        quantity: 1000.0,
        remainingQuantity: 1000.0,
        unitCost: 15.0,
      );

      final batchBaseRemaining = <int, double>{
        101: 1000.0,
      };

      // Simulated entries in the packing order form
      final entries = <Map<String, dynamic>>[
        {'id': 1, 'batch_id': 101, 'effective_weight': 500.0},
        {'id': 2, 'batch_id': null, 'effective_weight': 0.0},
      ];

      // Helper function matching the implementation in PackingOrderFormPage
      double getBatchRemainingForEntry(StationProductBatch batch, Map<String, dynamic> forEntry) {
        final bId = batch.id;
        if (bId == null) return 0.0;
        final baseAvail = batchBaseRemaining[bId] ?? batch.remainingQuantity;
        double consumedElsewhere = 0.0;
        for (final e in entries) {
          if (e['id'] != forEntry['id'] && e['batch_id'] == bId) {
            consumedElsewhere += (e['effective_weight'] as num).toDouble();
          }
        }
        final rem = baseAvail - consumedElsewhere;
        return rem > 0.0 ? rem : 0.0;
      }

      // Check available for Crop #1 (forEntry = entry #1) -> consumedElsewhere is 0 -> 1000.0
      expect(getBatchRemainingForEntry(batch1, entries[0]), 1000.0);

      // Check available for Crop #2 (forEntry = entry #2) -> consumedElsewhere is 500.0 (from entry #1) -> 500.0
      expect(getBatchRemainingForEntry(batch1, entries[1]), 500.0);

      // Verify batch is selectable in Crop #2 because remaining > 0
      final isSelectableInCrop2 = getBatchRemainingForEntry(batch1, entries[1]) > 0.001;
      expect(isSelectableInCrop2, isTrue);

      // Now Crop #2 selects Batch 101 and allocates 500 kg
      entries[1]['batch_id'] = 101;
      entries[1]['effective_weight'] = 500.0;

      // Add Crop #3
      final entry3 = {'id': 3, 'batch_id': null, 'effective_weight': 0.0};
      entries.add(entry3);

      // Check available for Crop #3 -> consumed elsewhere = 500 + 500 = 1000 -> 0.0 remaining
      expect(getBatchRemainingForEntry(batch1, entry3), 0.0);

      // Verify batch 101 is NOT selectable (hidden) in Crop #3 because balance reached zero
      final isSelectableInCrop3 = getBatchRemainingForEntry(batch1, entry3) > 0.001;
      expect(isSelectableInCrop3, isFalse);
    });

    test('2. Dynamic recalculation when adjusting or deleting crop quantities', () {
      final batch1 = StationProductBatch(
        id: 202,
        stationId: 1,
        productName: 'Lemon Eureka',
        productCode: 'LOT-LMN-002',
        quantity: 1200.0,
        remainingQuantity: 1200.0,
        unitCost: 20.0,
      );

      final batchBaseRemaining = <int, double>{
        202: 1200.0,
      };

      final entries = <Map<String, dynamic>>[
        {'id': 1, 'batch_id': 202, 'effective_weight': 700.0},
        {'id': 2, 'batch_id': 202, 'effective_weight': 500.0},
        {'id': 3, 'batch_id': null, 'effective_weight': 0.0},
      ];

      double getBatchRemainingForEntry(StationProductBatch batch, Map<String, dynamic> forEntry) {
        final bId = batch.id;
        if (bId == null) return 0.0;
        final baseAvail = batchBaseRemaining[bId] ?? batch.remainingQuantity;
        double consumedElsewhere = 0.0;
        for (final e in entries) {
          if (e['id'] != forEntry['id'] && e['batch_id'] == bId) {
            consumedElsewhere += (e['effective_weight'] as num).toDouble();
          }
        }
        final rem = baseAvail - consumedElsewhere;
        return rem > 0.0 ? rem : 0.0;
      }

      // Initially Crop #3 has 0 remaining
      expect(getBatchRemainingForEntry(batch1, entries[2]), 0.0);

      // User reduces Crop #1 from 700 to 400 kg
      entries[0]['effective_weight'] = 400.0;

      // Now Crop #3 should immediately have 300 kg available (1200 - 400 - 500)
      expect(getBatchRemainingForEntry(batch1, entries[2]), 300.0);
      expect(getBatchRemainingForEntry(batch1, entries[2]) > 0.001, isTrue);

      // User deletes Crop #2 entirely
      entries.removeAt(1);

      // Now Crop #3 (which is now at index 1) should have 800 kg available (1200 - 400)
      expect(getBatchRemainingForEntry(batch1, entries[1]), 800.0);
    });

    test('3. Deducting quantities consumed across other active/saved pending/draft orders', () {
      final batch1 = StationProductBatch(
        id: 303,
        stationId: 1,
        productName: 'Pomegranate Wonderful',
        productCode: 'LOT-POM-003',
        quantity: 2000.0,
        remainingQuantity: 2000.0,
        unitCost: 25.0,
      );

      // Other active/saved orders in DB: Order #10 has 400 kg, Order #11 has 350 kg
      final otherActiveOrdersLines = [
        {'packing_order_id': 10, 'batch_id': 303, 'quantity': 400.0},
        {'packing_order_id': 11, 'batch_id': 303, 'quantity': 350.0},
      ];

      double consumedByOtherOrders = 0.0;
      for (final line in otherActiveOrdersLines) {
        if (line['batch_id'] == batch1.id) {
          consumedByOtherOrders += (line['quantity'] as num).toDouble();
        }
      }

      final baseRemaining = (batch1.remainingQuantity - consumedByOtherOrders).clamp(0.0, double.infinity);
      expect(baseRemaining, 1250.0); // 2000 - 750

      final batchBaseRemaining = <int, double>{
        303: baseRemaining,
      };

      // In current order, Crop #1 takes 1000 kg
      final currentEntries = <Map<String, dynamic>>[
        {'id': 1, 'batch_id': 303, 'effective_weight': 1000.0},
        {'id': 2, 'batch_id': null, 'effective_weight': 0.0},
      ];

      double getBatchRemainingForEntry(StationProductBatch batch, Map<String, dynamic> forEntry) {
        final bId = batch.id;
        if (bId == null) return 0.0;
        final baseAvail = batchBaseRemaining[bId] ?? batch.remainingQuantity;
        double consumedElsewhere = 0.0;
        for (final e in currentEntries) {
          if (e['id'] != forEntry['id'] && e['batch_id'] == bId) {
            consumedElsewhere += (e['effective_weight'] as num).toDouble();
          }
        }
        final rem = baseAvail - consumedElsewhere;
        return rem > 0.0 ? rem : 0.0;
      }

      // Crop #2 has exactly 250 kg available (1250 base - 1000 Crop #1)
      expect(getBatchRemainingForEntry(batch1, currentEntries[1]), 250.0);
    });

    test('4. Validation prevents allocating greater than batch remaining balance', () {
      final batchBaseRemaining = <int, double>{
        404: 500.0,
      };

      final batch404 = StationProductBatch(
        id: 404,
        stationId: 1,
        productName: 'Mango Keitt',
        productCode: 'LOT-MNG-004',
        quantity: 500.0,
        remainingQuantity: 500.0,
        unitCost: 35.0,
      );

      final entries = [
        {'id': 1, 'batch_id': 404, 'effective_weight': 300.0},
        {'id': 2, 'batch_id': 404, 'effective_weight': 250.0}, // Exceeds by 50 kg! (300 + 250 = 550 > 500)
      ];

      double getBatchRemainingForEntry(StationProductBatch batch, Map<String, dynamic> forEntry) {
        final bId = batch.id;
        if (bId == null) return 0.0;
        final baseAvail = batchBaseRemaining[bId] ?? batch.remainingQuantity;
        double consumedElsewhere = 0.0;
        for (final e in entries) {
          if (e['id'] != forEntry['id'] && e['batch_id'] == bId) {
            consumedElsewhere += (e['effective_weight'] as num).toDouble();
          }
        }
        final rem = baseAvail - consumedElsewhere;
        return rem > 0.0 ? rem : 0.0;
      }

      // For entry #2, available is 500 - 300 = 200 kg
      final availableForEntry2 = getBatchRemainingForEntry(batch404, entries[1]);
      expect(availableForEntry2, 200.0);

      // Validation condition: effective_weight > available + epsilon
      final isEntry2OverLimit = (entries[1]['effective_weight'] as double) > availableForEntry2 + 0.001;
      expect(isEntry2OverLimit, isTrue);

      // Total order validation
      final totalUsed = entries.fold<double>(0.0, (sum, e) => sum + (e['effective_weight'] as double));
      final baseAvail = batchBaseRemaining[404]!;
      expect(totalUsed > baseAvail + 0.001, isTrue);
      expect(totalUsed, 550.0);
    });
  });
}
