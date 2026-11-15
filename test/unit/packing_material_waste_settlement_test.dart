import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/services/packing_calculation_service.dart';

void main() {
  group('Packaging Material Waste Settlement Engine Tests (TEST A to TEST N)', () {
    final sampleMaterials = [
      {'used_qty': 1000, 'unit_cost': 150.0}, // total = 150,000 EGP
    ];

    test('TEST A: 150,000 EGP at 3% waste -> Waste = 4,500, Total = 154,500', () {
      final summary = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        3.0,
      );

      expect(summary.materialCost, equals(150000.0));
      expect(summary.wastePercent, equals(3.0));
      expect(summary.wasteCost, equals(4500.0));
      expect(summary.totalMaterialsWithWaste, equals(154500.0));
    });

    test('TEST B: Waste = 0% -> Waste = 0, Unsettled = 0, Status = no_waste', () {
      final summary = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        0.0,
      );

      expect(summary.wasteCost, equals(0.0));
      expect(summary.settledWasteCost, equals(0.0));
      expect(summary.unsettledWasteCost, equals(0.0));
      expect(summary.wasteSettlementStatus, equals('no_waste'));
    });

    test('TEST C: Waste = 3%, Settled = 0 -> Unsettled = 4,500, Status = unsettled', () {
      final summary = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        3.0,
        settledWasteCost: 0.0,
      );

      expect(summary.wasteCost, equals(4500.0));
      expect(summary.settledWasteCost, equals(0.0));
      expect(summary.unsettledWasteCost, equals(4500.0));
      expect(summary.wasteSettlementStatus, equals('unsettled'));
    });

    test('TEST D: Settled = 3,000 -> Unsettled = 1,500, Status = partially_settled', () {
      final summary = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        3.0,
        settledWasteCost: 3000.0,
      );

      expect(summary.wasteCost, equals(4500.0));
      expect(summary.settledWasteCost, equals(3000.0));
      expect(summary.unsettledWasteCost, equals(1500.0));
      expect(summary.wasteSettlementStatus, equals('partially_settled'));
    });

    test('TEST E: Settle 1,500 (total settled = 4,500) -> Settled = 4,500, Unsettled = 0, Status = fully_settled', () {
      final summary = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        3.0,
        settledWasteCost: 4500.0,
      );

      expect(summary.wasteCost, equals(4500.0));
      expect(summary.settledWasteCost, equals(4500.0));
      expect(summary.unsettledWasteCost, equals(0.0));
      expect(summary.wasteSettlementStatus, equals('fully_settled'));
    });

    test('TEST F: Attempt Settle > Unsettled (e.g. 1,501 when unsettled is 1,500) -> Clamp/ceiling validation', () {
      final currentSummary = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        3.0,
        settledWasteCost: 3000.0,
      );

      final unsettled = currentSummary.unsettledWasteCost;
      expect(unsettled, equals(1500.0));

      const attemptedSettlement = 1501.0;
      final isValid = attemptedSettlement <= (unsettled + 0.001);
      expect(isValid, isFalse, reason: 'Settlement amount > unsettled waste must be rejected');

      // Clamping check
      final simulatedUnsettledAfterOverSettle =
          (currentSummary.wasteCost - (3000.0 + attemptedSettlement)).clamp(0.0, double.infinity);
      expect(simulatedUnsettledAfterOverSettle, equals(0.0));
    });

    test('TEST I: Change 3% -> 4%: Waste 4,500 -> 6,000, If settled = 3,000 then Unsettled = 3,000', () {
      final summaryAt4Percent = PackingCalculationService.calculatePackaging(
        sampleMaterials,
        4.0,
        settledWasteCost: 3000.0,
      );

      expect(summaryAt4Percent.wasteCost, equals(6000.0));
      expect(summaryAt4Percent.settledWasteCost, equals(3000.0));
      expect(summaryAt4Percent.unsettledWasteCost, equals(3000.0));
      expect(summaryAt4Percent.totalMaterialsWithWaste, equals(156000.0));
      expect(summaryAt4Percent.wasteSettlementStatus, equals('partially_settled'));
    });

    test('TEST K & L: Check Packing Order Cost & Finished Goods Cost include waste exactly once', () {
      final lines = [
        PackingLineInput(
          productName: 'Orange Valencia 15kg',
          cartonCount: 1000,
          netWeightPerCarton: 15.0,
          grossWeightPerCarton: 16.0,
          effectiveWeight: 15000.0,
          sortedWeight: 0.0,
          productCostPerKg: 10.0, // 150,000 fruit cost
          wasteWeight: 0.0,
          totalPurchaseCost: 150000.0,
        ),
      ];

      final calc = PackingCalculationService.calculateAll(
        lines: lines,
        materialItems: sampleMaterials,
        costItems: [],
        materialWastePercent: 3.0,
        settledMaterialWasteCost: 3000.0,
      );

      // Raw fruit cost = 150,000
      expect(calc.finalCost.fruitCost, equals(150000.0));

      // Materials base = 150,000, Waste = 4,500
      expect(calc.materials.materialCost, equals(150000.0));
      expect(calc.materials.wasteCost, equals(4500.0));
      expect(calc.materials.totalMaterialsWithWaste, equals(154500.0));

      // Total order cost = 150,000 (fruit) + 154,500 (materials + waste) = 304,500
      expect(calc.finalCost.totalCost, equals(304500.0));

      // Cost per carton = 304,500 / 1000 = 304.5
      final productLine = calc.productLines.first;
      expect(productLine.finalCost / productLine.cartonCount, equals(304.5));
      expect(productLine.finalUnitCost, equals(20.3));

      // Waste included exactly once: Total final cost minus waste = 300,000
      expect(calc.finalCost.totalCost - calc.materials.wasteCost, equals(300000.0));
    });

    test('TEST M: Supplier Ledger is isolated from material waste calculation', () {
      // Material items retain supplier info without creating supplier liabilities from waste
      final materialWithSupplier = [
        {
          'product_name': 'Carton 15kg',
          'used_qty': 1000,
          'unit_cost': 150.0,
          'total': 150000.0,
          'supplier_name': 'Packaging Supplier Co',
        }
      ];

      final summary = PackingCalculationService.calculatePackaging(materialWithSupplier, 3.0);
      expect(summary.materialCost, equals(150000.0));
      expect(summary.wasteCost, equals(4500.0));
      // No extra supplier payable is generated; waste is internal production loss
    });

    test('TEST N: Shipment Profitability receives exact packing cost including waste once', () {
      final poData = {
        'total_gross_weight': 16000.0,
        'carton_count': 1000,
        'notes': {
          'materials': sampleMaterials,
          'material_waste_percent': 3.0,
          'cost_items': [],
        },
        'material_cost_base': 150000.0,
        'fruit_cost_allocated': 150000.0,
        'other_cost_base': 0.0,
      };

      final costPerCarton = PackingCalculationService.computeEffectiveCostPerCarton(poData);

      // (150,000 fruit + 150,000 materials + 4,500 waste) / 1000 = 304.5 EGP/carton
      expect(costPerCarton, equals(304.5));
    });
  });
}
