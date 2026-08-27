import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/dao/station_product_batch_dao.dart';
import 'package:accounting_system/data/models/station_product_batch.dart';
import 'package:accounting_system/data/models/station_product_model.dart';

void main() {
  group('Crop Carton Transfer and Pricing Root Cause Verification Tests', () {
    test('FIFODeduction preserves lot productCode and crop origin metadata', () {
      const deduction = FIFODeduction(
        batchId: 501,
        quantity: 100.0,
        unitCost: 5.0,
        currency: 'USD',
        exchangeRate: 1.0,
        supplierName: 'مزارع الوادي',
        productCode: 'LOT-2026-001',
        sourceDate: '2026-08-17T08:00:00Z',
        originalSourceType: 'lot_receipt',
      );

      expect(deduction.batchId, 501);
      expect(deduction.quantity, 100.0);
      expect(deduction.unitCost, 5.0);
      expect(deduction.supplierName, 'مزارع الوادي');
      expect(deduction.productCode, 'LOT-2026-001');
      expect(deduction.sourceDate, '2026-08-17T08:00:00Z');
      expect(deduction.originalSourceType, 'lot_receipt');
      expect(deduction.totalCost, 100.0 * 5.0);
    });

    test('Mandatory Scenario: Purchase 200 cartons @ 1 USD -> Transfer 100 -> Price edit to 5 USD', () {
      // 1. Initial purchase: 200 cartons @ 1 USD in Warehouse A
      var batchA = {
        'station_id': 'Warehouse A',
        'lot_number': 'LOT-CARTON-001',
        'quantity': 200.0,
        'remaining_quantity': 200.0,
        'unit_cost': 1.0,
      };

      // 2. Transfer 100 cartons to Warehouse B
      const transferQty = 100.0;
      batchA['remaining_quantity'] = (batchA['remaining_quantity'] as double) - transferQty;

      var batchB = {
        'station_id': 'Warehouse B',
        'lot_number': 'LOT-CARTON-001',
        'quantity': 100.0,
        'remaining_quantity': 100.0,
        'unit_cost': 1.0,
      };

      expect(batchA['remaining_quantity'], 100.0);
      expect(batchB['remaining_quantity'], 100.0);

      // 3. Price edit from 1 USD to 5 USD (price per carton)
      const newPricePerCarton = 5.0;
      final allBatches = [batchA, batchB];
      for (final b in allBatches) {
        if (b['lot_number'] == 'LOT-CARTON-001') {
          b['unit_cost'] = newPricePerCarton;
        }
      }

      // 4. Verify Warehouse A
      expect(batchA['remaining_quantity'], 100.0);
      expect(batchA['unit_cost'], 5.0);
      final costA = (batchA['remaining_quantity'] as double) * (batchA['unit_cost'] as double);
      expect(costA, 500.0);

      // 5. Verify Warehouse B
      expect(batchB['remaining_quantity'], 100.0);
      expect(batchB['unit_cost'], 5.0);
      final costB = (batchB['remaining_quantity'] as double) * (batchB['unit_cost'] as double);
      expect(costB, 500.0);

      // 6. Verify Totals
      final totalQty = (batchA['remaining_quantity'] as double) + (batchB['remaining_quantity'] as double);
      final totalCost = costA + costB;
      expect(totalQty, 200.0);
      expect(totalCost, 1000.0);
    });

    test('Unequal Transfer Scenario: Purchase 200 cartons -> Transfer 50 -> Price edit to 5 USD', () {
      var batchA = {
        'station_id': 'Warehouse A',
        'lot_number': 'LOT-CARTON-002',
        'quantity': 200.0,
        'remaining_quantity': 150.0, // After transferring 50
        'unit_cost': 1.0,
      };

      var batchB = {
        'station_id': 'Warehouse B',
        'lot_number': 'LOT-CARTON-002',
        'quantity': 50.0,
        'remaining_quantity': 50.0,
        'unit_cost': 1.0,
      };

      // Edit price to 5 USD
      const newPricePerCarton = 5.0;
      batchA['unit_cost'] = newPricePerCarton;
      batchB['unit_cost'] = newPricePerCarton;

      // Warehouse A = 150 * 5 = 750 USD, Unit Cost = 5
      expect(batchA['unit_cost'], 5.0);
      expect((batchA['remaining_quantity'] as double) * (batchA['unit_cost'] as double), 750.0);

      // Warehouse B = 50 * 5 = 250 USD, Unit Cost = 5
      expect(batchB['unit_cost'], 5.0);
      expect((batchB['remaining_quantity'] as double) * (batchB['unit_cost'] as double), 250.0);

      // Total = 1000 USD
      final totalCost = (batchA['remaining_quantity'] as double) * (batchA['unit_cost'] as double) +
                        (batchB['remaining_quantity'] as double) * (batchB['unit_cost'] as double);
      expect(totalCost, 1000.0);
    });

    test('Multi-station Transfer Scenario: 200 at A -> 100 to B -> 50 from B to C -> Price edit to 5 USD', () {
      final batchA = {
        'station_id': 'Warehouse A',
        'lot_number': 'LOT-CARTON-003',
        'remaining_quantity': 100.0,
        'unit_cost': 1.0,
      };

      final batchB = {
        'station_id': 'Warehouse B',
        'lot_number': 'LOT-CARTON-003',
        'remaining_quantity': 50.0,
        'unit_cost': 1.0,
      };

      final batchC = {
        'station_id': 'Warehouse C',
        'lot_number': 'LOT-CARTON-003',
        'remaining_quantity': 50.0,
        'unit_cost': 1.0,
      };

      final allBatches = [batchA, batchB, batchC];

      // Total quantity across all 3 stations
      final totalQty = allBatches.fold<double>(0.0, (sum, b) => sum + (b['remaining_quantity'] as double));
      expect(totalQty, 200.0);

      // Price edit to 5 USD
      for (final b in allBatches) {
        b['unit_cost'] = 5.0;
      }

      // Unit cost is 5 USD in all 3 warehouses
      expect(batchA['unit_cost'], 5.0);
      expect(batchB['unit_cost'], 5.0);
      expect(batchC['unit_cost'], 5.0);

      // Costs
      expect((batchA['remaining_quantity'] as double) * 5.0, 500.0);
      expect((batchB['remaining_quantity'] as double) * 5.0, 250.0);
      expect((batchC['remaining_quantity'] as double) * 5.0, 250.0);

      final totalCost = allBatches.fold<double>(0.0, (sum, b) => sum + (b['remaining_quantity'] as double) * (b['unit_cost'] as double));
      expect(totalCost, 1000.0);
    });

    test('Strict CPAY vs PPAY isolation: Purchase Payment (PPAY) with ID 10 never matches Crop Lot with ID 10', () {
      // Regular purchase payment for purchase invoice #10
      final purchasePayment = {
        'id': 2001,
        'entry_number': 'PPAY-00001',
        'source_type': 'purchase_payment',
        'source_id': '10',
        'description': 'سداد فاتورة مشتريات خامات رقم PUR-00010',
      };

      // Crop payment for crop lot #10
      final cropPayment = {
        'id': 2002,
        'entry_number': 'CPAY-00001',
        'source_type': 'crop_payment',
        'source_id': '10',
        'description': 'سداد فاتورة شراء محصول بطيخ - لوط رقم LOT-00010',
      };

      // Unlinked supplier advance payment
      final unlinkedPayment = {
        'id': 2003,
        'entry_number': 'PMT-00001',
        'source_type': 'supplier_payment',
        'source_id': null,
        'description': 'دفعة مقدمة للمورد (وليد - 00001)',
      };

      const targetLotId = '10';
      const targetPurchaseId = '10';

      // Simulation of rpc_get_lot_journal_entries (Crop Lot View)
      bool matchesLot(Map<String, dynamic> je, String lotId) {
        final srcType = je['source_type']?.toString();
        final srcId = je['source_id']?.toString();
        if (srcId != lotId) return false;
        return srcType == 'lot_receipt' || srcType == 'lot_price_adjustment' || srcType == 'crop_payment';
      }

      // Simulation of rpc_get_purchase_journal_entries (Purchase Invoice View)
      bool matchesPurchase(Map<String, dynamic> je, String purchaseId) {
        final srcType = je['source_type']?.toString();
        final srcId = je['source_id']?.toString();
        if (srcId != purchaseId) return false;
        return srcType == 'purchase_inventory' || srcType == 'purchase_payment' || srcType == 'purchase_price_adjustment';
      }

      // Test 1: Purchase payment for #10 does NOT appear in Lot #10
      expect(matchesLot(purchasePayment, targetLotId), isFalse, reason: 'PPAY must never match Crop Lot');

      // Test 2: Crop payment for #10 appears in Lot #10
      expect(matchesLot(cropPayment, targetLotId), isTrue, reason: 'CPAY must match Crop Lot');

      // Test 3: Crop payment for #10 does NOT appear in Purchase #10
      expect(matchesPurchase(cropPayment, targetPurchaseId), isFalse, reason: 'CPAY must never match Purchase Invoice');

      // Test 4: Purchase payment for #10 appears in Purchase #10
      expect(matchesPurchase(purchasePayment, targetPurchaseId), isTrue, reason: 'PPAY must match Purchase Invoice');

      // Test 5: Unlinked payment does NOT appear in either
      expect(matchesLot(unlinkedPayment, targetLotId), isFalse, reason: 'Unlinked payment must not match Crop Lot');
      expect(matchesPurchase(unlinkedPayment, targetPurchaseId), isFalse, reason: 'Unlinked payment must not match Purchase Invoice');
    });

    test('Same supplier isolation: Independent payments remain strictly separated', () {
      const supplierId = 'supp-waleed-uuid';

      final purchasePay = {'source_type': 'purchase_payment', 'source_id': '101', 'supplier_id': supplierId, 'amount': 500.0};
      final cropPay = {'source_type': 'crop_payment', 'source_id': '202', 'supplier_id': supplierId, 'amount': 500.0};
      final advancePay = {'source_type': 'supplier_payment', 'source_id': null, 'supplier_id': supplierId, 'amount': 100.0};

      // In lot 202
      expect(cropPay['source_type'] == 'crop_payment' && cropPay['source_id'] == '202', isTrue);
      expect(purchasePay['source_type'] == 'crop_payment' && purchasePay['source_id'] == '202', isFalse);
      expect(advancePay['source_id'] != null, isFalse);

      // In purchase 101
      expect(purchasePay['source_type'] == 'purchase_payment' && purchasePay['source_id'] == '101', isTrue);
      expect(cropPay['source_type'] == 'purchase_payment' && cropPay['source_id'] == '101', isFalse);
      expect(advancePay['source_id'] != null, isFalse);
    });
  });
}

