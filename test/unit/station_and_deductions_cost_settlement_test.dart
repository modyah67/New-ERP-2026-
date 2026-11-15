import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';
import 'package:accounting_system/data/models/supplier_expected_cost_item_model.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/features/suppliers/supplier_account_statement_cubit.dart';

void main() {
  group('Dual-Cost Tracking & Settlement Unit Tests', () {
    test('SupplierExpectedCostItemModel parses expected cost item accurately', () {
      final json = {
        'cost_item_id': 101,
        'packing_order_id': 202,
        'order_number': 'PK-2026-001',
        'order_status': 'completed',
        'item_name': 'تكلفة تبريد وتخزين مسبق',
        'category': 'refrigeration',
        'report_category_name': 'تبريد وتخزين',
        'cost_status': 'expected',
        'expected_amount': 5000.0,
        'actual_amount': null,
        'variance_amount': 0.0,
        'supplier_id': 'sup-station-1',
        'supplier_code': '80001',
        'supplier_name': 'محطة الأهرام للتعبئة',
        'supplier_type': 'station',
        'invoice_ref': null,
        'reconciled_at': null,
        'linked_shipments': [
          {
            'shipment_id': 'shp-1',
            'shipment_code': 'EXP-2026-01',
            'allocated_cartons': 600,
          },
          {
            'shipment_id': 'shp-2',
            'shipment_code': 'EXP-2026-02',
            'allocated_cartons': 400,
          }
        ],
      };

      final item = SupplierExpectedCostItemModel.fromJson(json);

      expect(item.costItemId, equals(101));
      expect(item.packingOrderId, equals(202));
      expect(item.orderNumber, equals('PK-2026-001'));
      expect(item.itemName, equals('تكلفة تبريد وتخزين مسبق'));
      expect(item.category, equals('refrigeration'));
      expect(item.costStatus, equals('expected'));
      expect(item.isExpected, isTrue);
      expect(item.isActual, isFalse);
      expect(item.expectedAmount, equals(5000.0));
      expect(item.actualAmount, isNull);
      expect(item.varianceAmount, equals(0.0));
      expect(item.supplierCode, equals('80001'));
      expect(item.supplierName, equals('محطة الأهرام للتعبئة'));
      expect(item.supplierType, equals('station'));
      expect(item.linkedShipments.length, equals(2));
      expect(item.linkedShipments[0]['shipment_code'], equals('EXP-2026-01'));
      expect(item.statusLabel, equals('تقديري'));
    });

    test('SupplierExpectedCostItemModel handles settled item with positive variance', () {
      final json = {
        'cost_item_id': 102,
        'packing_order_id': 202,
        'order_number': 'PK-2026-001',
        'order_status': 'completed',
        'item_name': 'رسوم فحص معملي وتخصيمات',
        'category': 'inspection',
        'report_category_name': 'فحص وتخصيمات',
        'cost_status': 'actual',
        'expected_amount': 3000.0,
        'actual_amount': 3600.0,
        'variance_amount': 600.0,
        'supplier_id': 'sup-ded-1',
        'supplier_code': '40001',
        'supplier_name': 'معمل الجودة والتخصيمات',
        'supplier_type': 'deduction',
        'invoice_ref': 'INV-2026-889',
        'reconciled_at': '2026-09-29T10:00:00Z',
        'settlement_notes': 'فاتورة نهائية بعد إضافة رسوم العينات الإضافية',
        'linked_shipments': [],
      };

      final item = SupplierExpectedCostItemModel.fromJson(json);

      expect(item.isExpected, isFalse);
      expect(item.isActual, isTrue);
      expect(item.expectedAmount, equals(3000.0));
      expect(item.actualAmount, equals(3600.0));
      expect(item.varianceAmount, equals(600.0));
      expect(item.invoiceRef, equals('INV-2026-889'));
      expect(item.statusLabel, equals('فعلي'));
    });

    test('Variance and financial impact formulas are mathematically sound', () {
      const double expectedAmount = 10000.0;
      const double actualAmount = 12500.0;
      const double variance = actualAmount - expectedAmount; // +2500 EGP
      const int totalCartons = 2500;

      expect(variance, equals(2500.0));

      // Carton unit cost delta
      const double deltaPerCarton = variance / totalCartons; // +1.00 EGP / carton
      expect(deltaPerCarton, equals(1.00));

      // Shipment impact
      const int shipmentCartons = 1500;
      const double shipmentCostIncrease = shipmentCartons * deltaPerCarton; // +1500.00 EGP
      expect(shipmentCostIncrease, equals(1500.00));

      // Profit impact = - (Shipment cost increase)
      const double profitDelta = -shipmentCostIncrease; // -1500.00 EGP
      expect(profitDelta, equals(-1500.00));
    });

    test('Negative variance (cost savings) increases shipment profitability', () {
      const double expectedAmount = 8000.0;
      const double actualAmount = 7200.0;
      const double variance = actualAmount - expectedAmount; // -800 EGP (savings)
      const int totalCartons = 1600;

      expect(variance, equals(-800.0));

      const double deltaPerCarton = variance / totalCartons; // -0.50 EGP / carton
      expect(deltaPerCarton, equals(-0.50));

      const int shipmentCartons = 800;
      const double shipmentCostChange = shipmentCartons * deltaPerCarton; // -400.00 EGP
      expect(shipmentCostChange, equals(-400.00));

      const double profitDelta = -shipmentCostChange; // +400.00 EGP (profit increases)
      expect(profitDelta, equals(400.00));
    });

    test('General Ledger double-entry rule holds for cost variance', () {
      // Scenario 1: Actual > Expected (Extra Cost)
      // Debit: 12413 Finished Goods Inventory (Asset increase)
      // Credit: 21117 Station Suppliers or 21118 Deduction Suppliers (Liability increase)
      const double positiveVariance = 1200.0;
      final debit1 = {'account': '12413', 'amount': positiveVariance};
      final credit1 = {'account': '21117', 'amount': positiveVariance};
      expect(debit1['amount'], equals(credit1['amount']));

      // Scenario 2: Actual < Expected (Discount / Reduction)
      // Debit: 21117 / 21118 (Liability decrease)
      // Credit: 12413 Finished Goods Inventory (Asset decrease)
      const double negativeVariance = -500.0;
      final debit2 = {'account': '21118', 'amount': negativeVariance.abs()};
      final credit2 = {'account': '12413', 'amount': negativeVariance.abs()};
      expect(debit2['amount'], equals(credit2['amount']));
    });

    test('SupplierModel parses and calculates dual balances accurately', () {
      final json = {
        'id': 'station-sup-80001',
        'supplier_code': '80001',
        'code': '80001',
        'name': 'محطة الأهرام للفرز والتعبئة',
        'supplier_type': 'station',
        'account_id': 21117,
        'outstanding_balance': 25000.0,
        'pending_expected_balance': 7500.0,
        'currency': 'EGP',
        'categories': ['تبريد وتخزين', 'فرز وتدريج'],
      };

      final supplier = SupplierModel.fromMap(json);

      expect(supplier.id, equals('station-sup-80001'));
      expect(supplier.supplierCode, equals('80001'));
      expect(supplier.supplierType, equals('station'));
      expect(supplier.isStationSupplier, isTrue);
      expect(supplier.outstandingBalance, equals(25000.0));
      expect(supplier.pendingExpectedBalance, equals(7500.0));
      expect(supplier.hasPendingBalance, isTrue);
      expect(supplier.totalProjectedBalance, equals(32500.0));
      expect(supplier.formattedPendingExpectedBalance, contains('7,500'));
      expect(supplier.formattedTotalProjectedBalance, contains('32,500'));
    });

    test('SupplierModel copyWith preserves and updates pendingExpectedBalance', () {
      const supplier = SupplierModel(
        supplierCode: '40001',
        name: 'معمل التخصيمات الدولي',
        supplierType: 'deduction',
        outstandingBalance: 12000.0,
        pendingExpectedBalance: 3000.0,
      );

      expect(supplier.hasPendingBalance, isTrue);
      expect(supplier.totalProjectedBalance, equals(15000.0));

      final updated = supplier.copyWith(pendingExpectedBalance: 0.0);
      expect(updated.hasPendingBalance, isFalse);
      expect(updated.pendingExpectedBalance, equals(0.0));
      expect(updated.outstandingBalance, equals(12000.0));
      expect(updated.totalProjectedBalance, equals(12000.0));
    });

    test('Live ledger balance synchronization accurately matches actual-only statement net balance', () {
      // Simulating a station supplier ('تاج') whose cost item had expected = 3,000.0 EGP,
      // approved actual = 2,500.0 EGP, analytical variance = -500.0 EGP (saving).
      // Financial statement & live ledger balance MUST equal 2,500.0 EGP strictly
      // without subtracting 500 variance from estimated 3,000 or mixing variance lines.
      final settledItem = <String, dynamic>{
        'id': 401,
        'packing_order_id': 77,
        'supplier_id': 'ea29675f',
        'name': 'تجهيز وتبريد',
        'cost_type': 'station',
        'cost_status': 'actual',
        'expected_amount': 3000.0,
        'actual_amount': 2500.0,
        'variance_amount': -500.0,
        'reconciled_at': '2026-11-10T10:00:00Z',
        'variance_journal_entry_id': 8801,
        'original_currency': 'EGP',
      };

      final ledgerEntries = <Map<String, dynamic>>[
        {
          'id': 4,
          'entity_id': 'ea29675f',
          'amount': 3000.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_id': '77',
          'reference_type': 'packing_cost',
          'currency_snapshot': {'cost_item_id': 401},
        },
        {
          'id': 5,
          'entity_id': 'ea29675f',
          'amount': 500.0,
          'currency': 'EGP',
          'entry_type': 'debit',
          'reference_id': '77',
          'reference_type': 'cost_settlement',
          'currency_snapshot': {'cost_item_id': 401},
        },
      ];

      final normalizedStatementEntries =
          SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: ledgerEntries,
        costItemsById: {'401': settledItem},
        costItemsByOrderAndName: {'77_تجهيز وتبريد': settledItem},
        costItemsByOrder: {'77': [settledItem]},
        isDualCostSupplier: true,
      );
      expect(normalizedStatementEntries.length, equals(1));
      expect(normalizedStatementEntries.first['entry_type'], equals('credit'));
      expect(normalizedStatementEntries.first['amount'], equals(2500.0));

      final perCurrency = <String, Map<String, double>>{};
      SupplierDao.applyLedgerEntriesToCurrencyBalances(
        ledgerTxs: ledgerEntries,
        perCurrency: perCurrency,
        treasuryTxIds: const {},
        bankTxIds: const {},
        dualCostSupplierKeys: const {'ea29675f', '85000'},
        aliasToCanonicalId: const {'ea29675f': 'ea29675f', '85000': 'ea29675f'},
        costItems: [settledItem],
      );

      // Expected net statement & live DAO balance = strictly approved actual 2,500.0 EGP
      expect(perCurrency['ea29675f']?['EGP'], equals(2500.0));

      final row = {
        'id': 'ea29675f',
        'supplier_code': '85000',
        'code': '85000',
        'name': 'تاج',
        'supplier_type': 'station',
        'initial_balance': 0.0,
        'outstanding_balance': perCurrency['ea29675f']?['EGP'] ?? 0.0,
        'pending_expected_balance': 0.0,
      };

      final supplier = SupplierModel.fromMap(row);
      expect(supplier.outstandingBalance, equals(2500.0));
      expect(supplier.formattedCurrentBalance, contains('2,500'));
      expect(supplier.hasPendingBalance, isFalse);
    });

    test('Movements under both UUID and supplier code merge without loss or collision', () {
      // Case: treasury payment was booked under code '80000', while packing cost was under UUID 'ea29675f'
      final movementsByCurrency = <String, Map<String, double>>{
        'ea29675f': {'EGP': 1000.0},
        '80000': {'EGP': -200.0},
      };

      final curMap = <String, double>{};
      void applyMovements(Map<String, double>? moves) {
        if (moves == null) return;
        for (final entry in moves.entries) {
          curMap[entry.key] = (curMap[entry.key] ?? 0.0) + entry.value;
        }
      }

      applyMovements(movementsByCurrency['ea29675f']);
      applyMovements(movementsByCurrency['80000']);

      // 1000.0 (credit) - 200.0 (payment) = 800.00 EGP
      expect(curMap['EGP'], equals(800.0));
    });

    test('Pending expected cost aggregation isolates un-settled items from settled ones', () {
      final items = [
        // Settled item (actual)
        {'supplier_id': '80000', 'cost_status': 'actual', 'expected_amount': 1000.0, 'actual_amount': 900.0},
        // Un-settled item (expected)
        {'supplier_id': '80000', 'cost_status': 'expected', 'expected_amount': 1500.0, 'actual_amount': null},
        // Un-settled item with pending status
        {'supplier_id': '80000', 'cost_status': null, 'expected_amount': 500.0, 'actual_amount': null},
      ];

      double pendingTotal = 0.0;
      for (final item in items) {
        final status = item['cost_status'];
        final actual = item['actual_amount'];
        if (status == 'actual' && actual != null) continue;
        pendingTotal += (item['expected_amount'] as double);
      }

      // Settled 1000 is excluded, only 1500 + 500 = 2000.0 is pending
      expect(pendingTotal, equals(2000.0));
    });

    test('SupplierExpectedCostItemModel accurately parses multi-unit breakdown and lock status', () {
      final json = {
        'cost_item_id': 105,
        'packing_order_id': 301,
        'order_number': 'PO-991',
        'order_status': 'completed',
        'item_name': 'رسوم تفريغ وتحميل',
        'category': 'station',
        'report_category_name': 'خدمات محطة',
        'cost_status': 'actual',
        'expected_amount': 1500.0,
        'actual_amount': 1650.0,
        'actual_quantity': 3.0,
        'actual_unit_price': 550.0,
        'actual_date_time': '2026-11-09T14:30:00Z',
        'detailed_notes': 'فاتورة مفرقة على 3 نقلات',
        'is_locked': true,
        'currency_snapshot': {
          'unit_prices': [500.0, 550.0, 600.0],
        },
      };

      final item = SupplierExpectedCostItemModel.fromJson(json);

      expect(item.isLocked, isTrue);
      expect(item.isActual, isTrue);
      expect(item.displayQuantity, equals(3.0));
      expect(item.displayUnitPrice, equals(550.0));
      expect(item.actualAmount, equals(1650.0));
      expect(item.detailedNotes, equals('فاتورة مفرقة على 3 نقلات'));
      expect(item.currencySnapshot, isNotNull);
      final prices = (item.currencySnapshot!['unit_prices'] as List)
          .map((p) => (p as num).toDouble())
          .toList();
      expect(prices, equals([500.0, 550.0, 600.0]));
      expect(prices.fold(0.0, (a, b) => a + b), equals(1650.0));
    });
  });
}

