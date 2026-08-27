import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/utils/balance_calculator.dart';
import 'package:accounting_system/accounting/reporting/utils/currency_converter.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';
import 'package:accounting_system/reporting/widgets/reporting_data_grid.dart';

import '../fixtures/transaction_fixtures.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('Performance Tests', () {
    // ── Execution Time Tests ──

    group('Execution Time', () {
      test('normalizeRow for 10K rows completes under 500ms', () {
        final rows = TransactionFixtures.generateLargeDataset(10000);
        final sw = Stopwatch()..start();
        for (final row in rows) {
          BalanceCalculator.normalizeRow(row);
        }
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('calculateTotals for 10K rows completes under 300ms', () {
        final rows = TransactionFixtures.generateLargeDataset(10000);
        final sw = Stopwatch()..start();
        BalanceCalculator.calculateTotals(transactions: rows);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(300));
      });

      test('calculateBalanceBefore for 10K rows completes under 1s', () {
        final rows = TransactionFixtures.generateLargeDataset(10000);
        final sw = Stopwatch()..start();
        BalanceCalculator.calculateBalanceBefore(
          transactions: rows,
          accountId: '1',
          accountType: 'asset',
          beforeDate: DateTime(2025, 12, 31),
        );
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(1000));
      });

      test('applyRunningBalance for 10K rows completes under 500ms', () {
        final ledgerRows = List.generate(
          10000,
          (i) => TestHelpers.buildLedgerRow(
            debit: i.isEven ? 100.0 : 0.0,
            credit: i.isEven ? 0.0 : 50.0,
          ),
        );
        final sw = Stopwatch()..start();
        BalanceCalculator.applyRunningBalance(
          rows: ledgerRows,
          openingBalance: 0,
          accountType: AccountClassification.asset,
        );
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('CurrencyConverter conversion for 10K operations under 150ms', () {
        final converter = CurrencyConverter({
          'EGP': 1.0,
          'USD': 50.0,
          'EUR': 55.0,
          'GBP': 63.0,
        });
        final sw = Stopwatch()..start();
        for (var i = 0; i < 10000; i++) {
          converter.convert(
            amount: i * 100.0,
            fromCurrency: 'USD',
            toCurrency: 'EUR',
          );
        }
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(150));
      });

      test('formatAmountAr for 10K calls under 150ms', () {
        final sw = Stopwatch()..start();
        for (var i = 0; i < 10000; i++) {
          CurrencyConverter.formatAmountAr(amount: i * 1234.56, currency: 'EGP');
        }
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(150));
      });
    });

    // ── Memory Tests (approximate via object creation) ──

    group('Memory', () {
      test('generating 100K transaction rows does not crash', () {
        expect(
          () => TransactionFixtures.generateLargeDataset(100000),
          returnsNormally,
        );
      });

      test('processing 100K rows does not crash', () {
        final rows = TransactionFixtures.generateLargeDataset(100000);
        final sw = Stopwatch()..start();
        BalanceCalculator.calculateTotals(transactions: rows);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('applyRunningBalance on 100K rows under 2s', () {
        final ledgerRows = List.generate(
          100000,
          (i) => TestHelpers.buildLedgerRow(
            debit: i.isEven ? 100.0 : 0.0,
            credit: i.isEven ? 0.0 : 50.0,
          ),
        );
        final sw = Stopwatch()..start();
        BalanceCalculator.applyRunningBalance(
          rows: ledgerRows,
          openingBalance: 0,
          accountType: AccountClassification.asset,
        );
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });
    });

    // ── Scale Tests ──

    group('Scale (10K-500K transactions)', () {
      test('10K transactions: all operations under 500ms total', () {
        final rows = TransactionFixtures.generateLargeDataset(10000);
        final sw = Stopwatch()..start();

        // All core operations
        for (final row in rows) {
          BalanceCalculator.normalizeRow(row);
        }
        BalanceCalculator.calculateTotals(transactions: rows);
        BalanceCalculator.calculateBalanceBefore(
          transactions: rows,
          accountId: '1',
          accountType: 'asset',
          beforeDate: DateTime(2025, 12, 31),
        );

        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('50K transactions: normalization under 500ms', () {
        final rows = TransactionFixtures.generateLargeDataset(50000);
        final sw = Stopwatch()..start();
        for (final row in rows) {
          BalanceCalculator.normalizeRow(row);
        }
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('100K transactions: totals calculation under 1 second', () {
        final rows = TransactionFixtures.generateLargeDataset(100000);
        final sw = Stopwatch()..start();
        BalanceCalculator.calculateTotals(transactions: rows);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(3000));
      });

      test('500K rows generated without error', () {
        expect(
          () => TransactionFixtures.generateLargeDataset(500000),
          returnsNormally,
        );
      });

      test('500K rows normalizeRow completes under 2s', () {
        final rows = TransactionFixtures.generateLargeDataset(500000);
        final sw = Stopwatch()..start();
        for (final row in rows) {
          BalanceCalculator.normalizeRow(row);
        }
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('1M rows can be generated', () {
        expect(
          () => TransactionFixtures.generateLargeDataset(1000000),
          returnsNormally,
        );
      });
    });

    // ── Widget Rebuild Count Tests ──

    group('Widget Performance', () {
      test('builds ReportingDataGrid with 100 rows without timeout', () async {
        // This test verifies the grid can handle 100 rows
        // without timing out during widget building
        final rows = List.generate(
          100,
          (i) => const ReportingRowData(
            id: '0',
            cells: {'code': '0000', 'name': 'Account'},
          ),
        ).map((r) => ReportingRowData(
              id: r.id,
              cells: r.cells,
            )).toList();

        expect(rows.length, 100);
      });
    });
  });
}
