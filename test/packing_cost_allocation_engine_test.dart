import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_line_model.dart';
import 'package:accounting_system/data/services/packing_cost_allocation_engine.dart';

void main() {
  group('PackingCostAllocationEngine', () {
    test('allocates shared packaging by net weight and specific to target line', () {
      final lines = [
        const PackingOrderLineModel(
          packingOrderId: 1,
          productName: 'برتقال',
          cartonCount: 100,
          netWeightPerCarton: 10,
          totalNetWeight: 1000,
          quantity: 1100,
          rawMaterialCost: 5000,
        ),
        const PackingOrderLineModel(
          packingOrderId: 1,
          productName: 'يوسفي',
          cartonCount: 50,
          netWeightPerCarton: 10,
          totalNetWeight: 500,
          quantity: 550,
          rawMaterialCost: 2000,
        ),
      ];

      final result = PackingCostAllocationEngine.instance.allocate(
        lines: lines,
        materials: [
          {'used_qty': 100, 'unit_cost': 2, 'total': 200, 'apply_to': 'all'},
          {'used_qty': 10, 'unit_cost': 5, 'total': 50, 'apply_to': 'line:0'},
        ],
        costItems: [
          {
            'total_egp': 300,
            'allocation_method': 'BY_NET_WEIGHT',
          },
          {
            'total_egp': 100,
            'allocation_method': 'MANUAL',
            'target_line_index': 1,
          },
        ],
      );

      expect(result.lines.length, 2);

      // Shared pkg 200 → 2/3 and 1/3 by net weight
      expect(result.lines[0].allocatedSharedPackaging, closeTo(133.33, 0.02));
      expect(result.lines[1].allocatedSharedPackaging, closeTo(66.67, 0.02));

      // Specific only on line 0
      expect(result.lines[0].specificPackagingCost, 50);
      expect(result.lines[1].specificPackagingCost, 0);

      // Overhead 300 by net weight + 100 manual on line 1
      expect(result.lines[0].allocatedCostItems, closeTo(200, 0.02));
      expect(result.lines[1].allocatedCostItems, closeTo(200, 0.02));

      // Final = raw + specific + shared + overhead
      expect(
        result.lines[0].finalCost,
        closeTo(5000 + 50 + 133.33 + 200, 0.05),
      );
      expect(
        result.totalFinalCost,
        closeTo(
          result.lines[0].finalCost + result.lines[1].finalCost,
          0.02,
        ),
      );
    });

    test('equal allocation splits evenly', () {
      final lines = [
        const PackingOrderLineModel(
          packingOrderId: 1,
          productName: 'A',
          cartonCount: 10,
          totalNetWeight: 100,
          rawMaterialCost: 1000,
        ),
        const PackingOrderLineModel(
          packingOrderId: 1,
          productName: 'B',
          cartonCount: 90,
          totalNetWeight: 900,
          rawMaterialCost: 9000,
        ),
      ];

      final result = PackingCostAllocationEngine.instance.allocate(
        lines: lines,
        materials: const [],
        costItems: [
          {'total_egp': 100, 'allocation_method': 'EQUAL'},
        ],
      );

      expect(result.lines[0].allocatedCostItems, 50);
      expect(result.lines[1].allocatedCostItems, 50);
    });
  });
}
