import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

void main() {
  group('ReportFilter', () {
    test('default filter has null values', () {
      const filter = ReportFilter();
      expect(filter.fromDate, isNull);
      expect(filter.toDate, isNull);
      expect(filter.accountId, isNull);
      expect(filter.accountType, isNull);
      expect(filter.entityType, isNull);
      expect(filter.entityId, isNull);
      expect(filter.currency, isNull);
      expect(filter.searchQuery, isNull);
    });

    test('defaultFilter sets current month range', () {
      final filter = ReportFilter.defaultFilter();
      final now = DateTime.now();
      expect(filter.fromDate!.year, now.year);
      expect(filter.fromDate!.month, now.month);
      expect(filter.fromDate!.day, 1);
    });

    test('copyWith updates fields', () {
      const filter = ReportFilter();
      final updated = filter.copyWith(
        fromDate: DateTime(2025, 1, 1),
        toDate: DateTime(2025, 12, 31),
        accountId: '123',
      );
      expect(updated.fromDate, DateTime(2025, 1, 1));
      expect(updated.toDate, DateTime(2025, 12, 31));
      expect(updated.accountId, '123');
    });

    test('copyWith preserves unchanged fields', () {
      final filter = ReportFilter(
        fromDate: DateTime(2025, 1, 1),
        currency: 'USD',
      );
      final updated = filter.copyWith(accountId: '123');
      expect(updated.fromDate, DateTime(2025, 1, 1));
      expect(updated.currency, 'USD');
      expect(updated.accountId, '123');
    });

    test('copyWith clear flags set field to null', () {
      final filter = ReportFilter(
        fromDate: DateTime(2025, 1, 1),
        toDate: DateTime(2025, 12, 31),
        accountId: '123',
      );
      final updated = filter.copyWith(clearFromDate: true, clearAccountId: true);
      expect(updated.fromDate, isNull);
      expect(updated.toDate, DateTime(2025, 12, 31));
      expect(updated.accountId, isNull);
    });

    test('formattedFromDate formats correctly', () {
      final filter = ReportFilter(fromDate: DateTime(2025, 3, 5));
      expect(filter.formattedFromDate, '2025-03-05');
    });

    test('formattedToDate formats correctly', () {
      final filter = ReportFilter(toDate: DateTime(2025, 12, 31));
      expect(filter.formattedToDate, '2025-12-31');
    });

    test('formattedFromDate is null when not set', () {
      const filter = ReportFilter();
      expect(filter.formattedFromDate, isNull);
    });
  });

  group('AccountHierarchy', () {
    test('isRoot returns true when parentId is null', () {
      const account = AccountHierarchy(
        id: '1',
        code: '1000',
        name: 'Cash',
        nameAr: 'النقدية',
        classification: AccountClassification.asset,
      );
      expect(account.isRoot, isTrue);
    });

    test('isRoot returns false when parentId is set', () {
      const account = AccountHierarchy(
        id: '1',
        code: '1000',
        name: 'Cash',
        nameAr: 'النقدية',
        classification: AccountClassification.asset,
        parentId: '100',
      );
      expect(account.isRoot, isFalse);
    });

    test('hasChildren returns true when children is not empty', () {
      const account = AccountHierarchy(
        id: '1',
        code: '1000',
        name: 'Assets',
        nameAr: 'الأصول',
        classification: AccountClassification.asset,
        children: [
          AccountHierarchy(
            id: '2',
            code: '1100',
            name: 'Cash',
            nameAr: 'النقدية',
            classification: AccountClassification.asset,
          ),
        ],
      );
      expect(account.hasChildren, isTrue);
    });

    test('hasChildren returns false when children is empty', () {
      const account = AccountHierarchy(
        id: '1',
        code: '1000',
        name: 'Cash',
        nameAr: 'النقدية',
        classification: AccountClassification.asset,
      );
      expect(account.hasChildren, isFalse);
    });

    test('copyWith works correctly', () {
      const account = AccountHierarchy(
        id: '1',
        code: '1000',
        name: 'Cash',
        nameAr: 'النقدية',
        classification: AccountClassification.asset,
      );
      final updated = account.copyWith(name: 'New Cash', depth: 2);
      expect(updated.name, 'New Cash');
      expect(updated.depth, 2);
      expect(updated.code, '1000');
    });
  });

  group('TrialBalanceReport', () {
    test('isBalanced when debit equals credit', () {
      final report = ReportFilter.defaultFilter();
      final tb = TrialBalanceReport(
        asOfDate: DateTime(2025, 12, 31),
        rows: [],
        totalDebit: 100000,
        totalCredit: 100000,
        generatedAt: DateTime.now(),
      );
      expect(tb.isBalanced, isTrue);
    });

    test('isUnbalanced when debit differs from credit', () {
      final tb = TrialBalanceReport(
        asOfDate: DateTime(2025, 12, 31),
        rows: [],
        totalDebit: 100000,
        totalCredit: 95000,
        generatedAt: DateTime.now(),
      );
      expect(tb.isBalanced, isFalse);
    });

    test('difference computes correctly', () {
      final tb = TrialBalanceReport(
        asOfDate: DateTime(2025, 12, 31),
        rows: [],
        totalDebit: 100000,
        totalCredit: 95000,
        generatedAt: DateTime.now(),
      );
      expect(tb.difference, 5000.0);
    });

    test('groupedByType groups rows correctly', () {
      final tb = TrialBalanceReport(
        asOfDate: DateTime(2025, 12, 31),
        rows: [
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
            credit: 10000,
          ),
        ],
        totalDebit: 50000,
        totalCredit: 10000,
        generatedAt: DateTime.now(),
      );
      final grouped = tb.groupedByType;
      expect(grouped[AccountClassification.asset]!.length, 1);
      expect(grouped[AccountClassification.liability]!.length, 1);
    });
  });

  group('TrialBalanceRow', () {
    test('balance computes correctly', () {
      const row = TrialBalanceRow(
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        debit: 50000,
        credit: 10000,
      );
      expect(row.balance, 40000);
    });

    test('isDebitBalance for positive balance', () {
      const row = TrialBalanceRow(
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        debit: 50000,
        credit: 10000,
      );
      expect(row.isDebitBalance, isTrue);
    });

    test('isDebitBalance for zero balance', () {
      const row = TrialBalanceRow(
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        debit: 10000,
        credit: 10000,
      );
      expect(row.isDebitBalance, isTrue);
    });
  });

  group('LedgerRow', () {
    test('netAmount computes correctly', () {
      final row = LedgerRow(
        date: DateTime(2025, 1, 15),
        accountCode: '1000',
        accountName: 'Cash',
        debit: 5000,
        credit: 2000,
      );
      expect(row.netAmount, 3000);
    });
  });

  group('LedgerReport', () {
    test('isBalanced when debit equals credit', () {
      final report = LedgerReport(
        fromDate: DateTime(2025, 1, 1),
        toDate: DateTime(2025, 12, 31),
        rows: [],
        openingBalance: 0,
        closingBalance: 0,
        totalDebit: 100000,
        totalCredit: 100000,
        transactionCount: 0,
        generatedAt: DateTime.now(),
      );
      expect(report.isBalanced, isTrue);
    });
  });

  group('BalanceSheetReport', () {
    test('isBalanced when assets equal liabilities + equity', () {
      final report = BalanceSheetReport(
        asOfDate: DateTime(2025, 12, 31),
        assets: const BalanceSheetSection(
          title: 'Assets', titleAr: 'الأصول', lines: [], total: 200000,
        ),
        liabilities: const BalanceSheetSection(
          title: 'Liabilities', titleAr: 'الخصوم', lines: [], total: 120000,
        ),
        equity: const BalanceSheetSection(
          title: 'Equity', titleAr: 'حقوق الملكية', lines: [], total: 80000,
        ),
        totalAssets: 200000,
        totalLiabilitiesAndEquity: 200000,
        generatedAt: DateTime.now(),
      );
      expect(report.isBalanced, isTrue);
    });

    test('difference computes correctly', () {
      final report = BalanceSheetReport(
        asOfDate: DateTime(2025, 12, 31),
        assets: const BalanceSheetSection(
          title: 'Assets', titleAr: 'الأصول', lines: [], total: 200000,
        ),
        liabilities: const BalanceSheetSection(
          title: 'Liabilities', titleAr: 'الخصوم', lines: [], total: 100000,
        ),
        equity: const BalanceSheetSection(
          title: 'Equity', titleAr: 'حقوق الملكية', lines: [], total: 80000,
        ),
        totalAssets: 200000,
        totalLiabilitiesAndEquity: 180000,
        generatedAt: DateTime.now(),
      );
      expect(report.difference, 20000.0);
    });
  });

  group('AccountBalanceReport', () {
    test('netBalance computes correctly', () {
      const report = AccountBalanceReport(
        accountId: '1',
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        closingDebit: 50000,
        closingCredit: 10000,
      );
      expect(report.netBalance, 40000);
    });

    test('hasDebitBalance for asset with positive net', () {
      const report = AccountBalanceReport(
        accountId: '1',
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        closingDebit: 50000,
        closingCredit: 10000,
      );
      expect(report.hasDebitBalance, isTrue);
    });

    test('hasCreditBalance for asset with negative net', () {
      const report = AccountBalanceReport(
        accountId: '1',
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        closingDebit: 10000,
        closingCredit: 50000,
      );
      expect(report.hasCreditBalance, isTrue);
    });

    test('displayBalance returns absolute value of normal direction', () {
      const report = AccountBalanceReport(
        accountId: '1',
        accountCode: '1000',
        accountName: 'Cash',
        accountNameAr: 'النقدية',
        classification: AccountClassification.asset,
        closingDebit: 50000,
        closingCredit: 10000,
      );
      expect(report.displayBalance, 40000);
    });
  });

  group('CashFlowReport', () {
    test('netChangeInCash computes correctly', () {
      final report = CashFlowReport(
        fromDate: DateTime(2025, 1, 1),
        toDate: DateTime(2025, 12, 31),
        operating: const CashFlowSection(
          title: 'Operating', titleAr: 'تشغيل', lines: [], total: 100000,
        ),
        investing: const CashFlowSection(
          title: 'Investing', titleAr: 'استثمار', lines: [], total: -50000,
        ),
        financing: const CashFlowSection(
          title: 'Financing', titleAr: 'تمويل', lines: [], total: 20000,
        ),
        netCashFromOperating: 100000,
        netCashFromInvesting: -50000,
        netCashFromFinancing: 20000,
        netChangeInCash: 70000,
        generatedAt: DateTime.now(),
      );
      expect(report.netChangeInCash, 70000);
    });
  });

  group('CurrencyDisplay', () {
    test('displayLabel formats correctly', () {
      const display = CurrencyDisplay(
        currency: 'USD',
        amount: 100.0,
        exchangeRate: 50.0,
        amountInEgp: 5000.0,
      );
      expect(display.displayLabel, 'USD 100.00');
    });

    test('displayLabelEgp formats correctly', () {
      const display = CurrencyDisplay(
        currency: 'USD',
        amount: 100.0,
        exchangeRate: 50.0,
        amountInEgp: 5000.0,
      );
      expect(display.displayLabelEgp, 'EGP 5000.00');
    });
  });

  group('AccountStatementRow', () {
    test('defaults are correct', () {
      final row = AccountStatementRow(date: DateTime(2025, 1, 15));
      expect(row.debit, 0.0);
      expect(row.credit, 0.0);
      expect(row.runningBalance, 0.0);
      expect(row.description, isNull);
    });
  });
}
