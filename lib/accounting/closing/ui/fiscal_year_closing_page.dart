import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../fiscal_year/cubit/fiscal_year_cubit.dart';
import '../../fiscal_year/models/fiscal_year.dart';
import '../../fiscal_year/models/fiscal_year_status.dart';
import '../../fiscal_year/models/closing_progress.dart';
import '../../fiscal_year/models/closing_result.dart';

class FiscalYearClosingPage extends StatefulWidget {
  const FiscalYearClosingPage({super.key});

  @override
  State<FiscalYearClosingPage> createState() => _FiscalYearClosingPageState();
}

class _FiscalYearClosingPageState extends State<FiscalYearClosingPage> {
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
        title: const Text('نهاية السنة المالية'),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.go('/accounting'),
        ),
      ),
      body: BlocConsumer<FiscalYearCubit, FiscalYearState>(
        listener: (context, state) {
          if (state is FiscalYearClosingInProgress) {
            _showProgressDialog(context, state.progress);
          } else if (state is FiscalYearClosingSuccess) {
            Navigator.of(context).pop();
            _showClosingReport(state);
          } else if (state is FiscalYearClosingFailure) {
            Navigator.of(context).pop();
            _showErrorSnackBar(state.message);
          } else if (state is FiscalYearReopeningSuccess) {
            _showSuccessSnackBar(state.message);
          } else if (state is FiscalYearReopeningFailure) {
            _showErrorSnackBar(state.message);
          } else if (state is FiscalYearValidationSuccess) {
            _showSuccessSnackBar(state.messages.join('\n'));
          } else if (state is FiscalYearValidationFailure) {
            _showValidationErrors(state.errors);
          }
        },
        builder: (context, state) {
          if (state is FiscalYearLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          final fyState = state is FiscalYearLoaded ? state : null;

          if (fyState == null) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          return Column(
            children: [
              _buildHeader(fyState),
              Expanded(child: _buildFiscalYearList(fyState, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(FiscalYearLoaded state) {
    final current = state.currentFiscalYear;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current != null) ...[
            Text('السنة المالية الحالية: ${current.year}', style: AppTheme.heading2),
            const SizedBox(height: 4),
            Text(
              'من ${_formatDate(current.startDate)} إلى ${_formatDate(current.endDate)}',
              style: AppTheme.body,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _statusChip(current.status),
                const SizedBox(width: 12),
                Text('الأيام المتبقية: ${current.daysRemaining}', style: AppTheme.body),
              ],
            ),
          ] else
            Text('لا توجد سنة مالية حالية', style: AppTheme.heading3),
        ],
      ),
    );
  }

  Widget _buildFiscalYearList(FiscalYearLoaded state, FiscalYearState currentState) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.fiscalYears.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final fy = state.fiscalYears[index];
        return _buildFiscalYearCard(fy, currentState);
      },
    );
  }

  Widget _buildFiscalYearCard(FiscalYear fy, FiscalYearState currentState) {
    final isClosing = currentState is FiscalYearClosingInProgress &&
        currentState.progress.fiscalYearId == fy.id;

    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${fy.year} – ${fy.name}', style: AppTheme.heading3),
                const Spacer(),
                _statusChip(fy.status),
                if (fy.isCurrent) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'من ${_formatDate(fy.startDate)} إلى ${_formatDate(fy.endDate)}',
              style: AppTheme.body,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (fy.status.canTransitionToClosing)
                  _actionButton(
                    'إغلاق',
                    Icons.lock_clock,
                    AppTheme.warning,
                    () => _closeFiscalYear(fy),
                  ),
                if (fy.status == FiscalYearStatus.closing)
                  _actionButton(
                    'إغلاق',
                    Icons.lock_clock,
                    AppTheme.warning,
                    null,
                    enabled: false,
                  ),
                if (fy.status == FiscalYearStatus.closed)
                  _actionButton(
                    'إعادة فتح',
                    Icons.lock_open,
                    AppTheme.primary,
                    () => _reopenFiscalYear(fy),
                  ),
                if (fy.status == FiscalYearStatus.closed)
                  _actionButton(
                    'أرشفة',
                    Icons.archive,
                    AppTheme.textSecondary,
                    () => _archiveFiscalYear(fy),
                  ),
                if (!fy.isCurrent && fy.status == FiscalYearStatus.active)
                  _actionButton(
                    'تعيين حالية',
                    Icons.play_arrow,
                    AppTheme.success,
                    () => _setCurrent(fy),
                  ),
              ],
            ),
            if (isClosing) ...[
              const SizedBox(height: 12),
              _buildClosingProgress(
                (currentState as FiscalYearClosingInProgress).progress,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClosingProgress(ClosingProgress progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(progress.status.displayNameAr, style: AppTheme.body),
            const Spacer(),
            Text('${progress.progressPct}%', style: AppTheme.body),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress.progressPct / 100.0,
          backgroundColor: AppTheme.border,
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
        ),
        if (progress.currentStep != null) ...[
          const SizedBox(height: 4),
          Text(progress.currentStep!, style: AppTheme.body),
        ],
        if (progress.errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(progress.errorMessage!, style: AppTheme.body.copyWith(color: AppTheme.danger)),
        ],
      ],
    );
  }

  Widget _statusChip(FiscalYearStatus status) {
    Color color;
    switch (status) {
      case FiscalYearStatus.draft:
        color = AppTheme.textSecondary;
        break;
      case FiscalYearStatus.active:
        color = AppTheme.success;
        break;
      case FiscalYearStatus.closing:
        color = AppTheme.warning;
        break;
      case FiscalYearStatus.closed:
        color = AppTheme.danger;
        break;
      case FiscalYearStatus.archived:
        color = AppTheme.textMuted;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(status.displayNameAr, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback? onPressed, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? color.withValues(alpha: 0.2) : AppTheme.surface,
          foregroundColor: enabled ? color : AppTheme.textMuted,
          side: BorderSide(color: enabled ? color : AppTheme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _closeFiscalYear(FiscalYear fy) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('إغلاق السنة المالية ${fy.year}', style: AppTheme.heading3),
        content: Text(
          'هل أنت متأكد من إغلاق السنة المالية ${fy.year}؟\n\n'
          'سيتم:\n'
          '• إنشاء قيود إغلاق للحسابات المؤقتة\n'
          '• تحويل صافي الدخل إلى الأرباح المحتجزة\n'
          '• إنشاء قيود افتتاحية للسنة التالية\n'
          '• حفظ لقطة مخزون\n\n'
          'لا يمكن التراجع عن هذا الإجراء.',
          style: AppTheme.body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<FiscalYearCubit>().closeFiscalYear(
            fiscalYearId: fy.id,
            userId: 'current_user',
            createNextYear: true,
          );
    }
  }

  void _reopenFiscalYear(FiscalYear fy) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('إعادة فتح السنة المالية ${fy.year}', style: AppTheme.heading3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('هل أنت متأكد من إعادة فتح السنة المالية ${fy.year}؟', style: AppTheme.body),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'سبب إعادة الفتح (مطلوب)',
                border: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('إعادة فتح'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<FiscalYearCubit>().reopenFiscalYear(
            fiscalYearId: fy.id,
            userId: 'current_user',
            reason: reasonController.text,
          );
    }
    reasonController.dispose();
  }

  void _archiveFiscalYear(FiscalYear fy) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('أرشفة السنة المالية ${fy.year}', style: AppTheme.heading3),
        content: Text('هل أنت متأكد من أرشفة السنة المالية ${fy.year}؟', style: AppTheme.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.textSecondary),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<FiscalYearCubit>().archiveFiscalYear(
            fiscalYearId: fy.id,
            userId: 'current_user',
          );
    }
  }

  void _setCurrent(FiscalYear fy) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('تعيين كسنة حالية'),
        content: Text('هل تريد تعيين السنة المالية ${fy.year} كالسنة الحالية؟', style: AppTheme.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('نعم'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<FiscalYearCubit>().setCurrent(fy.id, performedBy: 'current_user');
    }
  }

  void _showProgressDialog(BuildContext context, ClosingProgress progress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progress: progress),
    );
  }

  void _showClosingReport(FiscalYearClosingSuccess state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('تقرير الإغلاق', style: AppTheme.heading3),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('صافي الدخل: ${state.netIncome.toStringAsFixed(2)} ج.م', style: AppTheme.body),
              const SizedBox(height: 8),
              Text('قيود الإغلاق: ${state.closingEntries.length}', style: AppTheme.body),
              if (state.result.durationFormatted != '-')
                Text('المدة: ${state.result.durationFormatted}', style: AppTheme.body),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  void _showValidationErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('مشاكل يجب إصلاحها', style: AppTheme.heading3),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: errors.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e, style: AppTheme.body)),
                ],
              ),
            )).toList(),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.success),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ProgressDialog extends StatefulWidget {
  final ClosingProgress progress;
  const _ProgressDialog({required this.progress});

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  late DateTime _startTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startTime);
    final pct = widget.progress.progressPct / 100.0;
    final estimated = pct > 0 ? Duration(milliseconds: (elapsed.inMilliseconds / pct * (1 - pct)).round()) : null;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.progress.status.displayNameAr, style: AppTheme.heading3),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            minHeight: 8,
          ),
          const SizedBox(height: 12),
          Text('${widget.progress.progressPct}%', style: AppTheme.heading2),
          if (widget.progress.currentStep != null) ...[
            const SizedBox(height: 8),
            Text(widget.progress.currentStep!, style: AppTheme.body),
          ],
          const SizedBox(height: 8),
          Text('الوقت المنقضي: ${_formatDuration(elapsed)}', style: AppTheme.body),
          if (estimated != null && widget.progress.progressPct < 100)
            Text('الوقت المتبقي: ~${_formatDuration(estimated)}', style: AppTheme.body),
          if (widget.progress.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(widget.progress.errorMessage!,
                style: AppTheme.body.copyWith(color: AppTheme.danger)),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
