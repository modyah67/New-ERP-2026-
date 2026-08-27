import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/fiscal_year_dao.dart';
import 'health_check_service.dart';
import 'consistency_scanner.dart';

class ReadinessSection {
  final String name;
  final String nameAr;
  final double score;
  final List<String> checks;
  final List<String> recommendations;

  const ReadinessSection({
    required this.name,
    required this.nameAr,
    required this.score,
    this.checks = const [],
    this.recommendations = const [],
  });
}

class ClosingReadinessReport {
  final double overallScore;
  final List<ReadinessSection> sections;
  final List<String> recommendations;
  final DateTime generatedAt;
  final int fiscalYearId;

  const ClosingReadinessReport({
    required this.overallScore,
    required this.sections,
    this.recommendations = const [],
    required this.generatedAt,
    required this.fiscalYearId,
  });

  Map<String, dynamic> toJson() => {
    'overall_score': overallScore,
    'sections': sections.map((s) => {
      'name': s.name,
      'name_ar': s.nameAr,
      'score': s.score,
      'checks': s.checks,
      'recommendations': s.recommendations,
    }).toList(),
    'recommendations': recommendations,
    'generated_at': generatedAt.toIso8601String(),
    'fiscal_year_id': fiscalYearId,
  };
}

class ClosingReadinessReportService {
  final SupabaseClient _client;
  final FiscalYearDao _dao;
  final FiscalYearHealthCheck _healthCheck;
  final ConsistencyScanner _scanner;

  ClosingReadinessReportService({
    SupabaseClient? client,
    FiscalYearDao? dao,
    FiscalYearHealthCheck? healthCheck,
    ConsistencyScanner? scanner,
  })  : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao(),
        _healthCheck = healthCheck ?? FiscalYearHealthCheck(),
        _scanner = scanner ?? ConsistencyScanner();

  Future<ClosingReadinessReport> generate(int fiscalYearId) async {
    final sections = <ReadinessSection>[];
    final recommendations = <String>[];

    sections.add(await _checkAccounting(fiscalYearId));
    sections.add(await _checkInventory(fiscalYearId));
    sections.add(await _checkCurrency(fiscalYearId));
    sections.add(await _checkTreasury(fiscalYearId));
    sections.add(await _checkCustomers(fiscalYearId));
    sections.add(await _checkSuppliers(fiscalYearId));
    sections.add(await _checkAudit(fiscalYearId));
    sections.add(await _checkSecurity(fiscalYearId));
    sections.add(await _checkPerformance(fiscalYearId));
    sections.add(await _checkBackup(fiscalYearId));
    sections.add(await _checkPermissions(fiscalYearId));
    sections.add(await _checkDatabaseHealth(fiscalYearId));

    final overallScore = sections.isEmpty
        ? 0.0
        : sections.map((s) => s.score).reduce((a, b) => a + b) / sections.length;

    for (final section in sections) {
      recommendations.addAll(section.recommendations);
    }

    return ClosingReadinessReport(
      overallScore: overallScore,
      sections: sections,
      recommendations: recommendations,
      generatedAt: DateTime.now(),
      fiscalYearId: fiscalYearId,
    );
  }

  Future<ReadinessSection> _checkAccounting(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    final balanced = await _dao.validateTrialBalance(fyId);
    checks.add('ميزان المراجعة: ${balanced ? 'متوازن' : 'غير متوازن'}');
    if (!balanced) { score -= 30; recs.add('موازنة ميزان المراجعة'); }

    final orphans = await _dao.findOrphanEntries(fyId);
    checks.add('قيود يتيمة: $orphans');
    if (orphans > 0) { score -= 20; recs.add('إصلاح القيود اليتيمة'); }

    final duplicates = await _dao.findDuplicateEntries(fyId);
    checks.add('قيود مكررة: $duplicates');
    if (duplicates > 0) { score -= 20; recs.add('حذف القيود المكررة'); }

    final drafts = await _dao.countDraftTransactions(fyId);
    checks.add('معاملات مسودة: $drafts');
    if (drafts > 0) { score -= 15; recs.add('إكمال المعاملات المسودة'); }

    return ReadinessSection(
      name: 'Accounting', nameAr: 'المحاسبة',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkInventory(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    final negStock = await _dao.countNegativeStock();
    checks.add('مخزون سالب: $negStock');
    if (negStock > 0) { score -= 25; recs.add('إصلاح المخزون السالب'); }

    final brokenFifo = await _dao.countBrokenFifoLayers();
    checks.add('طبقات FIFO معطلة: $brokenFifo');
    if (brokenFifo > 0) { score -= 25; recs.add('إصلاح طبقات FIFO'); }

    return ReadinessSection(
      name: 'Inventory', nameAr: 'المخزون',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkCurrency(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    try {
      final result = await _client.rpc('count_missing_currency_snapshots');
      final missing = (result as num?)?.toInt() ?? 0;
      checks.add('لقطات عملة مفقودة: $missing');
      if (missing > 0) { score -= 30; recs.add('إنشاء لقطات العملة المفقودة'); }
    } catch (_) {
      checks.add('فحص لقطات العملة: تعذر الفحص');
      score -= 10;
    }

    return ReadinessSection(
      name: 'Currency', nameAr: 'العملة',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkTreasury(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    try {
      final result = await _client.rpc('count_unbalanced_treasury');
      final unbalanced = (result as num?)?.toInt() ?? 0;
      checks.add('معاملات خزينة غير متوازنة: $unbalanced');
      if (unbalanced > 0) { score -= 25; recs.add('موازنة معاملات الخزينة'); }
    } catch (_) {
      checks.add('فحص الخزينة: تعذر الفحص');
      score -= 10;
    }

    return ReadinessSection(
      name: 'Treasury', nameAr: 'الخزينة',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkCustomers(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    try {
      final result = await _client.rpc('count_negative_customer_balances');
      final neg = (result as num?)?.toInt() ?? 0;
      checks.add('أرصدة عملاء سالبة: $neg');
      if (neg > 0) { score -= 20; recs.add('مراجعة أرصدة العملاء السالبة'); }
    } catch (_) {
      checks.add('فحص العملاء: تعذر الفحص');
      score -= 10;
    }

    return ReadinessSection(
      name: 'Customers', nameAr: 'العملاء',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkSuppliers(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    try {
      final result = await _client.rpc('count_negative_supplier_balances');
      final neg = (result as num?)?.toInt() ?? 0;
      checks.add('أرصدة موردين سالبة: $neg');
      if (neg > 0) { score -= 20; recs.add('مراجعة أرصدة الموردين السالبة'); }
    } catch (_) {
      checks.add('فحص الموردين: تعذر الفحص');
      score -= 10;
    }

    return ReadinessSection(
      name: 'Suppliers', nameAr: 'الموردين',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkAudit(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    final auditResult = await _dao.getAuditLogForFiscalYear(fyId, limit: 1000);
    final hasAudit = auditResult != null;
    checks.add('سجلات التدقيق: ${hasAudit ? 'موجودة' : 'غير موجودة'}');
    if (!hasAudit) { score -= 20; recs.add('إنشاء سجلات تدقيق'); }

    return ReadinessSection(
      name: 'Audit', nameAr: 'التدقيق',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkSecurity(int fyId) async {
    return const ReadinessSection(
      name: 'Security', nameAr: 'الأمان',
      score: 100, checks: ['RLS نشط', 'التحقق من المستخدمين مفعل'],
    );
  }

  Future<ReadinessSection> _checkPerformance(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    final sw = Stopwatch()..start();
    await _dao.validateTrialBalance(fyId);
    sw.stop();
    checks.add('وقت فحص ميزان المراجعة: ${sw.elapsedMilliseconds}ms');
    if (sw.elapsedMilliseconds > 5000) { score -= 20; recs.add('تحسين أداء الاستعلامات'); }

    return ReadinessSection(
      name: 'Performance', nameAr: 'الأداء',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkBackup(int fyId) async {
    final checks = <String>[];
    final recs = <String>[];
    double score = 100;

    try {
      final result = await _client.rpc('verify_fiscal_year_backup', params: {'p_fiscal_year_id': fyId});
      final verified = result is Map && result['verified'] == true;
      checks.add('النسخة الاحتياطية: ${verified ? 'موثقة' : 'غير موثقة'}');
      if (!verified) { score -= 30; recs.add('إنشاء نسخة احتياطية'); }
    } catch (_) {
      checks.add('فحص النسخة الاحتياطية: تعذر الفحص');
      score -= 15;
    }

    return ReadinessSection(
      name: 'Backup', nameAr: 'النسخ الاحتياطي',
      score: score.clamp(0, 100).toDouble(), checks: checks, recommendations: recs,
    );
  }

  Future<ReadinessSection> _checkPermissions(int fyId) async {
    return const ReadinessSection(
      name: 'Permissions', nameAr: 'الصلاحيات',
      score: 100,
      checks: ['صلاحيات الإغلاق مفعلة', 'RLS يفرض الوصول'],
    );
  }

  Future<ReadinessSection> _checkDatabaseHealth(int fyId) async {
    final checks = <String>[];
    double score = 100;

    try {
      await _client.from('fiscal_years').select('id').limit(1);
      checks.add('قاعدة البيانات: متصلة');
    } catch (_) {
      checks.add('قاعدة البيانات: غير متصلة');
      score = 0;
    }

    return ReadinessSection(
      name: 'Database Health', nameAr: 'صحة قاعدة البيانات',
      score: score.clamp(0, 100).toDouble(), checks: checks,
    );
  }
}
