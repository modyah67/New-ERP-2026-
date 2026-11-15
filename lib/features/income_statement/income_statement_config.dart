library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/export/report_export_service.dart' as export_svc;
import '../../reporting/models/reporting_models.dart';

class IncomeStatementConfig {
  IncomeStatementConfig._();

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
      key: 'amount',
      label: 'Amount',
      labelAr: 'المبلغ',
      flex: 2,
      alignRight: true,
      currency: 'EGP',
      sortable: true,
    ),
  ];

  static List<MetricData> buildMetrics(IncomeStatementReport report, {String? currencyFilter}) {
    return [
      MetricData(
        title: 'إجمالي الإيرادات',
        value: AppUtils.formatNumber(report.revenue.total),
        icon: Icons.trending_up,
        color: AppTheme.success,
      ),
      MetricData(
        title: 'تكلفة البضاعة المباعة',
        value: AppUtils.formatNumber(report.costOfGoodsSold.total),
        icon: Icons.inventory_outlined,
        color: AppTheme.danger,
      ),
      MetricData(
        title: 'إجمالي الربح',
        value: AppUtils.formatNumber(report.grossProfit),
        icon: Icons.show_chart,
        color: AppTheme.primary,
      ),
      MetricData(
        title: 'المصروفات التشغيلية',
        value: AppUtils.formatNumber(report.operatingExpenses.total),
        icon: Icons.receipt_long_outlined,
        color: AppTheme.accent,
      ),
      MetricData(
        title: 'صافي الدخل',
        value: AppUtils.formatNumber(report.netIncome),
        icon: Icons.account_balance_wallet_outlined,
        color: report.netIncome >= 0 ? AppTheme.success : AppTheme.danger,
      ),
      MetricData(
        title: 'هامش الربح الإجمالي',
        value: report.revenue.total > 0
            ? '${((report.grossProfit / report.revenue.total) * 100).toStringAsFixed(1)}%'
            : '0%',
        icon: Icons.percent_outlined,
        // textSecondary is the same in both modes as a semantic token;
        // use lightTextSecondary in light mode via the secondary color
        color: AppTheme.textSecondary,
      ),
    ];
  }

  static List<ExportAction> buildExportActions({
    required IncomeStatementReport report,
    required BuildContext context,
  }) {
    return [
      ExportAction(
        label: 'Excel',
        icon: Icons.table_chart_outlined,
        onPressed: () async {
          try {
            final excel =
                export_svc.ReportExportService.exportIncomeStatementToExcel(report);
            final bytes = excel.save();
            if (bytes != null) {
              final dir = await FileHelper.getExportDirectory();
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final file = File('${dir.path}/income_statement_$timestamp.xlsx');
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
      case 'code':
        return cellMap['code']?.toString() ?? '';
      case 'name':
        return cellMap['name']?.toString() ?? '';
      case 'amount':
        return AppUtils.formatNumber(
            (cellMap['amount'] as num?)?.toDouble() ?? 0.0);
      default:
        return '';
    }
  }
}
