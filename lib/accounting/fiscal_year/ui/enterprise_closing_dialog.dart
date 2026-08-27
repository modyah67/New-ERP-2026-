import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../services/progress_service.dart';

class EnterpriseClosingDialog extends StatefulWidget {
  final int fiscalYearId;
  final String fiscalYearName;
  final Stream<ClosingProgressEvent> progressStream;
  final VoidCallback? onCancel;

  const EnterpriseClosingDialog({
    super.key,
    required this.fiscalYearId,
    required this.fiscalYearName,
    required this.progressStream,
    this.onCancel,
  });

  static Future<void> show({
    required BuildContext context,
    required int fiscalYearId,
    required String fiscalYearName,
    required Stream<ClosingProgressEvent> progressStream,
    VoidCallback? onCancel,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EnterpriseClosingDialog(
        fiscalYearId: fiscalYearId,
        fiscalYearName: fiscalYearName,
        progressStream: progressStream,
        onCancel: onCancel,
      ),
    );
  }

  @override
  State<EnterpriseClosingDialog> createState() => _EnterpriseClosingDialogState();
}

class _EnterpriseClosingDialogState extends State<EnterpriseClosingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<ClosingProgressEvent>? _subscription;

  ClosingProgressEvent? _currentEvent;
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  bool _isComplete = false;
  bool _isFailed = false;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _subscription = widget.progressStream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _currentEvent = event;
          if (event.logs.isNotEmpty) {
            _logs.addAll(event.logs);
            if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
          }
          if (event.warnings.isNotEmpty) {
            for (final w in event.warnings) {
              _logs.add('[WARNING] $w');
            }
          }
          _isComplete = event.phase == ProgressEventPhase.completed;
          _isFailed = event.phase == ProgressEventPhase.failed;
        });
        _scrollLogs();
        if (_isComplete || _isFailed) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop(event);
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isFailed = true);
        }
      },
    );
  }

  void _scrollLogs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _currentEvent;
    final elapsed = _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;
    final canCancel = event?.canCancel ?? true;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(event),
            const SizedBox(height: 16),
            _buildProgressBar(event),
            const SizedBox(height: 16),
            _buildDetailsGrid(event, elapsed),
            const SizedBox(height: 12),
            if (event?.warnings.isNotEmpty == true) _buildWarnings(event!),
            _buildLogPanel(),
            const SizedBox(height: 16),
            _buildActions(canCancel),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ClosingProgressEvent? event) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, __) => Transform.scale(
            scale: _isComplete ? 1.0 : _pulseAnimation.value,
            child: Icon(
              _isComplete ? Icons.check_circle
                  : _isFailed ? Icons.error
                  : Icons.sync,
              color: _isComplete ? AppTheme.success
                  : _isFailed ? AppTheme.danger
                  : AppTheme.primary,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isComplete ? 'اكتمل الإغلاق'
                    : _isFailed ? 'فشل الإغلاق'
                    : 'جاري إغلاق السنة المالية',
                style: AppTheme.heading3,
              ),
              Text(
                widget.fiscalYearName,
                style: AppTheme.body.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(ClosingProgressEvent? event) {
    final pct = event?.progressPct ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(event?.currentStep ?? 'الإعداد...', style: AppTheme.body),
            Text('$pct%', style: AppTheme.body.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct / 100.0,
            backgroundColor: AppTheme.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              _isComplete ? AppTheme.success
                  : _isFailed ? AppTheme.danger
                  : AppTheme.primary,
            ),
            minHeight: 10,
          ),
        ),
        if (event?.currentOperation.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(
            event!.currentOperation,
            style: AppTheme.body.copyWith(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsGrid(ClosingProgressEvent? event, Duration elapsed) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _detailChip('الوقت المنقضي', _formatDuration(elapsed)),
        if (event?.estimatedRemaining != null)
          _detailChip('الوقت المتبقي المتوقع', _formatDuration(event!.estimatedRemaining!)),
        if (event?.rowsProcessed != null)
          _detailChip('الصفوف', '${event!.rowsProcessed} / ${event.totalRows ?? '?'}'),
        if (event?.currentTable != null)
          _detailChip('الجدول الحالي', event!.currentTable!),
      ],
    );
  }

  Widget _detailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.body.copyWith(fontSize: 10, color: AppTheme.textMuted)),
          Text(value, style: AppTheme.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildWarnings(ClosingProgressEvent event) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: event.warnings.take(5).map((w) => Row(
          children: [
            Icon(Icons.warning_amber, size: 14, color: AppTheme.warning),
            const SizedBox(width: 4),
            Expanded(child: Text(w, style: AppTheme.body.copyWith(fontSize: 11, color: AppTheme.warning))),
          ],
        )).toList(),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      height: 120,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: _logs.isEmpty
          ? Center(child: Text('في انتظار السجلات...', style: AppTheme.body.copyWith(color: AppTheme.textMuted, fontSize: 11)))
          : ListView.builder(
              controller: _logScrollController,
              itemCount: _logs.length,
              itemBuilder: (_, i) => Text(
                _logs[i],
                style: AppTheme.body.copyWith(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: _logs[i].startsWith('[WARNING]') ? AppTheme.warning : AppTheme.textSecondary,
                ),
              ),
            ),
    );
  }

  Widget _buildActions(bool canCancel) {
    if (_isComplete) {
      return Row(
        children: [
          Icon(Icons.check_circle, color: AppTheme.success, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تم الإغلاق بنجاح', style: AppTheme.body.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold)),
                if (_currentEvent?.metadata != null) ...[
                  Text('قيود الإغلاق: ${_currentEvent!.metadata!['closing_entries'] ?? '-'}', style: AppTheme.body.copyWith(fontSize: 11)),
                  Text('قيود الافتتاح: ${_currentEvent!.metadata!['opening_entries'] ?? '-'}', style: AppTheme.body.copyWith(fontSize: 11)),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_currentEvent),
            child: const Text('إغلاق'),
          ),
        ],
      );
    }

    if (_isFailed) {
      return Row(
        children: [
          Icon(Icons.error, color: AppTheme.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentEvent?.errorMessage ?? 'فشل غير معروف',
              style: AppTheme.body.copyWith(color: AppTheme.danger, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_currentEvent),
            child: const Text('إغلاق'),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (canCancel)
          OutlinedButton(
            onPressed: () {
              widget.onCancel?.call();
              Navigator.of(context).pop(null);
            },
            style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.danger)),
            child: Text('إلغاء', style: TextStyle(color: AppTheme.danger)),
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}س ${d.inMinutes % 60}د';
    if (d.inMinutes > 0) return '${d.inMinutes}د ${d.inSeconds % 60}ث';
    return '${d.inSeconds}ث';
  }
}
