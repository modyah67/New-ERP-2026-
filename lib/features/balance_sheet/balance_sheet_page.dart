library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../accounting/reporting/models/report_models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../reporting/widgets/reporting_scaffold.dart';
import '../../reporting/widgets/reporting_filter_bar.dart';
import '../../reporting/widgets/reporting_empty_state.dart';
import '../../reporting/widgets/reporting_error_view.dart';
import '../../reporting/widgets/reporting_data_grid.dart';
import 'balance_sheet_cubit.dart';
import 'balance_sheet_config.dart';

class BalanceSheetPage extends StatelessWidget {
  const BalanceSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalanceSheetCubit, BalanceSheetState>(
      builder: (context, state) {
        final cubit = context.read<BalanceSheetCubit>();

        if (state is BalanceSheetLoaded) {
          return _buildLoaded(context, state, cubit);
        }

        if (state is BalanceSheetRefreshing) {
          return _buildLoaded(context, state.current, cubit, isRefreshing: true);
        }

        return _buildLoadingOrError(context, state);
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    BalanceSheetLoaded state,
    BalanceSheetCubit cubit, {
    bool isRefreshing = false,
  }) {
    final report = state.report;

    final gridRows = _buildGridRows(report, state);

    final depthMap = _buildDepthMap(state.hierarchy);

    return ReportingScaffold(
      headerIcon: Icons.account_balance_outlined,
      headerTitle: 'الميزانية العامة',
      headerCount: report.assets.lines.length +
          report.liabilities.lines.length +
          report.equity.lines.length,
      headerCountLabel: 'حساب',
      headerActions: [
        IconButton(
          onPressed: () => cubit.toggleFullscreen(),
          icon: Icon(
            state.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: AppTheme.textSecondary,
          ),
          tooltip: 'شاشة كاملة',
        ),
      ],

      filterBar: ReportingFilterBar(
        onReset: () => cubit.resetFilters(),
        child: _buildFilterContent(context, state, cubit),
      ),

      isBalanced: report.isBalanced,
      totalDebit: report.totalAssets,
      totalCredit: report.totalLiabilitiesAndEquity,
      difference: report.difference,
      validationResult: state.validationResult,
      debitLabel: 'إجمالي الأصول',
      creditLabel: 'إجمالي الخصوم وحقوق الملكية',
      differenceLabel: 'الفرق',

      onRefresh: () => cubit.loadReport(refresh: true),
      onFullscreen: () => cubit.toggleFullscreen(),
      exportActions:
          BalanceSheetConfig.buildExportActions(report: report, context: context),

      columns: BalanceSheetConfig.columns,
      rows: gridRows,
      cellRenderer: (row, col) =>
          BalanceSheetConfig.renderCell(row.cells, col, row.isParent),
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      onSort: (col) => cubit.sort(col),
      onRowTap: (id) {
        final account = _findAccountById(state.hierarchy, id);
        if (account != null) {
          final fromDate = state.filter.fromDate ?? DateTime(2020, 1, 1);
          final toDate = state.filter.toDate ?? DateTime.now();
          context.push('/general-ledger', extra: {
            'accountId': account.code,
            'accountCode': account.code,
            'accountName': account.nameAr,
            'fromDate': fromDate,
            'toDate': toDate,
          });
        }
      },
      onExpandToggle: (id) => cubit.toggleAccountExpand(id),
      expandedIds: state.expandedAccountIds,
      depthMap: depthMap,
      showHierarchy: false,
      gridFooter: _buildFooter(report),
      emptyState: const ReportingEmptyState(
        title: 'لا توجد بيانات',
        subtitle: 'لم يتم العثور على بيانات الميزانية العامة',
      ),

      isRefreshing: isRefreshing,
    );
  }

  Widget _buildFilterContent(
      BuildContext context, BalanceSheetLoaded state, BalanceSheetCubit cubit) {
    return Row(
      children: [
        ReportingPresetButton(
          label: 'نهاية هذا العام',
          onPressed: () {
            final now = DateTime.now();
            cubit.setAsOfDate(DateTime(now.year, 12, 31));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'نهاية العام السابق',
          onPressed: () {
            final now = DateTime.now();
            cubit.setAsOfDate(DateTime(now.year - 1, 12, 31));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'نهاية هذا الربع',
          onPressed: () {
            final now = DateTime.now();
            final quarter = ((now.month - 1) ~/ 3);
            final endMonth = quarter * 3 + 3;
            cubit.setAsOfDate(
                DateTime(now.year, endMonth, DateTime(now.year, endMonth + 1, 0).day));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'نهاية هذا الشهر',
          onPressed: () {
            final now = DateTime.now();
            cubit.setAsOfDate(
                DateTime(now.year, now.month, DateTime(now.year, now.month + 1, 0).day));
          },
        ),
        const SizedBox(width: 16),
        // ReportingToggleButton(
        //   label: 'إخفاء الأصفار',
        //   isActive: state.hideZeroBalances,
        //   onPressed: () => cubit.toggleHideZeroBalances(),
        // ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: () => cubit.expandAll(),
          icon: Icon(Icons.unfold_more, size: 18, color: AppTheme.textSecondary),
          tooltip: 'توسيع الكل',
        ),
        IconButton(
          onPressed: () => cubit.collapseAll(),
          icon: Icon(Icons.unfold_less, size: 18, color: AppTheme.textSecondary),
          tooltip: 'طي الكل',
        ),
        const SizedBox(width: 12),
        Text('بتاريخ:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
              cubit.setAsOfDate(picked);
            }
          },
        ),
      ],
    );
  }
  Widget _buildFooter(BalanceSheetReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(20),
        border: Border(
            top: BorderSide(color: AppTheme.border.withAlpha(80), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 130),
              Expanded(
                flex: 3,
                child: Text(
                  'إجمالي الأصول',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  AppUtils.formatNumber(report.totalAssets),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 130),
              Expanded(
                flex: 3,
                child: Text(
                  'إجمالي الخصوم وحقوق الملكية',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  AppUtils.formatNumber(report.totalLiabilitiesAndEquity),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 130),
              Expanded(
                flex: 3,
                child: Text(
                  'الفرق',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  AppUtils.formatNumber(report.difference),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: report.isBalanced ? AppTheme.success : AppTheme.danger,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOrError(BuildContext context, BalanceSheetState state) {
    if (state is BalanceSheetLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF16D5FF)),
              SizedBox(height: 16),
              Text(
                'جاري تحميل الميزانية العامة...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (state is BalanceSheetError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ReportingErrorView(
          message: state.message,
          onRetry: () => context.read<BalanceSheetCubit>().loadReport(),
        ),
      );
    }

    return const Scaffold(backgroundColor: Colors.transparent);
  }

  AccountHierarchy? _findAccountById(List<AccountHierarchy> roots, String id) {
    for (final root in roots) {
      if (root.id == id) return root;
      final found = _findAccountById(root.children, id);
      if (found != null) return found;
    }
    return null;
  }

  Map<String, int> _buildDepthMap(List<AccountHierarchy> roots) {
    final map = <String, int>{};
    void walk(AccountHierarchy node, int depth) {
      map[node.id] = depth;
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    return map;
  }

  List<ReportingRowData> _buildGridRows(
    BalanceSheetReport report,
    BalanceSheetLoaded state,
  ) {
    final result = <ReportingRowData>[];
    var lineIndex = 0;

    void addSection(String title, String titleAr, BalanceSheetSection section,
        {bool isSectionHeader = true}) {
      if (isSectionHeader) {
        result.add(ReportingRowData(
          id: 'section_${title}',
          cells: {'code': '', 'name': titleAr, 'amount': section.total},
          hasChildren: false,
          isParent: true,
        ));
      }

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
        id: 'total_${title}',
        cells: {
          'code': '',
          'name': 'إجمالي $titleAr',
          'amount': section.total,
        },
        isParent: true,
      ));
    }

    addSection('assets', 'الأصول', report.assets);
    addSection('liabilities', 'الخصوم', report.liabilities);
    addSection('equity', 'حقوق الملكية', report.equity);

    result.add(ReportingRowData(
      id: 'total_le',
      cells: {
        'code': '',
        'name': 'إجمالي الخصوم وحقوق الملكية',
        'amount': report.totalLiabilitiesAndEquity,
      },
      isParent: true,
    ));

    return result;
  }
}
