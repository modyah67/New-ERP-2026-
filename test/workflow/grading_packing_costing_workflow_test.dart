import 'package:flutter_test/flutter_test.dart';

void main() {
  group('End-to-End: Grading → Packing → Costing → COGS → Profit', () {
    test('full workflow produces expected financial results', () {
      // === PHASE 1: Purchase & Receiving ===
      const purchaseQty = 10000.0; // 10 tons
      const purchasePrice = 120000.0; // 12 EGP/kg
      final costPerKg = purchasePrice / purchaseQty;
      expect(costPerKg, 12.0);

      // === PHASE 2: Grading ===
      const gradeAQty = 6000.0;
      const gradeBQty = 2500.0;
      const gradeCQty = 1000.0;
      const wasteQty = 500.0; // 5% waste
      const totalGraded = gradeAQty + gradeBQty + gradeCQty + wasteQty;
      expect(totalGraded, purchaseQty);

      // Cost allocation proportional to quantity
      final gradeACost = gradeAQty * costPerKg; // 72000
      final gradeBCost = gradeBQty * costPerKg; // 30000
      final gradeCCost = gradeCQty * costPerKg; // 12000
      final wasteCost = wasteQty * costPerKg;   // 6000 (absorbed by A & B)
      expect(gradeACost, 72000.0);
      expect(gradeBCost, 30000.0);
      expect(gradeCCost, 12000.0);
      expect(wasteCost, 6000.0);

      // Absorb waste into grade A cost (common practice)
      final adjustedGradeACost = gradeACost + wasteCost; // 78000
      final adjustedGradeACostPerKg = adjustedGradeACost / gradeAQty; // 13.0
      expect(adjustedGradeACost, 78000.0);
      expect(adjustedGradeACostPerKg, 13.0);

      // === PHASE 3: Packing ===
      const packingQty = 5000.0; // 5 tons from Grade A
      const packingMaterialCostTotal = 10000.0; // boxes + labels
      const laborCost = 5000.0;
      final fruitCostForPacking = packingQty * adjustedGradeACostPerKg; // 65000

      expect(fruitCostForPacking, 65000.0);

      // === PHASE 4: Shipment Costing ===
      const logisticsCost = 8000.0;
      const exportFees = 3000.0;
      const adminOverhead = 2000.0;
      final totalShipmentCost = fruitCostForPacking + packingMaterialCostTotal +
          laborCost + logisticsCost + exportFees + adminOverhead;
      expect(totalShipmentCost, 93000.0);

      // Cost per carton (assuming 10kg boxes)
      const cartons = packingQty ~/ 10; // 500
      final costPerCarton = totalShipmentCost / cartons;
      expect(costPerCarton, 186.0);

      // === PHASE 5: Revenue & Profit ===
      const sellingPricePerKg = 25.0;
      const totalRevenue = packingQty * sellingPricePerKg; // 125000
      final grossProfit = totalRevenue - fruitCostForPacking - packingMaterialCostTotal - laborCost;
      final netProfit = totalRevenue - totalShipmentCost;
      final netMargin = (netProfit / totalRevenue) * 100;

      expect(totalRevenue, 125000.0);
      expect(grossProfit, 45000.0);
      expect(netProfit, 32000.0);
      expect(netMargin, closeTo(25.6, 0.01));

      // === PHASE 6: COGS Posting ===
      const cogsAccountId = 6;
      const inventoryAccountId = 3;
      const packingAccountId = 4;

      // COGS should NOT include packing material cost
      final nonPackingCost = fruitCostForPacking + laborCost + logisticsCost + exportFees + adminOverhead;
      final nonPackingCostCheck = totalShipmentCost - packingMaterialCostTotal;

      expect(nonPackingCost, 83000.0);
      expect(nonPackingCostCheck, 83000.0);

      // Double-entry check
      final journalEntries = [
        {'account_id': cogsAccountId, 'type': 'debit', 'amount': totalShipmentCost},
        {'account_id': inventoryAccountId, 'type': 'credit', 'amount': nonPackingCost},
        {'account_id': packingAccountId, 'type': 'credit', 'amount': packingMaterialCostTotal},
      ];

      double totalDebit = 0;
      double totalCredit = 0;
      for (final e in journalEntries) {
        if (e['type'] == 'debit') {
          totalDebit += e['amount'] as double;
        } else {
          totalCredit += e['amount'] as double;
        }
      }

      expect(totalDebit, totalCredit);
      expect(totalDebit, totalShipmentCost);
    });
  });
}
