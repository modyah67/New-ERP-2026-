library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/export/report_export_service.dart' as export_svc;
import '../../reporting/models/reporting_models.dart';

/// Trial Balance report configuration.
///
/// Declares columns, metrics, filter types, and export actions.
/// The framework reads this to compose the Trial Balance page.
class TrialBalanceConfig {
  TrialBalanceConfig._();

  static const columns = [
    ReportColumn(
      key: 'code',
      label: 'Account',
      labelAr: 'الحساب',
      fixedWidth: 130,
      sortable: false,
    ),
    ReportColumn(
      key: 'name',
      label: 'Account Name',
      labelAr: 'اسم الحساب',
      flex: 3,
    ),
    ReportColumn(
      key: 'debit',
      label: 'Debit',
      labelAr: 'مدين',
      flex: 2,
      alignRight: true,
      sortable: true,
    ),
    ReportColumn(
      key: 'credit',
      label: 'Credit',
      labelAr: 'دائن',
      flex: 2,
      alignRight: true,
      sortable: true,
    ),
    ReportColumn(
      key: 'net',
      label: 'Balance',
      labelAr: 'الرصيد',
      flex: 2,
      alignRight: true,
      sortable: true,
    ),
    ReportColumn(
      key: 'type',
      label: 'Type',
      labelAr: 'النوع',
      fixedWidth: 70,
      alignRight: true,
    ),
  ];

  static List<MetricData> buildMetrics(TrialBalanceReport report) {
    int debitCount = 0;
    int creditCount = 0;
    for (final row in report.rows) {
      if (row.isDebitBalance) {
        debitCount++;
      } else {
        creditCount++;
      }
    }

    return [
      MetricData(
        title: 'إجمالي الحسابات',
        value: '${report.rows.length}',
        icon: Icons.account_tree_outlined,
        color: AppTheme.primary,
      ),
      MetricData(
        title: 'حسابات مدين',
        value: '$debitCount',
        icon: Icons.trending_down,
        color: AppTheme.success,
      ),
      MetricData(
        title: 'حسابات دائنة',
        value: '$creditCount',
        icon: Icons.trending_up,
        color: const Color(0xFFF4B400),
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
        title: 'الفرق',
        value: AppUtils.formatNumber(report.difference.abs()),
        icon: Icons.compare_arrows,
        color: report.isBalanced ? AppTheme.success : AppTheme.danger,
      ),
      MetricData(
        title: 'الحالة',
        value: report.isBalanced ? 'متوازن' : 'غير متوازن',
        icon: report.isBalanced
            ? Icons.check_circle_outline
            : Icons.warning_amber_outlined,
        color: report.isBalanced ? AppTheme.success : AppTheme.danger,
      ),
      MetricData(
        title: 'العملة',
        value: 'الكل (ج.م)',
        icon: Icons.monetization_on_outlined,
        color: AppTheme.accent,
      ),
    ];
  }

  static List<ExportAction> buildExportActions({
    required TrialBalanceReport report,
    required BuildContext context,
  }) {
    return [
      ExportAction(
        label: 'Excel',
        icon: Icons.table_chart_outlined,
        onPressed: () async {
          try {
            final excel =
                export_svc.ReportExportService.exportTrialBalanceToExcel(report);
            final bytes = excel.save();
            if (bytes != null) {
              final dir = await FileHelper.getExportDirectory();
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final file = File('${dir.path}/trial_balance_$timestamp.xlsx');
              await file.writeAsBytes(bytes);
              
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
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

  /// Renders a cell value for a given row and column key.
  static String renderCell(
      Map<String, dynamic> cellMap, ReportColumn column, bool isParent) {
    switch (column.key) {
      case 'code':
        return cellMap['code']?.toString() ?? '';
      case 'name':
        return cellMap['name']?.toString() ?? '';
      case 'debit':
        return AppUtils.formatNumber((cellMap['debit'] as num?)?.toDouble() ?? 0.0);
      case 'credit':
        return AppUtils.formatNumber((cellMap['credit'] as num?)?.toDouble() ?? 0.0);
      case 'net':
        final debit = (cellMap['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (cellMap['credit'] as num?)?.toDouble() ?? 0.0;
        return AppUtils.formatNumber((debit - credit).abs());
      case 'type':
        final debit = (cellMap['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (cellMap['credit'] as num?)?.toDouble() ?? 0.0;
        return (debit - credit) >= 0 ? 'مدين' : 'دائن';
      default:
        return '';
    }
  }
}
