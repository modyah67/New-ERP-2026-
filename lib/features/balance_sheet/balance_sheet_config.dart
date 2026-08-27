library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/export/report_export_service.dart' as export_svc;
import '../../reporting/models/reporting_models.dart';

class BalanceSheetConfig {
  BalanceSheetConfig._();

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

  static List<MetricData> buildMetrics(BalanceSheetReport report, {String? currencyFilter}) {
    final isBalanced = report.isBalanced;

    return [
      MetricData(
        title: 'إجمالي الأصول',
        value: AppUtils.formatNumber(report.totalAssets),
        icon: Icons.account_balance_outlined,
        color: AppTheme.primary,
      ),
      MetricData(
        title: 'إجمالي الخصوم',
        value: AppUtils.formatNumber(report.liabilities.total),
        icon: Icons.trending_down,
        color: AppTheme.danger,
      ),
      MetricData(
        title: 'إجمالي حقوق الملكية',
        value: AppUtils.formatNumber(report.equity.total),
        icon: Icons.trending_up,
        color: AppTheme.success,
      ),
      MetricData(
        title: 'إجمالي الخصوم وحقوق الملكية',
        value: AppUtils.formatNumber(report.totalLiabilitiesAndEquity),
        icon: Icons.balance_outlined,
        color: AppTheme.accent,
      ),
      MetricData(
        title: 'الفرق',
        value: AppUtils.formatNumber(report.difference.abs()),
        icon: Icons.compare_arrows,
        color: isBalanced ? AppTheme.success : AppTheme.danger,
      ),
      MetricData(
        title: 'الحالة',
        value: isBalanced ? 'متوازن' : 'غير متوازن',
        icon: isBalanced
            ? Icons.check_circle_outline
            : Icons.warning_amber_outlined,
        color: isBalanced ? AppTheme.success : AppTheme.danger,
      ),
    ];
  }

  static List<ExportAction> buildExportActions({
    required BalanceSheetReport report,
    required BuildContext context,
  }) {
    return [
      ExportAction(
        label: 'Excel',
        icon: Icons.table_chart_outlined,
        onPressed: () async {
          try {
            final excel =
                export_svc.ReportExportService.exportBalanceSheetToExcel(report);
            final bytes = excel.save();
            if (bytes != null) {
              final dir = await FileHelper.getExportDirectory();
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final file = File('${dir.path}/balance_sheet_$timestamp.xlsx');
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
