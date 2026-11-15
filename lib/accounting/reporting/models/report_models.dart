/// READ-ONLY Accounting Reporting Foundation — Immutable Models
///
/// These models are the single source of truth for ALL financial reports.
/// They are never modified after creation.
library;

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────

enum AccountClassification {
  asset,
  liability,
  equity,
  revenue,
  expense;

  String get labelAr => switch (this) {
        AccountClassification.asset => 'أصول',
        AccountClassification.liability => 'خصوم',
        AccountClassification.equity => 'حقوق الملكية',
        AccountClassification.revenue => 'إيرادات',
        AccountClassification.expense => 'مصروفات',
      };

  String get labelEn => name;

  bool get isDebitNormal => this == AccountClassification.asset ||
      this == AccountClassification.expense;

  bool get isCreditNormal => this == AccountClassification.liability ||
      this == AccountClassification.equity ||
      this == AccountClassification.revenue;
}

// ─────────────────────────────────────────────
// ACCOUNT HIERARCHY
// ─────────────────────────────────────────────

@immutable
class AccountHierarchy {
  final String id;
  final String code;
  final String name;
  final String nameAr;
  final AccountClassification classification;
  final String? parentId;
  final int depth;
  final List<AccountHierarchy> children;

  const AccountHierarchy({
    required this.id,
    required this.code,
    required this.name,
    required this.nameAr,
    required this.classification,
    this.parentId,
    this.depth = 0,
    this.children = const [],
  });

  AccountHierarchy copyWith({
    String? id,
    String? code,
    String? name,
    String? nameAr,
    AccountClassification? classification,
    String? parentId,
    int? depth,
    List<AccountHierarchy>? children,
  }) {
    return AccountHierarchy(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      classification: classification ?? this.classification,
      parentId: parentId ?? this.parentId,
      depth: depth ?? this.depth,
      children: children ?? this.children,
    );
  }

  bool get isRoot => parentId == null;
  bool get hasChildren => children.isNotEmpty;
}

// ─────────────────────────────────────────────
// ACCOUNT BALANCE REPORT
// ─────────────────────────────────────────────

@immutable
class AccountBalanceReport {
  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountNameAr;
  final AccountClassification classification;
  final double openingDebit;
  final double openingCredit;
  final double periodDebit;
  final double periodCredit;
  final double closingDebit;
  final double closingCredit;

  const AccountBalanceReport({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountNameAr,
    required this.classification,
    this.openingDebit = 0.0,
    this.openingCredit = 0.0,
    this.periodDebit = 0.0,
    this.periodCredit = 0.0,
    this.closingDebit = 0.0,
    this.closingCredit = 0.0,
  });

  /// Net balance: positive = debit balance, negative = credit balance
  double get netBalance => (closingDebit - closingCredit);

  /// Normal balance direction based on account type
  bool get hasDebitBalance => classification.isDebitNormal
      ? netBalance >= 0
      : netBalance < 0;

  bool get hasCreditBalance => !hasDebitBalance;

  double get displayBalance => hasDebitBalance ? netBalance : -netBalance;

  AccountBalanceReport copyWith({
    String? accountId,
    String? accountCode,
    String? accountName,
    String? accountNameAr,
    AccountClassification? classification,
    double? openingDebit,
    double? openingCredit,
    double? periodDebit,
    double? periodCredit,
    double? closingDebit,
    double? closingCredit,
  }) {
    return AccountBalanceReport(
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      accountNameAr: accountNameAr ?? this.accountNameAr,
      classification: classification ?? this.classification,
      openingDebit: openingDebit ?? this.openingDebit,
      openingCredit: openingCredit ?? this.openingCredit,
      periodDebit: periodDebit ?? this.periodDebit,
      periodCredit: periodCredit ?? this.periodCredit,
      closingDebit: closingDebit ?? this.closingDebit,
      closingCredit: closingCredit ?? this.closingCredit,
    );
  }
}

// ─────────────────────────────────────────────
// TRIAL BALANCE
// ─────────────────────────────────────────────

@immutable
class TrialBalanceRow {
  final String accountCode;
  final String accountName;
  final String accountNameAr;
  final AccountClassification classification;
  final double debit;
  final double credit;

  const TrialBalanceRow({
    required this.accountCode,
    required this.accountName,
    required this.accountNameAr,
    required this.classification,
    required this.debit,
    required this.credit,
  });

  double get balance => debit - credit;
  bool get isDebitBalance => balance >= 0;
}

@immutable
class TrialBalanceReport {
  final DateTime asOfDate;
  final List<TrialBalanceRow> rows;
  final double totalDebit;
  final double totalCredit;
  final DateTime generatedAt;
  final String? currencyFilter;

  const TrialBalanceReport({
    required this.asOfDate,
    required this.rows,
    required this.totalDebit,
    required this.totalCredit,
    required this.generatedAt,
    this.currencyFilter,
  });

  bool get isBalanced {
    return (totalDebit - totalCredit).abs() < 0.01;
  }
  double get difference => totalDebit - totalCredit;

  /// Grouped by account classification
  Map<AccountClassification, List<TrialBalanceRow>> get groupedByType {
    final grouped = <AccountClassification, List<TrialBalanceRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.classification, () => []).add(row);
    }
    return grouped;
  }
}

// ─────────────────────────────────────────────
// GENERAL LEDGER
// ─────────────────────────────────────────────

@immutable
class LedgerRow {
  final String? id;
  final DateTime date;
  final String? entryNumber;
  final String accountCode;
  final String accountName;
  final String? description;
  final double debit;
  final double credit;
  final double balance;
  final String? entityType;
  final String? entityId;
  final String? entityName;
  final String? referenceType;
  final String? referenceId;
  final String? costCenterId;
  final String? costCenterName;
  final String? currency;
  final double? exchangeRate;

  const LedgerRow({
    this.id,
    required this.date,
    this.entryNumber,
    required this.accountCode,
    required this.accountName,
    this.costCenterId,
    this.costCenterName,
    this.description,
    this.debit = 0.0,
    this.credit = 0.0,
    this.balance = 0.0,
    this.entityType,
    this.entityId,
    this.entityName,
    this.referenceType,
    this.referenceId,
    this.currency,
    this.exchangeRate,
  });

  double get netAmount => debit - credit;
}

@immutable
class LedgerReport {
  final DateTime fromDate;
  final DateTime toDate;
  final String? accountId;
  final List<LedgerRow> rows;
  final double openingBalance;
  final double closingBalance;
  final double totalDebit;
  final double totalCredit;
  final int transactionCount;
  final DateTime generatedAt;
  final String? currencyFilter;

  const LedgerReport({
    required this.fromDate,
    required this.toDate,
    this.accountId,
    required this.rows,
    required this.openingBalance,
    required this.closingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.transactionCount,
    required this.generatedAt,
    this.currencyFilter,
  });

  bool get isBalanced {
    if (accountId != null) return true;
    if (currencyFilter != null && currencyFilter!.isNotEmpty) return true;
    return (totalDebit - totalCredit).abs() < 0.01;
  }
}

// ─────────────────────────────────────────────
// BALANCE SHEET
// ─────────────────────────────────────────────

@immutable
class BalanceSheetLine {
  final String accountCode;
  final String accountName;
  final String accountNameAr;
  final double amount;

  const BalanceSheetLine({
    required this.accountCode,
    required this.accountName,
    required this.accountNameAr,
    required this.amount,
  });
}

@immutable
class BalanceSheetSection {
  final String title;
  final String titleAr;
  final List<BalanceSheetLine> lines;
  final double total;

  const BalanceSheetSection({
    required this.title,
    required this.titleAr,
    required this.lines,
    required this.total,
  });
}

@immutable
class BalanceSheetReport {
  final DateTime asOfDate;
  final BalanceSheetSection assets;
  final BalanceSheetSection liabilities;
  final BalanceSheetSection equity;
  final double totalAssets;
  final double totalLiabilitiesAndEquity;
  final DateTime generatedAt;
  final String? currencyFilter;

  const BalanceSheetReport({
    required this.asOfDate,
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totalAssets,
    required this.totalLiabilitiesAndEquity,
    required this.generatedAt,
    this.currencyFilter,
  });

  bool get isBalanced => (totalAssets - totalLiabilitiesAndEquity).abs() < 0.01;
  double get difference => totalAssets - totalLiabilitiesAndEquity;
}

// ─────────────────────────────────────────────
// INCOME STATEMENT
// ─────────────────────────────────────────────

@immutable
class IncomeStatementLine {
  final String accountCode;
  final String accountName;
  final String accountNameAr;
  final double amount;

  const IncomeStatementLine({
    required this.accountCode,
    required this.accountName,
    required this.accountNameAr,
    required this.amount,
  });
}

@immutable
class IncomeStatementSection {
  final String title;
  final String titleAr;
  final List<IncomeStatementLine> lines;
  final double total;

  const IncomeStatementSection({
    required this.title,
    required this.titleAr,
    required this.lines,
    required this.total,
  });
}

@immutable
class IncomeStatementReport {
  final DateTime fromDate;
  final DateTime toDate;
  final IncomeStatementSection revenue;
  final IncomeStatementSection costOfGoodsSold;
  final IncomeStatementSection operatingExpenses;
  final double grossProfit;
  final double operatingIncome;
  final double netIncome;
  final DateTime generatedAt;

  const IncomeStatementReport({
    required this.fromDate,
    required this.toDate,
    required this.revenue,
    required this.costOfGoodsSold,
    required this.operatingExpenses,
    required this.grossProfit,
    required this.operatingIncome,
    required this.netIncome,
    required this.generatedAt,
  });
}

// ─────────────────────────────────────────────
// CASH FLOW STATEMENT
// ─────────────────────────────────────────────

@immutable
class CashFlowLine {
  final String description;
  final String descriptionAr;
  final double amount;

  const CashFlowLine({
    required this.description,
    required this.descriptionAr,
    required this.amount,
  });
}

@immutable
class CashFlowSection {
  final String title;
  final String titleAr;
  final List<CashFlowLine> lines;
  final double total;

  const CashFlowSection({
    required this.title,
    required this.titleAr,
    required this.lines,
    required this.total,
  });
}

@immutable
class CashFlowReport {
  final DateTime fromDate;
  final DateTime toDate;
  final CashFlowSection operating;
  final CashFlowSection investing;
  final CashFlowSection financing;
  final double netCashFromOperating;
  final double netCashFromInvesting;
  final double netCashFromFinancing;
  final double netChangeInCash;
  final DateTime generatedAt;

  const CashFlowReport({
    required this.fromDate,
    required this.toDate,
    required this.operating,
    required this.investing,
    required this.financing,
    required this.netCashFromOperating,
    required this.netCashFromInvesting,
    required this.netCashFromFinancing,
    required this.netChangeInCash,
    required this.generatedAt,
  });
}

// ─────────────────────────────────────────────
// CURRENCY DISPLAY
// ─────────────────────────────────────────────

@immutable
class CurrencyDisplay {
  final String currency;
  final double amount;
  final double exchangeRate;
  final double amountInEgp;

  const CurrencyDisplay({
    required this.currency,
    required this.amount,
    required this.exchangeRate,
    required this.amountInEgp,
  });

  String get displayLabel => '$currency ${amount.toStringAsFixed(2)}';
  String get displayLabelEgp => 'EGP ${amountInEgp.toStringAsFixed(2)}';
}

@immutable
class MultiCurrencySummary {
  final List<CurrencyDisplay> currencies;
  final double totalInEgp;

  const MultiCurrencySummary({
    required this.currencies,
    required this.totalInEgp,
  });
}

// ─────────────────────────────────────────────
// REPORT FILTER
// ─────────────────────────────────────────────

@immutable
class ReportFilter {
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? accountId;
  final AccountClassification? accountType;
  final String? entityType;
  final String? entityId;
  final String? currency;
  final String? searchQuery;
  final int? limit;
  final int? offset;

  const ReportFilter({
    this.fromDate,
    this.toDate,
    this.accountId,
    this.accountType,
    this.entityType,
    this.entityId,
    this.currency,
    this.searchQuery,
    this.limit,
    this.offset,
  });

  static ReportFilter defaultFilter() {
    final now = DateTime.now();
    return ReportFilter(
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
    );
  }

  ReportFilter copyWith({
    DateTime? fromDate,
    DateTime? toDate,
    String? accountId,
    AccountClassification? accountType,
    String? entityType,
    String? entityId,
    String? currency,
    String? searchQuery,
    int? limit,
    int? offset,
    bool clearFromDate = false,
    bool clearToDate = false,
    bool clearAccountId = false,
    bool clearAccountType = false,
    bool clearEntityType = false,
    bool clearEntityId = false,
    bool clearCurrency = false,
    bool clearSearchQuery = false,
  }) {
    return ReportFilter(
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      accountType:
          clearAccountType ? null : (accountType ?? this.accountType),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      entityId: clearEntityId ? null : (entityId ?? this.entityId),
      currency: clearCurrency ? null : (currency ?? this.currency),
      searchQuery:
          clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  String? get formattedFromDate =>
      fromDate != null ? _formatDate(fromDate!) : null;
  String? get formattedToDate =>
      toDate != null ? _formatDate(toDate!) : null;

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
// VALIDATION RESULT
// ─────────────────────────────────────────────

@immutable
class ValidationResult {
  final bool isValid;
  final List<ValidationIssue> issues;
  final DateTime validatedAt;

  const ValidationResult({
    required this.isValid,
    required this.issues,
    required this.validatedAt,
  });

  factory ValidationResult.success() {
    return ValidationResult(
      isValid: true,
      issues: const [],
      validatedAt: DateTime.now(),
    );
  }

  factory ValidationResult.failure(List<ValidationIssue> issues) {
    return ValidationResult(
      isValid: false,
      issues: issues,
      validatedAt: DateTime.now(),
    );
  }

  int get errorCount =>
      issues.where((i) => i.severity == ValidationSeverity.error).length;
  int get warningCount =>
      issues.where((i) => i.severity == ValidationSeverity.warning).length;
}

@immutable
class ValidationIssue {
  final String code;
  final String message;
  final String messageAr;
  final ValidationSeverity severity;

  const ValidationIssue({
    required this.code,
    required this.message,
    required this.messageAr,
    required this.severity,
  });
}

enum ValidationSeverity {
  error,
  warning,
  info;
}

// ─────────────────────────────────────────────
// ACCOUNT STATEMENT (per-account detail)
// ─────────────────────────────────────────────

@immutable
class AccountStatementRow {
  final DateTime date;
  final String? description;
  final double debit;
  final double credit;
  final double runningBalance;
  final String? referenceType;
  final String? referenceId;
  final String? entityType;
  final String? entityId;

  const AccountStatementRow({
    required this.date,
    this.description,
    this.debit = 0.0,
    this.credit = 0.0,
    this.runningBalance = 0.0,
    this.referenceType,
    this.referenceId,
    this.entityType,
    this.entityId,
  });
}

@immutable
class AccountStatementReport {
  final String accountId;
  final String accountCode;
  final String accountName;
  final DateTime fromDate;
  final DateTime toDate;
  final double openingBalance;
  final List<AccountStatementRow> rows;
  final double closingBalance;
  final double totalDebit;
  final double totalCredit;
  final DateTime generatedAt;

  const AccountStatementReport({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.fromDate,
    required this.toDate,
    required this.openingBalance,
    required this.rows,
    required this.closingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.generatedAt,
  });
}
