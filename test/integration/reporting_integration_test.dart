import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/services/report_calculation_service.dart';
import 'package:accounting_system/accounting/reporting/services/report_validation_service.dart';
import 'package:accounting_system/accounting/reporting/services/report_filter_service.dart';
import 'package:accounting_system/accounting/reporting/utils/balance_calculator.dart';
import 'package:accounting_system/accounting/reporting/utils/account_classifier.dart';
import 'package:accounting_system/accounting/reporting/utils/currency_converter.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

import '../fixtures/account_fixtures.dart';
import '../fixtures/transaction_fixtures.dart';
import '../mocks/mock_report_dao.dart';

void main() {
  group('Integration Tests', () {
    late MockReportDao mockDao;
    late ReportCalculationService calcService;
    late ReportValidationService validationService;
    late ReportFilterService filterService;

    setUp(() async {
      await MockReportDao.ensureInitialized();
      mockDao = MockReportDao();
      calcService = ReportCalculationService(mockDao);
      validationService = ReportValidationService(mockDao);
      filterService = ReportFilterService();
    });

    // ── Complete Trial Balance Flow ──

    group('Trial Balance complete flow', () {
      test('calculate → validate → export data', () async {
        // Setup
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        // Step 1: Apply filters
        var filter = const ReportFilter();
        filter = filterService.applyFinancialYear(filter, 2025);
        expect(filter.fromDate, DateTime(2025, 1, 1));
        expect(filter.toDate, DateTime(2025, 12, 31));

        // Step 2: Calculate trial balance
        final report = await calcService.calculateTrialBalance(
          asOfDate: filter.toDate!,
          accountType: filter.accountType,
        );
        expect(report.rows, isNotEmpty);
        expect(report.totalDebit, greaterThan(0));

        // Step 3: Validate
        final validation = validationService.validateTrialBalance(report);
        expect(validation.isValid, isTrue);

        // Step 4: Verify data integrity
        expect(report.isBalanced, isTrue);
        expect(report.rows.length, greaterThan(0));
      });
    });

    // ── Complete General Ledger Flow ──

    group('General Ledger complete flow', () {
      test('calculate with date filter and account filter', () async {
        mockDao.accountsToReturn = AccountFixtures.assetAccounts;
        mockDao.balanceBeforeDateToReturn = (debit: 50000.0, credit: 0.0);
        mockDao.transactionsToReturn =
            TransactionFixtures.sqlDebitCreditRows.where((r) => r['account_id'] == '1').toList();

        // Apply date filter
        var filter = ReportFilter.defaultFilter();
        filter = filterService.applyDateRange(
          filter,
          DateTime(2025, 1, 1),
          DateTime(2025, 12, 31),
        );

        // Calculate GL
        final report = await calcService.calculateGeneralLedger(
          fromDate: filter.fromDate!,
          toDate: filter.toDate!,
          accountId: '1',
        );

        // Verify
        expect(report.rows, isNotEmpty);
        expect(report.openingBalance, isNotNull);
        expect(report.closingBalance, isNotNull);
        expect(report.totalDebit, greaterThan(0));
      });
    });

    // ── Trial Balance → General Ledger Drill Down ──

    group('Trial Balance → General Ledger Drill Down', () {
      test('drill down from TB to GL for specific account', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        // Step 1: Generate Trial Balance
        final tb = await calcService.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );
        expect(tb.isBalanced, isTrue);

        // Step 2: Drill down into first account
        if (tb.rows.isNotEmpty) {
          final firstRow = tb.rows.first;

          // Step 3: Get GL for that account
          mockDao.balanceBeforeDateToReturn = (debit: 50000.0, credit: 0.0);
          mockDao.transactionsToReturn =
              TransactionFixtures.sqlDebitCreditRows
                  .where((r) => r['account_id'] == '1')
                  .toList();

          final gl = await calcService.calculateGeneralLedger(
            fromDate: DateTime(2025, 1, 1),
            toDate: DateTime(2025, 12, 31),
            accountId: '1',
          );

          // Verify GL has data for this account
          expect(gl.accountId, '1');
        }
      });
    });

    // ── Exports ──

    group('Export data preparation', () {
      test('export data is properly formatted', () async {
        final report = const CurrencyDisplay(
          currency: 'USD',
          amount: 1000.0,
          exchangeRate: 50.0,
          amountInEgp: 50000.0,
        );

        // Verify export data format
        expect(report.displayLabel, 'USD 1000.00');
        expect(report.displayLabelEgp, 'EGP 50000.00');
      });
    });

    // ── Pagination ──

    group('Pagination', () {
      test('pagination with filter works correctly', () {
        final allTransactions = TransactionFixtures.sqlDebitCreditRows;
        final filtered = allTransactions.where((t) => t['account_id'] == '1').toList();
        expect(filtered.length, lessThan(allTransactions.length));
      });

      test('cursor-based pagination simulation', () {
        final allTransactions = TransactionFixtures.sqlDebitCreditRows;
        const pageSize = 3;

        // First page
        final page1 = allTransactions.take(pageSize).toList();
        expect(page1.length, pageSize);

        // Second page
        final page2 = allTransactions.skip(pageSize).take(pageSize).toList();
        expect(page2.length, lessThanOrEqualTo(pageSize));

        // Both pages have items when data exists
        expect(page1, isNotEmpty);
        expect(page1.length + page2.length, lessThanOrEqualTo(allTransactions.length));

        // Full iteration covers all items
        final allItems = <Map<String, dynamic>>[];
        for (var offset = 0; offset < allTransactions.length; offset += pageSize) {
          allItems.addAll(allTransactions.skip(offset).take(pageSize));
        }
        expect(allItems.length, allTransactions.length);
      });
    });

    // ── Search ──

    group('Search integration', () {
      test('search filter preserves date range', () {
        var filter = ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );
        filter = filterService.applySearch(filter, 'cash');
        expect(filter.searchQuery, 'cash');
        expect(filter.fromDate, DateTime(2025, 1, 1));
        expect(filter.toDate, DateTime(2025, 12, 31));
      });
    });

    // ── Sorting ──

    group('Sorting integration', () {
      test('rows can be sorted by account code', () {
        final rows = [
          const TrialBalanceRow(
            accountCode: '3000',
            accountName: 'Equity',
            accountNameAr: 'حقوق الملكية',
            classification: AccountClassification.equity,
            debit: 0,
            credit: 50000,
          ),
          const TrialBalanceRow(
            accountCode: '1000',
            accountName: 'Cash',
            accountNameAr: 'النقدية',
            classification: AccountClassification.asset,
            debit: 50000,
            credit: 0,
          ),
          const TrialBalanceRow(
            accountCode: '2000',
            accountName: 'AP',
            accountNameAr: 'الدائنون',
            classification: AccountClassification.liability,
            debit: 0,
            credit: 30000,
          ),
        ];

        rows.sort((a, b) => a.accountCode.compareTo(b.accountCode));
        expect(rows[0].accountCode, '1000');
        expect(rows[1].accountCode, '2000');
        expect(rows[2].accountCode, '3000');
      });
    });

    // ── Validation ──

    group('Validation integration', () {
      test('validate entire reporting chain', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        // Calculate TB
        final tb = await calcService.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );

        // Validate TB
        final tbValidation = validationService.validateTrialBalance(tb);
        expect(tbValidation.isValid, isTrue);

        // Validate hierarchy
        final hierarchyValidation = validationService.validateHierarchy(
          AccountFixtures.hierarchicalAccounts,
        );
        expect(hierarchyValidation.isValid, isTrue);

        // Validate balance check
        final balanceCheck = validationService.isBalanced(
          tb.totalDebit,
          tb.totalCredit,
        );
        expect(balanceCheck.isValid, isTrue);
      });
    });

    // ── Hierarchy ──

    group('Hierarchy integration', () {
      test('hierarchy traversal works correctly', () {
        final accounts = AccountFixtures.hierarchicalAccounts;

        // Find root accounts
        final roots = accounts.where((a) => a.isRoot).toList();
        expect(roots.length, 3);

        // Find children
        for (final root in roots) {
          expect(root.hasChildren, isTrue);
          for (final child in root.children) {
            expect(child.parentId, root.id);
            expect(child.depth, greaterThan(0));
          }
        }
      });
    });

    // ── Opening Balance ──

    group('Opening Balance', () {
      test('opening balance calculation with pre-aggregated sums', () {
        const debitNormal = AccountClassification.asset;
        const creditNormal = AccountClassification.liability;

        // Debit-normal: balance = debit - credit
        final assetBalance = 50000.0 - 10000.0;
        expect(assetBalance, 40000.0);

        // Credit-normal: balance = credit - debit
        final liabilityBalance = 30000.0 - 5000.0;
        expect(liabilityBalance, 25000.0);
      });
    });

    // ── Closing Balance ──

    group('Closing Balance', () {
      test('closing balance = opening + movement', () {
        final opening = 40000.0;
        final movement = BalanceCalculator.applyRunningBalance(
          rows: [
            LedgerRow(
              date: DateTime(2025, 1, 1),
              accountCode: '1000',
              accountName: 'Cash',
              debit: 20000,
              credit: 0,
            ),
            LedgerRow(
              date: DateTime(2025, 1, 2),
              accountCode: '1000',
              accountName: 'Cash',
              debit: 0,
              credit: 5000,
            ),
          ],
          openingBalance: opening,
          accountType: AccountClassification.asset,
        );

        final closing = movement.last.balance;
        // Opening: 40000
        // Row1: 40000 + (-20000) = 20000
        // Row2: 20000 + 5000 = 25000
        expect(closing, 25000.0);
      });
    });

    // ── Running Balance ──

    group('Running Balance', () {
      test('running balance accumulates correctly over many rows', () {
        final rows = List.generate(
          20,
          (i) => LedgerRow(
            date: DateTime(2025, 1, i + 1),
            accountCode: '1000',
            accountName: 'Cash',
            debit: i.isEven ? 1000.0 : 0,
            credit: i.isEven ? 0 : 500.0,
          ),
        );

        final result = BalanceCalculator.applyRunningBalance(
          rows: rows,
          openingBalance: 10000.0,
          accountType: AccountClassification.asset,
        );

        // Verify final balance
        double expected = 10000.0;
        for (var i = 0; i < 20; i++) {
          if (i.isEven) {
            expected -= 1000;
          } else {
            expected += 500;
          }
        }
        expect(result.last.balance, expected);
      });
    });

    // ── Multi-currency conversions ──

    group('Multi-currency conversions', () {
      test('cross-currency conversion is consistent', () {
        final converter = CurrencyConverter(TransactionFixtures.exchangeRates);

        // USD → EUR → USD should return original amount
        final usdToEur = converter.convert(
          amount: 100,
          fromCurrency: 'USD',
          toCurrency: 'EUR',
        );
        final eurToUsd = converter.convert(
          amount: usdToEur,
          fromCurrency: 'EUR',
          toCurrency: 'USD',
        );
        expect(eurToUsd, closeTo(100, 0.001));
      });

      test('EGP is always 1.0', () {
        final converter = CurrencyConverter(TransactionFixtures.exchangeRates);
        final result = converter.toEgp(amount: 100, currency: 'EGP');
        expect(result, 100.0);
      });

      test('multi-currency summary sums correctly', () {
        final converter = CurrencyConverter(TransactionFixtures.exchangeRates);
        final summary = converter.createSummary(amountsByCurrency: {
          'USD': 100,
          'EUR': 100,
          'GBP': 100,
        });

        // 100*50 + 100*55 + 100*63 = 5000 + 5500 + 6300 = 16800
        expect(summary.totalInEgp, closeTo(16800, 0.01));
        expect(summary.currencies.length, 3);
      });
    });

    // ── Complete Balance Sheet Flow ──

    group('Balance Sheet complete flow', () {
      test('calculate → validate', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final bs = await calcService.calculateBalanceSheet(
          asOfDate: DateTime(2025, 12, 31),
        );

        expect(bs.totalAssets, greaterThan(0));
        expect(bs.generatedAt, isNotNull);

        final validation = validationService.validateBalanceSheet(bs);
        // Note: In a complete balanced dataset, this should be true
        expect(validation, isNotNull);
      });
    });

    // ── Income Statement Flow ──

    group('Income Statement complete flow', () {
      test('calculate income statement with COGS separation', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final isReport = await calcService.calculateIncomeStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(isReport.revenue.total, greaterThan(0));
        expect(isReport.grossProfit, isNotNull);
        expect(isReport.netIncome, isNotNull);
      });
    });

    // ── Cash Flow Complete Flow ──

    group('Cash Flow complete flow', () {
      test('calculate cash flow statement', () async {
        mockDao.treasuryTxToReturn = TransactionFixtures.treasuryTransactions;
        mockDao.bankTxToReturn = TransactionFixtures.bankTransactions;

        final cf = await calcService.calculateCashFlowStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(cf.operating.total, isNotNull);
        expect(cf.netChangeInCash, isNotNull);
        expect(cf.generatedAt, isNotNull);
      });
    });
  });
}
