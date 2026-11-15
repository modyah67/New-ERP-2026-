import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme.dart';
import '../data_audit_service.dart';

/// Modal dialog providing interactive visualization of the Data Audit Report,
/// displaying verification status per table, breakdown of warnings, and one-click Excel/PDF exports.
class DataAuditDialog extends StatefulWidget {
  const DataAuditDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DataAuditDialog(),
    );
  }

  @override
  State<DataAuditDialog> createState() => _DataAuditDialogState();
}

class _DataAuditDialogState extends State<DataAuditDialog> {
  bool _isLoading = true;
  String? _error;
  DataAuditReport? _report;
  String _filterMode = 'all'; // 'all', 'warnings', 'passed'
  bool _isExportingExcel = false;
  bool _isPrintingPdf = false;
  final NumberFormat _currencyFmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _executeAudit();
  }

  Future<void> _executeAudit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final report = await DataAuditService.runAudit();
      if (!mounted) return;
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ أثناء فحص البيانات: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    if (_report == null) return;
    setState(() => _isExportingExcel = true);
    try {
      final path = await DataAuditService.exportExcel(_report!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم تصدير تقرير فحص البيانات بنجاح وفتحه:\n$path',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final isLockError = e.toString().contains('32') || e.toString().contains('another process');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLockError
                ? 'تنبيه: ملف Excel مفتوح حالياً في برنامج آخر (Microsoft Excel). يرجى إغلاقه أولاً أو إعادة المحاولة.'
                : 'فشل تصدير Excel: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  Future<void> _printPdf() async {
    if (_report == null) return;
    setState(() => _isPrintingPdf = true);
    try {
      await DataAuditService.printOrSharePdf(_report!);
    } catch (e) {
      if (!mounted) return;
      final isLockError = e.toString().contains('32') || e.toString().contains('another process');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLockError
                ? 'تنبيه: ملف PDF مفتوح حالياً في برنامج آخر. يرجى إغلاقه أولاً.'
                : 'فشل تجهيز تقرير PDF: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrintingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    final dialogWidth = (size.width * 0.95).clamp(320.0, 1150.0);
    final dialogHeight = (size.height * 0.92).clamp(400.0, 880.0);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF07192C) : Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF0EA5E9).withValues(alpha: 0.3) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          padding: EdgeInsets.all(isMobile ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              _buildHeader(isDark, isMobile),
              const SizedBox(height: 12),

              // ── Main Content Area ──
              Expanded(
                child: _isLoading
                    ? _buildLoadingState(isDark)
                    : (_error != null
                        ? _buildErrorState(isDark)
                        : _buildReportContent(isDark, isMobile)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, bool isMobile) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0284C7), Color(0xFF0F766E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'التحقق من صحة واكتمال البيانات (Data Audit Report)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMobile ? 14 : 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                'فحص ومطابقة نطاقات الأكواد والأرصدة الافتتاحية لكافة جداول النظام',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isMobile ? 10.5 : 12,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'إغلاق',
          color: isDark ? Colors.white70 : const Color(0xFF64748B),
        ),
      ],
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: 16),
          Text(
            'جاري فحص ومطابقة جداول البيانات ومراجعة نطاقات الأكواد...',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 48),
          const SizedBox(height: 12),
          Text(
            _error ?? 'حدث خطأ غير متوقع',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13.5,
              color: AppTheme.danger,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _executeAudit,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(bool isDark, bool isMobile) {
    final report = _report!;
    final filteredCategories = report.categories.where((cat) {
      if (_filterMode == 'warnings') return !cat.isPassed;
      if (_filterMode == 'passed') return cat.isPassed;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── KPI Ribbon ──
        _buildKpiRibbon(report, isDark, isMobile),
        const SizedBox(height: 12),

        // ── Action Buttons & Filter Bar ──
        _buildActionAndFilterBar(report, isDark, isMobile),
        const SizedBox(height: 10),

        // ── Results List / Table ──
        Expanded(
          child: filteredCategories.isEmpty
              ? _buildEmptyFilteredState(isDark)
              : ListView.separated(
                  itemCount: filteredCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final cat = filteredCategories[index];
                    return _buildCategoryCard(cat, isDark, isMobile);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKpiRibbon(DataAuditReport report, bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A223D) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF0EA5E9).withValues(alpha: 0.2) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 12,
        runSpacing: 10,
        children: [
          _buildKpiItem(
            title: 'إجمالي السجلات',
            value: '${report.totalRecords}',
            unit: 'سجل',
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFF0284C7),
            isDark: isDark,
          ),
          _buildKpiItem(
            title: 'إجمالي الأرصدة الافتتاحية',
            value: _currencyFmt.format(report.totalInitialBalance),
            unit: 'ج.م',
            icon: Icons.account_balance_wallet_outlined,
            color: const Color(0xFF0F766E),
            isDark: isDark,
          ),
          _buildKpiItem(
            title: 'فئات سليمة ومطابقة',
            value: '${report.totalPassedCategories}',
            unit: 'من ${report.categories.length}',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
          _buildKpiItem(
            title: 'فئات تتطلب مراجعة',
            value: '${report.totalWarningCategories}',
            unit: 'فئة',
            icon: Icons.warning_amber_rounded,
            color: report.totalWarningCategories > 0 ? const Color(0xFFF59E0B) : const Color(0xFF64748B),
            isDark: isDark,
          ),
          _buildKpiItem(
            title: 'إجمالي المخالفات المرصودة',
            value: '${report.totalIssues}',
            unit: 'تنبيه',
            icon: Icons.error_outline_rounded,
            color: report.totalIssues > 0 ? AppTheme.danger : const Color(0xFF10B981),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiItem({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionAndFilterBar(DataAuditReport report, bool isDark, bool isMobile) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        // Filter tabs
        Wrap(
          spacing: 6,
          children: [
            _buildFilterChip('all', 'كافة الفئات (${report.categories.length})', isDark),
            _buildFilterChip('warnings', 'تنبيهات (${report.totalWarningCategories})', isDark, isWarning: true),
            _buildFilterChip('passed', 'مطابقة (${report.totalPassedCategories})', isDark),
          ],
        ),

        // Export Actions
        Wrap(
          spacing: 8,
          children: [
            // Re-Audit
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _executeAudit,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة الفحص', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            // Export Excel
            ElevatedButton.icon(
              onPressed: _isExportingExcel ? null : _exportExcel,
              icon: _isExportingExcel
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.table_view_rounded, size: 16),
              label: Text(
                _isExportingExcel ? 'جاري التصدير...' : 'تصدير Excel (.xlsx)',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            // Print PDF
            ElevatedButton.icon(
              onPressed: _isPrintingPdf ? null : _printPdf,
              icon: _isPrintingPdf
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: Text(
                _isPrintingPdf ? 'جاري الإعداد...' : 'طباعة تقرير PDF',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0369A1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(String mode, String label, bool isDark, {bool isWarning = false}) {
    final isSelected = _filterMode == mode;
    final activeBg = isWarning ? const Color(0xFFF59E0B) : const Color(0xFF0284C7);

    return InkWell(
      onTap: () => setState(() => _filterMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeBg
              : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? activeBg
                : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(DataAuditCategoryResult cat, bool isDark, bool isMobile) {
    final isPassed = cat.isPassed;
    final badgeColor = isPassed ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A2038) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPassed
              ? (isDark ? Colors.white10 : const Color(0xFFE2E8F0))
              : badgeColor.withValues(alpha: 0.5),
          width: isPassed ? 1 : 1.3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ExpansionTile(
          initiallyExpanded: !isPassed,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPassed ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: badgeColor,
              size: 20,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            cat.categoryName,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            cat.tableName,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          'النطاق المعتمد: ${cat.codeRangeDisplay}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '|  السجلات: ${cat.totalCount}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                        if (cat.totalInitialBalance > 0)
                          Text(
                            '|  الأرصدة: ${_currencyFmt.format(cat.totalInitialBalance)} ${cat.currency}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  isPassed ? 'سليمة ومطابقة ✓' : 'تنبيه (${cat.warningCount})',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: isPassed
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'جميع الأكواد المسجلة في هذه الفئة ملتزمة تماماً بالنطاق القياسي المعتمد، والبيانات مكتملة 100%.',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Text(
                          'المخالفات والتنبيهات المكتشفة في هذه الفئة (${cat.issues.length}):',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...cat.issues.map((iss) => _buildIssueRow(iss, isDark)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueRow(DataAuditItemIssue iss, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181520) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              iss.issueType,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.danger,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'الكود: [${iss.code}]',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'الاسم: ${iss.name}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  iss.details,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFilteredState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off_rounded, size: 40, color: isDark ? Colors.white30 : const Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text(
            'لا توجد فئات مطابقة لشرط الفلترة المحدد',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
