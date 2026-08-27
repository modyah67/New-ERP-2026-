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

class CashFlowConfig {
  CashFlowConfig._();

  static const columns = [
    ReportColumn(
      key: 'description',
      label: 'Description',
      labelAr: 'البيان',
      flex: 4,
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

  static List<MetricData> buildMetrics(CashFlowReport report, {String? currencyFilter}) {
    return [
      MetricData(
        title: 'التدفقات التشغيلية',
        value: AppUtils.formatNumber(report.netCashFromOperating),
        icon: Icons.sync_alt_outlined,
        color: AppTheme.primary,
      ),
      MetricData(
        title: 'التدفقات الاستثمارية',
        value: AppUtils.formatNumber(report.netCashFromInvesting),
        icon: Icons.show_chart_outlined,
        color: AppTheme.accent,
      ),
      MetricData(
        title: 'التدفقات التمويلية',
        value: AppUtils.formatNumber(report.netCashFromFinancing),
        icon: Icons.account_balance_outlined,
        color: AppTheme.success,
      ),
      MetricData(
        title: 'صافي التدفق النقدي',
        value: AppUtils.formatNumber(report.netChangeInCash),
        icon: Icons.compare_arrows,
        color: report.netChangeInCash >= 0 ? AppTheme.success : AppTheme.danger,
      ),
    ];
  }

  static List<ExportAction> buildExportActions({
    required CashFlowReport report,
    required BuildContext context,
  }) {
    return [
      ExportAction(
        label: 'Excel',
        icon: Icons.table_chart_outlined,
        onPressed: () async {
          try {
            final excel =
                export_svc.ReportExportService.exportCashFlowToExcel(report);
            final bytes = excel.save();
            if (bytes != null) {
              final dir = await FileHelper.getExportDirectory();
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final file = File('${dir.path}/cash_flow_$timestamp.xlsx');
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
      case 'description':
        return cellMap['description']?.toString() ?? '';
      case 'amount':
        return AppUtils.formatNumber(
            (cellMap['amount'] as num?)?.toDouble() ?? 0.0);
      default:
        return '';
    }
  }
}
