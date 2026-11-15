// test/unit/account_cost_settlement_pdf_service_test.dart
// Unit tests for AccountCostSettlementPdfService (Landscape A4 Cost Settlement PDF)

import 'package:flutter/material.dart' show TextEditingController;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/features/accounts/services/account_cost_settlement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '.';
    });
  });

  group('AccountCostSettlementPdfService Tests', () {
    final sampleAccount = AccountModel(
      id: 'acc-31331',
      code: '31331',
      name: 'مصاريف إدارية وعمومية',
      type: 'expense',
      balance: 24800.0,
      isActive: true,
    );

    test('resolveRowsFromUi converts UI maps and controllers correctly', () {
      final items = [
        {
          'id': 101,
          'order_number': '119',
          'product_name': 'مانجو - وزن',
          'name': 'مصاريف إدارية',
          'category': 'admin',
          'expected_amount': 1000.0,
          'actual_amount': 1100.0,
          'actual_quantity': 1.0,
          'actual_unit_price': 1100.0,
          'actual_date_time': '2026-11-06T17:05:00Z',
          'detailed_notes': 'فاتورة مصاريف إدارية معتمدة',
          'is_locked': true,
        },
        {
          'id': 102,
          'order_number': '120',
          'product_name': 'عنب - علب',
          'name': 'مصاريف إدارية',
          'category': 'admin',
          'expected_amount': 500.0,
          'actual_amount': null,
          'is_locked': false,
        },
      ];

      final actualCtrls = {
        101: TextEditingController(text: '1,100.00'),
        102: TextEditingController(text: ''),
      };
      final qtyCtrls = {
        101: TextEditingController(text: '1'),
        102: TextEditingController(text: '1'),
      };
      final upCtrls = {
        101: TextEditingController(text: '1,100.00'),
        102: TextEditingController(text: ''),
      };
      final notesCtrls = {
        101: TextEditingController(text: 'فاتورة مصاريف إدارية معتمدة'),
        102: TextEditingController(text: ''),
      };
      final dateTimes = {
        101: DateTime(2026, 11, 6, 17, 5),
        102: DateTime(2026, 11, 7, 10, 0),
      };

      final resolved = AccountCostSettlementPdfService.resolveRowsFromUi(
        items: items,
        actualControllers: actualCtrls,
        qtyControllers: qtyCtrls,
        unitPriceControllers: upCtrls,
        notesControllers: notesCtrls,
        itemDateTimes: dateTimes,
        isItemLockedFn: (it) => it['is_locked'] == true,
        getEstimatedCostFn: (it) => (it['expected_amount'] as num).toDouble(),
      );

      expect(resolved.length, 2);

      // Item 1: Locked & Settled with variance
      expect(resolved[0].orderNumber, '119');
      expect(resolved[0].productName, 'مانجو - وزن');
      expect(resolved[0].estimatedCost, 1000.0);
      expect(resolved[0].actualAmount, 1100.0);
      expect(resolved[0].actualQuantity, 1.0);
      expect(resolved[0].actualUnitPrice, 1100.0);
      expect(resolved[0].varianceAmount, 100.0);
      expect(resolved[0].variancePct, 10.0);
      expect(resolved[0].isLocked, true);
      expect(resolved[0].statusText, 'معتمد ومقفل');

      // Item 2: Pending settlement
      expect(resolved[1].orderNumber, '120');
      expect(resolved[1].estimatedCost, 500.0);
      expect(resolved[1].actualAmount, 0.0);
      expect(resolved[1].isLocked, false);
      expect(resolved[1].statusText, 'بانتظار التسوية');
    });

    test('resolveRowsFromUi handles multi-unit price breakdowns and enriches notes', () {
      final items = [
        {
          'id': 201,
          'order_number': '125',
          'product_name': 'رمان - صناديق',
          'name': 'مصاريف إدارية',
          'category': 'admin',
          'expected_amount': 900.0,
          'actual_amount': 1100.0,
          'actual_quantity': 3.0,
          'actual_unit_price': 366.67,
          'detailed_notes': 'مصاريف نقل وتخليص',
          'is_locked': false,
        },
      ];

      final actualCtrls = {201: TextEditingController(text: '1,100.00')};
      final qtyCtrls = {201: TextEditingController(text: '3')};
      final upCtrls = {201: TextEditingController(text: '366.67')};
      final notesCtrls = {201: TextEditingController(text: 'مصاريف نقل وتخليص')};
      final dateTimes = {201: DateTime(2026, 11, 9, 12, 0)};
      final breakdowns = {
        201: [300.0, 350.0, 450.0],
      };

      final resolved = AccountCostSettlementPdfService.resolveRowsFromUi(
        items: items,
        actualControllers: actualCtrls,
        qtyControllers: qtyCtrls,
        unitPriceControllers: upCtrls,
        notesControllers: notesCtrls,
        itemDateTimes: dateTimes,
        unitPriceBreakdowns: breakdowns,
        isItemLockedFn: (_) => false,
        getEstimatedCostFn: (_) => 900.0,
      );

      expect(resolved.length, 1);
      expect(resolved[0].actualQuantity, 3.0);
      expect(resolved[0].actualAmount, 1100.0);
      expect(resolved[0].notes, contains('300 + 350 + 450'));
    });

    test('generateCostSettlementPdf compiles valid PDF bytes without error', () async {
      final rows = [
        CostSettlementPdfRow(
          index: 1,
          id: 1,
          orderNumber: '119',
          productName: 'مانجو - كرتون',
          itemName: 'مصاريف إدارية',
          category: 'admin',
          estimatedCost: 1000.0,
          actualQuantity: 1.0,
          actualUnitPrice: 1100.0,
          actualAmount: 1100.0,
          varianceAmount: 100.0,
          variancePct: 10.0,
          invoiceDateTime: DateTime(2026, 11, 6, 17, 5),
          notes: 'فاتورة سداد إداري رقم 98',
          isLocked: true,
          statusText: 'معتمد ومقفل',
        ),
        CostSettlementPdfRow(
          index: 2,
          id: 2,
          orderNumber: '120',
          productName: 'عنب - شيتات',
          itemName: 'مصاريف إدارية',
          category: 'admin',
          estimatedCost: 800.0,
          actualQuantity: 1.0,
          actualUnitPrice: 750.0,
          actualAmount: 750.0,
          varianceAmount: -50.0,
          variancePct: -6.25,
          invoiceDateTime: DateTime(2026, 11, 6, 18, 0),
          notes: 'وفر في الفاتورة الفعلية',
          isLocked: false,
          statusText: 'بانتظار الاعتماد',
        ),
      ];

      final bytes = await AccountCostSettlementPdfService.generateCostSettlementPdf(
        account: sampleAccount,
        rows: rows,
        currency: 'EGP',
        companyName: 'مزارع فروتي فارمز',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      // PDF magic header %PDF-
      expect(bytes[0], 0x25); // %
      expect(bytes[1], 0x50); // P
      expect(bytes[2], 0x44); // D
      expect(bytes[3], 0x46); // F
    });
  });
}

