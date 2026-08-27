import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

class TestHelpers {
  TestHelpers._();

  // ── Widget helpers ──────────────────────────

  static Widget wrapInApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  static Widget wrapInAppWithTheme(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: child,
      ),
    );
  }

  static Widget wrapInSizedBox(Widget child, {double width = 1200, double height = 800}) {
    return SizedBox(
      width: width,
      height: height,
      child: child,
    );
  }

  // ── Model builders ──────────────────────────

  static TrialBalanceRow buildTrialBalanceRow({
    String accountCode = '1000',
    String accountName = 'Cash',
    String accountNameAr = 'النقدية',
    AccountClassification classification = AccountClassification.asset,
    double debit = 0.0,
    double credit = 0.0,
  }) {
    return TrialBalanceRow(
      accountCode: accountCode,
      accountName: accountName,
      accountNameAr: accountNameAr,
      classification: classification,
      debit: debit,
      credit: credit,
    );
  }

  static TrialBalanceReport buildTrialBalanceReport({
    DateTime? asOfDate,
    List<TrialBalanceRow>? rows,
    double totalDebit = 0.0,
    double totalCredit = 0.0,
  }) {
    return TrialBalanceReport(
      asOfDate: asOfDate ?? DateTime(2025, 12, 31),
      rows: rows ?? [],
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      generatedAt: DateTime.now(),
    );
  }

  static BalanceSheetReport buildBalanceSheetReport({
    DateTime? asOfDate,
    double totalAssets = 0.0,
    double totalLiabilities = 0.0,
    double totalEquity = 0.0,
  }) {
    return BalanceSheetReport(
      asOfDate: asOfDate ?? DateTime(2025, 12, 31),
      assets: BalanceSheetSection(
        title: 'Assets',
        titleAr: 'الأصول',
        lines: [],
        total: totalAssets,
      ),
      liabilities: BalanceSheetSection(
        title: 'Liabilities',
        titleAr: 'الخصوم',
        lines: [],
        total: totalLiabilities,
      ),
      equity: BalanceSheetSection(
        title: 'Equity',
        titleAr: 'حقوق الملكية',
        lines: [],
        total: totalEquity,
      ),
      totalAssets: totalAssets,
      totalLiabilitiesAndEquity: totalLiabilities + totalEquity,
      generatedAt: DateTime.now(),
    );
  }

  static AccountHierarchy buildAccountHierarchy({
    String id = '1',
    String code = '1000',
    String name = 'Cash',
    String nameAr = 'النقدية',
    AccountClassification classification = AccountClassification.asset,
    String? parentId,
    int depth = 0,
    List<AccountHierarchy> children = const [],
  }) {
    return AccountHierarchy(
      id: id,
      code: code,
      name: name,
      nameAr: nameAr,
      classification: classification,
      parentId: parentId,
      depth: depth,
      children: children,
    );
  }

  static LedgerRow buildLedgerRow({
    String? id,
    DateTime? date,
    String? entryNumber,
    String accountCode = '1000',
    String accountName = 'Cash',
    String? description,
    double debit = 0.0,
    double credit = 0.0,
    double balance = 0.0,
    String? entityType,
    String? entityId,
    String? referenceType,
    String? referenceId,
    String? currency,
  }) {
    return LedgerRow(
      id: id,
      date: date ?? DateTime(2025, 1, 15),
      entryNumber: entryNumber,
      accountCode: accountCode,
      accountName: accountName,
      description: description,
      debit: debit,
      credit: credit,
      balance: balance,
      entityType: entityType,
      entityId: entityId,
      referenceType: referenceType,
      referenceId: referenceId,
      currency: currency,
    );
  }

  // ── Transaction builders ────────────────────

  static Map<String, dynamic> buildTransactionRow({
    String id = '1',
    String accountId = '1',
    double debit = 0.0,
    double credit = 0.0,
    String? type,
    double? amount,
    String date = '2025-01-15',
    String? transactionDate,
    String description = '',
    String? entryNumber,
  }) {
    return {
      'id': id,
      'account_id': accountId,
      'debit': debit,
      'credit': credit,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      'date': date,
      'transaction_date': transactionDate ?? date,
      'description': description,
      'entry_number': entryNumber,
    };
  }
}
