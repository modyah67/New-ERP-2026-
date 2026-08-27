import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/services/report_validation_service.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

import '../../fixtures/account_fixtures.dart';
import '../../fixtures/transaction_fixtures.dart' as tx_fixtures;
import '../../mocks/mock_report_dao.dart';
import '../../helpers/test_helpers.dart';

void main() {
  group('ReportValidationService', () {
    late MockReportDao mockDao;
    late ReportValidationService service;

    setUp(() async {
      await MockReportDao.ensureInitialized();
      mockDao = MockReportDao();
      service = ReportValidationService(mockDao);
    });

    group('validateTrialBalance', () {
      test('returns success for balanced trial balance', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000.0,
          totalCredit: 100000.0,
          rows: [
            TestHelpers.buildTrialBalanceRow(debit: 100000, credit: 0),
            TestHelpers.buildTrialBalanceRow(credit: 100000, debit: 0),
          ],
        );
        final result = service.validateTrialBalance(report);
        expect(result.isValid, isTrue);
        expect(result.issues, isEmpty);
      });

      test('returns error for unbalanced trial balance', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000.0,
          totalCredit: 95000.0,
          rows: [
            TestHelpers.buildTrialBalanceRow(debit: 100000, credit: 0),
            TestHelpers.buildTrialBalanceRow(credit: 95000, debit: 0),
          ],
        );
        final result = service.validateTrialBalance(report);
        expect(result.isValid, isFalse);
        expect(result.issues.length, 1);
        expect(result.issues[0].code, 'TB_UNBALANCED');
        expect(result.issues[0].severity, ValidationSeverity.error);
      });

      test('returns warning for empty trial balance', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 0.0,
          totalCredit: 0.0,
          rows: [],
        );
        final result = service.validateTrialBalance(report);
        expect(result.isValid, isFalse);
        expect(result.issues.length, 1);
        expect(result.issues[0].code, 'TB_EMPTY');
        expect(result.issues[0].severity, ValidationSeverity.warning);
      });

      test('handles small difference (< 0.01) as balanced', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000.0,
          totalCredit: 100000.005,
          rows: [TestHelpers.buildTrialBalanceRow(debit: 100000.0, credit: 100000.005)],
        );
        final result = service.validateTrialBalance(report);
        expect(result.isValid, isTrue);
      });

      test('handles exact difference of 0.01 as unbalanced', () {
        final report = TestHelpers.buildTrialBalanceReport(
          totalDebit: 100000.0,
          totalCredit: 99999.99,
        );
        final result = service.validateTrialBalance(report);
        expect(result.isValid, isFalse);
      });
    });

    group('validateBalanceSheet', () {
      test('returns success for balanced balance sheet', () {
        final report = TestHelpers.buildBalanceSheetReport(
          totalAssets: 200000.0,
          totalLiabilities: 120000.0,
          totalEquity: 80000.0,
        );
        final result = service.validateBalanceSheet(report);
        expect(result.isValid, isTrue);
      });

      test('returns error for unbalanced balance sheet', () {
        final report = TestHelpers.buildBalanceSheetReport(
          totalAssets: 200000.0,
          totalLiabilities: 100000.0,
          totalEquity: 80000.0,
        );
        final result = service.validateBalanceSheet(report);
        expect(result.isValid, isFalse);
        expect(result.issues.length, 1);
        expect(result.issues[0].code, 'BS_UNBALANCED');
      });

      test('handles zero balances as balanced', () {
        final report = TestHelpers.buildBalanceSheetReport(
          totalAssets: 0.0,
          totalLiabilities: 0.0,
          totalEquity: 0.0,
        );
        final result = service.validateBalanceSheet(report);
        expect(result.isValid, isTrue);
      });
    });

    group('isBalanced', () {
      test('returns success for balanced amounts', () {
        final result = service.isBalanced(10000.0, 10000.0);
        expect(result.isValid, isTrue);
      });

      test('returns error for unbalanced amounts', () {
        final result = service.isBalanced(10000.0, 9500.0);
        expect(result.isValid, isFalse);
        expect(result.issues.length, 1);
        expect(result.issues[0].code, 'NOT_BALANCED');
      });

      test('handles difference of 0.009 as balanced', () {
        final result = service.isBalanced(10000.0, 10000.009);
        expect(result.isValid, isTrue);
      });

      test('handles negative amounts', () {
        final result = service.isBalanced(-5000.0, -5000.0);
        expect(result.isValid, isTrue);
      });
    });

    group('validateHierarchy', () {
      test('returns success for valid hierarchy', () {
        final result = service.validateHierarchy(tx_fixtures.TransactionFixtures.validHierarchy);
        expect(result.isValid, isTrue);
      });

      test('detects duplicate account IDs', () {
        final result = service.validateHierarchy(tx_fixtures.TransactionFixtures.hierarchyWithDuplicates);
        expect(result.isValid, isFalse);
        expect(result.issues.any((i) => i.code == 'DUPLICATE_ACCOUNT'), isTrue);
      });

      test('detects missing parent references', () {
        final result = service.validateHierarchy(tx_fixtures.TransactionFixtures.hierarchyWithMissingParent);
        expect(result.isValid, isFalse);
        expect(result.issues.any((i) => i.code == 'MISSING_PARENT'), isTrue);
      });

      test('returns success for empty hierarchy', () {
        final result = service.validateHierarchy([]);
        expect(result.isValid, isTrue);
      });

      test('returns success for single root account', () {
        final result = service.validateHierarchy([
          tx_fixtures.TransactionFixtures.validHierarchy.first,
        ]);
        expect(result.isValid, isTrue);
      });
    });

    group('validateAccountBalances', () {
      test('returns success when stored balances match computed', () async {
        mockDao.storedBalancesToReturn = {
          '1': 40000.0,
          '2': 10000.0,
        };
        mockDao.accountTotalsToReturn = [
          {'account_id': '1', 'debit': 50000.0, 'credit': 10000.0},
          {'account_id': '2', 'debit': 25000.0, 'credit': 15000.0},
        ];

        final result = await service.validateAccountBalances();
        expect(result.isValid, isTrue);
      });

      test('detects balance drift', () async {
        mockDao.storedBalancesToReturn = {
          '1': 30000.0, // Stored
        };
        mockDao.accountTotalsToReturn = [
          {'account_id': '1', 'debit': 50000.0, 'credit': 10000.0}, // Computed: 40000
        ];

        final result = await service.validateAccountBalances();
        expect(result.isValid, isFalse);
        expect(result.issues.any((i) => i.code == 'BALANCE_DRIFT'), isTrue);
      });

      test('handles DAO exception gracefully', () async {
        mockDao.exceptionToThrow = Exception('DB connection failed');

        final result = await service.validateAccountBalances();
        expect(result.isValid, isFalse);
        expect(result.issues.any((i) => i.code == 'VALIDATION_ERROR'), isTrue);
      });

      test('returns success when stored balances empty', () async {
        mockDao.storedBalancesToReturn = {};
        mockDao.accountTotalsToReturn = [];

        final result = await service.validateAccountBalances();
        expect(result.isValid, isTrue);
      });
    });
  });

  group('ValidationResult', () {
    test('success factory creates valid result', () {
      final result = ValidationResult.success();
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('failure factory creates invalid result', () {
      final result = ValidationResult.failure([
        const ValidationIssue(
          code: 'TEST',
          message: 'test error',
          messageAr: 'خطأ تجريبي',
          severity: ValidationSeverity.error,
        ),
      ]);
      expect(result.isValid, isFalse);
      expect(result.issues.length, 1);
    });

    test('errorCount counts errors', () {
      final result = ValidationResult.failure([
        const ValidationIssue(
          code: 'E1',
          message: 'error 1',
          messageAr: 'خطأ 1',
          severity: ValidationSeverity.error,
        ),
        const ValidationIssue(
          code: 'E2',
          message: 'error 2',
          messageAr: 'خطأ 2',
          severity: ValidationSeverity.error,
        ),
        const ValidationIssue(
          code: 'W1',
          message: 'warning 1',
          messageAr: 'تحذير 1',
          severity: ValidationSeverity.warning,
        ),
      ]);
      expect(result.errorCount, 2);
    });

    test('warningCount counts warnings', () {
      final result = ValidationResult.failure([
        const ValidationIssue(
          code: 'W1',
          message: 'warning 1',
          messageAr: 'تحذير 1',
          severity: ValidationSeverity.warning,
        ),
        const ValidationIssue(
          code: 'W2',
          message: 'warning 2',
          messageAr: 'تحذير 2',
          severity: ValidationSeverity.warning,
        ),
      ]);
      expect(result.warningCount, 2);
    });
  });
}
