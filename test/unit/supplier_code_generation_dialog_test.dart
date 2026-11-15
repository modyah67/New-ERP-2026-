import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('Supplier Code Generation & Validation Guard Tests', () {
    test('Category-to-Range Mapping matches ERP architectural specification', () {
      final cropRange = SupplierModel.getCategoryRange('crop');
      expect(cropRange.minCode, 50000);
      expect(cropRange.maxCode, 59999);

      final packagingRange = SupplierModel.getCategoryRange('packaging');
      expect(packagingRange.minCode, 70000);
      expect(packagingRange.maxCode, 74999);

      final sharedRange = SupplierModel.getCategoryRange('shared');
      expect(sharedRange.minCode, 75000);
      expect(sharedRange.maxCode, 79999);

      final transportRange = SupplierModel.getCategoryRange('transport');
      expect(transportRange.minCode, 60000);
      expect(transportRange.maxCode, 69999);

      final stationRange = SupplierModel.getCategoryRange('station');
      expect(stationRange.minCode, 80000);
      expect(stationRange.maxCode, 89999);

      final shippingRange = SupplierModel.getCategoryRange('shipping');
      expect(shippingRange.minCode, 90000);
      expect(shippingRange.maxCode, 99999);
    });

    test('Strict Form Validation Guard prevents cross-category code mismatches (image_079fb4.png bug)', () {
      // Bug reproduction: Packaging selected with 50000 code must be blocked!
      final packagingMismatchError = SupplierModel.validateSupplierCode('50000', 'packaging');
      expect(packagingMismatchError, isNotNull);
      expect(packagingMismatchError, contains('70000'));
      expect(packagingMismatchError, contains('74999'));

      // Valid packaging codes must pass
      expect(SupplierModel.validateSupplierCode('70000', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('71800', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('74999', 'packaging'), isNull);

      // Shared supplier validation
      expect(SupplierModel.validateSupplierCode('50000', 'shared'), isNotNull);
      expect(SupplierModel.validateSupplierCode('70000', 'shared'), isNotNull);
      expect(SupplierModel.validateSupplierCode('75000', 'shared'), isNull);
      expect(SupplierModel.validateSupplierCode('79999', 'shared'), isNull);

      // Crop supplier validation
      expect(SupplierModel.validateSupplierCode('70000', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('50000', 'crop'), isNull);
      expect(SupplierModel.validateSupplierCode('51900', 'crop'), isNull);

      // Transport, Station, and Shipping validation
      expect(SupplierModel.validateSupplierCode('60000', 'transport'), isNull);
      expect(SupplierModel.validateSupplierCode('50000', 'transport'), isNotNull);

      expect(SupplierModel.validateSupplierCode('80000', 'station'), isNull);
      expect(SupplierModel.validateSupplierCode('50000', 'station'), isNotNull);

      expect(SupplierModel.validateSupplierCode('90000', 'shipping'), isNull);
      expect(SupplierModel.validateSupplierCode('50000', 'shipping'), isNotNull);
    });

    test('Initial baseline code for dropdown change matches category minCode immediately', () {
      for (final type in ['crop', 'packaging', 'shared', 'transport', 'station', 'shipping']) {
        final range = SupplierModel.getCategoryRange(type);
        final initialCode = range.minCode.toString();
        expect(SupplierModel.validateSupplierCode(initialCode, type), isNull);
      }
    });
  });
}
