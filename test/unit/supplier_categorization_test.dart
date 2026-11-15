import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('SupplierModel Categorization Tests', () {
    test('Defaults to crop when supplierType is omitted', () {
      const supplier = SupplierModel(
        supplierCode: '0001',
        name: 'مورد تجريبي',
      );

      expect(supplier.supplierType, equals('crop'));
      expect(supplier.isCropSupplier, isTrue);
      expect(supplier.isPackagingSupplier, isFalse);
      expect(supplier.isSharedSupplier, isFalse);
      expect(supplier.supplierTypeLabel, equals('مورد محاصيل'));
    });

    test('Crop supplier properties', () {
      const supplier = SupplierModel(
        supplierCode: '0002',
        name: 'مورد محاصيل',
        supplierType: 'crop',
      );

      expect(supplier.supplierType, equals('crop'));
      expect(supplier.isCropSupplier, isTrue);
      expect(supplier.isPackagingSupplier, isFalse);
      expect(supplier.isSharedSupplier, isFalse);
      expect(supplier.supplierTypeLabel, equals('مورد محاصيل'));
    });

    test('Packaging supplier properties', () {
      const supplier = SupplierModel(
        supplierCode: '0003',
        name: 'مورد مواد تعبئة',
        supplierType: 'packaging',
      );

      expect(supplier.supplierType, equals('packaging'));
      expect(supplier.isCropSupplier, isFalse);
      expect(supplier.isPackagingSupplier, isTrue);
      expect(supplier.isSharedSupplier, isFalse);
      expect(supplier.supplierTypeLabel, equals('مواد تعبئة وتغليف'));
    });

    test('fromMap parses supplier_type correctly and falls back to shared', () {
      final cropMap = {
        'id': 'uuid-1',
        'code': '0001',
        'name': 'مورد 1',
        'supplier_type': 'crop',
      };
      expect(SupplierModel.fromMap(cropMap).supplierType, equals('crop'));

      final pkgMap = {
        'id': 'uuid-2',
        'code': '0002',
        'name': 'مورد 2',
        'supplier_type': 'packaging',
      };
      expect(SupplierModel.fromMap(pkgMap).supplierType, equals('packaging'));

      final sharedMap = {
        'id': 'uuid-3',
        'code': '0003',
        'name': 'مورد 3',
        'supplier_type': 'shared',
      };
      expect(SupplierModel.fromMap(sharedMap).supplierType, equals('shared'));

      final nullMap = {
        'id': 'uuid-4',
        'code': '0004',
        'name': 'مورد 4',
      };
      expect(SupplierModel.fromMap(nullMap).supplierType, equals('shared'));

      final invalidMap = {
        'id': 'uuid-5',
        'code': '0005',
        'name': 'مورد 5',
        'supplier_type': 'unknown_type',
      };
      expect(SupplierModel.fromMap(invalidMap).supplierType, equals('shared'));
    });

    test('toInsertMap includes supplier_type', () {
      const supplier = SupplierModel(
        id: 'uuid-1',
        supplierCode: '0001',
        name: 'مورد',
        supplierType: 'packaging',
      );

      final map = supplier.toInsertMap();
      expect(map['supplier_type'], equals('packaging'));
    });

    test('copyWith updates supplierType', () {
      const supplier = SupplierModel(
        supplierCode: '0001',
        name: 'مورد',
        supplierType: 'crop',
      );

      final updated = supplier.copyWith(supplierType: 'shared');
      expect(updated.supplierType, equals('shared'));
      expect(updated.supplierCode, equals('0001'));
    });
  });

  group('Contextual Filtering Logic', () {
    final sCrop = const SupplierModel(supplierCode: '01', name: 'Crop Only', supplierType: 'crop');
    final sPkg = const SupplierModel(supplierCode: '02', name: 'Packaging Only', supplierType: 'packaging');
    final sShared = const SupplierModel(supplierCode: '03', name: 'Shared Both', supplierType: 'shared');

    final allSuppliers = [sCrop, sPkg, sShared];

    test('Packaging Purchases page only accepts packaging & shared suppliers', () {
      final packagingSuppliers = allSuppliers.where((s) => s.isPackagingSupplier).toList();

      expect(packagingSuppliers.length, equals(2));
      expect(packagingSuppliers.contains(sPkg), isTrue);
      expect(packagingSuppliers.contains(sShared), isTrue);
      expect(packagingSuppliers.contains(sCrop), isFalse);
    });

    test('Crops Purchase page only accepts crop & shared suppliers', () {
      final cropSuppliers = allSuppliers.where((s) => s.isCropSupplier).toList();

      expect(cropSuppliers.length, equals(2));
      expect(cropSuppliers.contains(sCrop), isTrue);
      expect(cropSuppliers.contains(sShared), isTrue);
      expect(cropSuppliers.contains(sPkg), isFalse);
    });
  });
}
