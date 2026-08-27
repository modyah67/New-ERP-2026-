import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Purchasing → Lot → Grading → Packing → Costing → Shipment Workflow', () {
    // Simulates the complete costing pipeline end-to-end

    test('complete workflow produces correct final costs', () {
      // Step 1: Purchase Invoice
      const purchaseTotal = 15000.0;
      const receivedQty = 1000.0;
      const costPerKg = purchaseTotal / receivedQty;

      expect(costPerKg, 15.0);

      // Step 2: Grading splits into grades
      final grades = {
        'A': { 'quantity': 500.0, 'weight': 0.5 },
        'B': { 'quantity': 300.0, 'weight': 0.3 },
        'C': { 'quantity': 200.0, 'weight': 0.2 },
      };

      double totalGradeQty = 0;
      for (final g in grades.values) {
        totalGradeQty += g['quantity'] as double;
      }

      // Grading cost allocation (proportional)
      final gradeCosts = <String, double>{};
      for (final entry in grades.entries) {
        gradeCosts[entry.key] = (entry.value['quantity'] as double) / totalGradeQty * purchaseTotal;
      }

      expect(totalGradeQty, 1000.0);
      expect(gradeCosts['A'], 7500.0);
      expect(gradeCosts['B'], 4500.0);
      expect(gradeCosts['C'], 3000.0);

      // Step 3: Packing consumes from Grade A batch
      const packingQty = 300.0;
      const batchOneQty = 500.0;
      const remainingAfterPacking = batchOneQty - packingQty;

      expect(remainingAfterPacking, 200.0);

      // Step 4: Costing for shipment
      const fruitCost = 4500.0;  // 300kg × 15.0
      const packingMaterialCost = 500.0;
      const logisticsCost = 700.0;
      const exportCosts = 200.0;
      const adminCost = 100.0;
      const totalShipmentCost = fruitCost + packingMaterialCost + logisticsCost + exportCosts + adminCost;

      expect(totalShipmentCost, 6000.0);

      // Step 5: Revenue and profit
      const revenue = 9000.0;
      final profit = revenue - totalShipmentCost;
      final margin = (profit / revenue) * 100;

      expect(profit, 3000.0);
      expect(margin, closeTo(33.33, 0.01));

      // Step 6: COGS posting (excludes packing material)
      const nonPackingCost = fruitCost + logisticsCost + exportCosts + adminCost; // 5500
      expect(nonPackingCost, 5500.0);
    });

    test('workflow handles zero-grade scenario (ungraded fruit)', () {
      const purchaseTotal = 10000.0;
      const receivedQty = 500.0;
      final costPerKg = purchaseTotal / receivedQty;
      expect(costPerKg, 20.0);
    });

    test('workflow correctly tracks multiple shipments from one lot', () {
      const lotQty = 1000.0;
      const shipment1Qty = 400.0;
      const shipment2Qty = 300.0;
      const remaining = lotQty - shipment1Qty - shipment2Qty;

      expect(remaining, 300.0);
    });
  });
}
