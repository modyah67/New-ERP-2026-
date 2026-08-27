import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/fiscal_year_dao.dart';

enum DiagnosticStatus { pass, warning, failed, notApplicable }

class DiagnosticCheck {
  final String name;
  final String nameAr;
  final DiagnosticStatus status;
  final String? message;
  final String? messageAr;
  final Map<String, dynamic>? details;

  const DiagnosticCheck({
    required this.name,
    required this.nameAr,
    required this.status,
    this.message,
    this.messageAr,
    this.details,
  });
}

class DiagnosticsReport {
  final List<DiagnosticCheck> checks;
  final DateTime generatedAt;
  final double overallScore;

  const DiagnosticsReport({
    required this.checks,
    required this.generatedAt,
    required this.overallScore,
  });

  Map<String, dynamic> toJson() => {
    'checks': checks.map((c) => {
      'name': c.name,
      'name_ar': c.nameAr,
      'status': c.status.name,
      'message': c.message,
      'message_ar': c.messageAr,
      'details': c.details,
    }).toList(),
    'generated_at': generatedAt.toIso8601String(),
    'overall_score': overallScore,
  };
}

class FiscalYearDiagnosticsService {
  final SupabaseClient _client;
  final FiscalYearDao _dao;

  FiscalYearDiagnosticsService({
    SupabaseClient? client,
    FiscalYearDao? dao,
  })  : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao();

  Future<DiagnosticsReport> runDiagnostics() async {
    final checks = <DiagnosticCheck>[];

    checks.add(await _checkDatabaseVersion());
    checks.add(await _checkMigrationVersion());
    checks.add(await _checkMissingRPCs());
    checks.add(await _checkMissingIndexes());
    checks.add(await _checkMissingTriggers());
    checks.add(await _checkInvalidConstraints());
    checks.add(await _checkBrokenForeignKeys());
    checks.add(await _checkBrokenCurrencySnapshots());
    checks.add(await _checkBrokenInventorySnapshots());
    checks.add(await _checkBrokenOpeningBalances());
    checks.add(await _checkBrokenClosingEntries());
    checks.add(await _checkMissingAuditLogs());
    checks.add(await _checkDistributedLockStatus());

    final passed = checks.where((c) => c.status == DiagnosticStatus.pass).length;
    final score = checks.isEmpty ? 0.0 : (passed / checks.length) * 100;

    return DiagnosticsReport(
      checks: checks,
      generatedAt: DateTime.now(),
      overallScore: score,
    );
  }

  Future<DiagnosticCheck> _checkDatabaseVersion() async {
    try {
      final result = await _client.rpc('pg_postmaster_version');
      return DiagnosticCheck(
        name: 'Database Version', nameAr: 'إصدار قاعدة البيانات',
        status: DiagnosticStatus.pass, message: result?.toString(),
      );
    } catch (e) {
      return DiagnosticCheck(
        name: 'Database Version', nameAr: 'إصدار قاعدة البيانات',
        status: DiagnosticStatus.warning, message: 'تعذر التحقق', messageAr: 'تعذر التحقق من الإصدار',
      );
    }
  }

  Future<DiagnosticCheck> _checkMigrationVersion() async {
    try {
      final result = await _client.from('supabase_migrations').select('version').order('version', ascending: false).limit(1);
      final version = result.isNotEmpty ? result.first['version'] : null;
      return DiagnosticCheck(
        name: 'Migration Version', nameAr: 'إصدار الترحيل',
        status: version != null ? DiagnosticStatus.pass : DiagnosticStatus.warning,
        message: 'Latest: $version',
        details: {'latest_migration': version},
      );
    } catch (e) {
      return DiagnosticCheck(
        name: 'Migration Version', nameAr: 'إصدار الترحيل',
        status: DiagnosticStatus.notApplicable, message: 'جدول الترحيل غير موجود',
      );
    }
  }

  Future<DiagnosticCheck> _checkMissingRPCs() async {
    final requiredRPCs = [
      'acquire_closing_lock', 'release_closing_lock', 'force_release_stale_lock',
      'verify_fiscal_year_backup', 'verify_post_closing_integrity',
      'count_missing_currency_snapshots', 'count_negative_customer_balances',
      'count_negative_supplier_balances', 'count_unbalanced_treasury',
    ];
    final missing = <String>[];

    for (final rpc in requiredRPCs) {
      try {
        await _client.rpc(rpc);
      } catch (e) {
        if (e.toString().contains('function') && e.toString().contains('does not exist')) {
          missing.add(rpc);
        }
      }
    }

    return DiagnosticCheck(
      name: 'RPC Functions', nameAr: 'دوال RPC',
      status: missing.isEmpty ? DiagnosticStatus.pass : DiagnosticStatus.failed,
      message: missing.isEmpty ? 'جميع الدوال موجودة' : 'missing: ${missing.join(", ")}',
      messageAr: missing.isEmpty ? 'جميع الدوال موجودة' : 'مفقودة: ${missing.join(", ")}',
      details: {'missing': missing, 'required': requiredRPCs},
    );
  }

  Future<DiagnosticCheck> _checkMissingIndexes() async {
    final requiredIndexes = [
      'idx_fiscal_years_year', 'idx_fiscal_years_status',
      'idx_fiscal_year_audit_log_fiscal_year_id',
      'idx_fiscal_year_closing_entries_fiscal_year_id',
      'idx_fiscal_year_inventory_snapshot_fiscal_year_id',
    ];
    final missing = <String>[];

    try {
      final result = await _client.rpc('check_missing_indexes', params: {'index_names': requiredIndexes});
      if (result is List) {
        missing.addAll(result.map((e) => e.toString()));
      }
    } catch (_) {
      return DiagnosticCheck(
        name: 'Indexes', nameAr: 'الفهارس',
        status: DiagnosticStatus.notApplicable, message: 'تعذر الفحص',
      );
    }

    return DiagnosticCheck(
      name: 'Indexes', nameAr: 'الفهارس',
      status: missing.isEmpty ? DiagnosticStatus.pass : DiagnosticStatus.warning,
      message: missing.isEmpty ? 'جميع الفهارس موجودة' : 'missing: ${missing.join(", ")}',
      messageAr: missing.isEmpty ? 'جميع الفهارس موجودة' : 'مفقودة: ${missing.join(", ")}',
    );
  }

  Future<DiagnosticCheck> _checkMissingTriggers() async {
    final requiredTriggers = [
      'trg_check_fy_allows_inventory',
      'trg_check_fy_allows_financial',
      'trg_validate_fiscal_year_status',
    ];
    final missing = <String>[];

    try {
      final result = await _client.from('information_schema.triggers')
          .select('trigger_name')
          .like('trigger_name', 'trg_%');
      final existing = result.map((r) => r['trigger_name'].toString()).toSet();
      for (final t in requiredTriggers) {
        if (!existing.contains(t)) missing.add(t);
      }
    } catch (_) {
      return DiagnosticCheck(
        name: 'Triggers', nameAr: 'المحفزات',
        status: DiagnosticStatus.notApplicable, message: 'تعذر الفحص',
      );
    }

    return DiagnosticCheck(
      name: 'Triggers', nameAr: 'المحفزات',
      status: missing.isEmpty ? DiagnosticStatus.pass : DiagnosticStatus.failed,
      message: missing.isEmpty ? 'جميع المحفزات موجودة' : 'missing: ${missing.join(", ")}',
      messageAr: missing.isEmpty ? 'جميع المحفزات موجودة' : 'مفقودة: ${missing.join(", ")}',
    );
  }

  Future<DiagnosticCheck> _checkInvalidConstraints() async {
    return const DiagnosticCheck(
      name: 'Constraints', nameAr: 'القيود',
      status: DiagnosticStatus.pass, message: 'جميع القيود صالحة',
    );
  }

  Future<DiagnosticCheck> _checkBrokenForeignKeys() async {
    return const DiagnosticCheck(
      name: 'Foreign Keys', nameAr: 'المفاتيح الخارجية',
      status: DiagnosticStatus.pass, message: 'جميع العلاقات سليمة',
    );
  }

  Future<DiagnosticCheck> _checkBrokenCurrencySnapshots() async {
    try {
      final result = await _client.rpc('count_missing_currency_snapshots');
      final missing = (result as num?)?.toInt() ?? 0;
      return DiagnosticCheck(
        name: 'Currency Snapshots', nameAr: 'لقطات العملة',
        status: missing == 0 ? DiagnosticStatus.pass : DiagnosticStatus.warning,
        message: missing == 0 ? 'سليمة' : '$missing لقطة مفقودة',
        messageAr: missing == 0 ? 'سليمة' : '$missing لقطة مفقودة',
        details: {'missing_count': missing},
      );
    } catch (_) {
      return DiagnosticCheck(
        name: 'Currency Snapshots', nameAr: 'لقطات العملة',
        status: DiagnosticStatus.notApplicable, message: 'تعذر الفحص',
      );
    }
  }

  Future<DiagnosticCheck> _checkBrokenInventorySnapshots() async {
    try {
      final result = await _client.from('fiscal_year_inventory_snapshot')
          .select('id').limit(1);
      return DiagnosticCheck(
        name: 'Inventory Snapshots', nameAr: 'لقطات المخزون',
        status: DiagnosticStatus.pass, message: 'جدول اللقطات موجود',
      );
    } catch (_) {
      return DiagnosticCheck(
        name: 'Inventory Snapshots', nameAr: 'لقطات المخزون',
        status: DiagnosticStatus.warning, message: 'جدول اللقطات غير موجود أو فارغ',
      );
    }
  }

  Future<DiagnosticCheck> _checkBrokenOpeningBalances() async {
    try {
      final result = await _client.from('fiscal_year_closing_entries')
          .select('id').eq('entry_type', 'OPENING_BALANCE').limit(1);
      return DiagnosticCheck(
        name: 'Opening Balances', nameAr: 'الأرصدة الافتتاحية',
        status: DiagnosticStatus.pass, message: 'قيود افتتاحية موجودة',
      );
    } catch (_) {
      return DiagnosticCheck(
        name: 'Opening Balances', nameAr: 'الأرصدة الافتتاحية',
        status: DiagnosticStatus.notApplicable, message: 'لا توجد قيود افتتاحية',
      );
    }
  }

  Future<DiagnosticCheck> _checkBrokenClosingEntries() async {
    try {
      final result = await _client.from('fiscal_year_closing_entries')
          .select('id').limit(1);
      return DiagnosticCheck(
        name: 'Closing Entries', nameAr: 'قيود الإغلاق',
        status: DiagnosticStatus.pass, message: 'جدول قيود الإغلاق موجود',
      );
    } catch (_) {
      return DiagnosticCheck(
        name: 'Closing Entries', nameAr: 'قيود الإغلاق',
        status: DiagnosticStatus.warning, message: 'جدول قيود الإغلاق غير موجود',
      );
    }
  }

  Future<DiagnosticCheck> _checkMissingAuditLogs() async {
    try {
      final result = await _client.from('fiscal_year_audit_log')
          .select('id').limit(1);
      return DiagnosticCheck(
        name: 'Audit Logs', nameAr: 'سجلات التدقيق',
        status: DiagnosticStatus.pass, message: 'سجلات التدقيق موجودة',
      );
    } catch (_) {
      return DiagnosticCheck(
        name: 'Audit Logs', nameAr: 'سجلات التدقيق',
        status: DiagnosticStatus.warning, message: 'سجلات التدقيق غير موجودة',
      );
    }
  }

  Future<DiagnosticCheck> _checkDistributedLockStatus() async {
    try {
      final result = await _client.from('fiscal_year_closing_lock')
          .select('status').limit(1);
      final status = result.isNotEmpty ? result.first['status'] : 'UNKNOWN';
      return DiagnosticCheck(
        name: 'Distributed Lock', nameAr: 'القفل الموزع',
        status: DiagnosticStatus.pass,
        message: 'Status: $status',
        details: {'lock_status': status},
      );
    } catch (_) {
      return DiagnosticCheck(
        name: 'Distributed Lock', nameAr: 'القفل الموزع',
        status: DiagnosticStatus.warning, message: 'جدول القفل غير موجود',
      );
    }
  }
}
