import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/widgets/order_range_filter_field.dart';
import 'package:accounting_system/data/models/supplier_expected_cost_item_model.dart';

void main() {
  group('OrderRangeFilterHelper', () {
    test('normalizeDigits converts Arabic-Indic and Eastern digits to ASCII', () {
      expect(OrderRangeFilterHelper.normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(OrderRangeFilterHelper.normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(OrderRangeFilterHelper.normalizeDigits('PO-١٠٥ / #۴۲'), 'PO-105 / #42');
      expect(OrderRangeFilterHelper.normalizeDigits(''), '');
    });

    test('parseFilterBound handles empty, ASCII, Arabic, prefixed, and invalid strings', () {
      expect(OrderRangeFilterHelper.parseFilterBound(null), isNull);
      expect(OrderRangeFilterHelper.parseFilterBound(''), isNull);
      expect(OrderRangeFilterHelper.parseFilterBound('   '), isNull);
      expect(OrderRangeFilterHelper.parseFilterBound('abc'), isNull);
      expect(OrderRangeFilterHelper.parseFilterBound('0'), 0);
      expect(OrderRangeFilterHelper.parseFilterBound('105'), 105);
      expect(OrderRangeFilterHelper.parseFilterBound(' ٢٤٠ '), 240);
      expect(OrderRangeFilterHelper.parseFilterBound('#42'), 42);
      expect(OrderRangeFilterHelper.parseFilterBound('PO-2026-088'), 88);
    });

    test('extractNumericOrderId extracts orderNumber digits and falls back to packingOrderId', () {
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: '12', packingOrderId: 99),
        12,
      );
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: '#12', packingOrderId: 99),
        12,
      );
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: 'PO-105', packingOrderId: 99),
        105,
      );
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: 'أمر #١٥', packingOrderId: 99),
        15,
      );
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: '-', packingOrderId: 77),
        77,
      );
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: '', packingOrderId: 77),
        77,
      );
      expect(
        OrderRangeFilterHelper.extractNumericOrderId(orderNumber: null, packingOrderId: null),
        isNull,
      );
    });

    test('matchesOrderRange honors unbounded, inclusive closed, open-ended, and fallback matching', () {
      // Unbounded
      expect(
        OrderRangeFilterHelper.matchesOrderRange(orderNumber: '5', packingOrderId: 5),
        isTrue,
      );

      // Inclusive closed bounds [10, 20]
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '10',
          packingOrderId: 100,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isTrue,
      );
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '15',
          packingOrderId: 100,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isTrue,
      );
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '20',
          packingOrderId: 100,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isTrue,
      );
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '9',
          packingOrderId: 15,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isFalse,
      );
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '21',
          packingOrderId: 15,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isFalse,
      );

      // Open lower bound (>= 15)
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: 'PO-15',
          fromOrderId: 15,
        ),
        isTrue,
      );
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: 'PO-14',
          fromOrderId: 15,
        ),
        isFalse,
      );

      // Open upper bound (<= 15)
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '١٥',
          toOrderId: 15,
        ),
        isTrue,
      );
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '١٦',
          toOrderId: 15,
        ),
        isFalse,
      );

      // Missing orderNumber digits falls back to packingOrderId
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '-',
          packingOrderId: 12,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isTrue,
      );

      // Unresolvable ID returns false when range is active
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '-',
          packingOrderId: null,
          fromOrderId: 10,
          toOrderId: 20,
        ),
        isFalse,
      );

      // Inverted bounds reject all items
      expect(
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: '15',
          fromOrderId: 20,
          toOrderId: 10,
        ),
        isFalse,
      );
    });

    test('formatRangeLabel produces expected Arabic labels', () {
      expect(OrderRangeFilterHelper.formatRangeLabel(), isNull);
      expect(
        OrderRangeFilterHelper.formatRangeLabel(fromOrderId: 15, toOrderId: 15),
        'شحنة / أمر #15',
      );
      expect(
        OrderRangeFilterHelper.formatRangeLabel(fromOrderId: 10, toOrderId: 25),
        'من شحنة / أمر #10 إلى #25',
      );
      expect(
        OrderRangeFilterHelper.formatRangeLabel(fromOrderId: 10),
        'من شحنة / أمر #10',
      );
      expect(
        OrderRangeFilterHelper.formatRangeLabel(toOrderId: 25),
        'حتى شحنة / أمر #25',
      );
    });

    test('filters SupplierExpectedCostItemModel and Map rows cleanly with exact KPI totals', () {
      final supplierItems = [
        const SupplierExpectedCostItemModel(
          costItemId: 1,
          packingOrderId: 1,
          orderNumber: '1',
          orderStatus: 'completed',
          itemName: 'تبريد 1',
          category: 'packing',
          reportCategoryName: 'تبريد',
          costStatus: 'expected',
          expectedAmount: 1000,
        ),
        const SupplierExpectedCostItemModel(
          costItemId: 2,
          packingOrderId: 2,
          orderNumber: '2',
          orderStatus: 'completed',
          itemName: 'تشغيل محطة 2',
          category: 'packing',
          reportCategoryName: 'محطة',
          costStatus: 'actual',
          expectedAmount: 2000,
          actualAmount: 2300,
        ),
        const SupplierExpectedCostItemModel(
          costItemId: 3,
          packingOrderId: 3,
          orderNumber: '3',
          orderStatus: 'completed',
          itemName: 'تخصيم 3',
          category: 'deductions',
          reportCategoryName: 'تخصيم',
          costStatus: 'actual',
          expectedAmount: 1500,
          actualAmount: 1400,
        ),
        const SupplierExpectedCostItemModel(
          costItemId: 4,
          packingOrderId: 5,
          orderNumber: '5',
          orderStatus: 'completed',
          itemName: 'محطة 5',
          category: 'packing',
          reportCategoryName: 'محطة',
          costStatus: 'expected',
          expectedAmount: 5000,
        ),
      ];

      final filteredSupplier = supplierItems
          .where((item) => OrderRangeFilterHelper.matchesOrderRange(
                orderNumber: item.orderNumber,
                packingOrderId: item.packingOrderId,
                fromOrderId: 2,
                toOrderId: 4,
              ))
          .toList();

      expect(filteredSupplier.map((e) => e.costItemId).toList(), [2, 3]);
      final totalEst = filteredSupplier.fold<double>(0.0, (s, e) => s + e.expectedAmount);
      final totalAct = filteredSupplier.fold<double>(
        0.0,
        (s, e) => s + (e.actualAmount ?? e.expectedAmount),
      );
      expect(totalEst, 3500.0);
      expect(totalAct, 3700.0);
      expect(totalAct - totalEst, 200.0);

      final adminRows = [
        {'id': 11, 'packing_order_id': 1, 'order_number': '1'},
        {'id': 12, 'packing_order_id': 3, 'order_number': '3'},
        {'id': 13, 'packing_order_id': 6, 'order_number': '6'},
      ];
      final filteredAdmin = adminRows
          .where((r) => OrderRangeFilterHelper.matchesOrderRange(
                orderNumber: r['order_number']?.toString(),
                packingOrderId: (r['packing_order_id'] as num?)?.toInt(),
                fromOrderId: 2,
                toOrderId: 5,
              ))
          .toList();
      expect(filteredAdmin.map((r) => r['id']).toList(), [12]);
    });
  });

  group('OrderRangeFilterBar widget', () {
    testWidgets('updates bounds, triggers onChanged/onApplyQuery, and clears cleanly', (tester) async {
      final fromCtrl = TextEditingController();
      final toCtrl = TextEditingController();
      var changedCount = 0;
      var applyCount = 0;
      var clearCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: Center(
                    child: OrderRangeFilterBar(
                      fromController: fromCtrl,
                      toController: toCtrl,
                      onChanged: () => setState(() => changedCount++),
                      onApplyQuery: () => applyCount++,
                      onClear: () => setState(() => clearCount++),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('من شحنة/أمر'), findsOneWidget);
      expect(find.text('إلى شحنة/أمر'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10');
      await tester.pump();
      await tester.enterText(fields.at(1), '25');
      await tester.pump();

      expect(fromCtrl.text, '10');
      expect(toCtrl.text, '25');
      expect(changedCount, 2);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.filter_alt_rounded));
      await tester.pump();
      expect(applyCount, 1);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(fromCtrl.text, isEmpty);
      expect(toCtrl.text, isEmpty);
      expect(clearCount, 1);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      fromCtrl.dispose();
      toCtrl.dispose();
    });
  });
}

