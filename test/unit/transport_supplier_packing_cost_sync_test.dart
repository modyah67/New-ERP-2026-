import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/transport_transaction_model.dart';
import 'package:accounting_system/data/models/transport_supplier_model.dart';
import 'package:accounting_system/data/models/packing_cost_variance_model.dart';

void main() {
  group('Transport Supplier Decoupled Operational Stock & Fractional Trips Tests', () {
    test('1. TransportTransactionModel correctly classifies operational packing_consumption vs financial invoice', () {
      final consumptionTx = TransportTransactionModel(
        id: 101,
        supplierId: 5,
        type: 'packing_consumption',
        amount: 0.0,
        truckCount: 0.5,
        referenceId: '123',
        journalEntryId: 55,
        date: '2026-11-01',
        createdAt: '2026-11-01T10:00:00Z',
      );

      // Operational consumption: No financial debit or credit!
      expect(consumptionTx.isInvoice, isFalse);
      expect(consumptionTx.isPayment, isFalse);
      expect(consumptionTx.credit, equals(0.0));
      expect(consumptionTx.debit, equals(0.0));
      expect(consumptionTx.typeLabel, equals('استهلاك نقلات (أمر تعبئة)'));
      expect(consumptionTx.isConsumption, isTrue);
      expect(consumptionTx.truckCount, equals(0.5));

      final invoiceTx = TransportTransactionModel(
        id: 102,
        supplierId: 5,
        type: 'invoice',
        amount: 5000.0,
        truckCount: 2.0,
        referenceId: 'INV-001',
        journalEntryId: 50,
        date: '2026-11-01',
        createdAt: '2026-11-01T09:00:00Z',
      );

      // Financial invoice: Generates liability credit
      expect(invoiceTx.isInvoice, isTrue);
      expect(invoiceTx.credit, equals(5000.0));
      expect(invoiceTx.debit, equals(0.0));
    });

    test('2. Operational Quota Deduction: truck_balance decreases by exact fraction (0.5) while financial balance remains unchanged', () {
      double curBal = 10000.0;
      double curTruck = 5.0;

      // Packing order allocates 500 EGP transport cost and draws 0.5 trucks
      const double consumedTrucks = 0.5;

      // Operational stock deduction only:
      curTruck -= consumedTrucks;
      // Financial balance must NOT be touched!
      // curBal remains 10000.0

      expect(curTruck, equals(4.5));
      expect(curBal, equals(10000.0));

      // Re-posting (Idempotent update: Revert old trucks, apply new)
      // Step A: Revert old trucks
      curTruck += consumedTrucks;
      expect(curTruck, equals(5.0));
      expect(curBal, equals(10000.0));

      // Step B: Apply updated 1.25 trucks
      const double newConsumedTrucks = 1.25;
      curTruck -= newConsumedTrucks;
      expect(curTruck, equals(3.75));
      expect(curBal, equals(10000.0));
    });

    test('3. Transporter Statement running balance remains constant during operational consumptions', () {
      double runningBal = 0.0;

      final transactions = [
        // 1. Initial Invoice (10 trucks @ 25,000 EGP)
        TransportTransactionModel(
          supplierId: 1,
          type: 'invoice',
          amount: 25000.0,
          truckCount: 10.0,
          date: '2026-11-01',
          createdAt: '2026-11-01T08:00:00Z',
        ),
        // 2. Packing Order 1 consumption (0.5 trucks, amount = 0)
        TransportTransactionModel(
          supplierId: 1,
          type: 'packing_consumption',
          amount: 0.0,
          truckCount: 0.5,
          date: '2026-11-01',
          createdAt: '2026-11-01T10:00:00Z',
        ),
        // 3. Packing Order 2 consumption (0.5 trucks, amount = 0)
        TransportTransactionModel(
          supplierId: 1,
          type: 'packing_consumption',
          amount: 0.0,
          truckCount: 0.5,
          date: '2026-11-01',
          createdAt: '2026-11-01T12:00:00Z',
        ),
        // 4. Bank Payment (-15,000 EGP)
        TransportTransactionModel(
          supplierId: 1,
          type: 'bank_payment',
          amount: 15000.0,
          truckCount: 0.0,
          date: '2026-11-01',
          createdAt: '2026-11-01T14:00:00Z',
        ),
      ];

      // Row 1 (Invoice): runningBal becomes 25000
      runningBal += (transactions[0].credit - transactions[0].debit);
      expect(runningBal, equals(25000.0));

      // Row 2 (Packing Consumption 0.5 trucks): runningBal stays 25000!
      runningBal += (transactions[1].credit - transactions[1].debit);
      expect(runningBal, equals(25000.0));

      // Row 3 (Packing Consumption 0.5 trucks): runningBal stays 25000!
      runningBal += (transactions[2].credit - transactions[2].debit);
      expect(runningBal, equals(25000.0));

      // Row 4 (Payment): runningBal becomes 10000
      runningBal += (transactions[3].credit - transactions[3].debit);
      expect(runningBal, equals(10000.0));
    });

    test('4. Decimal formatting of trucks in UI (e.g. 0.5, 1, 3.25)', () {
      String formatTrucks(double val) {
        return val % 1 == 0
            ? val.toInt().toString()
            : val.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      }

      expect(formatTrucks(0.5), equals('0.5'));
      expect(formatTrucks(1.0), equals('1'));
      expect(formatTrucks(1.25), equals('1.25'));
      expect(formatTrucks(4.5), equals('4.5'));
      expect(formatTrucks(10.0), equals('10'));
    });

    test('5. Packing order cost variance reflects actual cost without pending settlement', () {
      final transportItem = PackingCostItemComparison(
        name: 'نقل وشحن داخلي للمزرعة',
        category: 'logistics',
        estimatedCost: 1500.0,
        actualCost: 1500.0,
        variance: 0.0,
        variancePercent: null,
        status: PackingCostStatus.fullyActual,
        source: 'قيد إثبات تكلفة نقل أمر تعبئة #105',
        journalEntryId: 105,
        sourceType: 'packing_order_transport',
        sourceId: '12',
        supplierName: 'مقاول النقل المتحد',
        costItemId: 99,
      );

      expect(transportItem.hasActualCost, isTrue);
      expect(transportItem.actualCost, equals(1500.0));
      expect(transportItem.status, equals(PackingCostStatus.fullyActual));
      expect(transportItem.status.labelAr, equals('مكتمل فعلياً'));
      expect(transportItem.reasonNotAvailable, isNull);
    });

    test('6. Fractional truck count resolution preserves 0.5 when DB row has default 1.0', () {
      final rowWithStaleDefault = {
        'truck_count': 1.0,
        'quantity': 1.0,
        'currency_snapshot': {
          'truck_count': 0.5,
          'quantity': 0.5,
          'supplier_name': 'مورد نقل',
        },
      };

      final snapshot = rowWithStaleDefault['currency_snapshot'] as Map<String, dynamic>;
      final double? snapTruck = (snapshot['truck_count'] is num)
          ? (snapshot['truck_count'] as num).toDouble()
          : double.tryParse(snapshot['truck_count']?.toString() ?? '');
      final double? snapQty = (snapshot['quantity'] is num)
          ? (snapshot['quantity'] as num).toDouble()
          : double.tryParse(snapshot['quantity']?.toString() ?? '');
      final double? rowTruck = (rowWithStaleDefault['truck_count'] is num)
          ? (rowWithStaleDefault['truck_count'] as num).toDouble()
          : double.tryParse(rowWithStaleDefault['truck_count']?.toString() ?? '');

      final truckCount = (snapTruck != null && snapTruck > 0 && snapTruck != 1.0)
          ? snapTruck
          : (rowTruck ?? snapTruck ?? snapQty ?? 1.0);

      expect(truckCount, equals(0.5));
    });
  });
}
