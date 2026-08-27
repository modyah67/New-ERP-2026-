import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../cubit/fiscal_year_cubit.dart';
import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';
import '../services/health_check_service.dart';

class FiscalYearDashboardPage extends StatefulWidget {
  const FiscalYearDashboardPage({super.key});

  @override
  State<FiscalYearDashboardPage> createState() => _FiscalYearDashboardPageState();
}

class _FiscalYearDashboardPageState extends State<FiscalYearDashboardPage> {
  List<HealthCheckItem> _healthChecks = [];
  bool _isLoadingHealth = false;

  @override
  void initState() {
    super.initState();
    context.read<FiscalYearCubit>().loadFiscalYears();
    _loadHealthChecks();
  }

  Future<void> _loadHealthChecks() async {
    setState(() => _isLoadingHealth = true);
    try {
      final state = context.read<FiscalYearCubit>().state;
      if (state is FiscalYearLoaded && state.currentFiscalYear != null) {
        final healthCheck = FiscalYearHealthCheck();
        final checks = await healthCheck.runAllChecks(state.currentFiscalYear!.id);
        if (mounted) setState(() => _healthChecks = checks);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingHealth = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('لوحة السنة المالية'),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
      ),
      body: BlocBuilder<FiscalYearCubit, FiscalYearState>(
        builder: (context, state) {
          if (state is FiscalYearLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (state is FiscalYearLoaded) {
            return _buildDashboard(state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildDashboard(FiscalYearLoaded state) {
    final current = state.currentFiscalYear;
    final healthScore = _healthChecks.isEmpty ? 0.0 : FiscalYearHealthCheck().calculateReadinessScore(_healthChecks);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current != null) _buildCurrentFyCard(current),
          const SizedBox(height: 16),
          _buildReadinessCard(healthScore),
          const SizedBox(height: 16),
          _buildHealthCheckList(),
          const SizedBox(height: 16),
          _buildQuickStats(state),
        ],
      ),
    );
  }

  Widget _buildCurrentFyCard(FiscalYear fy) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('السنة المالية الحالية', style: AppTheme.heading3),
                const Spacer(),
                _statusChip(fy.status),
              ],
            ),
            const SizedBox(height: 12),
            Text('${fy.year} – ${fy.name}', style: AppTheme.heading2),
            const SizedBox(height: 8),
            Text('من ${_formatDate(fy.startDate)} إلى ${_formatDate(fy.endDate)}', style: AppTheme.body),
            const SizedBox(height: 8),
            Row(
              children: [
                _infoChip('الأيام المتبقية', '${fy.daysRemaining}'),
                const SizedBox(width: 8),
                if (fy.closedAt != null)
                  _infoChip('تاريخ الإغلاق', _formatDate(fy.closedAt!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessCard(double score) {
    final color = score >= 90 ? AppTheme.success : score >= 70 ? AppTheme.warning : AppTheme.danger;
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('جاهزية الإغلاق', style: AppTheme.heading3),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: AppTheme.border,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${score.toStringAsFixed(0)}%', style: AppTheme.heading2.copyWith(color: color)),
                    Text(
                      score >= 90 ? 'جاهز للإغلاق' : score >= 70 ? 'يحتاج مراجعة' : 'غير جاهز',
                      style: AppTheme.body.copyWith(color: color),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCheckList() {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('فحص الحالة', style: AppTheme.heading3),
                const Spacer(),
                if (_isLoadingHealth)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadHealthChecks,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_healthChecks.isEmpty)
              const Text('اضغط على تحديث لفحص الحالة', style: AppTheme.body)
            else
              ..._healthChecks.map((check) => _buildHealthCheckItem(check)),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCheckItem(HealthCheckItem check) {
    IconData icon;
    Color color;
    switch (check.status) {
      case HealthStatus.pass:
        icon = Icons.check_circle;
        color = AppTheme.success;
        break;
      case HealthStatus.warning:
        icon = Icons.warning;
        color = AppTheme.warning;
        break;
      case HealthStatus.failed:
        icon = Icons.error;
        color = AppTheme.danger;
        break;
      case HealthStatus.pending:
        icon = Icons.hourglass_empty;
        color = AppTheme.textMuted;
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(check.nameAr, style: AppTheme.body)),
          if (check.message != null)
            Text(check.message!, style: AppTheme.body.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildQuickStats(FiscalYearLoaded state) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ملخص', style: AppTheme.heading3),
            const SizedBox(height: 12),
            Row(
              children: [
                _infoChip('إجمالي السنوات', '${state.fiscalYears.length}'),
                const SizedBox(width: 8),
                _infoChip('السنوات المغلقة', '${state.closedYears.length}'),
                const SizedBox(width: 8),
                _infoChip('السنوات النشطة', '${state.fiscalYears.where((f) => f.status == FiscalYearStatus.active).length}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(FiscalYearStatus status) {
    Color color;
    switch (status) {
      case FiscalYearStatus.draft: color = AppTheme.textSecondary; break;
      case FiscalYearStatus.active: color = AppTheme.success; break;
      case FiscalYearStatus.closing: color = AppTheme.warning; break;
      case FiscalYearStatus.closed: color = AppTheme.danger; break;
      case FiscalYearStatus.archived: color = AppTheme.textMuted; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: color)),
      child: Text(status.displayNameAr, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(value, style: AppTheme.heading3),
          Text(label, style: AppTheme.body.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
