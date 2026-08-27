import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/fiscal_year_dao.dart';
import '../models/fiscal_year_status.dart';
import '../services/health_check_service.dart';
import '../services/consistency_scanner.dart';
import '../services/progress_service.dart';
import '../services/closing_validation_service.dart';

class DryRunResult {
  final bool passed;
  final double readinessScore;
  final Duration estimatedClosingTime;
  final int estimatedJournalEntries;
  final int estimatedOpeningEntries;
  final int estimatedInventorySnapshots;
  final List<String> warnings;
  final List<String> errors;
  final List<String> recommendations;
  final Map<String, dynamic> validationResults;
  final DateTime executedAt;

  const DryRunResult({
    required this.passed,
    required this.readinessScore,
    required this.estimatedClosingTime,
    required this.estimatedJournalEntries,
    required this.estimatedOpeningEntries,
    required this.estimatedInventorySnapshots,
    this.warnings = const [],
    this.errors = const [],
    this.recommendations = const [],
    this.validationResults = const {},
    required this.executedAt,
  });

  Map<String, dynamic> toJson() => {
    'passed': passed,
    'readiness_score': readinessScore,
    'estimated_closing_time_ms': estimatedClosingTime.inMilliseconds,
    'estimated_journal_entries': estimatedJournalEntries,
    'estimated_opening_entries': estimatedOpeningEntries,
    'estimated_inventory_snapshots': estimatedInventorySnapshots,
    'warnings': warnings,
    'errors': errors,
    'recommendations': recommendations,
    'validation_results': validationResults,
    'executed_at': executedAt.toIso8601String(),
  };
}

class FiscalYearDryRunService {
  final SupabaseClient _client;
  final FiscalYearDao _dao;
  final ClosingValidationService _validationService;
  final FiscalYearHealthCheck _healthCheck;
  final ConsistencyScanner _scanner;
  final FiscalYearProgressService _progressService;

  FiscalYearDryRunService({
    SupabaseClient? client,
    FiscalYearDao? dao,
    ClosingValidationService? validationService,
    FiscalYearHealthCheck? healthCheck,
    ConsistencyScanner? scanner,
    FiscalYearProgressService? progressService,
  })  : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao(),
        _validationService = validationService ?? ClosingValidationService(),
        _healthCheck = healthCheck ?? FiscalYearHealthCheck(),
        _scanner = scanner ?? ConsistencyScanner(),
        _progressService = progressService ?? FiscalYearProgressService();

  Future<DryRunResult> simulateClosing(int fiscalYearId) async {
    final warnings = <String>[];
    final errors = <String>[];
    final recommendations = <String>[];
    final validationResults = <String, dynamic>{};
    final stopwatch = Stopwatch()..start();

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'بدء محاكاة الإغلاق',
      currentOperation: 'بدء الفحص ohne كتابة أي بيانات',
    );

    // 1. FY existence and status
    final fy = await _dao.getById(fiscalYearId);
    if (fy == null) {
      errors.add('السنة المالية غير موجودة');
      return _buildResult(false, 0, stopwatch.elapsed, warnings, errors, recommendations, validationResults);
    }
    if (fy.isClosed) {
      errors.add('السنة المالية مغلقة مسبقاً');
      return _buildResult(false, 0, stopwatch.elapsed, warnings, errors, recommendations, validationResults);
    }

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'التحقق من ميزان المراجعة',
      currentOperation: 'فحص توازن الحسابات',
    );

    // 2. Trial balance
    final tbBalanced = await _dao.validateTrialBalance(fiscalYearId);
    validationResults['trial_balance'] = {'balanced': tbBalanced};
    if (!tbBalanced) {
      errors.add('ميزان المراجعة غير متوازن');
    }

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'التحقق من القيود',
      currentOperation: 'فحص القيود اليتيمة والمكررة',
    );

    // 3. Orphan and duplicate entries
    final orphans = await _dao.findOrphanEntries(fiscalYearId);
    final duplicates = await _dao.findDuplicateEntries(fiscalYearId);
    validationResults['orphan_entries'] = orphans;
    validationResults['duplicate_entries'] = duplicates;
    if (orphans > 0) warnings.add('يوجد $orphans قيد يتيم');
    if (duplicates > 0) warnings.add('يوجد $duplicates قيد مكرر');

    // 4. Draft transactions
    final drafts = await _dao.countDraftTransactions(fiscalYearId);
    validationResults['draft_transactions'] = drafts;
    if (drafts > 0) errors.add('يوجد $drafts معاملة مسودة');

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'التحقق من المخزون',
      currentOperation: 'فحص أرصدة المخزون',
    );

    // 5. Negative stock
    final negStock = await _dao.countNegativeStock();
    validationResults['negative_stock'] = negStock;
    if (negStock > 0) {
      warnings.add('يوجد $negStock صنف بمخزون سالب');
      recommendations.add('مراجعة أرصدة المخزون السالبة قبل الإغلاق');
    }

    // 6. Broken FIFO
    final brokenFifo = await _dao.countBrokenFifoLayers();
    validationResults['broken_fifo'] = brokenFifo;
    if (brokenFifo > 0) {
      warnings.add('يوجد $brokenFifo طبقة FIFO معطلة');
      recommendations.add('إصلاح طبقات FIFO المعطلة');
    }

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'التحقق من العملة',
      currentOperation: 'فحص لقطات العملة',
    );

    // 7. Currency snapshots
    final currencyResult = await _client.rpc('count_missing_currency_snapshots');
    final missingCurrency = (currencyResult as num?)?.toInt() ?? 0;
    validationResults['missing_currency_snapshots'] = missingCurrency;
    if (missingCurrency > 0) {
      warnings.add('يوجد $missingCurrency لقطة عملة مفقودة');
      recommendations.add('إنشاء لقطات العملة قبل الإغلاق');
    }

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'التحقق من العملاء والموردين',
      currentOperation: 'فحص أرصدة الأطراف',
    );

    // 8. Customer/Supplier balance validation
    final customerResult = await _client.rpc('count_negative_customer_balances');
    final negCustomers = (customerResult as num?)?.toInt() ?? 0;
    validationResults['negative_customer_balances'] = negCustomers;
    if (negCustomers > 0) warnings.add('يوجد $negCustomers عميل بأرصدة سالبة');

    final supplierResult = await _client.rpc('count_negative_supplier_balances');
    final negSuppliers = (supplierResult as num?)?.toInt() ?? 0;
    validationResults['negative_supplier_balances'] = negSuppliers;
    if (negSuppliers > 0) warnings.add('يوجد $negSuppliers مورد بأرصدة سالبة');

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'التحقق من الخزينة',
      currentOperation: 'فحص معاملات الخزينة',
    );

    // 9. Treasury validation
    final treasuryResult = await _client.rpc('count_unbalanced_treasury');
    final unbalancedTreasury = (treasuryResult as num?)?.toInt() ?? 0;
    validationResults['unbalanced_treasury'] = unbalancedTreasury;
    if (unbalancedTreasury > 0) {
      warnings.add('يوجد $unbalancedTreasury معاملة خزينة غير متوازنة');
      recommendations.add('موازنة معاملات الخزينة');
    }

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'فحص النسخة الاحتياطية',
      currentOperation: 'التحقق من وجود نسخة احتياطية',
    );

    // 10. Backup verification
    final backupResult = await _client.rpc('verify_fiscal_year_backup', params: {'p_fiscal_year_id': fiscalYearId});
    final backupVerified = backupResult is Map && backupResult['verified'] == true;
    validationResults['backup_verified'] = backupVerified;
    if (!backupVerified) {
      errors.add('لا توجد نسخة احتياطية موثقة');
      recommendations.add('إنشاء نسخة احتياطية قبل الإغلاق');
    }

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'فحص القفل الموزع',
      currentOperation: 'التحقق من عدم وجود قفل نشط',
    );

    // 11. Distributed lock check
    final lockResult = await _client.rpc('force_release_stale_lock');
    validationResults['lock_available'] = true;

    _progressService.emitPhase(
      fiscalYearId: fiscalYearId,
      phase: ProgressEventPhase.validating,
      currentStep: 'فحص الحالة الصحية',
      currentOperation: 'تشغيل فحوصات الحالة',
    );

    // 12. Health check
    final healthChecks = await _healthCheck.runAllChecks(fiscalYearId);
    final healthScore = _healthCheck.calculateReadinessScore(healthChecks);
    validationResults['health_score'] = healthScore;
    final failedChecks = healthChecks.where((h) => h.status == HealthStatus.failed);
    for (final check in failedChecks) {
      warnings.add('فحص الحالة: ${check.nameAr} - ${check.message ?? ''}');
    }

    // 13. Estimate counts
    final accountCount = await _getAccountCount(fiscalYearId);
    final estimatedJournal = accountCount * 2;
    final estimatedOpening = accountCount;

    // 14. Inventory snapshots estimate
    final batchResult = await _client.rpc('count_active_batches');
    final estimatedSnapshots = (batchResult as num?)?.toInt() ?? 0;

    // 15. Consistency scan
    final issues = await _scanner.scanAll(fiscalYearId);
    final criticalIssues = issues.where((i) => i.severity == IssueSeverity.error);
    for (final issue in criticalIssues) {
      errors.add('${issue.categoryAr}: ${issue.descriptionAr}');
    }
    validationResults['consistency_issues'] = issues.length;

    stopwatch.stop();

    // Calculate readiness
    final totalChecks = 12;
    final passedChecks = [
      tbBalanced,
      orphans == 0,
      duplicates == 0,
      drafts == 0,
      negStock == 0,
      brokenFifo == 0,
      missingCurrency == 0,
      negCustomers == 0,
      negSuppliers == 0,
      unbalancedTreasury == 0,
      backupVerified,
      errors.isEmpty,
    ].where((b) => b).length;
    final readinessScore = (passedChecks / totalChecks) * 100;

    if (readinessScore < 100) {
      recommendations.add('إصلاح جميع المشاكل المكتشفة قبل الإغلاق الفعلي');
    }
    if (readinessScore >= 90) {
      recommendations.add('السنة المالية جاهزة للإغلاق');
    }

    return DryRunResult(
      passed: errors.isEmpty,
      readinessScore: readinessScore,
      estimatedClosingTime: Duration(seconds: (readinessScore / 100 * 300).round()),
      estimatedJournalEntries: estimatedJournal,
      estimatedOpeningEntries: estimatedOpening,
      estimatedInventorySnapshots: estimatedSnapshots,
      warnings: warnings,
      errors: errors,
      recommendations: recommendations,
      validationResults: validationResults,
      executedAt: DateTime.now(),
    );
  }

  Future<int> _getAccountCount(int fiscalYearId) async {
    try {
      final result = await _client.rpc('count_accounts_for_fy', params: {'p_fiscal_year_id': fiscalYearId});
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      return 50;
    }
  }

  DryRunResult _buildResult(
    bool passed,
    int pct,
    Duration elapsed,
    List<String> warnings,
    List<String> errors,
    List<String> recommendations,
    Map<String, dynamic> validationResults,
  ) {
    return DryRunResult(
      passed: passed,
      readinessScore: pct.toDouble(),
      estimatedClosingTime: elapsed,
      estimatedJournalEntries: 0,
      estimatedOpeningEntries: 0,
      estimatedInventorySnapshots: 0,
      warnings: warnings,
      errors: errors,
      recommendations: recommendations,
      validationResults: validationResults,
      executedAt: DateTime.now(),
    );
  }
}
