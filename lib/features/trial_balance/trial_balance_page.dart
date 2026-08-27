library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../accounting/reporting/models/report_models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../reporting/widgets/reporting_scaffold.dart';
import '../../reporting/widgets/reporting_filter_bar.dart';
import '../../reporting/widgets/reporting_data_grid.dart';
import '../../reporting/widgets/reporting_empty_state.dart';
import '../../reporting/widgets/reporting_error_view.dart';
import 'trial_balance_cubit.dart';
import 'trial_balance_config.dart';

class TrialBalancePage extends StatelessWidget {
  const TrialBalancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TrialBalanceCubit, TrialBalanceState>(
      builder: (context, state) {
        final cubit = context.read<TrialBalanceCubit>();

        if (state is TrialBalanceLoaded) {
          return _buildLoaded(context, state, cubit);
        }

        if (state is TrialBalanceRefreshing) {
          return _buildLoaded(context, state.current, cubit, isRefreshing: true);
        }

        return _buildLoadingOrError(context, state);
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    TrialBalanceLoaded state,
    TrialBalanceCubit cubit, {
    bool isRefreshing = false,
  }) {
    final report = state.report;

    final gridRows = _buildGridRows(
      report,
      state.hierarchy,
      state.expandedAccountIds,
      state.searchQuery,
      state.hideZeroBalances,
      state.showParentAccounts,
    );

    final depthMap = _buildDepthMap(state.hierarchy);

    final totalsMap = <String, Map<String, double>>{};
    for (final row in report.rows) {
      totalsMap[row.accountCode] = {
        'debit': row.debit,
        'credit': row.credit,
      };
    }

    return ReportingScaffold(
      // ── Header ──
      headerIcon: Icons.balance_outlined,
      headerTitle: 'الميزان التجريبي',
      headerCount: report.rows.length,
      headerCountLabel: 'حساب',
      headerActions: [
        // Fullscreen button
        IconButton(
          onPressed: () => cubit.toggleFullscreen(),
          icon: Icon(
            state.isFullscreen
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
            color: AppTheme.textSecondary,
          ),
          tooltip: 'شاشة كاملة',
        ),
      ],

      // ── Filter ──
      filterBar: ReportingFilterBar(
        onReset: () => cubit.resetFilters(),
        child: _buildFilterContent(context, state, cubit),
      ),

      // ── Validation ──
      isBalanced: report.isBalanced,
      totalDebit: report.totalDebit,
      totalCredit: report.totalCredit,
      difference: report.difference,
      validationResult: state.validationResult,

      // ── Toolbar ──
      onRefresh: () => cubit.loadReport(refresh: true),
      onFullscreen: () => cubit.toggleFullscreen(),
      exportActions:
          TrialBalanceConfig.buildExportActions(report: report, context: context),

      // ── Data Grid ──
      columns: TrialBalanceConfig.columns,
      rows: gridRows,
      cellRenderer: (row, col) =>
          TrialBalanceConfig.renderCell(row.cells, col, row.isParent),
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      onSort: (col) => cubit.sort(col),
      onRowTap: (id) {
        final account = _findAccountById(state.hierarchy, id);
        if (account != null) {
          context.push('/general-ledger', extra: {
            'accountId': account.code,
            'accountCode': account.code,
            'accountName': account.nameAr,
            'fromDate': state.filter.fromDate,
            'toDate': state.filter.toDate,
          });
        }
      },
      onExpandToggle: (id) => cubit.toggleAccountExpand(id),
      expandedIds: state.expandedAccountIds,
      depthMap: depthMap,
      showHierarchy: true,
      gridFooter: _buildFooter(report),
      emptyState: const ReportingEmptyState(
        title: 'لا توجد حسابات',
        subtitle: 'لم يتم العثور على حسابات تطابق الفلتر المحدد',
      ),

      // ── Refresh overlay ──
      isRefreshing: isRefreshing,
    );
  }

  Widget _buildFilterContent(BuildContext context, TrialBalanceLoaded state, TrialBalanceCubit cubit) {
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
              DateTime(now.year, endMonth, DateTime(now.year, endMonth + 1, 0).day),
            );
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'هذا الشهر',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(
                DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
          },
        ),
        const SizedBox(width: 16),
        ReportingToggleButton(
          label: 'إخفاء الأصفار',
          isActive: state.hideZeroBalances,
          onPressed: () => cubit.toggleHideZeroBalances(),
        ),
        const SizedBox(width: 4),
        ReportingToggleButton(
          label: 'حسابات أب',
          isActive: state.showParentAccounts,
          onPressed: () => cubit.toggleShowParentAccounts(),
        ),
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
        // Date range chips
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
              cubit.setDateRange(picked.isAfter(to) ? to : picked, picked.isAfter(to) ? picked : to);
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
              cubit.setDateRange(picked.isBefore(from) ? picked : from, picked.isBefore(from) ? from : picked);
            }
          },
        ),
      ],
    );
  }

  Widget _buildFooter(TrialBalanceReport report) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(20),
        border: Border(top: BorderSide(color: AppTheme.border.withAlpha(80), width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 130),
          const Expanded(
            flex: 3,
            child: Text(
              'الإجمالي',
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
              AppUtils.formatNumber(report.totalDebit),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.success,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              AppUtils.formatNumber(report.totalCredit),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF4B400),
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
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
          const SizedBox(width: 50),
        ],
      ),
    );
  }

  Widget _buildLoadingOrError(BuildContext context, TrialBalanceState state) {
    if (state is TrialBalanceLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF16D5FF)),
              SizedBox(height: 16),
              Text(
                'جاري تحميل الميزان التجريبي...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (state is TrialBalanceError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ReportingErrorView(
          message: state.message,
          onRetry: () => context.read<TrialBalanceCubit>().loadReport(),
        ),
      );
    }

    return const Scaffold(backgroundColor: Colors.transparent);
  }

  // ── Hierarchy helpers ──

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
    TrialBalanceReport report,
    List<AccountHierarchy> hierarchy,
    Set<String> expandedIds,
    String searchQuery,
    bool hideZeroBalances,
    bool showParentAccounts,
  ) {
    final totalsMap = <String, Map<String, double>>{};
    for (final row in report.rows) {
      totalsMap[row.accountCode] = {
        'debit': row.debit,
        'credit': row.credit,
      };
    }

    final matchedCodes = <String>{};
    if (searchQuery.isNotEmpty) {
      final lower = searchQuery.toLowerCase();
      for (final row in report.rows) {
        if (row.accountCode.toLowerCase().contains(lower) ||
            row.accountName.toLowerCase().contains(lower) ||
            row.accountNameAr.contains(searchQuery)) {
          matchedCodes.add(row.accountCode);
        }
      }
    }

    bool isLeafVisible(AccountHierarchy leaf) {
      // Exclude 2100 branch and shadow accounts (2101, 2102, 2105, 5210)
      if (['2100', '2101', '2102', '2105', '5210'].contains(leaf.code)) return false;
      
      if (searchQuery.isNotEmpty && !matchedCodes.contains(leaf.code)) return false;

      if (hideZeroBalances) {
        final t = totalsMap[leaf.code];
        final debit = t?['debit'] ?? 0.0;
        final credit = t?['credit'] ?? 0.0;
        if ((debit - credit).abs() < 0.01) return false;
      }
      return true;
    }

    final hasVisibleLeafCache = <String, bool>{};
    bool computeHasVisibleLeaf(AccountHierarchy node) {
      if (!node.hasChildren) {
        final v = isLeafVisible(node);
        hasVisibleLeafCache[node.id] = v;
        return v;
      }
      bool hasVisible = false;
      for (final child in node.children) {
        if (computeHasVisibleLeaf(child)) {
          hasVisible = true;
        }
      }
      hasVisibleLeafCache[node.id] = hasVisible;
      return hasVisible;
    }

    for (final root in hierarchy) {
      computeHasVisibleLeaf(root);
    }

    final result = <ReportingRowData>[];

    void traverse(AccountHierarchy node) {
      if (['2100', '2101', '2102', '2105', '5210'].contains(node.code)) return;
      if (!(hasVisibleLeafCache[node.id] ?? false)) return;

      if (!node.hasChildren) {
        final t = totalsMap[node.code];
        final debit = t?['debit'] ?? 0.0;
        final credit = t?['credit'] ?? 0.0;
        
        result.add(ReportingRowData(
          id: node.id,
          cells: {
            'code': node.code,
            'name': node.nameAr,
            'debit': debit,
            'credit': credit,
          },
          hasChildren: false,
          isParent: false,
        ));
      } else {
        if (showParentAccounts) {
          final childTotals = _computeChildTotals(node, totalsMap);
          result.add(ReportingRowData(
            id: node.id,
            cells: {
              'code': node.code,
              'name': node.nameAr,
              'debit': childTotals['debit']!,
              'credit': childTotals['credit']!,
            },
            hasChildren: true,
            isParent: true,
          ));

          if (expandedIds.contains(node.id) || searchQuery.isNotEmpty) {
            for (final child in node.children) {
              traverse(child);
            }
          }
        } else {
          // Flatten: traverse children without adding the parent
          for (final child in node.children) {
            traverse(child);
          }
        }
      }
    }

    for (final root in hierarchy) {
      traverse(root);
    }

    return result;
  }

  Map<String, double> _computeChildTotals(
    AccountHierarchy account,
    Map<String, Map<String, double>> totalsMap,
  ) {
    if (!account.hasChildren) {
      final t = totalsMap[account.code];
      return {
        'debit': t?['debit'] ?? 0.0,
        'credit': t?['credit'] ?? 0.0,
      };
    }

    double debitSum = 0.0;
    double creditSum = 0.0;

    void sumChildren(AccountHierarchy node) {
      for (final child in node.children) {
        final t = totalsMap[child.code];
        if (t != null) {
          debitSum += t['debit'] ?? 0.0;
          creditSum += t['credit'] ?? 0.0;
        }
        if (child.hasChildren) {
          sumChildren(child);
        }
      }
    }

    sumChildren(account);
    return {'debit': debitSum, 'credit': creditSum};
  }
}
