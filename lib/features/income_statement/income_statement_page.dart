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
import 'income_statement_cubit.dart';
import 'income_statement_config.dart';

class IncomeStatementPage extends StatelessWidget {
  const IncomeStatementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IncomeStatementCubit, IncomeStatementState>(
      builder: (context, state) {
        final cubit = context.read<IncomeStatementCubit>();

        if (state is IncomeStatementLoaded) {
          return _buildLoaded(context, state, cubit);
        }

        if (state is IncomeStatementRefreshing) {
          return _buildLoaded(context, state.current, cubit, isRefreshing: true);
        }

        return _buildLoadingOrError(context, state);
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    IncomeStatementLoaded state,
    IncomeStatementCubit cubit, {
    bool isRefreshing = false,
  }) {
    final report = state.report;
    final gridRows = _buildGridRows(report, state);

    return ReportingScaffold(
      headerIcon: Icons.assessment_outlined,
      headerTitle: 'قائمة الدخل',
      headerCount: report.revenue.lines.length +
          report.costOfGoodsSold.lines.length +
          report.operatingExpenses.lines.length,
      headerCountLabel: 'حساب',

      filterBar: ReportingFilterBar(
        onReset: () => cubit.resetFilters(),
        child: _buildFilterContent(context, state, cubit),
      ),

      isBalanced: report.netIncome >= 0,
      totalDebit: report.revenue.total,
      totalCredit: report.costOfGoodsSold.total + report.operatingExpenses.total,
      difference: report.netIncome,
      debitLabel: 'إجمالي الإيرادات',
      creditLabel: 'إجمالي التكاليف والمصروفات',
      differenceLabel: 'صافي الدخل',
      showStatusBadge: false,

      onRefresh: () => cubit.loadReport(refresh: true),
      onFullscreen: () => cubit.toggleFullscreen(),
      exportActions: IncomeStatementConfig.buildExportActions(
          report: report, context: context),

      columns: IncomeStatementConfig.columns,
      rows: gridRows,
      cellRenderer: (row, col) =>
          IncomeStatementConfig.renderCell(row.cells, col, row.isParent),

      emptyState: const ReportingEmptyState(
        title: 'لا توجد بيانات',
        subtitle: 'لم يتم العثور على بيانات قائمة الدخل',
      ),

      isRefreshing: isRefreshing,
    );
  }

  Widget _buildFilterContent(
      BuildContext context, IncomeStatementLoaded state, IncomeStatementCubit cubit) {
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
        const SizedBox(width: 16),
        ReportingToggleButton(
          label: 'إخفاء الأصفار',
          isActive: state.hideZeroBalances,
          onPressed: () => cubit.toggleHideZeroBalances(),
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
      BuildContext context, IncomeStatementLoaded state, IncomeStatementCubit cubit) {
    final currencies = ['الكل', 'EGP', 'USD', 'EUR', 'GBP'];
    return Row(
      children: [
        Text('العملة:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(width: 6),
        for (final c in currencies) ...[
          _buildCurrencyChip(
            label: c == 'الكل' ? 'الكل / مجمع' : c,
            isActive: state.currencyFilter == (c == 'الكل' ? null : c),
            onPressed: () => cubit.setCurrencyFilter(c == 'الكل' ? null : c),
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

  Widget _buildLoadingOrError(
      BuildContext context, IncomeStatementState state) {
    if (state is IncomeStatementLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF16D5FF)),
              SizedBox(height: 16),
              Text(
                'جاري تحميل قائمة الدخل...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (state is IncomeStatementError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ReportingErrorView(
          message: state.message,
          onRetry: () => context.read<IncomeStatementCubit>().loadReport(),
        ),
      );
    }

    return const Scaffold(backgroundColor: Colors.transparent);
  }

  List<ReportingRowData> _buildGridRows(
    IncomeStatementReport report,
    IncomeStatementLoaded state,
  ) {
    final result = <ReportingRowData>[];
    var lineIndex = 0;

    void addSection(String sectionId, String titleAr,
        IncomeStatementSection section, Color color) {
      result.add(ReportingRowData(
        id: 'section_$sectionId',
        cells: {'code': '', 'name': titleAr, 'amount': null},
        isParent: true,
      ));

      for (final line in section.lines) {
        if (state.hideZeroBalances && line.amount.abs() < 0.01) continue;
        result.add(ReportingRowData(
          id: 'line_${lineIndex++}',
          cells: {
            'code': line.accountCode,
            'name': line.accountNameAr,
            'amount': line.amount,
          },
        ));
      }

      result.add(ReportingRowData(
        id: 'total_$sectionId',
        cells: {'code': '', 'name': 'إجمالي $titleAr', 'amount': section.total},
        isParent: true,
      ));
    }

    addSection('revenue', 'الإيرادات', report.revenue, AppTheme.success);
    addSection('cogs', 'تكلفة البضاعة المباعة', report.costOfGoodsSold, AppTheme.danger);

    result.add(ReportingRowData(
      id: 'gross_profit',
      cells: {'code': '', 'name': 'إجمالي الربح', 'amount': report.grossProfit},
      isParent: true,
    ));

    addSection('expenses', 'المصروفات التشغيلية', report.operatingExpenses, AppTheme.accent);

    result.add(ReportingRowData(
      id: 'net_income',
      cells: {'code': '', 'name': 'صافي الدخل', 'amount': report.netIncome},
      isParent: true,
    ));

    return result;
  }
}
