import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('Supplier Category Ranges & Strict Code Segregation Tests', () {
    test('Category range boundaries are strictly segregated and non-overlapping', () {
      const crop = SupplierModel.cropRange;
      const transport = SupplierModel.transportRange;
      const packaging = SupplierModel.packagingRange;
      const shared = SupplierModel.sharedRange;
      const station = SupplierModel.stationRange;
      const shipping = SupplierModel.shippingRange;

      // Assert ranges
      expect(crop.minCode, 50000);
      expect(crop.maxCode, 59999);

      expect(transport.minCode, 60000);
      expect(transport.maxCode, 69999);

      expect(packaging.minCode, 70000);
      expect(packaging.maxCode, 74999);

      expect(shared.minCode, 75000);
      expect(shared.maxCode, 79999);

      expect(station.minCode, 85000);
      expect(station.maxCode, 89999);

      expect(shipping.minCode, 90000);
      expect(shipping.maxCode, 99999);

      // Verify no overlap between Packaging (70000..74999) and Shared (75000..79999)
      expect(packaging.maxCode < shared.minCode, isTrue);
      expect(crop.maxCode < transport.minCode, isTrue);
      expect(transport.maxCode < packaging.minCode, isTrue);
      expect(shared.maxCode < station.minCode, isTrue);
      expect(station.maxCode < shipping.minCode, isTrue);
    });

    test('Strict Validation - Crop Suppliers (50000 to 59999)', () {
      expect(SupplierModel.validateSupplierCode('50000', 'crop'), isNull);
      expect(SupplierModel.validateSupplierCode('50018', 'crop'), isNull);
      expect(SupplierModel.validateSupplierCode('55000', 'crop'), isNull);
      expect(SupplierModel.validateSupplierCode('59999', 'crop'), isNull);

      expect(SupplierModel.validateSupplierCode('49999', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('60000', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('70000', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('75000', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('abc', 'crop'), isNotNull);
    });

    test('Strict Validation - Packaging Suppliers (70000 to 74999)', () {
      expect(SupplierModel.validateSupplierCode('70000', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('71700', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('73000', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('74999', 'packaging'), isNull);

      expect(SupplierModel.validateSupplierCode('69999', 'packaging'), isNotNull);
      expect(SupplierModel.validateSupplierCode('75000', 'packaging'), isNotNull); // 75000 belongs to shared!
      expect(SupplierModel.validateSupplierCode('79999', 'packaging'), isNotNull);
      expect(SupplierModel.validateSupplierCode('50000', 'packaging'), isNotNull);
    });

    test('Strict Validation - Shared Suppliers (75000 to 79999)', () {
      expect(SupplierModel.validateSupplierCode('75000', 'shared'), isNull);
      expect(SupplierModel.validateSupplierCode('75001', 'shared'), isNull);
      expect(SupplierModel.validateSupplierCode('77500', 'shared'), isNull);
      expect(SupplierModel.validateSupplierCode('79999', 'shared'), isNull);

      // Must reject anything below 75000 (e.g. packaging 70000..74999 or crop 50000..59999)
      expect(SupplierModel.validateSupplierCode('74999', 'shared'), isNotNull);
      expect(SupplierModel.validateSupplierCode('70000', 'shared'), isNotNull);
      expect(SupplierModel.validateSupplierCode('50000', 'shared'), isNotNull);
      expect(SupplierModel.validateSupplierCode('80000', 'shared'), isNotNull);
    });

    test('SupplierModel flags for Shared Suppliers reflect dual capability', () {
      const sharedSupplier = SupplierModel(
        supplierCode: '75000',
        name: 'مورد مشترك - العالمية للتوريدات',
        supplierType: 'shared',
      );

      expect(sharedSupplier.isSharedSupplier, isTrue);
      expect(sharedSupplier.isCropSupplier, isTrue);
      expect(sharedSupplier.isPackagingSupplier, isTrue);
      expect(sharedSupplier.supplierTypeLabel, 'مورد مشترك');
    });

    test('SupplierModel flags for pure Crop and Packaging suppliers', () {
      const cropSupplier = SupplierModel(
        supplierCode: '50001',
        name: 'مورد محاصيل - الحاج ياسر',
        supplierType: 'crop',
      );
      expect(cropSupplier.isCropSupplier, isTrue);
      expect(cropSupplier.isPackagingSupplier, isFalse);
      expect(cropSupplier.isSharedSupplier, isFalse);

      const packSupplier = SupplierModel(
        supplierCode: '70001',
        name: 'مورد مواد تعبئة - يوسف',
        supplierType: 'packaging',
      );
      expect(packSupplier.isCropSupplier, isFalse);
      expect(packSupplier.isPackagingSupplier, isTrue);
      expect(packSupplier.isSharedSupplier, isFalse);
    });

    test('SupplierModel.validateSupplierName enforces mandatory name and length', () {
      expect(SupplierModel.validateSupplierName(null), 'اسم المورد مطلوب');
      expect(SupplierModel.validateSupplierName(''), 'اسم المورد مطلوب');
      expect(SupplierModel.validateSupplierName('   '), 'اسم المورد مطلوب');
      expect(SupplierModel.validateSupplierName('أ'), contains('قصير جداً'));
      expect(SupplierModel.validateSupplierName('وليد'), isNull);
      expect(SupplierModel.validateSupplierName('شركة الفاخر لتجارة الحاصلات'), isNull);
    });
  });
}
