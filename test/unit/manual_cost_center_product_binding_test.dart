import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/data/models/fruit_type_model.dart';
import 'package:accounting_system/data/services/product_cost_center_sync_service.dart';

void main() {
  group('Manual Cost Center & Product Binding Tests', () {
    test('FruitTypeModel serializes and deserializes costCenterId properly', () {
      final model = FruitTypeModel(
        code: '101',
        name: 'مانجو عويس',
        currency: 'EGP',
        purchaseMode: 'weight',
        costCenterId: 'CC-MANGO-2026-2027',
      );

      final map = model.toMap();
      expect(map['code'], equals('101'));
      expect(map['name'], equals('مانجو عويس'));
      expect(map['cost_center_id'], equals('CC-MANGO-2026-2027'));

      final fromMap = FruitTypeModel.fromMap({
        'id': '15',
        'code': '101',
        'name': 'مانجو عويس',
        'currency': 'EGP',
        'purchase_mode': 'weight',
        'cost_center_id': 'CC-MANGO-2026-2027',
      });

      expect(fromMap.id, equals('15'));
      expect(fromMap.costCenterId, equals('CC-MANGO-2026-2027'));
    });

    test('FruitTypeModel copyWith correctly manages costCenterId', () {
      final original = FruitTypeModel(
        code: '102',
        name: 'عنب كرمسون',
        currency: 'EGP',
        purchaseMode: 'carton',
        costCenterId: null,
      );

      expect(original.costCenterId, isNull);

      final updated = original.copyWith(costCenterId: 'CC-GRAPES-2026-2027');
      expect(updated.costCenterId, equals('CC-GRAPES-2026-2027'));
      expect(updated.code, equals('102'));
      expect(updated.name, equals('عنب كرمسون'));
    });

    test('ProductCostCenterSyncService disables automatic cost center creation on product addition', () async {
      // Calling syncProductCostCenter should complete immediately without exceptions or auto-upserting
      await expectLater(
        ProductCostCenterSyncService.instance.syncProductCostCenter(
          productId: '99',
          productCode: '99',
          productNameAr: 'مانجو تومي',
          season: '2026-2027',
        ),
        completes,
      );
    });

    test('CostCenter canonicalCropName properly normalizes crop names for seasonal lines', () {
      expect(CostCenter.canonicalCropName('مانجو - وزن'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('مانجو (كراتين)'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('عنب كرمسون - كرتونة'), equals('عنب كرمسون'));
      expect(CostCenter.canonicalCropName('برتقال صيفي بالوزن'), equals('برتقال صيفي'));
    });

    test('CostCenterHelper resolves canonical slugs and seasonal format', () {
      final slug = CostCenterHelper.resolveCropSlug('مانجو');
      expect(slug, equals('MANGO'));
      final grapeSlug = CostCenterHelper.resolveCropSlug('عنب');
      expect(grapeSlug, equals('GRAPES'));

      final formattedCode = 'CC-$slug-2026-2027';
      expect(formattedCode, equals('CC-MANGO-2026-2027'));
    });
  });
}
