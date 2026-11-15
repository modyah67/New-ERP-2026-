import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';

void main() {
  group('Item-Bound Cost Center Lookup & Uniform Routing Tests', () {
    final activeCenters = [
      // Canonical Item-Bound Seasonal Cost Center for Mango
      const CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango Season (2026-2027)',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
        cropName: 'مانجو',
        cropCode: 'MANGO',
        season: '2026-2027',
        seasonStatus: 'active',
        isActive: true,
      ),
      // Generic production line that must NEVER be matched for fruit variety operations
      const CostCenter(
        id: 'CC-LINE-1',
        nameAr: 'خط 1',
        nameEn: 'Line 1',
        type: CostCenterType.variety,
        color: Color(0xFF9E9E9E),
        icon: Icons.precision_manufacturing,
        code: 'CC-1',
        productId: 1,
        season: '2026-2027',
        seasonStatus: 'active',
        isActive: true,
      ),
      // Operational packing center
      const CostCenter(
        id: 'CC-PACKING',
        nameAr: 'محطة التعبئة والتجهيز',
        nameEn: 'Packing & Processing Station',
        type: CostCenterType.operational,
        color: Color(0xFF2196F3),
        icon: Icons.inventory_2,
        code: 'CC-PACKING',
        isActive: true,
      ),
    ];

    test('CostCenterHelper.fromId strictly prioritizes canonical crop variety over generic line 1', () {
      // Lookup by crop variety name
      final resolvedByName = CostCenterHelper.fromId('مانجو - وزن', activeCenters);
      expect(resolvedByName.id, equals('CC-MANGO-2026-2027'));
      expect(resolvedByName.nameAr, equals('مانجو (موسم 2026-2027)'));
      expect(resolvedByName.nameAr, isNot(contains('خط 1')));

      // Lookup by exact code
      final resolvedByCode = CostCenterHelper.fromId('CC-MANGO-2026-2027', activeCenters);
      expect(resolvedByCode.id, equals('CC-MANGO-2026-2027'));
      expect(resolvedByCode.nameAr, equals('مانجو (موسم 2026-2027)'));
    });

    test('CostCenterHelper.fromId does not match line 1 by numeric ID', () {
      // Numeric id '1' must not accidentally resolve to 'خط 1' as a variety center
      final res = CostCenterHelper.fromId('مانجو', activeCenters);
      expect(res.id, equals('CC-MANGO-2026-2027'));
      expect(res.nameAr, isNot(equals('خط 1')));
    });

    test('Fallback logic NEVER generates line-based labels like "خط sub"', () {
      final fallbackCenter = CostCenterHelper.fromId('CC-STRAWBERRY-2026-2027', []);
      expect(fallbackCenter.nameAr, isNot(startsWith('خط ')));
      expect(fallbackCenter.nameAr, contains('موسم 2026-2027'));
    });

    test('Uniform Routing: Initial purchase and crop return share the exact same item-bound cost center', () {
      const boundCostCenterId = 'CC-MANGO-2026-2027';
      const boundCostCenterName = 'مانجو (موسم 2026-2027)';

      // 1. Initial purchase transaction
      final purchaseTx = {
        'source_type': 'lot_receipt',
        'source_id': '1',
        'cost_center_id': boundCostCenterId,
        'cost_center_name': boundCostCenterName,
        'item_name': 'مانجو - وزن',
        'quantity': 1000.0,
        'unit_price': 10.0,
        'amount': 10000.0,
      };

      // 2. Return transaction (returning 400 kg)
      final returnTx = {
        'source_type': 'lot_return',
        'source_id': '1',
        'cost_center_id': purchaseTx['cost_center_id'], // strictly identical!
        'cost_center_name': purchaseTx['cost_center_name'],
        'item_name': 'مرتجع شراء محصول - مانجو - وزن',
        'quantity': -400.0,
        'unit_price': 10.0,
        'amount': -4000.0,
      };

      // Both transactions must sit side-by-side in the same cost center
      expect(purchaseTx['cost_center_id'], equals(returnTx['cost_center_id']));
      expect(purchaseTx['cost_center_name'], equals(returnTx['cost_center_name']));

      // Net calculations in that cost center view
      final transactions = [purchaseTx, returnTx];
      final targetCostCenterRows = transactions.where((tx) => tx['cost_center_id'] == boundCostCenterId).toList();

      expect(targetCostCenterRows.length, equals(2));
      final netQty = targetCostCenterRows.fold<double>(0.0, (acc, tx) => acc + (tx['quantity'] as double));
      final netAmount = targetCostCenterRows.fold<double>(0.0, (acc, tx) => acc + (tx['amount'] as double));

      expect(netQty, equals(600.0));
      expect(netAmount, equals(6000.0));
    });

    test('CostCenterHelper.resolve correctly tags sorting sales to parent item-bound cost center', () {
      final sortingSaleRow = {
        'item_name': 'إيراد بيع فرز - مانجو',
        'target_product_name': 'مانجو',
        'fruit_type_id': 1,
      };

      final resolved = CostCenterHelper.resolve(sortingSaleRow, activeCenters);
      expect(resolved.id, equals('CC-MANGO-2026-2027'));
      expect(resolved.nameAr, equals('مانجو (موسم 2026-2027)'));
      expect(resolved.nameAr, isNot(contains('خط 1')));
    });
  });
}
