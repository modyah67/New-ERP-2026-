import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/utils/balance_calculator.dart';
import 'package:accounting_system/accounting/reporting/utils/account_classifier.dart';
import 'package:accounting_system/accounting/reporting/utils/currency_converter.dart';
import 'package:accounting_system/accounting/reporting/services/report_filter_service.dart';
import 'package:accounting_system/accounting/reporting/services/report_validation_service.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';
import 'package:accounting_system/core/utils.dart';

import '../fixtures/transaction_fixtures.dart';
import '../fixtures/account_fixtures.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('Regression Tests', () {
    // ── Broken Filters ──

    group('Broken Filters', () {
      late ReportFilterService filterService;

      setUp(() {
        filterService = ReportFilterService();
      });

      test('date range filter preserves account filter', () {
        var filter = const ReportFilter(accountId: '123', currency: 'USD');
        filter = filterService.applyDateRange(
          filter,
          DateTime(2025, 1, 1),
          DateTime(2025, 12, 31),
        );
        expect(filter.accountId, '123');
        expect(filter.currency, 'USD');
        expect(filter.fromDate, DateTime(2025, 1, 1));
        expect(filter.toDate, DateTime(2025, 12, 31));
      });

      test('clearAll resets everything', () {
        final filter = ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: '123',
          accountType: AccountClassification.asset,
          currency: 'USD',
          searchQuery: 'cash',
        );
        final cleared = filterService.clearAll(filter);
        expect(cleared.fromDate, isNull);
        expect(cleared.toDate, isNull);
        expect(cleared.accountId, isNull);
        expect(cleared.accountType, isNull);
        expect(cleared.currency, isNull);
        expect(cleared.searchQuery, isNull);
      });

      test('filter validation catches reversed dates', () {
        final filter = ReportFilter(
          fromDate: DateTime(2025, 12, 31),
          toDate: DateTime(2025, 1, 1),
        );
        final errors = filterService.validateFilter(filter);
        expect(errors.length, 1);
        expect(errors[0].field, 'dateRange');
      });

      test('stacking multiple filters works correctly', () {
        var filter = const ReportFilter();
        filter = filterService.applyFinancialYear(filter, 2025);
        filter = filterService.applyAccountType(filter, AccountClassification.asset);
        filter = filterService.applyCurrency(filter, 'USD');
        filter = filterService.applySearch(filter, 'cash');

        expect(filter.fromDate, DateTime(2025, 1, 1));
        expect(filter.toDate, DateTime(2025, 12, 31));
        expect(filter.accountType, AccountClassification.asset);
        expect(filter.currency, 'USD');
        expect(filter.searchQuery, 'cash');
      });
    });

    // ── Broken Exports ──

    group('Broken Exports (formatting)', () {
      test('CurrencyConverter formatAmount handles edge cases', () {
        expect(
          CurrencyConverter.formatAmount(amount: 0, currency: 'USD'),
          'USD 0.00',
        );
        expect(
          CurrencyConverter.formatAmount(amount: -100, currency: 'EGP'),
          'EGP -100.00',
        );
        expect(
          CurrencyConverter.formatAmount(amount: 999999.99, currency: 'EUR'),
          'EUR 999999.99',
        );
      });

      test('AppUtils.formatNumber handles edge cases', () {
        expect(AppUtils.formatNumber(0), '0.00');
        expect(AppUtils.formatNumber(-0.01), '-0.01');
        expect(AppUtils.formatNumber(1000000000), '1,000,000,000.00');
      });

      test('currency conversion roundtrip preserves value', () {
        final converter = CurrencyConverter({
          'EGP': 1.0,
          'USD': 50.0,
        });
        final original = 100.0;
        final inEgp = converter.toEgp(amount: original, currency: 'USD');
        final backToUsd = converter.convert(
          amount: inEgp,
          fromCurrency: 'EGP',
          toCurrency: 'USD',
        );
        expect(backToUsd, closeTo(original, 0.001));
      });
    });

    // ── Broken Hierarchy ──

    group('Broken Hierarchy', () {
      test('hierarchy builds correctly from flat list', () {
        final accounts = AccountFixtures.hierarchicalAccounts;
        final roots = accounts.where((a) => a.isRoot).toList();
        expect(roots.length, 3); // Assets, Liabilities, Equity
      });

      test('parent has children', () {
        final accounts = AccountFixtures.hierarchicalAccounts;
        final assets = accounts.firstWhere((a) => a.id == '100');
        expect(assets.hasChildren, isTrue);
        expect(assets.children.length, 2);
      });

      test('child has parentId', () {
        final accounts = AccountFixtures.hierarchicalAccounts;
        final cash = accounts.expand((a) => [a, ...a.children]).firstWhere(
              (a) => a.id == '1',
            );
        expect(cash.parentId, '100');
      });

      test('children have correct depth', () {
        final accounts = AccountFixtures.hierarchicalAccounts;
        final cash = accounts.expand((a) => [a, ...a.children]).firstWhere(
              (a) => a.id == '1',
            );
        expect(cash.depth, 1);
      });
    });

    // ── Broken Pagination ──

    group('Broken Pagination', () {
      test('calculateTotals with offset works', () {
        final transactions = TransactionFixtures.sqlDebitCreditRows;
        // Get totals for first 3 transactions
        final totals = BalanceCalculator.calculateTotals(
          transactions: transactions.take(3).toList(),
        );
        expect(totals.count, 3);
      });

      test('calculateTotals with accountId filter', () {
        final transactions = TransactionFixtures.sqlDebitCreditRows;
        final totals = BalanceCalculator.calculateTotals(
          transactions: transactions,
          accountId: '1',
        );
        expect(totals.count, 2); // Account 1 has 2 transactions
      });
    });

    // ── Broken Search ──

    group('Broken Search', () {
      test('filter search preserves other fields', () {
        var filter = ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: '123',
        );
        filter = ReportFilterService().applySearch(filter, 'cash');
        expect(filter.searchQuery, 'cash');
        expect(filter.fromDate, DateTime(2025, 1, 1));
        expect(filter.accountId, '123');
      });
    });

    // ── Broken Sorting ──

    group('Broken Sorting', () {
      test('Trial balance rows are sorted by code', () {
        final rows = [
          TestHelpers.buildTrialBalanceRow(accountCode: '3000'),
          TestHelpers.buildTrialBalanceRow(accountCode: '1000'),
          TestHelpers.buildTrialBalanceRow(accountCode: '2000'),
        ];
        rows.sort((a, b) => a.accountCode.compareTo(b.accountCode));
        expect(rows[0].accountCode, '1000');
        expect(rows[1].accountCode, '2000');
        expect(rows[2].accountCode, '3000');
      });
    });

    // ── Broken Calculations ──

    group('Broken Calculations', () {
      test('normalizeRow handles both patterns', () {
        // SQL pattern
        final sqlRow = {'debit': 1000.0, 'credit': 0.0};
        final (sqlDebit, sqlCredit) = BalanceCalculator.normalizeRow(sqlRow);
        expect(sqlDebit, 1000.0);
        expect(sqlCredit, 0.0);

        // Dart pattern
        final dartRow = {'debit': 0, 'credit': 0, 'type': 'debit', 'amount': 1000.0};
        final (dartDebit, dartCredit) = BalanceCalculator.normalizeRow(dartRow);
        expect(dartDebit, 1000.0);
        expect(dartCredit, 0.0);
      });

      test('calculateBalanceBefore handles empty transactions', () {
        final balance = BalanceCalculator.calculateBalanceBefore(
          transactions: [],
          accountId: '1',
          accountType: 'asset',
          beforeDate: DateTime(2025, 1, 1),
        );
        expect(balance, 0.0);
      });

      test('calculateTotals handles mixed patterns', () {
        final transactions = [
          {'account_id': '1', 'debit': 1000.0, 'credit': 0.0},
          {'account_id': '1', 'debit': 0, 'credit': 0, 'type': 'debit', 'amount': 500.0},
        ];
        final totals = BalanceCalculator.calculateTotals(
          transactions: transactions,
          accountId: '1',
        );
        expect(totals.debit, 1500.0);
        expect(totals.credit, 0.0);
      });
    });

    // ── Broken Drill-Down ──

    group('Broken Drill-Down', () {
      test('account statement uses correct account', () {
        // Verify that AccountStatementReport correctly stores accountId
        final report = AccountStatementReport(
          accountId: '1',
          accountCode: '1000',
          accountName: 'Cash',
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          openingBalance: 50000,
          rows: [],
          closingBalance: 50000,
          totalDebit: 0,
          totalCredit: 0,
          generatedAt: DateTime(2025, 12, 31),
        );
        expect(report.accountId, '1');
        expect(report.accountCode, '1000');
      });
    });

    // ── Broken Validation ──

    group('Broken Validation', () {
      test('validation result errorCount and warningCount are correct', () {
        final result = ValidationResult.failure([
          const ValidationIssue(
            code: 'E1',
            message: 'Error 1',
            messageAr: 'خطأ 1',
            severity: ValidationSeverity.error,
          ),
          const ValidationIssue(
            code: 'E2',
            message: 'Error 2',
            messageAr: 'خطأ 2',
            severity: ValidationSeverity.error,
          ),
          const ValidationIssue(
            code: 'W1',
            message: 'Warning 1',
            messageAr: 'تحذير 1',
            severity: ValidationSeverity.warning,
          ),
          const ValidationIssue(
            code: 'I1',
            message: 'Info 1',
            messageAr: 'معلومات 1',
            severity: ValidationSeverity.info,
          ),
        ]);
        expect(result.errorCount, 2);
        expect(result.warningCount, 1);
        expect(result.isValid, isFalse);
      });

      test('validation result success has no issues', () {
        final result = ValidationResult.success();
        expect(result.isValid, isTrue);
        expect(result.issues, isEmpty);
        expect(result.errorCount, 0);
        expect(result.warningCount, 0);
      });
    });
  });
}
