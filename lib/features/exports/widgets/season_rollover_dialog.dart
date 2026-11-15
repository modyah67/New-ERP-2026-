import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme.dart';
import '../../../data/models/cost_center.dart';
import '../../../data/services/cost_center_service.dart';

class SeasonRolloverDialog extends StatefulWidget {
  final CostCenter? initialCostCenter;
  final List<CostCenter> activeCostCenters;
  final double? currentNetBalance;
  final int? transactionCount;
  final VoidCallback? onRolloverCompleted;

  const SeasonRolloverDialog({
    super.key,
    this.initialCostCenter,
    required this.activeCostCenters,
    this.currentNetBalance,
    this.transactionCount,
    this.onRolloverCompleted,
  });

  static Future<bool?> show(
    BuildContext context, {
    CostCenter? costCenter,
    required List<CostCenter> activeCostCenters,
    double? currentNetBalance,
    int? transactionCount,
    VoidCallback? onRolloverCompleted,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SeasonRolloverDialog(
        initialCostCenter: costCenter,
        activeCostCenters: activeCostCenters,
        currentNetBalance: currentNetBalance,
        transactionCount: transactionCount,
        onRolloverCompleted: onRolloverCompleted,
      ),
    );
  }

  @override
  State<SeasonRolloverDialog> createState() => _SeasonRolloverDialogState();
}

class _SeasonRolloverDialogState extends State<SeasonRolloverDialog> {
  final _service = CostCenterService.instance;
  final _nextSeasonCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  CostCenter? _selectedCenter;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Prefer seasonal/variety cost centers that are open
    final candidates = widget.activeCostCenters
        .where((c) => c.type == CostCenterType.variety && !c.isClosed)
        .toList();

    if (widget.initialCostCenter != null) {
      final initialId = widget.initialCostCenter!.id.toLowerCase();
      final initialCode = widget.initialCostCenter!.code?.toLowerCase();
      CostCenter? matched;
      for (final c in widget.activeCostCenters) {
        if (c.id.toLowerCase() == initialId ||
            (initialCode != null && c.id.toLowerCase() == initialCode) ||
            (c.code != null && c.code!.toLowerCase() == initialId) ||
            (c.code != null && initialCode != null && c.code!.toLowerCase() == initialCode)) {
          matched = c;
          break;
        }
      }
      _selectedCenter = matched ?? widget.initialCostCenter;
    } else if (candidates.isNotEmpty) {
      _selectedCenter = candidates.first;
    } else if (widget.activeCostCenters.isNotEmpty) {
      _selectedCenter = widget.activeCostCenters.firstWhere(
        (c) => !c.isClosed,
        orElse: () => widget.activeCostCenters.first,
      );
    }

    _updateNextSeasonDefault();
  }

  @override
  void dispose() {
    _nextSeasonCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _updateNextSeasonDefault() {
    final center = _selectedCenter;
    final currentSeason = center?.season?.trim() ?? '2026-2027';
    final isFinal = center?.isFinalSeason ?? false;
    _nextSeasonCtrl.text = _computeNextSeason(currentSeason, isFinal: isFinal);
  }

  /// Calculates next season string:
  /// - Stage 1 (Period 1 to 2): preserves current season year range (e.g. "2026-2027")
  /// - Stage 2 (Final closure): increments sequentially to next year (e.g. "2026-2027" -> "2027-2028")
  static String _computeNextSeason(String currentSeason, {bool isFinal = false}) {
    final yearMatch = RegExp(r'(\d{4})').firstMatch(currentSeason);
    if (yearMatch != null) {
      final startYear = int.tryParse(yearMatch.group(1)!) ?? 2026;
      if (isFinal) {
        final nextStart = startYear + 1;
        final nextEnd = nextStart + 1;
        return '$nextStart-$nextEnd';
      } else {
        final nextEnd = startYear + 1;
        return '$startYear-$nextEnd';
      }
    }

    final nowYear = DateTime.now().year;
    return isFinal ? '$nowYear-${nowYear + 1}' : currentSeason;
  }

  /// Dynamic suggestions based on closure stage
  List<String> get _seasonSuggestions {
    final center = _selectedCenter;
    final cur = center?.season ?? '';
    final m = RegExp(r'(\d{4})').firstMatch(cur);
    final baseYear = m != null ? (int.tryParse(m.group(1)!) ?? 2026) : 2026;
    final isFinal = center?.isFinalSeason ?? false;

    if (!isFinal) {
      return [
        '$baseYear-${baseYear + 1}',
      ];
    } else {
      return [
        '${baseYear + 1}-${baseYear + 2}',
        '${baseYear + 2}-${baseYear + 3}',
        '${baseYear + 3}-${baseYear + 4}',
      ];
    }
  }

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);

  /// Safely deduplicated cost centers for dropdown selection, ensuring _selectedCenter is always present
  List<CostCenter> get _dropdownCenters {
    final seenIds = <String>{};
    final list = <CostCenter>[];

    // If _selectedCenter is set, ensure it is added first
    if (_selectedCenter != null) {
      list.add(_selectedCenter!);
      seenIds.add(_selectedCenter!.id.toLowerCase());
      if (_selectedCenter!.code != null && _selectedCenter!.code!.isNotEmpty) {
        seenIds.add(_selectedCenter!.code!.toLowerCase());
      }
    }

    for (final cc in widget.activeCostCenters) {
      final idLower = cc.id.toLowerCase();
      final codeLower = cc.code?.toLowerCase();

      // Skip duplicates
      if (seenIds.contains(idLower) || (codeLower != null && seenIds.contains(codeLower))) {
        continue;
      }

      // Filter out permanently closed centers unless it matches current selection
      if (cc.isPermanentlyClosed && cc.id != _selectedCenter?.id) {
        continue;
      }

      seenIds.add(idLower);
      if (codeLower != null && codeLower.isNotEmpty) {
        seenIds.add(codeLower);
      }
      list.add(cc);
    }

    return list;
  }

  String get _newSeasonPreviewName {
    final center = _selectedCenter;
    if (center == null) return '—';
    final rawName = center.cropName ?? center.nameAr;
    final cleanCrop = CostCenter.canonicalCropName(rawName);
    final nextSeason = _nextSeasonCtrl.text.trim();
    if (nextSeason.isEmpty) return cleanCrop;
    return '$cleanCrop (موسم $nextSeason)';
  }

  String get _newSeasonPreviewCode {
    final center = _selectedCenter;
    if (center == null) return '—';
    final rawName = center.cropName ?? center.nameAr;
    final cleanCrop = CostCenter.canonicalCropName(rawName);
    final slug = center.cropCode ??
        CostCenterHelper.resolveCropSlug(cleanCrop);
    final nextSeason = _nextSeasonCtrl.text.trim();
    return 'CC-$slug-$nextSeason';
  }

  /// Determines the closure stage label for the dialog header
  String get _closureStageDescription {
    final center = _selectedCenter;
    if (center == null) return '';
    if (center.isPermanentlyClosed) {
      return 'السنة مقفلة نهائياً (للاطلاع فقط) — تم استنفاد الموسمين المسموح بهما';
    }
    if (center.isClosed) {
      return 'مركز التكلفة مقفل بالفعل';
    }
    if (center.isFinalSeason) {
      return 'الإقفال النهائي للسنة الزراعية — سيتم إقفال الكارت الحالي نهائياً (للاطلاع فقط) وإنشاء كارت جديد للسنة القادمة';
    }
    return 'إقفال الفترة الأولى والترحيل إلى الفترة الثانية داخل نفس كارت مركز التكلفة الحالي بدون إنشاء كارت جديد';
  }

  /// Whether the currently selected center is eligible for closure
  bool get _canPerformClosure {
    final center = _selectedCenter;
    if (center == null) return false;
    return center.canClose;
  }

  /// Show final closure confirmation dialog
  Future<bool> _confirmFinalClosure() async {
    final center = _selectedCenter;
    if (center == null) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F1E36) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تأكيد الإقفال النهائي للسنة الزراعية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أنت على وشك إقفال الموسم الثاني والأخير لمركز التكلفة:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        center.nameAr,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '⚠️ هذا الإجراء نهائي ولا يمكن التراجع عنه:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• سيتم إقفال السنة الزراعية نهائياً\n'
                  '• لن يكون ممكناً إجراء أي ترحيل إضافي على هذا المركز\n'
                  '• سيتم ترحيل الرصيد المتبقي إلى مركز تكلفة جديد للسنة القادمة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF475569),
                    height: 1.8,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'تراجع',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'تأكيد الإقفال النهائي',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _submitRollover() async {
    final center = _selectedCenter;
    if (center == null) {
      setState(() => _errorMessage = 'يرجى اختيار مركز التكلفة المراد إقفاله');
      return;
    }

    if (center.isPermanentlyClosed) {
      setState(() => _errorMessage = 'مركز التكلفة (${center.nameAr}) مقفل نهائياً للسنة الزراعية. تم استنفاد الموسمين المسموح بهما.');
      return;
    }

    if (center.isClosed) {
      setState(() => _errorMessage = 'مركز التكلفة (${center.nameAr}) مقفل بالفعل ولا يمكن تكرار إقفاله أو ترحيله.');
      return;
    }

    String nextSeason = _nextSeasonCtrl.text.trim();
    if (!center.isFinalSeason) {
      if (nextSeason.isEmpty) {
        nextSeason = center.season ?? '2026-2027';
      }
    } else {
      if (nextSeason.isEmpty) {
        setState(() => _errorMessage = 'يرجى إدخال اسم السنة الزراعية الجديدة (مثال: 2027-2028)');
        return;
      }
      // Validate 4-digit year format
      final yearMatch = RegExp(r'(\d{4})').firstMatch(nextSeason);
      if (yearMatch == null) {
        setState(() => _errorMessage = 'تنسيق السنة الزراعية غير صحيح (مثال: 2027-2028)');
        return;
      }

      // Final closure confirmation
      final confirmed = await _confirmFinalClosure();
      if (!confirmed) return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final idToPass = center.dbId ?? center.code ?? center.id;
      final targetStage = center.isFinalSeason ? 'final_closure' : 'season_1_to_2';
      final isMatchingInitialCenter = widget.initialCostCenter == null ||
          widget.initialCostCenter!.id == center.id ||
          widget.initialCostCenter!.code == center.code;
      final balanceToPass = isMatchingInitialCenter
          ? (widget.currentNetBalance ?? center.currentBalance)
          : center.currentBalance;

      final res = await _service.closeAndRolloverSeason(
        costCenterId: idToPass,
        nextSeason: nextSeason,
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
        targetStage: targetStage,
        overrideRolloverBalance: balanceToPass,
      );

      if (!mounted) return;

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }

      widget.onRolloverCompleted?.call();

      final balance = res['rollover_balance'];
      final balanceStr = (balance is num) ? _fmt(balance.toDouble()) : balance?.toString() ?? '0.00';
      final newName = res['new_cost_center_name']?.toString() ?? _newSeasonPreviewName;
      final isFinal = res['is_final_closure'] == true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFinal
                ? 'تم إقفال السنة الزراعية نهائياً (${center.season}) وتعيين الكارت للاطلاع فقط!\nوإنشاء كارت جديد: $newName برصيد مرحل EGP $balanceStr'
                : 'تم إقفال الفترة الأولى بنجاح والترحيل إلى الفترة الثانية!\nداخل نفس كارت المركز: ${center.nameAr} برصيد مرحل EGP $balanceStr',
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          ),
          backgroundColor: isFinal ? const Color(0xFFD97706) : const Color(0xFF10B981),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = 'فشل تنفيذ الإقفال والترحيل: $e';
      });
    }
  }

  /// Builds the closure stage indicator badge
  Widget _buildStageIndicator() {
    final center = _selectedCenter;
    if (center == null) return const SizedBox.shrink();

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String label;

    if (center.isPermanentlyClosed) {
      bgColor = Colors.redAccent.withValues(alpha: 0.15);
      borderColor = Colors.redAccent.withValues(alpha: 0.4);
      textColor = Colors.redAccent;
      icon = Icons.lock_rounded;
      label = 'السنة مقفلة نهائياً 🔒';
    } else if (center.isClosed) {
      bgColor = Colors.orangeAccent.withValues(alpha: 0.12);
      borderColor = Colors.orangeAccent.withValues(alpha: 0.3);
      textColor = Colors.orangeAccent;
      icon = Icons.lock_outline_rounded;
      label = 'الموسم مقفل بالفعل';
    } else if (center.isFinalSeason) {
      bgColor = Colors.redAccent.withValues(alpha: 0.08);
      borderColor = Colors.redAccent.withValues(alpha: 0.25);
      textColor = Colors.redAccent;
      icon = Icons.warning_amber_rounded;
      label = 'الإقفال النهائي للسنة الزراعية';
    } else {
      bgColor = const Color(0xFF10B981).withValues(alpha: 0.08);
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.25);
      textColor = const Color(0xFF10B981);
      icon = Icons.published_with_changes_rounded;
      label = 'إقفال الموسم الأول ← الموسم الثاني';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (!center.isPermanentlyClosed && !center.isClosed) ...[
                  const SizedBox(height: 2),
                  Text(
                    _closureStageDescription,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Season number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'فترة ${center.seasonNumber}/2',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final centers = _dropdownCenters;
    final center = (_selectedCenter != null && centers.any((c) => c.id == _selectedCenter!.id))
        ? _selectedCenter
        : (centers.isNotEmpty ? centers.first : _selectedCenter);
    final balance = widget.currentNetBalance ?? center?.currentBalance ?? 0.0;
    final txCount = widget.transactionCount;
    final isPermanentlyLocked = center?.isPermanentlyClosed ?? false;
    final isClosedAlready = center?.isClosed ?? false;
    final canClose = _canPerformClosure;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F1E36) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isPermanentlyLocked
                ? Colors.redAccent.withValues(alpha: 0.5)
                : (isDark
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                    : const Color(0xFFCBD5E1)),
            width: 1.5,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isPermanentlyLocked
                              ? [Colors.redAccent, Colors.red.shade800]
                              : (center?.isFinalSeason == true && !isClosedAlready)
                                  ? [Colors.redAccent, const Color(0xFFD97706)]
                                  : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (isPermanentlyLocked
                                    ? Colors.redAccent
                                    : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPermanentlyLocked
                            ? Icons.lock_rounded
                            : Icons.published_with_changes_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPermanentlyLocked
                                ? 'السنة الزراعية مقفلة نهائياً'
                                : (center?.isFinalSeason == true
                                    ? 'الإقفال النهائي للسنة الزراعية'
                                    : 'إقفال وترحيل الفترة (الموسم الأول ← الثاني)'),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            isPermanentlyLocked
                                ? 'تم استنفاد الموسمين المسموح بهما لهذا المركز'
                                : (center?.isFinalSeason == true
                                    ? 'إقفال حسابات السنة الزراعية ونقل الرصيد للسنة الجديدة'
                                    : 'إقفال حسابات الفترة الأولى ونقل الرصيد للفترة الثانية ضمن نفس الموسم'),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Stage Indicator Badge ──
                _buildStageIndicator(),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Cost Center Selector (if not locked) ──
                Text(
                  'مركز التكلفة المراد إقفاله:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF071426) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: center?.id,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF071426) : Colors.white,
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                      items: centers.map((cc) {
                        return DropdownMenuItem<String>(
                          value: cc.id,
                          child: Row(
                            children: [
                              Icon(cc.icon, size: 16, color: cc.isPermanentlyClosed ? Colors.grey : (cc.isClosed ? Colors.orange : cc.color)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  cc.nameAr + (cc.isPermanentlyClosed ? ' (مقفل نهائياً)' : (cc.isClosed ? ' (مقفل)' : '')),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: cc.isPermanentlyClosed
                                        ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                                        : (cc.isClosed
                                            ? (isDark ? Colors.white54 : const Color(0xFF64748B))
                                            : (isDark ? Colors.white : const Color(0xFF0F172A))),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cc.isPermanentlyClosed
                                      ? Colors.redAccent.withValues(alpha: 0.15)
                                      : cc.isClosed
                                          ? Colors.orangeAccent.withValues(alpha: 0.15)
                                          : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  cc.isPermanentlyClosed
                                      ? 'مقفل نهائياً'
                                      : cc.isClosed
                                          ? 'مقفل'
                                          : 'فترة ${cc.seasonNumber}/2',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: cc.isPermanentlyClosed
                                        ? Colors.redAccent
                                        : cc.isClosed
                                            ? Colors.orangeAccent
                                            : const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (newId) {
                        if (newId == null) return;
                        final matched = centers.firstWhere(
                          (c) => c.id == newId,
                          orElse: () => _selectedCenter ?? centers.first,
                        );
                        setState(() {
                          _selectedCenter = matched;
                          _updateNextSeasonDefault();
                        });
                      },
                    ),
                  ),
                ),

                // ── Permanently Closed Banner ──
                if (isPermanentlyLocked) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_rounded, color: Colors.redAccent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هذا المركز مقفل نهائياً للسنة الزراعية.\n'
                            'تم استنفاد الموسمين (الفترة ١ والفترة ٢) ولا يمكن الترحيل.',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (isClosedAlready) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, color: Colors.orangeAccent, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هذا المركز مقفل بالفعل لهذا الموسم وتم ترحيله، ولا يمكن تكرار إقفاله.',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Current Season Metrics Preview Card ──
                if (!isPermanentlyLocked) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF071830) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.25)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.history_edu_rounded, color: Color(0xFF38BDF8), size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'الموسم المنتهي: ${center?.season ?? "2026-2027"}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF38BDF8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (txCount != null) ...[
                              Text(
                                '$txCount حركة مسجلة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'الرصيد المتبقي للترحيل:',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'EGP ${_fmt(balance)}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: balance < 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── Stage 1 vs Stage 2 Configuration ──
                  if (canClose) ...[
                    if (center?.isFinalSeason == true) ...[
                      // ── Stage 2: Final Closure (Creates New Year Card) ──
                      Text(
                        'السنة الزراعية الجديدة القادمة:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nextSeasonCtrl,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'مثال: 2027-2028',
                          hintStyle: TextStyle(
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF071426) : const Color(0xFFF1F5F9),
                          prefixIcon: const Icon(Icons.event_repeat_rounded, color: Color(0xFFF59E0B)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _seasonSuggestions.map((s) {
                          final isSelected = _nextSeasonCtrl.text.trim() == s;
                          return ActionChip(
                            label: Text(s,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: isSelected
                                      ? (isDark ? const Color(0xFFF59E0B) : const Color(0xFFB45309))
                                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                )),
                            backgroundColor: isSelected
                                ? const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.25 : 0.15)
                                : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFFF59E0B)
                                  : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                            ),
                            onPressed: () {
                              setState(() {
                                _nextSeasonCtrl.text = s;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // New Season Preview Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF10B981).withValues(alpha: 0.08)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.add_circle_outline_rounded,
                                    color: Color(0xFF10B981), size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'معاينة كارت مركز التكلفة الجديد للسنة القادمة:',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: Color(0xFF10B981),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _newSeasonPreviewName,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        'الكود: $_newSeasonPreviewCode',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 14, color: Colors.orangeAccent),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'سيتم إقفال الكارت الحالي نهائياً ويتحول وضعه إلى (للاطلاع فقط / Read-Only).',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: isDark ? Colors.orange.shade200 : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // ── Stage 1: Period 1 -> Period 2 within SAME Card ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF10B981).withValues(alpha: 0.08)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.sync_alt_rounded,
                                  color: Color(0xFF10B981), size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'الترحيل داخل نفس كارت مركز التكلفة الحالي:',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${center?.nameAr ?? ""} (${center?.code ?? ""})',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'سيتم ترحيل الرصيد المتبقي (EGP ${_fmt(balance)}) من الفترة الأولى إلى الفترة الثانية داخل نفس الكارت الحالي تماماً بدون إنشاء أي كارت جديد، وسيظل الكارت مفتوحاً ونشطاً لتسجيل حركات الفترة الثانية.',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      height: 1.4,
                                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ── Optional Notes Field ──
                    TextField(
                      controller: _notesCtrl,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'ملاحظات الإقفال (اختياري)',
                        labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white60 : const Color(0xFF64748B)),
                        hintText: 'مثال: إقفال موسمي ونقل الرصيد للموسم الجديد',
                        hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white30 : const Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF071426) : const Color(0xFFF1F5F9),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primary),
                        ),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 24),

                // ── Action Buttons ──
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          isPermanentlyLocked ? 'إغلاق' : 'إلغاء',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    // Only show the action button if the center is NOT permanently closed
                    if (!isPermanentlyLocked) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (_submitting || !canClose)
                              ? null
                              : _submitRollover,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  canClose
                                      ? (center?.isFinalSeason == true
                                          ? Icons.lock_clock_rounded
                                          : Icons.lock_reset_rounded)
                                      : Icons.lock_rounded,
                                  size: 20,
                                ),
                          label: Text(
                            _submitting
                                ? 'جاري الإقفال والترحيل...'
                                : isClosedAlready
                                    ? 'الموسم مقفل بالفعل'
                                    : (center?.isFinalSeason == true
                                        ? 'تأكيد الإقفال النهائي وإنشاء السنة الجديدة'
                                        : 'تأكيد ترحيل الفترة الأولى إلى الفترة الثانية'),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !canClose
                                ? (isDark ? Colors.grey.shade800 : const Color(0xFFCBD5E1))
                                : (center?.isFinalSeason == true
                                    ? Colors.redAccent
                                    : const Color(0xFFD97706)),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
