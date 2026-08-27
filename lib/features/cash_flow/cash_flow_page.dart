library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounting/reporting/models/report_models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../reporting/widgets/reporting_scaffold.dart';
import '../../reporting/widgets/reporting_filter_bar.dart';
import '../../reporting/widgets/reporting_empty_state.dart';
import '../../reporting/widgets/reporting_error_view.dart';
import '../../reporting/widgets/reporting_data_grid.dart';
import 'cash_flow_cubit.dart';
import 'cash_flow_config.dart';

class CashFlowPage extends StatelessWidget {
  const CashFlowPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CashFlowCubit, CashFlowState>(
      builder: (context, state) {
        final cubit = context.read<CashFlowCubit>();

        if (state is CashFlowLoaded) {
          return _buildLoaded(context, state, cubit);
        }

        if (state is CashFlowRefreshing) {
          return _buildLoaded(context, state.current, cubit, isRefreshing: true);
        }

        return _buildLoadingOrError(context, state);
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    CashFlowLoaded state,
    CashFlowCubit cubit, {
    bool isRefreshing = false,
  }) {
    final report = state.report;
    final gridRows = _buildGridRows(report, state);

    return ReportingScaffold(
      headerIcon: Icons.payments_outlined,
      headerTitle: 'قائمة التدفقات النقدية',
      headerCount: report.operating.lines.length +
          report.investing.lines.length +
          report.financing.lines.length,
      headerCountLabel: 'بند',

      filterBar: ReportingFilterBar(
        onReset: () => cubit.resetFilters(),
        child: _buildFilterContent(context, state, cubit),
      ),

      onRefresh: () => cubit.loadReport(refresh: true),
      onFullscreen: () => cubit.toggleFullscreen(),
      exportActions: CashFlowConfig.buildExportActions(
          report: report, context: context),

      columns: CashFlowConfig.columns,
      rows: gridRows,
      cellRenderer: (row, col) =>
          CashFlowConfig.renderCell(row.cells, col, row.isParent),

      emptyState: const ReportingEmptyState(
        title: 'لا توجد بيانات',
        subtitle: 'لم يتم العثور على بيانات التدفقات النقدية',
      ),

      isRefreshing: isRefreshing,
    );
  }

  Widget _buildFilterContent(
      BuildContext context, CashFlowLoaded state, CashFlowCubit cubit) {
    return Row(
      children: [
        ReportingPresetButton(
          label: 'هذا العام',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'العام السابق',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(
                DateTime(now.year - 1, 1, 1), DateTime(now.year - 1, 12, 31));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'هذا الربع',
          onPressed: () {
            final now = DateTime.now();
            final quarter = ((now.month - 1) ~/ 3);
            final startMonth = quarter * 3 + 1;
            final endMonth = startMonth + 2;
            cubit.setDateRange(
              DateTime(now.year, startMonth, 1),
              DateTime(now.year, endMonth,
                  DateTime(now.year, endMonth + 1, 0).day),
            );
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'هذا الشهر',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(
                DateTime(now.year, now.month, 1),
                DateTime(now.year, now.month + 1, 0));
          },
        ),
        const SizedBox(width: 12),
        _buildCurrencyFilter(context, state, cubit),
        const SizedBox(width: 12),
        Text('من:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(width: 6),
        ReportingDateChip(
          label: state.filter.fromDate != null
              ? AppUtils.formatDate(state.filter.fromDate!)
              : '...',
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: state.filter.fromDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              final to = state.filter.toDate ?? DateTime.now();
              cubit.setDateRange(picked.isAfter(to) ? to : picked,
                  picked.isAfter(to) ? picked : to);
            }
          },
        ),
        const SizedBox(width: 12),
        Text('إلى:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(width: 6),
        ReportingDateChip(
          label: state.filter.toDate != null
              ? AppUtils.formatDate(state.filter.toDate!)
              : '...',
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: state.filter.toDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              final from = state.filter.fromDate ?? DateTime(2020, 1, 1);
              cubit.setDateRange(picked.isBefore(from) ? picked : from,
                  picked.isBefore(from) ? from : picked);
            }
          },
        ),
      ],
    );
  }

  Widget _buildCurrencyFilter(
      BuildContext context, CashFlowLoaded state, CashFlowCubit cubit) {
    final currencies = ['EGP', 'USD', 'EUR', 'GBP'];
    return Row(
      children: [
        Text('العملة:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(width: 6),
        for (final c in currencies) ...[
          _buildCurrencyChip(
            label: c,
            isActive: state.currencyFilter == c,
            onPressed: () => cubit.setCurrencyFilter(c),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildCurrencyChip({
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppTheme.primary : AppTheme.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOrError(BuildContext context, CashFlowState state) {
    if (state is CashFlowLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF16D5FF)),
              SizedBox(height: 16),
              Text(
                'جاري تحميل قائمة التدفقات النقدية...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (state is CashFlowError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ReportingErrorView(
          message: state.message,
          onRetry: () => context.read<CashFlowCubit>().loadReport(),
        ),
      );
    }

    return const Scaffold(backgroundColor: Colors.transparent);
  }

  List<ReportingRowData> _buildGridRows(
    CashFlowReport report,
    CashFlowLoaded state,
  ) {
    final result = <ReportingRowData>[];
    var lineIndex = 0;

    void addSection(String sectionId, String titleAr,
        CashFlowSection section) {
      result.add(ReportingRowData(
        id: 'section_$sectionId',
        cells: {'description': titleAr, 'amount': section.total},
        isParent: true,
      ));

      for (final line in section.lines) {
        if (state.hideZeroBalances && line.amount.abs() < 0.01) continue;
        result.add(ReportingRowData(
          id: 'line_${lineIndex++}',
          cells: {
            'description': line.descriptionAr,
            'amount': line.amount,
          },
        ));
      }
    }

    addSection('operating', 'الأنشطة التشغيلية', report.operating);
    result.add(ReportingRowData(
      id: 'total_operating',
      cells: {
        'description': 'صافي التدفقات من الأنشطة التشغيلية',
        'amount': report.netCashFromOperating,
      },
      isParent: true,
    ));

    addSection('investing', 'الأنشطة الاستثمارية', report.investing);
    result.add(ReportingRowData(
      id: 'total_investing',
      cells: {
        'description': 'صافي التدفقات من الأنشطة الاستثمارية',
        'amount': report.netCashFromInvesting,
      },
      isParent: true,
    ));

    addSection('financing', 'الأنشطة التمويلية', report.financing);
    result.add(ReportingRowData(
      id: 'total_financing',
      cells: {
        'description': 'صافي التدفقات من الأنشطة التمويلية',
        'amount': report.netCashFromFinancing,
      },
      isParent: true,
    ));

    result.add(ReportingRowData(
      id: 'net_change',
      cells: {
        'description': 'صافي التغير في النقد',
        'amount': report.netChangeInCash,
      },
      isParent: true,
    ));

    return result;
  }
}
