/// ReportValidationService — Reusable validation engine for financial reports
library;

import '../dao/report_dao.dart';
import '../models/report_models.dart';

class ReportValidationService {
  final ReportDao _dao;

  ReportValidationService(this._dao);

  ValidationResult validateTrialBalance(TrialBalanceReport report) {
    final issues = <ValidationIssue>[];
    final diff = (report.totalDebit - report.totalCredit).abs();
    if (diff >= 0.01) {
      issues.add(ValidationIssue(
        code: 'TB_UNBALANCED',
        message: 'Trial balance not balanced. Diff: ${diff.toStringAsFixed(2)}',
        messageAr: 'الميزانية التجريبية غير متوازنة. الفرق: ${diff.toStringAsFixed(2)}',
        severity: ValidationSeverity.error,
      ));
    }
    if (report.rows.isEmpty) {
      issues.add(ValidationIssue(
        code: 'TB_EMPTY',
        message: 'Trial balance has no rows',
        messageAr: 'الميزانية التجريبية فارغة',
        severity: ValidationSeverity.warning,
      ));
    }
    return issues.isEmpty ? ValidationResult.success() : ValidationResult.failure(issues);
  }

  ValidationResult validateBalanceSheet(BalanceSheetReport report) {
    final issues = <ValidationIssue>[];
    final diff = (report.totalAssets - report.totalLiabilitiesAndEquity).abs();
    if (diff >= 0.01) {
      issues.add(ValidationIssue(
        code: 'BS_UNBALANCED',
        message: 'Balance sheet not balanced. Diff: ${diff.toStringAsFixed(2)}',
        messageAr: 'الميزانية العامة غير متوازنة. الفرق: ${diff.toStringAsFixed(2)}',
        severity: ValidationSeverity.error,
      ));
    }
    return issues.isEmpty ? ValidationResult.success() : ValidationResult.failure(issues);
  }

  Future<ValidationResult> validateAccountBalances() async {
    final issues = <ValidationIssue>[];
    try {
      final storedBalances = await _dao.getStoredAccountBalances();
      final computedTotals = await _dao.getAccountTotals();
      final computedMap = <String, double>{};
      for (final t in computedTotals) {
        final accountId = t['account_id'].toString();
        final debit = (t['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (t['credit'] as num?)?.toDouble() ?? 0.0;
        computedMap[accountId] = debit - credit;
      }
      for (final entry in storedBalances.entries) {
        final stored = entry.value;
        final computed = computedMap[entry.key] ?? 0.0;
        final diff = (stored - computed).abs();
        if (diff >= 0.01) {
          issues.add(ValidationIssue(
            code: 'BALANCE_DRIFT',
            message: 'Account ${entry.key}: stored=${stored.toStringAsFixed(2)}, computed=${computed.toStringAsFixed(2)}',
            messageAr: 'الحساب ${entry.key}: المخزون=${stored.toStringAsFixed(2)}, المحسوب=${computed.toStringAsFixed(2)}',
            severity: ValidationSeverity.warning,
          ));
        }
      }
    } catch (e) {
      issues.add(ValidationIssue(
        code: 'VALIDATION_ERROR',
        message: 'Error validating balances: $e',
        messageAr: 'خطأ في التحقق من الأرصدة: $e',
        severity: ValidationSeverity.error,
      ));
    }
    return issues.isEmpty ? ValidationResult.success() : ValidationResult.failure(issues);
  }

  ValidationResult isBalanced(double totalDebit, double totalCredit) {
    final diff = (totalDebit - totalCredit).abs();
    if (diff < 0.01) return ValidationResult.success();
    return ValidationResult.failure([
      ValidationIssue(
        code: 'NOT_BALANCED',
        message: 'Debit: ${totalDebit.toStringAsFixed(2)}, Credit: ${totalCredit.toStringAsFixed(2)}, Diff: ${diff.toStringAsFixed(2)}',
        messageAr: 'مدين: ${totalDebit.toStringAsFixed(2)}, دائن: ${totalCredit.toStringAsFixed(2)}, الفرق: ${diff.toStringAsFixed(2)}',
        severity: ValidationSeverity.error,
      ),
    ]);
  }

  ValidationResult validateHierarchy(List<AccountHierarchy> hierarchy) {
    final issues = <ValidationIssue>[];
    final seenIds = <String>{};
    for (final account in hierarchy) {
      if (seenIds.contains(account.id)) {
        issues.add(ValidationIssue(
          code: 'DUPLICATE_ACCOUNT',
          message: 'Duplicate account ID: ${account.id}',
          messageAr: 'معرف حساب مكرر: ${account.id}',
          severity: ValidationSeverity.error,
        ));
      }
      seenIds.add(account.id);
      if (account.parentId != null) {
        final parentExists = hierarchy.any((a) => a.id == account.parentId);
        if (!parentExists) {
          issues.add(ValidationIssue(
            code: 'MISSING_PARENT',
            message: 'Account ${account.code} references missing parent',
            messageAr: 'الحساب ${account.code} يشير إلى أب مفقود',
            severity: ValidationSeverity.warning,
          ));
        }
      }
    }
    return issues.isEmpty ? ValidationResult.success() : ValidationResult.failure(issues);
  }

  ValidationResult validateIncomeStatement(IncomeStatementReport report) {
    final issues = <ValidationIssue>[];
    if (report.revenue.lines.isEmpty) {
      issues.add(ValidationIssue(
        code: 'IS_NO_REVENUE',
        message: 'Income statement has no revenue lines',
        messageAr: 'قائمة الدخل لا تحتوي على إيرادات',
        severity: ValidationSeverity.warning,
      ));
    }
    if (report.netIncome < 0) {
      issues.add(ValidationIssue(
        code: 'IS_NET_LOSS',
        message: 'Net loss: ${report.netIncome.toStringAsFixed(2)}',
        messageAr: 'خالص الخسارة: ${report.netIncome.toStringAsFixed(2)}',
        severity: ValidationSeverity.warning,
      ));
    }
    return issues.isEmpty ? ValidationResult.success() : ValidationResult.failure(issues);
  }

  ValidationResult validateCashFlowStatement(CashFlowReport report) {
    final issues = <ValidationIssue>[];
    final diff = (report.netChangeInCash -
            (report.netCashFromOperating +
                report.netCashFromInvesting +
                report.netCashFromFinancing))
        .abs();
    if (diff >= 0.01) {
      issues.add(ValidationIssue(
        code: 'CF_UNBALANCED',
        message: 'Cash flow components do not sum to net change. Diff: ${diff.toStringAsFixed(2)}',
        messageAr: 'مكونات التدفقات النقدية لا تساوي التغير الصافي. الفرق: ${diff.toStringAsFixed(2)}',
        severity: ValidationSeverity.error,
      ));
    }
    return issues.isEmpty ? ValidationResult.success() : ValidationResult.failure(issues);
  }
}
