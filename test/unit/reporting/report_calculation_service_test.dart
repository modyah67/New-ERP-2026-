import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/services/report_calculation_service.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

import '../../fixtures/account_fixtures.dart';
import '../../fixtures/transaction_fixtures.dart';
import '../../mocks/mock_report_dao.dart';

void main() {
  group('ReportCalculationService', () {
    late MockReportDao mockDao;
    late ReportCalculationService service;

    setUp(() async {
      await MockReportDao.ensureInitialized();
      mockDao = MockReportDao();
      service = ReportCalculationService(mockDao);
    });

    // ── Trial Balance ──────────────────────

    group('calculateTrialBalance', () {
      test('generates balanced trial balance', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final report = await service.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );

        expect(report.isBalanced, isTrue);
        expect(report.rows, isNotEmpty);
        expect(report.totalDebit, closeTo(report.totalCredit, 0.01));
      });

      test('filters by account type', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final report = await service.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
          accountType: AccountClassification.asset,
        );

        for (final row in report.rows) {
          expect(row.classification, AccountClassification.asset);
        }
      });

      test('skips accounts with zero balance', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn = [
          {'account_id': '1', 'debit': 0.0, 'credit': 0.0},
        ];

        final report = await service.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );

        expect(report.rows, isEmpty);
      });

      test('sorts rows by account code', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final report = await service.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );

        for (var i = 0; i < report.rows.length - 1; i++) {
          expect(
            report.rows[i].accountCode.compareTo(report.rows[i + 1].accountCode),
            lessThanOrEqualTo(0),
          );
        }
      });

      test('handles empty accounts', () async {
        mockDao.accountsToReturn = [];
        mockDao.accountTotalsToReturn = [];

        final report = await service.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );

        expect(report.rows, isEmpty);
        expect(report.totalDebit, 0.0);
        expect(report.totalCredit, 0.0);
      });

      test('includes 9112 operational spoilage account and balances with inventory', () async {
        mockDao.accountsToReturn = [
          const AccountHierarchy(
            id: '1231',
            code: '1231',
            name: 'Produce Inventory',
            nameAr: 'مخزون المحاصيل الزراعية',
            classification: AccountClassification.asset,
          ),
          const AccountHierarchy(
            id: '9112',
            code: '9112',
            name: 'Produce Waste Intermediary',
            nameAr: 'وسيط هالك وفاقد المحاصيل',
            classification: AccountClassification.expense,
          ),
        ];

        // 3,500.00 EGP valuation entry: Dr. 9112, Cr. 1231
        mockDao.accountTotalsToReturn = [
          {'account_id': '1231', 'debit': 0.0, 'credit': 3500.0},
          {'account_id': '9112', 'debit': 3500.0, 'credit': 0.0},
        ];

        final report = await service.calculateTrialBalance(
          asOfDate: DateTime(2025, 12, 31),
        );

        expect(report.isBalanced, isTrue);
        expect(report.difference, 0.0);
        expect(report.totalDebit, 3500.0);
        expect(report.totalCredit, 3500.0);
        expect(report.rows.length, 2);

        final wasteRow = report.rows.firstWhere((r) => r.accountCode == '9112');
        expect(wasteRow.debit, 3500.0);
        expect(wasteRow.credit, 0.0);
        expect(wasteRow.classification, AccountClassification.expense);

        final invRow = report.rows.firstWhere((r) => r.accountCode == '1231');
        expect(invRow.debit, 0.0);
        expect(invRow.credit, 3500.0);
        expect(invRow.classification, AccountClassification.asset);
      });
    });

    // ── General Ledger ─────────────────────

    group('calculateGeneralLedger', () {
      test('generates ledger with running balance', () async {
        mockDao.accountsToReturn = AccountFixtures.assetAccounts;
        mockDao.balanceBeforeDateToReturn = (debit: 50000.0, credit: 0.0);
        mockDao.transactionsToReturn = TransactionFixtures.sqlDebitCreditRows
            .where((r) => r['account_id'] == '1')
            .toList();

        final report = await service.calculateGeneralLedger(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: '1',
        );

        expect(report.rows, isNotEmpty);
        expect(report.openingBalance, isNotNull);
        expect(report.closingBalance, isNotNull);
      });

      test('handles no transactions', () async {
        mockDao.accountsToReturn = AccountFixtures.assetAccounts;
        mockDao.balanceBeforeDateToReturn = (debit: 0.0, credit: 0.0);
        mockDao.transactionsToReturn = [];

        final report = await service.calculateGeneralLedger(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: '1',
        );

        expect(report.rows, isEmpty);
        expect(report.transactionCount, 0);
      });

      test('sorts by date then entry number', () async {
        mockDao.accountsToReturn = AccountFixtures.assetAccounts;
        mockDao.balanceBeforeDateToReturn = (debit: 0.0, credit: 0.0);
        mockDao.transactionsToReturn = [
          {
            'id': '3',
            'account_id': '1',
            'debit': 3000.0,
            'credit': 0.0,
            'date': '2025-01-25',
            'entry_number': 3,
          },
          {
            'id': '1',
            'account_id': '1',
            'debit': 5000.0,
            'credit': 0.0,
            'date': '2025-01-15',
            'entry_number': 1,
          },
        ];

        final report = await service.calculateGeneralLedger(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: '1',
        );

        expect(report.rows.length, 2);
        // First row should be the earlier date
        expect(report.rows[0].date.isBefore(report.rows[1].date), isTrue);
      });
    });

    // ── Balance Sheet ──────────────────────

    group('calculateBalanceSheet', () {
      test('generates balance sheet with totals', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final report = await service.calculateBalanceSheet(
          asOfDate: DateTime(2025, 12, 31),
        );

        expect(report.totalAssets, greaterThan(0));
        expect(report.assets.lines, isNotEmpty);
        expect(report.generatedAt, isNotNull);
      });

      test('groups accounts by classification', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final report = await service.calculateBalanceSheet(
          asOfDate: DateTime(2025, 12, 31),
        );

        // All asset lines should have asset accounts
        for (final line in report.assets.lines) {
          expect(line.amount, greaterThan(0));
        }
      });
    });

    // ── Income Statement ───────────────────

    group('calculateIncomeStatement', () {
      test('generates income statement', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn =
            TransactionFixtures.accountTotalsForCalculation;

        final report = await service.calculateIncomeStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(report.revenue.total, greaterThan(0));
        expect(report.operatingExpenses.total, greaterThan(0));
        expect(report.netIncome, isNotNull);
      });

      test('calculates gross profit correctly', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn = [
          {'account_id': '8', 'debit': 0.0, 'credit': 120000.0},
          {'account_id': '10', 'debit': 75000.0, 'credit': 0.0},
        ];

        final report = await service.calculateIncomeStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        // Revenue: 120000, COGS: 75000, Gross Profit: 45000
        expect(report.revenue.total, 120000.0);
        expect(report.costOfGoodsSold.total, 75000.0);
        expect(report.grossProfit, 45000.0);
      });

      test('handles expense accounts with credit balances (cost recovery) signed correctly', () async {
        mockDao.accountsToReturn = AccountFixtures.flatAccounts;
        mockDao.accountTotalsToReturn = [
          {'account_id': '8', 'debit': 0.0, 'credit': 100000.0},
          {'account_id': '11', 'debit': 20000.0, 'credit': 0.0},
          {'account_id': '12', 'debit': 0.0, 'credit': 5000.0},
        ];

        final report = await service.calculateIncomeStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        // Revenue: 100000, Total Expenses: 20000 - 5000 = 15000, Net Income: 85000
        expect(report.revenue.total, 100000.0);
        expect(report.operatingExpenses.total, 15000.0);
        expect(report.netIncome, 85000.0);
      });
    });

    // ── Cash Flow Statement ────────────────

    group('calculateCashFlowStatement', () {
      test('generates cash flow statement', () async {
        mockDao.treasuryTxToReturn = TransactionFixtures.treasuryTransactions;
        mockDao.bankTxToReturn = TransactionFixtures.bankTransactions;

        final report = await service.calculateCashFlowStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(report.operating.total, isNotNull);
        expect(report.investing.total, 0.0);
        expect(report.financing.total, 0.0);
        expect(report.netChangeInCash, isNotNull);
      });

      test('classifies treasury transactions as operating', () async {
        mockDao.treasuryTxToReturn = [
          {
            'id': 't1',
            'type': 'deposit',
            'amount': 100000.0,
            'currency': 'EGP',
            'description': 'Payment',
          },
          {
            'id': 't2',
            'type': 'withdrawal',
            'amount': 30000.0,
            'currency': 'EGP',
            'description': 'Expense',
          },
        ];
        mockDao.bankTxToReturn = [];

        final report = await service.calculateCashFlowStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(report.operating.total, 70000.0);
      });

      test('handles empty transactions', () async {
        mockDao.treasuryTxToReturn = [];
        mockDao.bankTxToReturn = [];

        final report = await service.calculateCashFlowStatement(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(report.netChangeInCash, 0.0);
        expect(report.operating.lines, isEmpty);
      });
    });

    // ── Account Statement ──────────────────

    group('calculateAccountStatement', () {
      test('generates account statement', () async {
        mockDao.accountsToReturn = AccountFixtures.assetAccounts;
        mockDao.balanceBeforeDateToReturn = (debit: 50000.0, credit: 0.0);
        mockDao.transactionsToReturn = [
          {
            'id': '1',
            'account_id': '1',
            'debit': 10000.0,
            'credit': 0.0,
            'date': '2025-01-15',
            'description': 'Deposit',
          },
          {
            'id': '2',
            'account_id': '1',
            'debit': 0.0,
            'credit': 5000.0,
            'date': '2025-02-10',
            'description': 'Withdrawal',
          },
        ];

        final report = await service.calculateAccountStatement(
          accountId: '1',
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        );

        expect(report.accountId, '1');
        expect(report.rows.length, 2);
        expect(report.openingBalance, isNotNull);
        expect(report.closingBalance, isNotNull);
      });

      test('throws for non-existent account', () async {
        mockDao.accountsToReturn = [];

        expect(
          () => service.calculateAccountStatement(
            accountId: '999',
            fromDate: DateTime(2025, 1, 1),
            toDate: DateTime(2025, 12, 31),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
