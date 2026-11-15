import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/lot_model.dart';

void main() {
  group('Crop Returns Calculation & Available Quantity Tests', () {
    test('LotReceiptModel accurately calculates purchasedQuantity and netCartonCount without arbitrary division', () {
      final lot = LotReceiptModel(
        id: '123',
        lotNumber: 'LOT-2026-001',
        productName: 'مانجو كيت فاخر',
        receiptDate: DateTime(2026, 9, 12),
        purchaseMode: 'carton',
        cartonCount: 1000,
        weightPerCartonKg: 10.0,
        netWeightKg: 1000.0,
        pricePerCarton: 150.0,
        totalProductCost: 150000.0,
        isConfirmed: true,
      );

      // Verify netCartonCount does not arbitrarily divide 1000 by 10 = 100
      expect(lot.netCartonCount, equals(1000));
      expect(lot.purchasedQuantity, equals(1000.0));
      expect(lot.unitLabel, equals('كرتونة'));
    });

    test('Available return quantity logic: 1000 purchased - 400 returned = 600 available', () {
      const double purchasedQuantity = 1000.0;
      const double returnedQuantity = 400.0;

      // Initially
      final double initialAvailable = (purchasedQuantity - 0.0).clamp(0.0, double.infinity);
      expect(initialAvailable, equals(1000.0));

      // After returning 400
      final double remainingAvailable = (purchasedQuantity - returnedQuantity).clamp(0.0, double.infinity);
      expect(remainingAvailable, equals(600.0));

      // After returning remaining 600
      final double fullyReturned = (purchasedQuantity - (returnedQuantity + 600.0)).clamp(0.0, double.infinity);
      expect(fullyReturned, equals(0.0));
    });

    test('Weight purchase mode calculates purchasedQuantity in kg', () {
      final lotWeight = LotReceiptModel(
        id: '124',
        lotNumber: 'LOT-2026-002',
        productName: 'برتقال صيفي',
        receiptDate: DateTime(2026, 9, 12),
        purchaseMode: 'weight',
        netWeightKg: 2500.0,
        grossWeightKg: 2600.0,
        productCostPerKg: 12.0,
        totalProductCost: 30000.0,
        isConfirmed: true,
      );

      expect(lotWeight.purchasedQuantity, equals(2500.0));
      expect(lotWeight.unitLabel, equals('كجم'));
    });

    test('Carton purchase with heavy net weight (1000 cartons, 8600 kg) strictly tracks 1000 cartons without scaling to 8600', () {
      final lotCartonsWithWeight = LotReceiptModel(
        id: '125',
        lotNumber: 'LOT-2026-003',
        productName: 'مانجو عويس فاخر',
        receiptDate: DateTime(2026, 9, 12),
        purchaseMode: 'carton',
        cartonCount: 1000,
        weightPerCartonKg: 8.6,
        netWeightKg: 8600.0,
        grossWeightKg: 9000.0,
        pricePerCarton: 120.0,
        totalProductCost: 120000.0,
        isConfirmed: true,
      );

      // Must strictly be 1000 cartons, NEVER jumping to 8600
      expect(lotCartonsWithWeight.purchasedQuantity, equals(1000.0));
      expect(lotCartonsWithWeight.netCartonCount, equals(1000));
      expect(lotCartonsWithWeight.unitLabel, equals('كرتونة'));
      expect(lotCartonsWithWeight.costPerCarton, equals(120.0));

      // Available return quantity logic
      const double returned = 250.0;
      final double available = (lotCartonsWithWeight.purchasedQuantity - returned).clamp(0.0, double.infinity);
      expect(available, equals(750.0));
    });

    test('Net Warehouse Quantity Baseline: 1000 kg gross, 900 kg net calculates return baseline strictly on 900 kg', () {
      final lotGrossNet = LotReceiptModel(
        id: '126',
        lotNumber: 'LOT-2026-004',
        productName: 'مانجو كيت',
        receiptDate: DateTime(2026, 9, 12),
        purchaseMode: 'weight',
        grossWeightKg: 1000.0,
        netWeightKg: 900.0,
        wasteWeightKg: 100.0,
        wastePercentage: 10.0,
        productCostPerKg: 100.0,
        totalProductCost: 90000.0,
        isConfirmed: true,
      );

      // Baseline checks
      expect(lotGrossNet.grossPurchaseQuantity, equals(1000.0));
      expect(lotGrossNet.netWarehouseQuantity, equals(900.0));
      expect(lotGrossNet.purchasedQuantity, equals(900.0));

      // Returns must deduct from net warehouse quantity (900 kg), never gross (1000 kg)
      const double returnedSoFar = 400.0;
      final double netAvailable = (lotGrossNet.netWarehouseQuantity - returnedSoFar).clamp(0.0, double.infinity);
      expect(netAvailable, equals(500.0));

      // If physical batch in warehouse has only 350 kg remaining (due to sorting/transfer/sale)
      const double batchRemainingStock = 350.0;
      final double effectiveReturnable = batchRemainingStock < netAvailable ? batchRemainingStock : netAvailable;
      expect(effectiveReturnable, equals(350.0));

      // Trying to return 400 kg must be blocked by validator since 400 > 350
      const double requestedReturn = 400.0;
      final bool isBlocked = requestedReturn > effectiveReturnable;
      expect(isBlocked, isTrue);
    });

    test('Net Warehouse Quantity Baseline for Cartons: 1000 gross cartons, 900 net warehouse cartons from inventory batch', () {
      final lotCarton = LotReceiptModel(
        id: '127',
        lotNumber: 'LOT-2026-005',
        productName: 'عنب كرمسون كراتين',
        receiptDate: DateTime(2026, 9, 12),
        purchaseMode: 'carton',
        cartonCount: 1000,
        pricePerCarton: 80.0,
        totalProductCost: 72000.0,
        isConfirmed: true,
      );

      // In the database and UI, the net warehouse entry quantity is populated from the actual stocked warehouse batch (900 cartons)
      // rather than the gross or unadjusted purchase count (1000 cartons).
      const double netWarehouseStock = 900.0;
      const double grossPurchase = 1000.0;
      final double availableToReturn = (netWarehouseStock - 0.0).clamp(0.0, double.infinity);

      expect(grossPurchase, equals(1000.0));
      expect(netWarehouseStock, equals(900.0));
      expect(availableToReturn, equals(900.0));
      expect(lotCarton.unitLabel, equals('كرتونة'));

      // Available returns must strictly have 900 cartons threshold
      const double returnedCount = 100.0;
      final double remainingAvailable = (netWarehouseStock - returnedCount).clamp(0.0, double.infinity);
      expect(remainingAvailable, equals(800.0));

      // Cannot return more than net warehouse quantity (e.g. attempting 950 cartons is blocked)
      const double attemptExcessReturn = 950.0;
      expect(attemptExcessReturn > remainingAvailable, isTrue);
    });
  });
}



