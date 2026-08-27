/// Balance Calculator — Computes opening/closing balances and running totals
///
/// Handles the dual debit/credit representation in the transactions table:
/// - SQL-written rows: `debit`/`credit` columns populated, `type`/`amount` are NULL/0
/// - Dart-written rows: `type`/`amount` columns populated, `debit`/`credit` are 0
library;

import '../models/report_models.dart';
import 'account_classifier.dart';

class BalanceCalculator {
  BalanceCalculator._();

  /// Normalize a raw database row into debit/credit values
  ///
  /// Handles both representation patterns:
  /// 1. `debit`/`credit` columns (SQL RPC writes)
  /// 2. `type`/`amount` columns (Dart app writes)
  static (double debit, double credit) normalizeRow(Map<String, dynamic> row) {
    // Try SQL-written pattern first (debit/credit columns)
    final rawDebit = (row['debit'] as num?)?.toDouble() ?? 0.0;
    final rawCredit = (row['credit'] as num?)?.toDouble() ?? 0.0;

    if (rawDebit > 0 || rawCredit > 0) {
      return (rawDebit, rawCredit);
    }

    // Fall back to Dart-written pattern (type/amount columns)
    final type = row['type'] as String? ?? '';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;

    if (type == 'debit') {
      return (amount, 0.0);
    } else if (type == 'credit') {
      return (0.0, amount);
    }

    return (0.0, 0.0);
  }

  /// Calculate balance before a given date for a specific account
  ///
  /// Pre-indexes transactions by account_id for O(1) lookups instead of
  /// O(N) per-account iteration. Hoists classify() outside the inner loop.
  static double calculateBalanceBefore({
    required List<Map<String, dynamic>> transactions,
    required String accountId,
    required String accountType,
    required DateTime beforeDate,
  }) {
    // Pre-index: group transactions by account_id for O(1) lookup
    final indexed = <String, List<Map<String, dynamic>>>{};
    for (final row in transactions) {
      final id = row['account_id']?.toString() ?? '';
      if (id.isNotEmpty) {
        indexed.putIfAbsent(id, () => []);
        indexed[id]!.add(row);
      }
    }

    final accountTransactions = indexed[accountId];
    if (accountTransactions == null || accountTransactions.isEmpty) {
      return 0.0;
    }

    // Classify once outside the loop (accountType is constant per account)
    final classification = AccountClassifier.classify(accountType);

    double balance = 0.0;
    for (final row in accountTransactions) {
      final txDateStr = row['transaction_date']?.toString() ??
          row['transaction_date']?.toString() ??
          '';
      if (txDateStr.isEmpty) continue;

      final txDate = DateTime.tryParse(txDateStr);
      if (txDate == null || !txDate.isBefore(beforeDate)) continue;

      final (debit, credit) = normalizeRow(row);
      final amount = debit > 0 ? debit : credit;
      final type = debit > 0 ? 'debit' : 'credit';

      balance += AccountClassifier.normalizeAmount(
        amount: amount,
        transactionType: type,
        accountType: classification,
      );
    }

    return balance;
  }

  /// Calculate totals (debit/credit sums) for a set of transactions
  static ({double debit, double credit, int count}) calculateTotals({
    required List<Map<String, dynamic>> transactions,
    String? accountId,
  }) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    int count = 0;

    for (final row in transactions) {
      if (accountId != null) {
        final rowAccountId = row['account_id']?.toString() ?? '';
        if (rowAccountId != accountId) continue;
      }

      final (debit, credit) = normalizeRow(row);
      totalDebit += debit;
      totalCredit += credit;
      count++;
    }

    return (debit: totalDebit, credit: totalCredit, count: count);
  }

  /// Calculate running balance for a series of ledger rows
  ///
  /// Assumes rows are already sorted by date ascending.
  /// [openingBalance] is the balance before the first row.
  static List<LedgerRow> applyRunningBalance({
    required List<LedgerRow> rows,
    required double openingBalance,
    required AccountClassification accountType,
  }) {
    double running = openingBalance;
    final result = <LedgerRow>[];

    for (final row in rows) {
      final normalizedDebit = AccountClassifier.normalizeAmount(
        amount: row.debit,
        transactionType: 'debit',
        accountType: accountType,
      );
      final normalizedCredit = AccountClassifier.normalizeAmount(
        amount: row.credit,
        transactionType: 'credit',
        accountType: accountType,
      );

      running += normalizedDebit + normalizedCredit;

      result.add(LedgerRow(
        id: row.id,
        date: row.date,
        entryNumber: row.entryNumber,
        accountCode: row.accountCode,
        accountName: row.accountName,
        description: row.description,
        debit: row.debit,
        credit: row.credit,
        balance: running,
        entityType: row.entityType,
        entityId: row.entityId,
        entityName: row.entityName,
        referenceType: row.referenceType,
        referenceId: row.referenceId,
        currency: row.currency,
        exchangeRate: row.exchangeRate,
      ));
    }

    return result;
  }
}
