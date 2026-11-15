import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/utils/account_classifier.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

void main() {
  group('AccountClassifier', () {
    group('classify', () {
      test('classifies asset correctly', () {
        expect(AccountClassifier.classify('asset'), AccountClassification.asset);
      });

      test('classifies liability correctly', () {
        expect(AccountClassifier.classify('liability'), AccountClassification.liability);
      });

      test('classifies equity correctly', () {
        expect(AccountClassifier.classify('equity'), AccountClassification.equity);
      });

      test('classifies revenue correctly', () {
        expect(AccountClassifier.classify('revenue'), AccountClassification.revenue);
      });

      test('classifies expense correctly', () {
        expect(AccountClassifier.classify('expense'), AccountClassification.expense);
      });

      test('handles case insensitivity', () {
        expect(AccountClassifier.classify('ASSET'), AccountClassification.asset);
        expect(AccountClassifier.classify('Liability'), AccountClassification.liability);
        expect(AccountClassifier.classify('EQUITY'), AccountClassification.equity);
      });

      test('throws for unknown account type', () {
        expect(
          () => AccountClassifier.classify('unknown'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for empty string', () {
        expect(
          () => AccountClassifier.classify(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('reclassifies 9112 and 9111 operational loss accounts to expense', () {
        expect(
          AccountClassifier.classify('system', accountCode: '9112'),
          AccountClassification.expense,
        );
        expect(
          AccountClassifier.classify('system', accountCode: '9111'),
          AccountClassification.expense,
        );
        expect(
          AccountClassifier.classify('unknown', accountCode: '9112'),
          AccountClassification.expense,
        );
      });

      test('identifies operational loss and cost accounts correctly', () {
        expect(AccountClassifier.isOperationalLossOrCostAccount('9112'), isTrue);
        expect(AccountClassifier.isOperationalLossOrCostAccount('9111'), isTrue);
        expect(AccountClassifier.isOperationalLossOrCostAccount('3131'), isTrue);
        expect(AccountClassifier.isOperationalLossOrCostAccount('1000'), isFalse);
        expect(AccountClassifier.isOperationalLossOrCostAccount('9000'), isFalse);
        expect(AccountClassifier.isOperationalLossOrCostAccount(null), isFalse);
      });
    });

    group('isBalanceSheet', () {
      test('returns true for asset', () {
        expect(AccountClassifier.isBalanceSheet(AccountClassification.asset), isTrue);
      });

      test('returns true for liability', () {
        expect(AccountClassifier.isBalanceSheet(AccountClassification.liability), isTrue);
      });

      test('returns true for equity', () {
        expect(AccountClassifier.isBalanceSheet(AccountClassification.equity), isTrue);
      });

      test('returns false for revenue', () {
        expect(AccountClassifier.isBalanceSheet(AccountClassification.revenue), isFalse);
      });

      test('returns false for expense', () {
        expect(AccountClassifier.isBalanceSheet(AccountClassification.expense), isFalse);
      });
    });

    group('isIncomeStatement', () {
      test('returns true for revenue', () {
        expect(AccountClassifier.isIncomeStatement(AccountClassification.revenue), isTrue);
      });

      test('returns true for expense', () {
        expect(AccountClassifier.isIncomeStatement(AccountClassification.expense), isTrue);
      });

      test('returns false for asset', () {
        expect(AccountClassifier.isIncomeStatement(AccountClassification.asset), isFalse);
      });

      test('returns false for liability', () {
        expect(AccountClassifier.isIncomeStatement(AccountClassification.liability), isFalse);
      });

      test('returns false for equity', () {
        expect(AccountClassifier.isIncomeStatement(AccountClassification.equity), isFalse);
      });
    });

    group('isBalanceIncrease', () {
      test('returns true for credit', () {
        expect(AccountClassifier.isBalanceIncrease('credit'), isTrue);
      });

      test('returns false for debit', () {
        expect(AccountClassifier.isBalanceIncrease('debit'), isFalse);
      });

      test('returns false for unknown type', () {
        expect(AccountClassifier.isBalanceIncrease('unknown'), isFalse);
      });
    });

    group('normalizeAmount', () {
      test('asset debit-normal: credit increases balance', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 1000.0,
          transactionType: 'credit',
          accountType: AccountClassification.asset,
        );
        expect(result, 1000.0);
      });

      test('asset debit-normal: debit decreases balance', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 1000.0,
          transactionType: 'debit',
          accountType: AccountClassification.asset,
        );
        expect(result, -1000.0);
      });

      test('liability credit-normal: credit increases balance (negative sign)', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 1000.0,
          transactionType: 'credit',
          accountType: AccountClassification.liability,
        );
        expect(result, -1000.0);
      });

      test('liability credit-normal: debit decreases balance (positive sign)', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 1000.0,
          transactionType: 'debit',
          accountType: AccountClassification.liability,
        );
        expect(result, 1000.0);
      });

      test('expense debit-normal behaves like asset', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 500.0,
          transactionType: 'credit',
          accountType: AccountClassification.expense,
        );
        expect(result, 500.0);
      });

      test('revenue credit-normal behaves like liability', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 500.0,
          transactionType: 'credit',
          accountType: AccountClassification.revenue,
        );
        expect(result, -500.0);
      });

      test('equity credit-normal behaves like liability', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 500.0,
          transactionType: 'debit',
          accountType: AccountClassification.equity,
        );
        expect(result, 500.0);
      });

      test('zero amount returns zero', () {
        final result = AccountClassifier.normalizeAmount(
          amount: 0.0,
          transactionType: 'debit',
          accountType: AccountClassification.asset,
        );
        expect(result, 0.0);
      });
    });

    group('normalBalanceSide', () {
      test('asset returns debit', () {
        expect(AccountClassifier.normalBalanceSide(AccountClassification.asset), 'debit');
      });

      test('expense returns debit', () {
        expect(AccountClassifier.normalBalanceSide(AccountClassification.expense), 'debit');
      });

      test('liability returns credit', () {
        expect(AccountClassifier.normalBalanceSide(AccountClassification.liability), 'credit');
      });

      test('equity returns credit', () {
        expect(AccountClassifier.normalBalanceSide(AccountClassification.equity), 'credit');
      });

      test('revenue returns credit', () {
        expect(AccountClassifier.normalBalanceSide(AccountClassification.revenue), 'credit');
      });
    });

    group('sectionTitle', () {
      test('returns correct Arabic for asset', () {
        expect(AccountClassifier.sectionTitle(AccountClassification.asset), 'الأصول');
      });

      test('returns correct Arabic for liability', () {
        expect(AccountClassifier.sectionTitle(AccountClassification.liability), 'الخصوم');
      });

      test('returns correct Arabic for equity', () {
        expect(AccountClassifier.sectionTitle(AccountClassification.equity), 'حقوق الملكية');
      });

      test('returns correct Arabic for revenue', () {
        expect(AccountClassifier.sectionTitle(AccountClassification.revenue), 'الإيرادات');
      });

      test('returns correct Arabic for expense', () {
        expect(AccountClassifier.sectionTitle(AccountClassification.expense), 'المصروفات');
      });
    });

    group('balanceSheetTypes', () {
      test('contains asset, liability, equity', () {
        expect(AccountClassifier.balanceSheetTypes, contains(AccountClassification.asset));
        expect(AccountClassifier.balanceSheetTypes, contains(AccountClassification.liability));
        expect(AccountClassifier.balanceSheetTypes, contains(AccountClassification.equity));
        expect(AccountClassifier.balanceSheetTypes.length, 3);
      });
    });

    group('incomeStatementTypes', () {
      test('contains revenue, expense', () {
        expect(AccountClassifier.incomeStatementTypes, contains(AccountClassification.revenue));
        expect(AccountClassifier.incomeStatementTypes, contains(AccountClassification.expense));
        expect(AccountClassifier.incomeStatementTypes.length, 2);
      });
    });

    group('AccountClassification enum', () {
      test('isDebitNormal for asset', () {
        expect(AccountClassification.asset.isDebitNormal, isTrue);
      });

      test('isDebitNormal for expense', () {
        expect(AccountClassification.expense.isDebitNormal, isTrue);
      });

      test('isCreditNormal for liability', () {
        expect(AccountClassification.liability.isCreditNormal, isTrue);
      });

      test('isCreditNormal for equity', () {
        expect(AccountClassification.equity.isCreditNormal, isTrue);
      });

      test('isCreditNormal for revenue', () {
        expect(AccountClassification.revenue.isCreditNormal, isTrue);
      });

      test('labelAr returns Arabic', () {
        expect(AccountClassification.asset.labelAr, 'أصول');
        expect(AccountClassification.liability.labelAr, 'خصوم');
        expect(AccountClassification.equity.labelAr, 'حقوق الملكية');
        expect(AccountClassification.revenue.labelAr, 'إيرادات');
        expect(AccountClassification.expense.labelAr, 'مصروفات');
      });

      test('labelEn returns enum name', () {
        expect(AccountClassification.asset.labelEn, 'asset');
        expect(AccountClassification.liability.labelEn, 'liability');
      });
    });
  });
}
