import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/services/cost_category_service.dart';
import 'package:accounting_system/features/packing/widgets/cost_item_category_dropdown.dart';

void main() {
  final sampleCatalog = <Map<String, dynamic>>[
    {'id': 1, 'name': 'مواد التعبئة', 'supplier_type': 'packaging', 'scope': 'packing'},
    {'id': 2, 'name': 'شراء خامات', 'supplier_type': 'crop', 'scope': 'packing'},
    {'id': 3, 'name': 'أخرى', 'supplier_type': 'general', 'scope': 'all'},
    {'id': 10, 'name': 'تشغيل', 'supplier_type': 'station', 'scope': 'packing'},
    {'id': 11, 'name': 'تبريد', 'supplier_type': 'general', 'scope': 'packing'}, // legacy DB default
    {'id': 12, 'name': 'خدمة محطة إضافية', 'supplier_type': 'station', 'scope': 'packing'},
    {'id': 13, 'name': 'عمالة', 'supplier_type': null, 'scope': 'packing'},
    {'id': 14, 'name': 'اعادة تدوير', 'supplier_type': null, 'scope': 'packing'},
    {'id': 20, 'name': 'رسوم فحص', 'supplier_type': 'deduction', 'scope': 'all'},
    {'id': 21, 'name': 'تخصيم عربي', 'supplier_type': 'general', 'scope': 'all'}, // legacy DB default
    {'id': 22, 'name': 'تحليل خاص', 'supplier_type': 'deduction', 'scope': 'all'},
    {'id': 23, 'name': 'دفاتر حجر زراعي', 'supplier_type': null, 'scope': 'all'},
    {'id': 24, 'name': 'دفاتر حجر سلامه غذاء', 'supplier_type': null, 'scope': 'all'},
    {'id': 30, 'name': 'مصاريف إدارية وعمومية', 'supplier_type': 'admin', 'scope': 'all'},
    {'id': 31, 'name': 'رسوم واشتراكات وتراخيص', 'supplier_type': 'admin', 'scope': 'all'},
    {'id': 40, 'name': 'لوجستيك ونقل', 'supplier_type': 'transport', 'scope': 'all'},
    {'id': 50, 'name': 'مصاريف مهندسين', 'supplier_type': 'engineer', 'scope': 'packing'},
  ];

  group('CostCategoryService supplier-type filtering unit tests', () {
    test('resolveCategorySupplierType respects explicit types and legacy defaults', () {
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 1, 'name': 'مواد التعبئة', 'supplier_type': 'packaging'}),
        equals('general'),
      );
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 10, 'name': 'تشغيل', 'supplier_type': 'station'}),
        equals('station'),
      );
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 11, 'name': 'تبريد', 'supplier_type': 'general'}),
        equals('station'),
      );
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 21, 'name': 'تخصيم عربي', 'supplier_type': null}),
        equals('deduction'),
      );
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 30, 'name': 'مصاريف إدارية وعمومية', 'supplier_type': 'admin'}),
        equals('admin'),
      );
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 40, 'name': 'لوجستيك ونقل', 'supplier_type': 'logistics'}),
        equals('transport'),
      );
      expect(
        CostCategoryService.resolveCategorySupplierType({'id': 50, 'name': 'مصاريف مهندسين', 'supplier_type': 'engineer'}),
        equals('engineer'),
      );
    });

    test('filterCategoriesBySupplierType strictly isolates station categories', () {
      final stationCats = CostCategoryService.filterCategoriesBySupplierType(
        sampleCatalog,
        supplierType: 'station',
      );
      expect(stationCats.keys, equals([10, 11, 12, 13, 14]));
      expect(stationCats.values, containsAll(['تشغيل', 'تبريد', 'خدمة محطة إضافية', 'عمالة', 'اعادة تدوير']));
      expect(stationCats.containsKey(1), isFalse);
      expect(stationCats.containsKey(20), isFalse);
      expect(stationCats.containsKey(23), isFalse);
      expect(stationCats.containsKey(30), isFalse);
      expect(stationCats.containsKey(40), isFalse);
    });

    test('filterCategoriesBySupplierType strictly isolates deduction categories', () {
      final deductionCats = CostCategoryService.filterCategoriesBySupplierType(
        sampleCatalog,
        supplierType: 'deduction',
      );
      expect(deductionCats.keys, equals([20, 21, 22, 23, 24]));
      expect(deductionCats.values, containsAll(['رسوم فحص', 'تخصيم عربي', 'تحليل خاص', 'دفاتر حجر زراعي', 'دفاتر حجر سلامه غذاء']));
      expect(deductionCats.containsKey(10), isFalse);
      expect(deductionCats.containsKey(13), isFalse);
      expect(deductionCats.containsKey(1), isFalse);
      expect(deductionCats.containsKey(30), isFalse);
    });

    test('filterCategoriesBySupplierType strictly isolates general categories', () {
      final generalCats = CostCategoryService.filterCategoriesBySupplierType(
        sampleCatalog,
        supplierType: 'general',
      );
      expect(generalCats.keys, equals([1, 2, 3]));
      expect(generalCats.values, containsAll(['مواد التعبئة', 'شراء خامات', 'أخرى']));
      expect(generalCats.containsKey(10), isFalse);
      expect(generalCats.containsKey(20), isFalse);
      expect(generalCats.containsKey(30), isFalse);
      expect(generalCats.containsKey(40), isFalse);
      expect(generalCats.containsKey(50), isFalse);
    });

    test('filterCategoriesBySupplierType strictly isolates admin categories', () {
      final adminCats = CostCategoryService.filterCategoriesBySupplierType(
        sampleCatalog,
        supplierType: 'admin',
      );
      expect(adminCats.keys, equals([30, 31]));
    });

    test('resolveSelectedCategoryIdForSupplierType resets invalid ID when switching types', () {
      final stationCats = CostCategoryService.filterCategoriesBySupplierType(
        sampleCatalog,
        supplierType: 'station',
      );
      expect(
        CostCategoryService.resolveSelectedCategoryIdForSupplierType(
          currentCategoryId: 1, // general id
          filteredCategories: stationCats,
          supplierType: 'station',
        ),
        equals(10),
      );
      expect(
        CostCategoryService.resolveSelectedCategoryIdForSupplierType(
          currentCategoryId: 12, // already station id
          filteredCategories: stationCats,
          supplierType: 'station',
        ),
        equals(12),
      );
      expect(
        CostCategoryService.resolveSelectedCategoryIdForSupplierType(
          currentCategoryId: 10,
          filteredCategories: const {},
          supplierType: 'deduction',
        ),
        isNull,
      );
      expect(
        CostCategoryService.resolveSelectedCategoryIdForSupplierType(
          currentCategoryId: 10,
          filteredCategories: stationCats,
          supplierType: 'transport',
        ),
        isNull,
      );
    });

    test('isAutoGeneratedItemName detects category labels while preserving custom user text', () {
      final names = sampleCatalog.map((c) => c['name'] as String);
      expect(CostCategoryService.isAutoGeneratedItemName('', names), isTrue);
      expect(CostCategoryService.isAutoGeneratedItemName('تشغيل', names), isTrue);
      expect(CostCategoryService.isAutoGeneratedItemName('مصاريف إدارية', names), isTrue);
      expect(
        CostCategoryService.isAutoGeneratedItemName('كرتون تصدير برتقال خاص خط 2', names),
        isFalse,
      );
    });
  });

  group('CostItemCategoryDropdown widget tests', () {
    testWidgets('re-filters dropdown options immediately when switching supplier type chips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _CategoryFilterTestHost(catalog: sampleCatalog),
          ),
        ),
      );

      // Initially on general tab
      expect(find.text('مواد التعبئة'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      // General items visible; station / deduction items excluded
      expect(find.text('مواد التعبئة').hitTestable(), findsWidgets);
      expect(find.text('شراء خامات'), findsWidgets);
      expect(find.text('تشغيل'), findsNothing);
      expect(find.text('رسوم فحص'), findsNothing);

      // Close dropdown
      await tester.tap(find.text('شراء خامات').last);
      await tester.pumpAndSettle();

      // Switch to station chip
      await tester.tap(find.text('مورد محطة'));
      await tester.pumpAndSettle();

      // Selected item immediately switches to first station category
      expect(find.text('تشغيل'), findsOneWidget);
      expect(find.text('شراء خامات'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      expect(find.text('تشغيل').hitTestable(), findsWidgets);
      expect(find.text('تبريد'), findsWidgets);
      expect(find.text('مواد التعبئة'), findsNothing);
      expect(find.text('رسوم فحص'), findsNothing);
      expect(find.text('مصاريف إدارية وعمومية'), findsNothing);

      // Select second station option
      await tester.tap(find.text('تبريد').last);
      await tester.pumpAndSettle();

      // Switch to deduction chip
      await tester.tap(find.text('مورد تخصيمات'));
      await tester.pumpAndSettle();

      expect(find.text('رسوم فحص'), findsOneWidget);
      expect(find.text('تبريد'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      expect(find.text('رسوم فحص').hitTestable(), findsWidgets);
      expect(find.text('تحليل خاص'), findsWidgets);
      expect(find.text('تشغيل'), findsNothing);
      expect(find.text('مواد التعبئة'), findsNothing);
    });

    testWidgets('handles out-of-range selectedCategoryId and empty filtered categories without assertion errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CostItemCategoryDropdown(
                keyPrefix: 'test_empty',
                supplierType: 'station',
                filteredCategories: const {},
                selectedCategoryId: 999,
                decoration: const InputDecoration(labelText: 'تصنيف البند'),
                isDark: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('لا توجد تصنيفات مسجلة لهذا النوع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _CategoryFilterTestHost extends StatefulWidget {
  final List<Map<String, dynamic>> catalog;

  const _CategoryFilterTestHost({required this.catalog});

  @override
  State<_CategoryFilterTestHost> createState() => _CategoryFilterTestHostState();
}

class _CategoryFilterTestHostState extends State<_CategoryFilterTestHost> {
  String _supplierType = 'general';
  late int? _selectedCategoryId =
      CostCategoryService.resolveSelectedCategoryIdForSupplierType(
    currentCategoryId: null,
    filteredCategories: CostCategoryService.filterCategoriesBySupplierType(
      widget.catalog,
      supplierType: _supplierType,
    ),
    supplierType: _supplierType,
  );

  void _selectSupplierType(String type) {
    setState(() {
      _supplierType = type;
      final nextFiltered = CostCategoryService.filterCategoriesBySupplierType(
        widget.catalog,
        supplierType: type,
      );
      _selectedCategoryId =
          CostCategoryService.resolveSelectedCategoryIdForSupplierType(
        currentCategoryId: _selectedCategoryId,
        filteredCategories: nextFiltered,
        supplierType: type,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = CostCategoryService.filterCategoriesBySupplierType(
      widget.catalog,
      supplierType: _supplierType,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('عام / خامات'),
                selected: _supplierType == 'general',
                onSelected: (v) {
                  if (v) _selectSupplierType('general');
                },
              ),
              ChoiceChip(
                label: const Text('مورد محطة'),
                selected: _supplierType == 'station',
                onSelected: (v) {
                  if (v) _selectSupplierType('station');
                },
              ),
              ChoiceChip(
                label: const Text('مورد تخصيمات'),
                selected: _supplierType == 'deduction',
                onSelected: (v) {
                  if (v) _selectSupplierType('deduction');
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          CostItemCategoryDropdown(
            keyPrefix: 'add_cost_cat',
            supplierType: _supplierType,
            filteredCategories: filtered,
            selectedCategoryId: _selectedCategoryId,
            decoration: const InputDecoration(labelText: 'تصنيف البند'),
            isDark: false,
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
        ],
      ),
    );
  }
}

