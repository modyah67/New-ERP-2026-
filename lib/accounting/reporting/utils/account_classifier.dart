/// Account Classifier — Maps raw account_type strings to typed enums
///
/// Handles the mapping between database account_type values
/// and the [AccountClassification] enum used throughout the reporting layer.
library;

import '../models/report_models.dart';

class AccountClassifier {
  AccountClassifier._();

  /// Check if an account code belongs to operational waste, spoilage, loss, or cost of activity
  /// that participates in inventory valuation and cost entries.
  static bool isOperationalLossOrCostAccount(String? code) {
    if (code == null) return false;
    final c = code.trim();
    // Intermediary spoilage / waste accounts:
    // 9112 (وسيط هالك وفاقد المحاصيل), 9111 (وسيط هالك مواد التعبئة)
    // Legacy: 2106, 2107, 9106, 9107, 51102, 51103, 51104, 3131, 3132
    if (c == '9112' ||
        c == '9111' ||
        c == '9107' ||
        c == '9106' ||
        c == '2107' ||
        c == '2106' ||
        c == '3131' ||
        c == '3132' ||
        c == '51102' ||
        c == '51103' ||
        c == '51104') {
      return true;
    }
    if (c.startsWith('911') ||
        c.startsWith('313') ||
        c.startsWith('312') ||
        c.startsWith('311')) {
      return true;
    }
    return false;
  }

  /// Map database account_type string to [AccountClassification].
  ///
  /// If [accountCode] is provided and represents an operational loss/spoilage
  /// intermediary account (e.g. 9112 وسيط هالك وفاقد المحاصيل, 9111 وسيط هالك مواد التعبئة),
  /// it is always re-classified under [AccountClassification.expense] (المصروفات والتكاليف / تكلفة النشاط)
  /// so it participates properly in valuation and financial statements.
  static AccountClassification classify(String accountType, {String? accountCode}) {
    if (accountCode != null && isOperationalLossOrCostAccount(accountCode)) {
      return AccountClassification.expense;
    }

    final normalized = accountType.trim().toLowerCase();
    return switch (normalized) {
      'asset' => AccountClassification.asset,
      'liability' => AccountClassification.liability,
      'equity' => AccountClassification.equity,
      'revenue' => AccountClassification.revenue,
      'expense' || 'cogs' => AccountClassification.expense,
      'suspense' => AccountClassification.equity,
      'system' => (accountCode != null && isOperationalLossOrCostAccount(accountCode))
          ? AccountClassification.expense
          : AccountClassification.equity,
      _ => throw ArgumentError('Unknown or invalid account type: "$accountType"'),
    };
  }

  /// Check if the account type is a balance sheet account
  static bool isBalanceSheet(AccountClassification type) {
    return type == AccountClassification.asset ||
        type == AccountClassification.liability ||
        type == AccountClassification.equity;
  }

  /// Check if the account type is an income statement account
  static bool isIncomeStatement(AccountClassification type) {
    return type == AccountClassification.revenue ||
        type == AccountClassification.expense;
  }

  /// Get all balance sheet account types
  static const balanceSheetTypes = [
    AccountClassification.asset,
    AccountClassification.liability,
    AccountClassification.equity,
  ];

  /// Get all income statement account types
  static const incomeStatementTypes = [
    AccountClassification.revenue,
    AccountClassification.expense,
  ];

  /// Determine if a transaction type increases the account balance
  ///
  /// In this system's non-standard convention:
  /// - `type='credit'` = balance INCREASES
  /// - `type='debit'` = balance DECREASES
  ///
  /// This is INVERTED from standard accounting.
  static bool isBalanceIncrease(String transactionType) {
    return transactionType == 'credit';
  }

  /// Normalize a raw transaction amount based on account type and transaction type
  ///
  /// Returns a SIGNED value where:
  /// - Positive = normal debit balance direction
  /// - Negative = normal credit balance direction
  ///
  /// This maps the system's non-standard convention to standard accounting.
  static double normalizeAmount({
    required double amount,
    required String transactionType,
    required AccountClassification accountType,
  }) {
    // System convention: credit = IN (+), debit = OUT (-)
    final isIncoming = transactionType == 'credit';

    // For debit-normal accounts (assets, expenses):
    //   incoming (credit) increases the balance → positive
    //   outgoing (debit) decreases the balance → negative
    // For credit-normal accounts (liabilities, equity, revenue):
    //   incoming (credit) increases the balance → negative (credit side)
    //   outgoing (debit) decreases the balance → positive (debit side)
    if (accountType.isDebitNormal) {
      return isIncoming ? amount : -amount;
    } else {
      return isIncoming ? -amount : amount;
    }
  }

  /// Get the normal balance side for an account type
  ///
  /// Returns 'debit' for asset/expense, 'credit' for liability/equity/revenue
  static String normalBalanceSide(AccountClassification type) {
    return type.isDebitNormal ? 'debit' : 'credit';
  }

  /// Get Arabic label for account type grouping
  static String sectionTitle(AccountClassification type) {
    return switch (type) {
      AccountClassification.asset => 'الأصول',
      AccountClassification.liability => 'الخصوم',
      AccountClassification.equity => 'حقوق الملكية',
      AccountClassification.revenue => 'الإيرادات',
      AccountClassification.expense => 'المصروفات',
    };
  }
}
