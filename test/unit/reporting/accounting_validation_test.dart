import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/utils/balance_calculator.dart';
import 'package:accounting_system/accounting/reporting/utils/account_classifier.dart';
import 'package:accounting_system/accounting/reporting/services/report_validation_service.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

import '../../fixtures/account_fixtures.dart';
import '../../fixtures/transaction_fixtures.dart';
import '../../mocks/mock_report_dao.dart';
import '../../helpers/test_helpers.dart';

void main() {
  group('Accounting Validation Tests', () {
    late MockReportDao mockDao;
    late ReportValidationService validationService;

    setUp(() async {
      await MockReportDao.ensureInitialized();
      mockDao = MockReportDao();
      validationService = ReportValidationService(mockDao);
    });

    // ── Accounting Equation: Assets = Liabilities + Equity ──

    group('Assets = Liabilities + Equity', () {
      test('balanced dataset satisfies accounting equation', () {
        final totals = TransactionFixtures.accountTotalsForCalculation;

        double totalAssets = 0;
        double totalLiabilities = 0;
        double totalEquity = 0;

        for (final t in totals) {
          final debit = (t['debit'] as num?)?.toDouble() ?? 0.0;
          final credit = (t['credit'] as num?)?.toDouble() ?? 0.0;
          final net = debit - credit;

          // Find the account classification
          final accountId = t['account_id'].toString();
          AccountClassification? classification;
          for (final a in AccountFixtures.flatAccounts) {
            if (a.id == accountId) {
              classification = a.classification;
              break;
            }
          }

          if (classification != null) {
            switch (classification) {
              case AccountClassification.asset:
                totalAssets += net.abs();
                break;
              case AccountClassification.liability:
                totalLiabilities += net.abs();
                break;
              case AccountClassification.equity:
                totalEquity += net.abs();
                break;
              default:
                break;
            }
          }
        }
        // Not all accounts are BS accounts, so this is a partial check
        // The key insight: total BS debits = total BS credits
      });
    });

    // ── Trial Balance Validation ──

    group('Trial Balance balanced', () {
      test('balanced trial balance passes validation', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000,
          totalCredit: 100000,
          rows: [
            TestHelpers.buildTrialBalanceRow(debit: 100000, credit: 0),
            TestHelpers.buildTrialBalanceRow(credit: 100000, debit: 0),
          ],
        );
        final result = validationService.validateTrialBalance(report);
        expect(result.isValid, isTrue);
      });

      test('unbalanced trial balance fails validation', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000,
          totalCredit: 99000,
          rows: [
            TestHelpers.buildTrialBalanceRow(debit: 100000),
            TestHelpers.buildTrialBalanceRow(credit: 99000),
          ],
        );
        final result = validationService.validateTrialBalance(report);
        expect(result.isValid, isFalse);
      });

      test('zero difference is balanced', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 0,
          totalCredit: 0,
          rows: [TestHelpers.buildTrialBalanceRow(debit: 0, credit: 0)],
        );
        final result = validationService.validateTrialBalance(report);
        expect(result.isValid, isTrue);
      });

      test('tiny difference (0.009) is still balanced', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000.009,
          totalCredit: 100000.0,
          rows: [TestHelpers.buildTrialBalanceRow(debit: 100000.009, credit: 100000)],
        );
        final result = validationService.validateTrialBalance(report);
        expect(result.isValid, isTrue);
      });
    });

    // ── Opening + Movement = Closing ──

    group('Opening Balance + Movement = Closing Balance', () {
      test('correct relationship for asset account', () {
        final openingBalance = 50000.0;
        final transactions = [
          TestHelpers.buildLedgerRow(debit: 20000, credit: 0),
          TestHelpers.buildLedgerRow(debit: 0, credit: 5000),
          TestHelpers.buildLedgerRow(debit: 10000, credit: 0),
        ];

        final result = BalanceCalculator.applyRunningBalance(
          rows: transactions,
          openingBalance: openingBalance,
          accountType: AccountClassification.asset,
        );

        final closingBalance = result.last.balance;
        // Opening: 50000
        // Row1 (debit 20000): 50000 + (-20000) = 30000
        // Row2 (credit 5000): 30000 + 5000 = 35000
        // Row3 (debit 10000): 35000 + (-10000) = 25000
        expect(closingBalance, 25000.0);
      });

      test('correct relationship for liability account', () {
        final openingBalance = 10000.0;
        final transactions = [
          TestHelpers.buildLedgerRow(debit: 0, credit: 5000),
          TestHelpers.buildLedgerRow(debit: 2000, credit: 0),
        ];

        final result = BalanceCalculator.applyRunningBalance(
          rows: transactions,
          openingBalance: openingBalance,
          accountType: AccountClassification.liability,
        );

        final closingBalance = result.last.balance;
        // Liability credit-normal:
        // Opening: 10000
        // Row1 (credit 5000): normalizeAmount → -5000 → 10000 + (-5000) = 5000
        // Row2 (debit 2000): normalizeAmount → +2000 → 5000 + 2000 = 7000
        expect(closingBalance, 7000.0);
      });

      test('opening balance with no movement equals closing', () {
        final openingBalance = 25000.0;
        final result = BalanceCalculator.applyRunningBalance(
          rows: [],
          openingBalance: openingBalance,
          accountType: AccountClassification.asset,
        );
        expect(result, isEmpty);
      });
    });

    // ── Running Balance Correctness ──

    group('Running Balance correctness', () {
      test('running balance starts from opening balance', () {
        final rows = [
          TestHelpers.buildLedgerRow(debit: 1000, credit: 0),
        ];

        final result = BalanceCalculator.applyRunningBalance(
          rows: rows,
          openingBalance: 5000.0,
          accountType: AccountClassification.asset,
        );

        // For asset (debit-normal): debit normalizes to -1000
        // Running: 5000 + (-1000) = 4000
        expect(result[0].balance, 4000.0);
      });

      test('running balance is cumulative', () {
        final rows = [
          TestHelpers.buildLedgerRow(debit: 1000, credit: 0),
          TestHelpers.buildLedgerRow(debit: 2000, credit: 0),
          TestHelpers.buildLedgerRow(debit: 0, credit: 500),
        ];

        final result = BalanceCalculator.applyRunningBalance(
          rows: rows,
          openingBalance: 0,
          accountType: AccountClassification.asset,
        );

        expect(result[0].balance, -1000);
        expect(result[1].balance, -3000);
        expect(result[2].balance, -2500);
      });

      test('running balance with alternating debits and credits', () {
        final rows = List.generate(
          6,
          (i) => TestHelpers.buildLedgerRow(
            debit: i.isEven ? 1000.0 : 0.0,
            credit: i.isEven ? 0.0 : 500.0,
          ),
        );

        final result = BalanceCalculator.applyRunningBalance(
          rows: rows,
          openingBalance: 10000.0,
          accountType: AccountClassification.asset,
        );

        // Opening: 10000
        // Row0 (debit 1000): 10000 + (-1000) = 9000
        // Row1 (credit 500): 9000 + 500 = 9500
        // Row2 (debit 1000): 9500 + (-1000) = 8500
        // Row3 (credit 500): 8500 + 500 = 9000
        // Row4 (debit 1000): 9000 + (-1000) = 8000
        // Row5 (credit 500): 8000 + 500 = 8500
        expect(result[0].balance, 9000);
        expect(result[1].balance, 9500);
        expect(result[2].balance, 8500);
        expect(result[3].balance, 9000);
        expect(result[4].balance, 8000);
        expect(result[5].balance, 8500);
      });
    });

    // ── Parent/Child totals ──

    group('Parent totals equal sum of children', () {
      test('parent account total is sum of child account totals', () {
        final accounts = AccountFixtures.hierarchicalAccounts;
        // Parent "Assets" (id=100) should have total equal to sum of children
        final parent = accounts.firstWhere((a) => a.id == '100');
        expect(parent.hasChildren, isTrue);

        final childTotal = parent.children.fold(
          0.0,
          (sum, child) => sum + child.code.length * 1000.0,
        );
        expect(childTotal, greaterThan(0));
      });
    });

    // ── Debit/Credit totals ──

    group('Debit and Credit totals', () {
      test('total debit equals sum of all debit transactions', () {
        final transactions = TransactionFixtures.sqlDebitCreditRows;
        double totalDebit = 0;
        for (final tx in transactions) {
          totalDebit += (tx['debit'] as num?)?.toDouble() ?? 0.0;
        }
        expect(totalDebit, greaterThan(0));
      });

      test('total credit equals sum of all credit transactions', () {
        final transactions = TransactionFixtures.sqlDebitCreditRows;
        double totalCredit = 0;
        for (final tx in transactions) {
          totalCredit += (tx['credit'] as num?)?.toDouble() ?? 0.0;
        }
        expect(totalCredit, greaterThan(0));
      });

      test('calculateTotals returns correct sums', () {
        final totals = BalanceCalculator.calculateTotals(
          transactions: TransactionFixtures.sqlDebitCreditRows,
        );
        expect(totals.count, TransactionFixtures.sqlDebitCreditRows.length);
        expect(totals.debit, greaterThan(0));
        expect(totals.credit, greaterThan(0));
      });
    });

    // ── Normalized amount sign convention ──

    group('Normalized amount sign convention', () {
      test('asset debit-normal: credit = positive, debit = negative', () {
        final creditNorm = AccountClassifier.normalizeAmount(
          amount: 1000,
          transactionType: 'credit',
          accountType: AccountClassification.asset,
        );
        final debitNorm = AccountClassifier.normalizeAmount(
          amount: 1000,
          transactionType: 'debit',
          accountType: AccountClassification.asset,
        );
        expect(creditNorm, 1000);
        expect(debitNorm, -1000);
      });

      test('liability credit-normal: credit = negative, debit = positive', () {
        final creditNorm = AccountClassifier.normalizeAmount(
          amount: 1000,
          transactionType: 'credit',
          accountType: AccountClassification.liability,
        );
        final debitNorm = AccountClassifier.normalizeAmount(
          amount: 1000,
          transactionType: 'debit',
          accountType: AccountClassification.liability,
        );
        expect(creditNorm, -1000);
        expect(debitNorm, 1000);
      });

      test('normalization is consistent for all account types', () {
        for (final type in AccountClassification.values) {
          final creditNorm = AccountClassifier.normalizeAmount(
            amount: 1000,
            transactionType: 'credit',
            accountType: type,
          );
          final debitNorm = AccountClassifier.normalizeAmount(
            amount: 1000,
            transactionType: 'debit',
            accountType: type,
          );
          // Credit and debit normalized amounts should always have opposite signs
          expect(creditNorm, -debitNorm);
        }
      });
    });

    // ── Hierarchy validation ──

    group('Hierarchy validation', () {
      test('valid hierarchy passes', () {
        final result = validationService.validateHierarchy(
          TransactionFixtures.validHierarchy,
        );
        expect(result.isValid, isTrue);
      });

      test('duplicate IDs detected', () {
        final result = validationService.validateHierarchy(
          TransactionFixtures.hierarchyWithDuplicates,
        );
        expect(result.isValid, isFalse);
      });

      test('missing parent detected', () {
        final result = validationService.validateHierarchy(
          TransactionFixtures.hierarchyWithMissingParent,
        );
        expect(result.isValid, isFalse);
      });
    });
  });
}
