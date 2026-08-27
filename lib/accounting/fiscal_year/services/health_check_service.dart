import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/fiscal_year_dao.dart';

enum HealthStatus { pass, warning, failed, pending }

class HealthCheckItem {
  final String name;
  final String nameAr;
  final HealthStatus status;
  final String? message;
  final int? count;

  const HealthCheckItem({
    required this.name,
    required this.nameAr,
    required this.status,
    this.message,
    this.count,
  });
}

class FiscalYearHealthCheck {
  final SupabaseClient _client;
  final FiscalYearDao _dao;

  FiscalYearHealthCheck({SupabaseClient? client, FiscalYearDao? dao})
      : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao();

  Future<List<HealthCheckItem>> runAllChecks(int fiscalYearId) async {
    final results = await Future.wait([
      _checkTrialBalance(fiscalYearId),
      _checkJournalIntegrity(fiscalYearId),
      _checkInventory(),
      _checkFifoLayers(),
      _checkBatchIntegrity(),
      _checkCurrencySnapshots(fiscalYearId),
      _checkCustomerBalances(fiscalYearId),
      _checkSupplierBalances(fiscalYearId),
      _checkTreasury(),
      _checkExchangeRates(),
      _checkPendingDocuments(fiscalYearId),
      _checkDraftTransactions(fiscalYearId),
      _checkAuditStatus(fiscalYearId),
      _checkBackupAvailability(fiscalYearId),
      _checkDistributedLock(),
      _checkPermissions(),
    ]);
    return results;
  }

  Future<HealthCheckItem> _checkTrialBalance(int fyId) async {
    try {
      final balanced = await _dao.validateTrialBalance(fyId);
      return HealthCheckItem(
        name: 'Trial Balance',
        nameAr: 'ميزان المراجعة',
        status: balanced ? HealthStatus.pass : HealthStatus.failed,
        message: balanced ? 'متوازن' : 'غير متوازن',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Trial Balance', nameAr: 'ميزان المراجعة', status: HealthStatus.failed, message: e.toString());
    }
  }

  Future<HealthCheckItem> _checkJournalIntegrity(int fyId) async {
    try {
      final orphans = await _dao.findOrphanEntries(fyId);
      final duplicates = await _dao.findDuplicateEntries(fyId);
      if (orphans > 0 || duplicates > 0) {
        return HealthCheckItem(
          name: 'Journal Integrity',
          nameAr: 'سلامة القيود',
          status: HealthStatus.failed,
          message: '$orphans قيد يتيم، $duplicates قيد مكرر',
          count: orphans + duplicates,
        );
      }
      return HealthCheckItem(name: 'Journal Integrity', nameAr: 'سلامة القيود', status: HealthStatus.pass, message: 'سليم');
    } catch (e) {
      return HealthCheckItem(name: 'Journal Integrity', nameAr: 'سلامة القيود', status: HealthStatus.failed, message: e.toString());
    }
  }

  Future<HealthCheckItem> _checkInventory() async {
    try {
      final negative = await _dao.countNegativeStock();
      return HealthCheckItem(
        name: 'Inventory',
        nameAr: 'المخزون',
        status: negative == 0 ? HealthStatus.pass : HealthStatus.failed,
        message: negative == 0 ? 'سليم' : '$negative صنف بمخزون سالب',
        count: negative,
      );
    } catch (e) {
      return HealthCheckItem(name: 'Inventory', nameAr: 'المخزون', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkFifoLayers() async {
    try {
      final broken = await _dao.countBrokenFifoLayers();
      return HealthCheckItem(
        name: 'FIFO Layers',
        nameAr: 'طبقات FIFO',
        status: broken == 0 ? HealthStatus.pass : HealthStatus.failed,
        message: broken == 0 ? 'سليمة' : '$broken طبقة مكسورة',
        count: broken,
      );
    } catch (e) {
      return HealthCheckItem(name: 'FIFO Layers', nameAr: 'طبقات FIFO', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkBatchIntegrity() async {
    try {
      final response = await _client.from('stock_batches')
          .select('id')
          .lt('remaining_quantity', 0);
      final count = (response as List).length;
      return HealthCheckItem(
        name: 'Batch Integrity',
        nameAr: 'سلامة الدفعات',
        status: count == 0 ? HealthStatus.pass : HealthStatus.failed,
        message: count == 0 ? 'سليمة' : '$count دفعات بكميات سالبة',
        count: count,
      );
    } catch (e) {
      return HealthCheckItem(name: 'Batch Integrity', nameAr: 'سلامة الدفعات', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkCurrencySnapshots(int fyId) async {
    try {
      final response = await _client.from('transactions')
          .select('id')
          .isFilter('currency_snapshot', null);
      final missing = (response as List).length;
      return HealthCheckItem(
        name: 'Currency Snapshots',
        nameAr: 'لقطات العملة',
        status: missing == 0 ? HealthStatus.pass : HealthStatus.warning,
        message: missing == 0 ? 'مكتملة' : '$missing معاملة بدون لقطة عملة',
        count: missing,
      );
    } catch (e) {
      return HealthCheckItem(name: 'Currency Snapshots', nameAr: 'لقطات العملة', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkCustomerBalances(int fyId) async {
    try {
      final accounts = await _client.from('accounts')
          .select('id')
          .eq('account_type', 'asset')
          .eq('is_active', true);
      return HealthCheckItem(
        name: 'Customer Balances',
        nameAr: 'أرصدة العملاء',
        status: HealthStatus.pass,
        message: '${(accounts as List).length} حساب',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Customer Balances', nameAr: 'أرصدة العملاء', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkSupplierBalances(int fyId) async {
    try {
      final accounts = await _client.from('accounts')
          .select('id')
          .eq('account_type', 'liability')
          .eq('is_active', true);
      return HealthCheckItem(
        name: 'Supplier Balances',
        nameAr: 'أرصدة الموردين',
        status: HealthStatus.pass,
        message: '${(accounts as List).length} حساب',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Supplier Balances', nameAr: 'أرصدة الموردين', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkTreasury() async {
    try {
      final response = await _client.from('cashboxes').select('id');
      return HealthCheckItem(
        name: 'Treasury',
        nameAr: 'الخزينة',
        status: HealthStatus.pass,
        message: '${(response as List).length} خزينة',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Treasury', nameAr: 'الخزينة', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkExchangeRates() async {
    try {
      final response = await _client.from('exchange_rates')
          .select('id')
          .order('created_at', ascending: false)
          .limit(1);
      final hasRates = (response as List).isNotEmpty;
      return HealthCheckItem(
        name: 'Exchange Rates',
        nameAr: 'أسعار الصرف',
        status: hasRates ? HealthStatus.pass : HealthStatus.warning,
        message: hasRates ? 'محدثة' : 'لا توجد أسعار صرف',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Exchange Rates', nameAr: 'أسعار الصرف', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkPendingDocuments(int fyId) async {
    try {
      final fy = await _dao.getById(fyId);
      if (fy == null) return HealthCheckItem(name: 'Pending Documents', nameAr: 'مستندات معلقة', status: HealthStatus.failed, message: 'السنة غير موجودة');
      final drafts = await _dao.countDraftTransactions(fyId);
      return HealthCheckItem(
        name: 'Pending Documents',
        nameAr: 'مستندات معلقة',
        status: drafts == 0 ? HealthStatus.pass : HealthStatus.warning,
        message: drafts == 0 ? 'لا توجد' : '$drafts مستند مسودة',
        count: drafts,
      );
    } catch (e) {
      return HealthCheckItem(name: 'Pending Documents', nameAr: 'مستندات معلقة', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkDraftTransactions(int fyId) async {
    try {
      final count = await _dao.countDraftTransactions(fyId);
      return HealthCheckItem(
        name: 'Draft Transactions',
        nameAr: 'معاملات مسودة',
        status: count == 0 ? HealthStatus.pass : HealthStatus.failed,
        message: count == 0 ? 'لا توجد' : '$count معاملة مسودة',
        count: count,
      );
    } catch (e) {
      return HealthCheckItem(name: 'Draft Transactions', nameAr: 'معاملات مسودة', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkAuditStatus(int fyId) async {
    try {
      final log = await _dao.getAuditLogForFiscalYear(fyId, limit: 1);
      final hasLog = log != null && (log['entries'] as List?)?.isNotEmpty == true;
      return HealthCheckItem(
        name: 'Audit Status',
        nameAr: 'حالة التدقيق',
        status: hasLog ? HealthStatus.pass : HealthStatus.pending,
        message: hasLog ? 'يوجد سجل' : 'لا يوجد سجل',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Audit Status', nameAr: 'حالة التدقيق', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkBackupAvailability(int fyId) async {
    try {
      final backups = await _dao.getBackupMetadata(fyId);
      return HealthCheckItem(
        name: 'Backup Verification',
        nameAr: 'التحقق من النسخ الاحتياطي',
        status: backups.isNotEmpty ? HealthStatus.pass : HealthStatus.pending,
        message: backups.isNotEmpty ? '${backups.length} نسخة احتياطية' : 'لا توجد نسخ احتياطية',
        count: backups.length,
      );
    } catch (e) {
      return HealthCheckItem(name: 'Backup Verification', nameAr: 'التحقق من النسخ الاحتياطي', status: HealthStatus.warning, message: 'تعذر التحقق');
    }
  }

  Future<HealthCheckItem> _checkDistributedLock() async {
    try {
      await _client.rpc('force_release_stale_lock');
      return HealthCheckItem(
        name: 'Distributed Lock',
        nameAr: 'القفل الموزع',
        status: HealthStatus.pass,
        message: 'متاح',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Distributed Lock', nameAr: 'القفل الموزع', status: HealthStatus.failed, message: 'غير متاح');
    }
  }

  Future<HealthCheckItem> _checkPermissions() async {
    try {
      final user = _client.auth.currentUser;
      return HealthCheckItem(
        name: 'Permissions',
        nameAr: 'الصلاحيات',
        status: user != null ? HealthStatus.pass : HealthStatus.failed,
        message: user != null ? 'مسجل الدخول' : 'غير مسجل',
      );
    } catch (e) {
      return HealthCheckItem(name: 'Permissions', nameAr: 'الصلاحيات', status: HealthStatus.failed, message: e.toString());
    }
  }

  double calculateReadinessScore(List<HealthCheckItem> checks) {
    if (checks.isEmpty) return 0;
    int total = 0;
    for (final check in checks) {
      switch (check.status) {
        case HealthStatus.pass:
          total += 100;
          break;
        case HealthStatus.warning:
          total += 60;
          break;
        case HealthStatus.failed:
          total += 0;
          break;
        case HealthStatus.pending:
          total += 30;
          break;
      }
    }
    return total / checks.length;
  }
}
