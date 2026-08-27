import '../models/fiscal_year.dart';
import '../dao/fiscal_year_dao.dart';

class ClosingReportService {
  final FiscalYearDao _dao;

  ClosingReportService({FiscalYearDao? dao}) : _dao = dao ?? FiscalYearDao();

  Future<Map<String, dynamic>> getFiscalYearSummary(int fiscalYearId) async {
    final fy = await _dao.getById(fiscalYearId);
    if (fy == null) return {};

    final tb = await _dao.validateTrialBalance(fiscalYearId);
    final revenueAccounts = await _dao.getRevenueAccounts();
    final expenseAccounts = await _dao.getExpenseAccounts();

    double totalRevenue = 0;
    double totalExpenses = 0;

    for (final account in revenueAccounts) {
      final totals = await _dao.getAccountTotals(account['account_code'] as String, fiscalYearId);
      totalRevenue += totals['credit']! - totals['debit']!;
    }

    for (final account in expenseAccounts) {
      final totals = await _dao.getAccountTotals(account['account_code'] as String, fiscalYearId);
      totalExpenses += totals['debit']! - totals['credit']!;
    }

    final closingEntries = await _dao.getClosingEntries(fiscalYearId, entryType: 'CLOSE_REVENUE');
    final openingEntries = await _dao.getClosingEntries(fiscalYearId, entryType: 'OPENING_BALANCE');
    final inventorySnapshots = await _dao.getInventorySnapshots(fiscalYearId);
    final backups = await _dao.getBackupMetadata(fiscalYearId);

    return {
      'fiscal_year': fy.toJson(),
      'trial_balance_balanced': tb,
      'total_revenue': totalRevenue,
      'total_expenses': totalExpenses,
      'net_income': totalRevenue - totalExpenses,
      'closing_entries_count': closingEntries.length,
      'opening_entries_count': openingEntries.length,
      'inventory_snapshots_count': inventorySnapshots.length,
      'backups_count': backups.length,
    };
  }

  Future<List<Map<String, dynamic>>> getTrialBalanceBeforeClosing(int fiscalYearId) async {
    final accounts = await _dao.getAccountBalances(fiscalYearId);
    return accounts;
  }

  Future<Map<String, dynamic>> generateClosingReport({
    required FiscalYear fiscalYear,
    required double netIncome,
    required Map<String, double> revenueTotals,
    required Map<String, double> expenseTotals,
  }) async {
    return <String, dynamic>{
      'title': 'تقرير إغلاق السنة المالية',
      'fiscal_year': fiscalYear.year,
      'start_date': fiscalYear.startDate.toIso8601String(),
      'end_date': fiscalYear.endDate.toIso8601String(),
      'net_income': netIncome,
      'revenue_totals': revenueTotals,
      'expense_totals': expenseTotals,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> generateOpeningReport({
    required int newFiscalYearId,
    required int entriesCount,
  }) async {
    return <String, dynamic>{
      'title': 'تقرير القيود الافتتاحية',
      'new_fiscal_year_id': newFiscalYearId,
      'entries_count': entriesCount,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<List<Map<String, dynamic>>> getAuditReport(int fiscalYearId) async {
    final result = await _dao.getAuditLogForFiscalYear(fiscalYearId);
    if (result == null) return [];
    return (result['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> getCurrencySnapshotReport(int fiscalYearId) async {
    final snapshots = await _dao.getInventorySnapshots(fiscalYearId);
    return {
      'total_snapshots': snapshots.length,
      'snapshots': snapshots,
    };
  }
}
