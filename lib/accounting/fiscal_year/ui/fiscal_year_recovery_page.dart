import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../cubit/fiscal_year_cubit.dart';
import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';
import 'reopen_fiscal_year_dialog.dart';

class FiscalYearRecoveryPage extends StatefulWidget {
  const FiscalYearRecoveryPage({super.key});

  @override
  State<FiscalYearRecoveryPage> createState() => _FiscalYearRecoveryPageState();
}

class _FiscalYearRecoveryPageState extends State<FiscalYearRecoveryPage> {
  @override
  void initState() {
    super.initState();
    context.read<FiscalYearCubit>().loadFiscalYears();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('مركز الاسترداد'),
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
          if (state is FiscalYearClosingInProgress) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text(state.progress.currentStep ?? 'جاري الإغلاق...', style: AppTheme.heading3),
                ],
              ),
            );
          }
          if (state is FiscalYearClosingFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                    const SizedBox(height: 16),
                    const Text('فشل الإغلاق:', style: AppTheme.heading3),
                    const SizedBox(height: 8),
                    Text(state.message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.read<FiscalYearCubit>().loadFiscalYears(),
                      child: const Text('المحاولة مرة أخرى'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is FiscalYearClosingSuccess) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
                  const SizedBox(height: 16),
                  const Text('تم إقفال السنة المالية بنجاح', style: AppTheme.heading3),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('رجوع'),
                  ),
                ],
              ),
            );
          }
          if (state is FiscalYearLoaded) {
            return _buildRecoveryCenter(state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildRecoveryCenter(FiscalYearLoaded state) {
    final closingYears = state.fiscalYears.where((f) => f.status == FiscalYearStatus.closing).toList();
    final closedYears = state.closedYears;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('عمليات الإغلاق المعلقة', Icons.pending_actions, AppTheme.warning),
          if (closingYears.isEmpty)
            _buildEmptyState('لا توجد عمليات إغلاق معلقة')
          else
            ...closingYears.map((fy) => _buildClosingIssueCard(fy, state)),
          const SizedBox(height: 24),
          _buildSectionHeader('سجل الإغلاق', Icons.history, AppTheme.primary),
          if (closedYears.isEmpty)
            _buildEmptyState('لا توجد سنوات مغلقة')
          else
            ...closedYears.map((fy) => _buildClosedYearCard(fy)),
          const SizedBox(height: 24),
          _buildSectionHeader('حالة القفل الموزع', Icons.lock, AppTheme.info),
          _buildLockStatusCard(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: AppTheme.heading3),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(message, style: AppTheme.body)),
      ),
    );
  }

  Widget _buildClosingIssueCard(FiscalYear fy, FiscalYearLoaded state) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.warning)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: AppTheme.warning, size: 20),
                const SizedBox(width: 8),
                Text('سنة مالية ${fy.year} – عملية إغلاق معلقة', style: AppTheme.heading3),
              ],
            ),
            const SizedBox(height: 8),
            Text('الحالة: ${fy.status.displayNameAr}', style: AppTheme.body),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _forceRollback(fy),
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('إعادة تعيين'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _resumeClosing(fy),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('متابعة'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedYearCard(FiscalYear fy) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: ListTile(
        leading: Icon(Icons.check_circle, color: AppTheme.success),
        title: Text('السنة المالية ${fy.year}', style: AppTheme.heading3),
        subtitle: Text(
          'أُغلقت في ${fy.closedAt != null ? _formatDate(fy.closedAt!) : '-'}',
          style: AppTheme.body,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fy.status == FiscalYearStatus.closed)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'إعادة فتح',
                onPressed: () => _reopenFiscalYear(fy),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockStatusCard() {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_open, color: AppTheme.success, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('القفل متاح', style: AppTheme.heading3),
                Text('لا توجد عمليات إغلاق جارية', style: AppTheme.body),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _forceRollback(FiscalYear fy) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('إعادة تعيين السنة المالية ${fy.year}', style: AppTheme.heading3),
        content: Text('هل تريد إعادة تعيين حالة السنة المالية إلى نشطة؟ سيتم حفظ هذا الإجراء في سجل التدقيق.', style: AppTheme.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<FiscalYearCubit>().reopenFiscalYear(
            fiscalYearId: fy.id,
            userId: 'current_user',
            reason: 'إعادة تعيين من مركز الاسترداد',
          );
    }
  }

  void _resumeClosing(FiscalYear fy) async {
    context.read<FiscalYearCubit>().closeFiscalYear(
          fiscalYearId: fy.id,
          userId: 'current_user',
          createNextYear: true,
        );
  }

  void _reopenFiscalYear(FiscalYear fy) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReopenFiscalYearDialog(fiscalYear: fy),
    );

    if (reason != null && mounted) {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '00000000-0000-0000-0000-000000000000';
      context.read<FiscalYearCubit>().reopenFiscalYear(
            fiscalYearId: fy.id,
            userId: userId,
            reason: reason,
          );
    }
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
