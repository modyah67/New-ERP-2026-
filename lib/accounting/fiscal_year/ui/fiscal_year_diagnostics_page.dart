import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../core/injection.dart';
import '../cubit/fiscal_year_cubit.dart';
import '../services/diagnostics_service.dart';
import '../services/production_validator.dart';
import '../services/stress_test_service.dart';
import '../services/readiness_report_service.dart';

class FiscalYearDiagnosticsPage extends StatefulWidget {
  const FiscalYearDiagnosticsPage({super.key});

  @override
  State<FiscalYearDiagnosticsPage> createState() => _FiscalYearDiagnosticsPageState();
}

class _FiscalYearDiagnosticsPageState extends State<FiscalYearDiagnosticsPage> {
  DiagnosticsReport? _diagnosticsReport;
  ProductionValidationReport? _validationReport;
  StressTestResult? _stressResult;
  ClosingReadinessReport? _readinessReport;
  bool _isRunningDiagnostics = false;
  bool _isRunningValidation = false;
  bool _isRunningStress = false;
  bool _isRunningReadiness = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('التشخيص والمراجعة النهائية'),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActionButtons(),
            const SizedBox(height: 16),
            if (_diagnosticsReport != null) _buildDiagnosticsReport(),
            if (_validationReport != null) _buildValidationReport(),
            if (_readinessReport != null) _buildReadinessReport(),
            if (_stressResult != null) _buildStressTestReport(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: _isRunningDiagnostics ? null : _runDiagnostics,
          icon: _isRunningDiagnostics
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bug_report, size: 16),
          label: const Text('تشخيص النظام'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
        ),
        ElevatedButton.icon(
          onPressed: _isRunningValidation ? null : _runValidation,
          icon: _isRunningValidation
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.verified, size: 16),
          label: const Text('التحقق النهائي'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
        ),
        ElevatedButton.icon(
          onPressed: _isRunningReadiness ? null : _runReadinessReport,
          icon: _isRunningReadiness
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.speed, size: 16),
          label: const Text('تقرير الجاهزية'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
        ),
        ElevatedButton.icon(
          onPressed: _isRunningStress ? null : _runStressTest,
          icon: _isRunningStress
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.timeline, size: 16),
          label: const Text('اختبار الأداء'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
        ),
      ],
    );
  }

  Future<void> _runDiagnostics() async {
    setState(() => _isRunningDiagnostics = true);
    try {
      final service = sl<FiscalYearDiagnosticsService>();
      final report = await service.runDiagnostics();
      if (mounted) setState(() => _diagnosticsReport = report);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
    if (mounted) setState(() => _isRunningDiagnostics = false);
  }

  Future<void> _runValidation() async {
    setState(() => _isRunningValidation = true);
    try {
      final service = sl<FiscalYearProductionValidator>();
      final report = await service.validate();
      if (mounted) setState(() => _validationReport = report);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
    if (mounted) setState(() => _isRunningValidation = false);
  }

  Future<void> _runReadinessReport() async {
    setState(() => _isRunningReadiness = true);
    try {
      final state = context.read<FiscalYearCubit>().state;
      if (state is FiscalYearLoaded && state.currentFiscalYear != null) {
        final service = sl<ClosingReadinessReportService>();
        final report = await service.generate(state.currentFiscalYear!.id);
        if (mounted) setState(() => _readinessReport = report);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
    if (mounted) setState(() => _isRunningReadiness = false);
  }

  Future<void> _runStressTest() async {
    setState(() => _isRunningStress = true);
    try {
      final service = FiscalYearStressTestService();
      final result = await service.runBenchmark();
      if (mounted) setState(() => _stressResult = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
    if (mounted) setState(() => _isRunningStress = false);
  }

  Widget _buildDiagnosticsReport() {
    final report = _diagnosticsReport!;
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('تقرير التشخيص', style: AppTheme.heading3),
                const Spacer(),
                _scoreBadge(report.overallScore),
              ],
            ),
            const SizedBox(height: 12),
            ...report.checks.map((check) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    check.status == DiagnosticStatus.pass ? Icons.check_circle
                        : check.status == DiagnosticStatus.warning ? Icons.warning
                        : check.status == DiagnosticStatus.failed ? Icons.error
                        : Icons.info_outline,
                    size: 16,
                    color: check.status == DiagnosticStatus.pass ? AppTheme.success
                        : check.status == DiagnosticStatus.warning ? AppTheme.warning
                        : check.status == DiagnosticStatus.failed ? AppTheme.danger
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(check.nameAr, style: AppTheme.body.copyWith(fontSize: 13))),
                  if (check.messageAr != null)
                    Text(check.messageAr!, style: AppTheme.body.copyWith(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationReport() {
    final report = _validationReport!;
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, color: AppTheme.success, size: 20),
                const SizedBox(width: 8),
                Text('التحقق النهائي من الإنتاج', style: AppTheme.heading3),
                const Spacer(),
                _scoreBadge(report.overallScore),
              ],
            ),
            const SizedBox(height: 12),
            ...report.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    item.status == 'PASS' ? Icons.check_circle
                        : item.status == 'WARNING' ? Icons.warning
                        : Icons.error,
                    size: 16,
                    color: item.status == 'PASS' ? AppTheme.success
                        : item.status == 'WARNING' ? AppTheme.warning
                        : AppTheme.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.nameAr, style: AppTheme.body.copyWith(fontSize: 13))),
                  Text(item.status, style: AppTheme.body.copyWith(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessReport() {
    final report = _readinessReport!;
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: AppTheme.warning, size: 20),
                const SizedBox(width: 8),
                Text('تقرير جاهزية الإغلاق', style: AppTheme.heading3),
                const Spacer(),
                _scoreBadge(report.overallScore),
              ],
            ),
            const SizedBox(height: 12),
            ...report.sections.map((section) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    section.score >= 90 ? Icons.check_circle
                        : section.score >= 70 ? Icons.warning
                        : Icons.error,
                    size: 16,
                    color: section.score >= 90 ? AppTheme.success
                        : section.score >= 70 ? AppTheme.warning
                        : AppTheme.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(section.nameAr, style: AppTheme.body.copyWith(fontSize: 13))),
                  _scoreBadge(section.score),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildStressTestReport() {
    final result = _stressResult!;
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: AppTheme.danger, size: 20),
                const SizedBox(width: 8),
                Text('تقرير اختبار الأداء', style: AppTheme.heading3),
              ],
            ),
            const SizedBox(height: 12),
            _stressMetric('وقت التنفيذ', '${result.executionTime.inSeconds} ثانية'),
            _stressMetric('الذاكرة القصوى', '${(result.peakMemoryBytes / 1024 / 1024).toStringAsFixed(1)} MB'),
            _stressMetric('متوسط وقت الاستعلام', '${result.avgQueryTimeMs.toStringAsFixed(3)} ms'),
            _stressMetric('صف/ثانية', result.rowsPerSecond.toStringAsFixed(0)),
            _stressMetric('وقت CPU', '${result.cpuTime.inMilliseconds} ms'),
          ],
        ),
      ),
    );
  }

  Widget _stressMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.body.copyWith(fontSize: 13)),
          Text(value, style: AppTheme.body.copyWith(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _scoreBadge(double score) {
    final color = score >= 90 ? AppTheme.success : score >= 70 ? AppTheme.warning : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text('${score.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
