import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('Supplier Account Statement - Packaging Material Suppliers Filter Tests', () {
    final sampleSuppliers = [
      const SupplierModel(
        id: '1',
        supplierCode: '50001',
        name: 'مزارع النيل للبطاطس',
        supplierType: 'crop',
      ),
      const SupplierModel(
        id: '2',
        supplierCode: '85001',
        name: 'محطة الفرز والتعبئة المركزية',
        supplierType: 'station',
      ),
      const SupplierModel(
        id: '3',
        supplierCode: '40001',
        name: 'مورد تخصيمات وتدريج',
        supplierType: 'deduction',
      ),
      const SupplierModel(
        id: '4',
        supplierCode: '60001',
        name: 'شركة النقل السريع',
        supplierType: 'transport',
      ),
      const SupplierModel(
        id: '5',
        supplierCode: '70001',
        name: 'مصنع الأهرام للكرتون ومواد التعبئة',
        supplierType: 'packaging',
      ),
      const SupplierModel(
        id: '6',
        supplierCode: '70002',
        name: 'مطبعة النور للاستيكر والتغليف',
        supplierType: 'sticker',
      ),
      const SupplierModel(
        id: '7',
        supplierCode: '701',
        name: 'مورد مواد تعبئه وتغليف - يوسف',
        supplierType: 'packaging',
      ),
      const SupplierModel(
        id: '8',
        supplierCode: '70010',
        name: 'شركة الصفا للشريط اللاصق ومواد التعبئة',
        supplierType: 'other',
        categories: ['تعبئة وتغليف'],
      ),
    ];

    List<SupplierModel> getFilteredSuppliers(
        List<SupplierModel> suppliers, String selectedCategoryFilter) {
      if (selectedCategoryFilter == 'all') return suppliers;
      return suppliers.where((s) {
        final code =
            int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final type = s.supplierType.toLowerCase().trim();
        if (selectedCategoryFilter == 'station') {
          return type == 'station' || (code >= 85000 && code <= 89999);
        } else if (selectedCategoryFilter == 'deduction') {
          return type == 'deduction' ||
              type == 'deductions' ||
              (code >= 40000 && code <= 49999);
        } else if (selectedCategoryFilter == 'packaging') {
          return type == 'packaging' ||
              type == 'sticker' ||
              type.contains('تعبئ') ||
              type.contains('pack') ||
              s.categories.any((c) =>
                  c.toLowerCase().contains('pack') || c.contains('تعبئ')) ||
              (code >= 70000 && code <= 74999) ||
              (code >= 700 && code <= 749);
        } else if (selectedCategoryFilter == 'transport') {
          return type == 'transport' || (code >= 60000 && code <= 69999);
        } else if (selectedCategoryFilter == 'crop') {
          return type == 'crop' || (code >= 50000 && code <= 59999);
        }
        return true;
      }).toList();
    }

    String resolveCategoryForSupplier(SupplierModel s) {
      final code =
          int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final type = s.supplierType.toLowerCase().trim();
      if (type == 'station' || (code >= 85000 && code <= 89999)) {
        return 'station';
      } else if (type == 'deduction' ||
          type == 'deductions' ||
          (code >= 40000 && code <= 49999)) {
        return 'deduction';
      } else if (type == 'packaging' ||
          type == 'sticker' ||
          type.contains('تعبئ') ||
          type.contains('pack') ||
          (code >= 70000 && code <= 74999) ||
          (code >= 700 && code <= 749)) {
        return 'packaging';
      } else if (type == 'transport' || (code >= 60000 && code <= 69999)) {
        return 'transport';
      } else if (type == 'crop' || (code >= 50000 && code <= 59999)) {
        return 'crop';
      }
      return 'all';
    }

    test('1. "جميع الموردين" returns all suppliers in list', () {
      final filtered = getFilteredSuppliers(sampleSuppliers, 'all');
      expect(filtered.length, equals(sampleSuppliers.length));
    });

    test('2. "موردي مواد التعبئة" filter returns only packaging, sticker, and 70xxx/70x suppliers', () {
      final filtered = getFilteredSuppliers(sampleSuppliers, 'packaging');
      expect(filtered.length, equals(4));
      expect(filtered.map((s) => s.id), containsAll(['5', '6', '7', '8']));
      expect(filtered.any((s) => s.id == '1'), isFalse); // crop excluded
      expect(filtered.any((s) => s.id == '2'), isFalse); // station excluded
      expect(filtered.any((s) => s.id == '3'), isFalse); // deduction excluded
      expect(filtered.any((s) => s.id == '4'), isFalse); // transport excluded
    });

    test('3. Auto-detect category maps packaging suppliers to "packaging"', () {
      final s5 = sampleSuppliers.firstWhere((s) => s.id == '5');
      final s6 = sampleSuppliers.firstWhere((s) => s.id == '6');
      final s7 = sampleSuppliers.firstWhere((s) => s.id == '7');
      expect(resolveCategoryForSupplier(s5), equals('packaging'));
      expect(resolveCategoryForSupplier(s6), equals('packaging'));
      expect(resolveCategoryForSupplier(s7), equals('packaging'));
    });

    test('4. Auto-detect category correctly identifies other supplier types', () {
      final s1 = sampleSuppliers.firstWhere((s) => s.id == '1');
      final s2 = sampleSuppliers.firstWhere((s) => s.id == '2');
      final s3 = sampleSuppliers.firstWhere((s) => s.id == '3');
      final s4 = sampleSuppliers.firstWhere((s) => s.id == '4');
      expect(resolveCategoryForSupplier(s1), equals('crop'));
      expect(resolveCategoryForSupplier(s2), equals('station'));
      expect(resolveCategoryForSupplier(s3), equals('deduction'));
      expect(resolveCategoryForSupplier(s4), equals('transport'));
    });

    test('5. Incompatible supplier clearance when switching to packaging category', () {
      // Suppose a crop supplier was selected
      final selectedSupplier = sampleSuppliers.firstWhere((s) => s.id == '1');
      const newFilter = 'packaging';
      final filtered = getFilteredSuppliers(sampleSuppliers, newFilter);

      // Check if selectedSupplier belongs to new filtered set
      final isCompatible = filtered.any((s) => s.id == selectedSupplier.id);
      expect(isCompatible, isFalse);

      // If incompatible, selection should be cleared
      final SupplierModel? resultingSelection = isCompatible ? selectedSupplier : null;
      expect(resultingSelection, isNull);
    });

    test('6. Compatible supplier is retained when switching to packaging category', () {
      // Suppose a packaging supplier was already selected under "all"
      final selectedSupplier = sampleSuppliers.firstWhere((s) => s.id == '5');
      const newFilter = 'packaging';
      final filtered = getFilteredSuppliers(sampleSuppliers, newFilter);

      final isCompatible = filtered.any((s) => s.id == selectedSupplier.id);
      expect(isCompatible, isTrue);

      final SupplierModel? resultingSelection = isCompatible ? selectedSupplier : null;
      expect(resultingSelection, equals(selectedSupplier));
    });
  });
}

