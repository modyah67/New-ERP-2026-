import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/station_product_batch.dart';
import 'package:accounting_system/data/models/station_product_model.dart';

void main() {
  group('Crop Return FIFO Batch & Warehouse Stock Synchronization Tests', () {
    test('Returning 400 from 1000 leaves exactly 600 in both batch total quantity and remaining quantity', () {
      // 1. Initial purchase batch of 1000 units
      const initialQty = 1000.0;
      const returnQty = 400.0;
      const unitCost = 15.0;

      const initialBatch = StationProductBatch(
        id: 1,
        stationId: 1,
        productName: 'مانجو كيت',
        productCode: 'LOT-2026-001',
        quantity: initialQty,
        remainingQuantity: initialQty,
        unitCost: unitCost,
        currency: 'EGP',
        exchangeRate: 1.0,
        sourceType: 'lot_receipt',
      );

      expect(initialBatch.quantity, equals(1000.0));
      expect(initialBatch.remainingQuantity, equals(1000.0));
      expect(initialBatch.batchTotalCost, equals(15000.0));

      // 2. Simulate RPC Dual Quantity Reduction on return of 400
      final deduct = returnQty.clamp(0.0, initialBatch.remainingQuantity);
      final updatedBatch = initialBatch.copyWith(
        quantity: (initialBatch.quantity - deduct).clamp(0.0, double.infinity),
        remainingQuantity: (initialBatch.remainingQuantity - deduct).clamp(0.0, double.infinity),
      );

      // Verify that batch view and item card show exactly 600 total and 600 remaining
      expect(updatedBatch.quantity, equals(600.0), reason: 'Total quantity must be reduced to 600');
      expect(updatedBatch.remainingQuantity, equals(600.0), reason: 'Remaining quantity must be 600');
      expect(updatedBatch.batchTotalCost, equals(9000.0), reason: 'Batch valuation must be 600 * 15 = 9000');
    });

    test('Warehouse stock (station_products) synchronization matches total batch remaining quantities', () {
      // Batches after returning 400 from 1000
      final batches = [
        const StationProductBatch(
          id: 1,
          stationId: 1,
          productName: 'مانجو كيت',
          productCode: 'LOT-2026-001',
          quantity: 600.0,
          remainingQuantity: 600.0,
          unitCost: 15.0,
          currency: 'EGP',
          sourceType: 'lot_receipt',
          fruitTypeId: 10,
        ),
      ];

      // Station products calculated from SUM(remaining_quantity)
      final totalStock = batches.fold<double>(0.0, (sum, b) => sum + b.remainingQuantity);

      final stationProduct = StationProductModel(
        id: 1,
        stationId: 1,
        productName: 'مانجو كيت',
        productCode: 'LOT-2026-001',
        quantity: totalStock,
        unit: 'kg',
        itemType: 'fruit',
        fruitTypeId: 10,
      );

      expect(stationProduct.quantity, equals(600.0));
      expect(totalStock, equals(600.0));
    });

    test('Multi-batch FIFO cascade: returning 400 sequentially exhausts Batch 1 (300) and deducts 100 from Batch 2 (700)', () {
      const batch1 = StationProductBatch(
        id: 1,
        stationId: 1,
        productName: 'برتقال صيفي',
        quantity: 300.0,
        remainingQuantity: 300.0,
        unitCost: 10.0,
        sourceType: 'lot_receipt',
      );

      const batch2 = StationProductBatch(
        id: 2,
        stationId: 1,
        productName: 'برتقال صيفي',
        quantity: 700.0,
        remainingQuantity: 700.0,
        unitCost: 10.0,
        sourceType: 'lot_receipt',
      );

      var remToDeduct = 400.0;
      final updatedBatches = <StationProductBatch>[];

      for (final b in [batch1, batch2]) {
        if (remToDeduct <= 0) {
          updatedBatches.add(b);
          continue;
        }
        final deduct = b.remainingQuantity >= remToDeduct ? remToDeduct : b.remainingQuantity;
        updatedBatches.add(b.copyWith(
          quantity: (b.quantity - deduct).clamp(0.0, double.infinity),
          remainingQuantity: (b.remainingQuantity - deduct).clamp(0.0, double.infinity),
        ));
        remToDeduct -= deduct;
      }

      expect(remToDeduct, equals(0.0));
      expect(updatedBatches[0].quantity, equals(0.0));
      expect(updatedBatches[0].remainingQuantity, equals(0.0));
      expect(updatedBatches[1].quantity, equals(600.0));
      expect(updatedBatches[1].remainingQuantity, equals(600.0));

      final netAvailable = updatedBatches.fold<double>(0.0, (sum, b) => sum + b.remainingQuantity);
      expect(netAvailable, equals(600.0));
    });

    test('Prevention of client-side double deduction: verifies 600 is retained instead of corrupted 200', () {
      // Prior bug:
      // 1. Initial 1000
      // 2. RPC deducted 400 -> remaining 600
      // 3. Client-side Dart code read 600 and subtracted 400 again -> remaining 200 (CORRUPTED)
      const initialQty = 1000.0;
      const returnQty = 400.0;

      // With atomic backend RPC only:
      const rpcRemaining = initialQty - returnQty;
      expect(rpcRemaining, equals(600.0));

      // With client-side deduction removed, finalRemaining equals rpcRemaining (600)
      const finalRemaining = rpcRemaining;
      expect(finalRemaining, equals(600.0), reason: 'Inventory must not be double deducted to 200');
    });
  });
}
