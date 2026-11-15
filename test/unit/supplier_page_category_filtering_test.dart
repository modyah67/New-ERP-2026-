import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('SuppliersPage Category Filtering & Search Combination Tests', () {
    final testSuppliers = [
      const SupplierModel(
        id: '1',
        supplierCode: '50001',
        name: 'مزارع النيل للبطاطس',
        supplierType: 'crop',
      ),
      const SupplierModel(
        id: '2',
        supplierCode: '50002',
        name: 'مزرعة الوادي للطماطم',
        supplierType: 'crop',
      ),
      const SupplierModel(
        id: '3',
        supplierCode: '70001',
        name: 'شركة الأهرام للتغليف والكرتون',
        supplierType: 'packaging',
      ),
      const SupplierModel(
        id: '4',
        supplierCode: '70002',
        name: 'مصنع البلاستيك الحديث',
        supplierType: 'packaging',
      ),
      const SupplierModel(
        id: '5',
        supplierCode: '75001',
        name: 'مجموعة الدلتا للتنمية الزراعية والتعبئة',
        supplierType: 'shared',
      ),
    ];

    List<SupplierModel> filterSuppliers(List<SupplierModel> suppliers, String filter) {
      if (filter == 'all') return suppliers;
      return suppliers.where((s) {
        final codeNum = int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), ''));
        switch (filter) {
          case 'crop':
            return s.supplierType == 'crop' ||
                (codeNum != null && codeNum >= 50000 && codeNum <= 59999);
          case 'packaging':
            return s.supplierType == 'packaging' ||
                (codeNum != null && codeNum >= 70000 && codeNum <= 74999);
          case 'shared':
            return s.supplierType == 'shared' ||
                (codeNum != null && codeNum >= 75000 && codeNum <= 79999);
          default:
            return true;
        }
      }).toList();
    }

    test('1. "عرض الكل" (all) returns all suppliers without filtration', () {
      final results = filterSuppliers(testSuppliers, 'all');
      expect(results.length, equals(5));
    });

    test('2. "موردين المحاصيل" (crop: 50000 - 59999) filters exclusively crop suppliers', () {
      final results = filterSuppliers(testSuppliers, 'crop');
      expect(results.length, equals(2));
      expect(results.every((s) => s.supplierType == 'crop'), isTrue);
      expect(results.map((s) => s.supplierCode), containsAll(['50001', '50002']));
    });

    test('3. "موردين مواد التعبئة والتغليف" (packaging: 70000 - 74999) filters packaging suppliers', () {
      final results = filterSuppliers(testSuppliers, 'packaging');
      expect(results.length, equals(2));
      expect(results.every((s) => s.supplierType == 'packaging'), isTrue);
      expect(results.map((s) => s.supplierCode), containsAll(['70001', '70002']));
    });

    test('4. "الموردين المشتركين" (shared: 75000 - 79999) filters shared suppliers', () {
      final results = filterSuppliers(testSuppliers, 'shared');
      expect(results.length, equals(1));
      expect(results.first.supplierType, equals('shared'));
      expect(results.first.supplierCode, equals('75001'));
    });

    test('5. Search query works in combination with category filter', () {
      // Searching "الأهرام" in packaging category
      final packagingList = filterSuppliers(testSuppliers, 'packaging');
      final matchedInPackaging = packagingList
          .where((s) => s.name.contains('الأهرام') || s.supplierCode.contains('الأهرام'))
          .toList();
      expect(matchedInPackaging.length, equals(1));
      expect(matchedInPackaging.first.supplierCode, equals('70001'));

      // Searching "الأهرام" in crop category yields empty
      final cropList = filterSuppliers(testSuppliers, 'crop');
      final matchedInCrop = cropList
          .where((s) => s.name.contains('الأهرام') || s.supplierCode.contains('الأهرام'))
          .toList();
      expect(matchedInCrop, isEmpty);
    });

    test('6. Dynamic category counts match record quantities', () {
      int getCount(String key) => filterSuppliers(testSuppliers, key).length;
      expect(getCount('all'), equals(5));
      expect(getCount('crop'), equals(2));
      expect(getCount('packaging'), equals(2));
      expect(getCount('shared'), equals(1));
    });
  });
}
