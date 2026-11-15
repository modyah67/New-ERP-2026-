library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/export/report_export_service.dart' as export_svc;
import '../../reporting/models/reporting_models.dart';

class GeneralLedgerConfig {
  GeneralLedgerConfig._();

  static const columns = [
    ReportColumn(
      key: 'date',
      label: 'Date',
      labelAr: 'التاريخ',
      fixedWidth: 110,
      sortable: true,
    ),
    ReportColumn(
      key: 'entryNumber',
      label: 'Entry#',
      labelAr: 'رقم القيد',
      fixedWidth: 130,
    ),
    ReportColumn(
      key: 'accountCode',
      label: 'Account',
      labelAr: 'الحساب',
      fixedWidth: 180,
    ),
    ReportColumn(
      key: 'costCenter',
      label: 'Cost Center',
      labelAr: 'مركز التكلفة',
      fixedWidth: 200,
    ),
    ReportColumn(
      key: 'description',
      label: 'Description',
      labelAr: 'البيان',
      minWidth: 400,
      flex: 4,
    ),
    ReportColumn(
      key: 'debit',
      label: 'Debit',
      labelAr: 'مدين',
      fixedWidth: 130,
      alignRight: true,
      sortable: true,
    ),
    ReportColumn(
      key: 'credit',
      label: 'Credit',
      labelAr: 'دائن',
      fixedWidth: 130,
      alignRight: true,
      sortable: true,
    ),
    ReportColumn(
      key: 'balance',
      label: 'Balance',
      labelAr: 'الرصيد',
      fixedWidth: 130,
      alignRight: true,
      sortable: true,
    ),
  ];

  static List<MetricData> buildMetrics(LedgerReport report, BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final textPrimary = AppTheme.getTextPrimary(context);

    return [
      MetricData(
        title: 'العمليات',
        value: '${report.transactionCount}',
        icon: Icons.receipt_long_outlined,
        color: primary,
      ),
      MetricData(
        title: 'إجمالي المدين',
        value: AppUtils.formatNumber(report.totalDebit),
        icon: Icons.arrow_downward,
        color: AppTheme.success,
      ),
      MetricData(
        title: 'إجمالي الدائن',
        value: AppUtils.formatNumber(report.totalCredit),
        icon: Icons.arrow_upward,
        color: const Color(0xFFF4B400),
      ),
      MetricData(
        title: 'الرصيد الافتتاحي',
        value: AppUtils.formatNumber(report.openingBalance),
        icon: Icons.play_circle_outline,
        color: AppTheme.accent,
      ),
      MetricData(
        title: 'الرصيد الختامي',
        value: AppUtils.formatNumber(report.closingBalance),
        icon: Icons.flag_outlined,
        color: textPrimary,
      ),
    ];
  }

  static List<ExportAction> buildExportActions({
    required LedgerReport report,
    required BuildContext context,
  }) {
    return [
      ExportAction(
        label: 'Excel',
        icon: Icons.table_chart_outlined,
        onPressed: () async {
          try {
            final excel = export_svc.ReportExportService.exportLedgerToExcel(report);
            final bytes = excel.save();
            if (bytes != null) {
              final dir = await FileHelper.getExportDirectory();
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final file = File('${dir.path}/general_ledger_$timestamp.xlsx');
              await file.writeAsBytes(bytes);

              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم حفظ ملف الإكسيل بنجاح في المستندات'),
                  backgroundColor: AppTheme.success,
                ),
              );
            }
          } catch (e) {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('خطأ: $e'),
                backgroundColor: AppTheme.danger,
              ),
            );
          }
        },
      ),
    ];
  }

  static String renderCell(
      Map<String, dynamic> cellMap, ReportColumn column, bool isParent) {
    switch (column.key) {
      case 'date':
        final d = cellMap['date'] as DateTime?;
        return d != null ? AppUtils.formatDate(d) : '';
      case 'entryNumber':
        return cellMap['entryNumber']?.toString() ?? '';
      case 'accountCode':
        return cellMap['accountCode']?.toString() ?? '';
      case 'costCenter':
        return cellMap['costCenter']?.toString() ?? '';
      case 'description':
        final desc = cellMap['description']?.toString() ?? '';
        return desc.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      case 'debit':
        final v = (cellMap['debit'] as num?)?.toDouble() ?? 0.0;
        final c = cellMap['currency'] as String?;
        return v > 0 ? '${AppUtils.formatNumber(v)} ${c ?? ''}'.trim() : '';
      case 'credit':
        final v = (cellMap['credit'] as num?)?.toDouble() ?? 0.0;
        final c = cellMap['currency'] as String?;
        return v > 0 ? '${AppUtils.formatNumber(v)} ${c ?? ''}'.trim() : '';
      case 'balance':
        final v = (cellMap['balance'] as num?)?.toDouble() ?? 0.0;
        final c = cellMap['currency'] as String?;
        return '${AppUtils.formatNumber(v)} ${c ?? ''}'.trim();
      default:
        return '';
    }
  }

  /// Custom widget renderer for cells that need rich rendering (badges, tooltips).
  /// Returns null for columns that should use the default text renderer.
  static Widget? renderCellWidget(BuildContext context,
      Map<String, dynamic> cellMap, ReportColumn column, bool isParent) {
    if (column.key != 'costCenter') return null;

    final isDark = AppTheme.isDark(context);
    final ccName = cellMap['costCenter']?.toString() ?? '';

    if (ccName.isEmpty) {
      return Text(
        '—',
        style: TextStyle(
          color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
          fontFamily: 'Cairo',
          fontSize: 12,
        ),
      );
    }

    // Theme-aware colors
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final tooltipBg = isDark ? const Color(0xFF0E2A47) : const Color(0xFF0F172A);

    return Tooltip(
      message: ccName,
      waitDuration: const Duration(milliseconds: 250),
      textStyle: const TextStyle(
        fontSize: 13,
        color: Colors.white,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: tooltipBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withAlpha(100)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: primary.withAlpha(25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: primary.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 13, color: primary.withAlpha(180)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                ccName,
                style: TextStyle(
                  color: primary,
                  fontSize: 11.5,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
