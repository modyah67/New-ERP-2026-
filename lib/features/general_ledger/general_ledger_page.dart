library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../reporting/widgets/reporting_scaffold.dart';
import '../../reporting/widgets/reporting_filter_bar.dart';
import '../../reporting/widgets/reporting_data_grid.dart';
import '../../reporting/widgets/reporting_empty_state.dart';
import '../../reporting/widgets/reporting_error_view.dart';
import 'general_ledger_cubit.dart';
import 'general_ledger_config.dart';

class GeneralLedgerPage extends StatelessWidget {
  const GeneralLedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GeneralLedgerCubit, GeneralLedgerState>(
      builder: (context, state) {
        final cubit = context.read<GeneralLedgerCubit>();

        if (state is GeneralLedgerLoaded) {
          return _buildLoaded(context, state, cubit);
        }

        if (state is GeneralLedgerRefreshing) {
          return _buildLoaded(context, state.current, cubit, isRefreshing: true);
        }

        return _buildLoadingOrError(context, state);
      },
    );
  }

  Widget _buildLoadMoreButton(BuildContext context, GeneralLedgerLoaded state, GeneralLedgerCubit cubit) {
    if (!state.hasMore) return const SizedBox.shrink();

    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: state.isLoadingMore
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary,
                ),
              )
            : TextButton.icon(
                onPressed: () => cubit.loadMore(),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('تحميل المزيد'),
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                ),
              ),
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    GeneralLedgerLoaded state,
    GeneralLedgerCubit cubit, {
    bool isRefreshing = false,
  }) {
    final report = state.report;
    final isDark = AppTheme.isDark(context);
    final bgColor = isDark ? AppTheme.sidebarBg : AppTheme.lightBackground;

    var filteredRows = report.rows;
    if (state.searchQuery.isNotEmpty) {
      final q = state.searchQuery.toLowerCase();
      filteredRows = report.rows.where((row) {
        final entryStr = row.entryNumber?.toString() ?? '';
        final desc = row.description ?? '';
        final code = row.accountCode;
        final cc = (row.costCenterName ?? row.costCenterId ?? '').toLowerCase();
        final debitStr = row.debit > 0 ? row.debit.toString() : '';
        final creditStr = row.credit > 0 ? row.credit.toString() : '';
        return entryStr.toLowerCase().contains(q) ||
            desc.toLowerCase().contains(q) ||
            code.toLowerCase().contains(q) ||
            cc.contains(q) ||
            debitStr.contains(q) ||
            creditStr.contains(q);
      }).toList();
    }

    final gridRows = filteredRows
        .map((row) => ReportingRowData(
              id: row.id ?? '',
              cells: {
                'date': row.date,
                'entryNumber': row.entryNumber,
                'accountCode': row.accountCode,
                'costCenter': row.costCenterName ?? row.costCenterId ?? '',
                'description': row.description ?? '',
                'debit': row.debit,
                'credit': row.credit,
                'balance': row.balance,
                'currency': row.currency,
              },
            ))
        .toList();

    List<LedgerRow> sortedRows = List.of(report.rows);
    if (state.sortColumn != null) {
      sortedRows.sort((a, b) {
        int cmp;
        switch (state.sortColumn) {
          case 'date':
            cmp = a.date.compareTo(b.date);
          case 'debit':
            cmp = a.debit.compareTo(b.debit);
          case 'credit':
            cmp = a.credit.compareTo(b.credit);
          case 'balance':
            cmp = a.balance.compareTo(b.balance);
          default:
            cmp = 0;
        }
        return state.sortAscending ? cmp : -cmp;
      });
      gridRows
        ..clear()
        ..addAll(sortedRows.map((row) => ReportingRowData(
              id: row.id ?? '',
              cells: {
                'date': row.date,
                'entryNumber': row.entryNumber,
                'accountCode': row.accountCode,
                'costCenter': row.costCenterName ?? row.costCenterId ?? '',
                'description': row.description ?? '',
                'debit': row.debit,
                'credit': row.credit,
                'balance': row.balance,
                'currency': row.currency,
              },
            )));
    }

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Expanded(
            child: ReportingScaffold(
              backgroundColor: bgColor,
              headerIcon: Icons.book_outlined,
              headerTitle: state.drillDownAccountCode != null
                  ? 'دفتر الأستاذ — ${state.drillDownAccountCode} ${state.drillDownAccountName ?? ''}'
                  : 'دفتر الأستاذ',
              headerCount: report.transactionCount,
              headerCountLabel: 'قيود',
              headerActions: [
                Builder(builder: (ctx) {
                  final iconColor = AppTheme.getTextSecondary(ctx);
                  return IconButton(
                    onPressed: () => cubit.toggleFullscreen(),
                    icon: Icon(
                      state.isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: iconColor,
                    ),
                    tooltip: 'شاشة كاملة',
                  );
                }),
              ],
              filterBar: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReportingFilterBar(
                    onReset: () => cubit.resetFilters(),
                    child: _buildFilterContent(context, state, cubit),
                  ),
                  const SizedBox(height: 12),
                  _buildEntityFilters(context, state, cubit),
                ],
              ),
              metrics: GeneralLedgerConfig.buildMetrics(report, context),
              onRefresh: () => cubit.loadReport(refresh: true),
              onFullscreen: () => cubit.toggleFullscreen(),
              exportActions: GeneralLedgerConfig.buildExportActions(
                  report: report, context: context),
              columns: GeneralLedgerConfig.columns,
              rows: gridRows,
              cellRenderer: (row, col) =>
                  GeneralLedgerConfig.renderCell(row.cells, col, row.isParent),
              widgetCellRenderer: (row, col) =>
                  GeneralLedgerConfig.renderCellWidget(context, row.cells, col, row.isParent),
              sortColumn: state.sortColumn,
              sortAscending: state.sortAscending,
              onSort: (col) => cubit.sort(col),
              emptyState: const ReportingEmptyState(
                title: 'لا توجد قيود',
                subtitle: 'لم يتم العثور على قيود تطابق الفلتر المحدد',
              ),
              isRefreshing: isRefreshing,
            ),
          ),
          _buildLoadMoreButton(context, state, cubit),
        ],
      ),
    );
  }

  Widget _buildFilterContent(
      BuildContext context, GeneralLedgerLoaded state, GeneralLedgerCubit cubit) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);

    return Row(
      children: [
        ReportingPresetButton(
          label: 'هذا الشهر',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(
                DateTime(now.year, now.month, 1),
                DateTime(now.year, now.month + 1, 0));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'هذا العام',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(
                DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
          },
        ),
        const SizedBox(width: 8),
        ReportingPresetButton(
          label: 'العام السابق',
          onPressed: () {
            final now = DateTime.now();
            cubit.setDateRange(
                DateTime(now.year - 1, 1, 1),
                DateTime(now.year - 1, 12, 31));
          },
        ),
        const SizedBox(width: 16),
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
              cubit.setDateRange(
                  picked.isAfter(to) ? to : picked,
                  picked.isAfter(to) ? picked : to);
            }
          },
        ),
        const SizedBox(width: 12),
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
              cubit.setDateRange(
                  picked.isBefore(from) ? picked : from,
                  picked.isBefore(from) ? from : picked);
            }
          },
        ),
        const SizedBox(width: 12),
        _buildCurrencyFilter(context, state, cubit),
        const SizedBox(width: 12),
        if (state.filter.accountId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'حساب محدد',
                  style: TextStyle(
                      fontSize: 12,
                      color: textPrimary,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => cubit.setAccountId(null),
                  child: Icon(Icons.close,
                      size: 14, color: textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCurrencyFilter(
      BuildContext context, GeneralLedgerLoaded state, GeneralLedgerCubit cubit) {
    final textSecondary = AppTheme.getTextSecondary(context);

    return Row(
      children: [
        Text('العملة:', style: TextStyle(fontSize: 12, color: textSecondary, fontFamily: 'Cairo')),
        const SizedBox(width: 6),
        _buildCurrencyChip(
          context: context,
          label: 'الكل (ج.م)',
          isActive: state.currencyFilter == null,
          onPressed: () => cubit.setCurrencyFilter(null),
        ),
        const SizedBox(width: 4),
        for (final c in ['EGP', 'USD', 'EUR', 'GBP']) ...[
          _buildCurrencyChip(
            context: context,
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
    required BuildContext context,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final borderColor = AppTheme.getBorderColor(context);
    final textSecondary = AppTheme.getTextSecondary(context);

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? primary.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? primary : borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? primary : textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOrError(BuildContext context, GeneralLedgerState state) {
    final isDark = AppTheme.isDark(context);
    final bgColor = isDark ? AppTheme.sidebarBg : AppTheme.lightBackground;
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final textColor = AppTheme.getTextSecondary(context);

    if (state is GeneralLedgerLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: 16),
              Text(
                'جاري تحميل دفتر الأستاذ...',
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (state is GeneralLedgerError) {
      return Scaffold(
        backgroundColor: bgColor,
        body: ReportingErrorView(
          message: state.message,
          onRetry: () => context.read<GeneralLedgerCubit>().loadReport(),
        ),
      );
    }

    return Scaffold(backgroundColor: bgColor);
  }

  Widget _buildEntityFilters(BuildContext context, GeneralLedgerLoaded state,
      GeneralLedgerCubit cubit) {
    final textSecondary = AppTheme.getTextSecondary(context);

    String getTreasuryAccount(String? currency) {
      switch (currency) {
        case 'USD': return '12212';
        case 'EUR': return '12213';
        case 'GBP': return '12214';
        default: return '12211';
      }
    }

    String getBankAccount(String? currency) {
      switch (currency) {
        case 'USD': return '12112';
        case 'EUR': return '12113';
        case 'GBP': return '12114';
        default: return '12111';
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: textSecondary),
          const SizedBox(width: 8),
          Text(
            'تصفية حسب الحساب / الجهة:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textSecondary,
                fontFamily: 'Cairo'),
          ),
          const SizedBox(width: 12),
          _buildEntityChip(context, 'المرتبات', '3111', state, cubit),
          _buildEntityChip(context, 'الإنتاج التام', '12413', state, cubit),
          _buildEntityChip(context, 'مخزون الفرز', '12414', state, cubit),
          _buildEntityChip(context, 'المحاصيل (المخزون)', '12412', state, cubit),
          _buildEntityChip(context, 'مواد التعبئة', '12411', state, cubit),
          _buildEntityChip(context, 'مبيعات الفراولة', '4111', state, cubit),
          _buildEntityChip(context, 'إيرادات التصدير', '4113', state, cubit),
          _buildEntityChip(context, 'العملاء', '1251', state, cubit, groupPrefix: '1251'),
          _buildEntityChip(context, 'الموردين', '211', state, cubit, groupPrefix: '211'),
          _buildEntityChip(context, 'شيكات برسم التحصيل', '12121', state, cubit, groupPrefix: '1212'),
          _buildEntityChip(context, 'أوراق الدفع', '2112', state, cubit, groupPrefix: '2112'),
          _buildEntityChip(context, 'المساهمين', '2321', state, cubit, groupPrefix: '2321'),
          _buildEntityChip(context, 'الخزينة الرئيسية', getTreasuryAccount(state.currencyFilter), state, cubit, groupPrefix: '1221'),
          _buildEntityChip(context, 'الحسابات البنكية', getBankAccount(state.currencyFilter), state, cubit, groupPrefix: '1211'),
          _buildEntityChip(context, 'إهلاك الأصول', '3211', state, cubit),
          _buildEntityChip(context, 'فروق العمله', '3221', state, cubit),
          _buildEntityChip(context, 'تكاليف المبيعات', '341', state, cubit),
        ],
      ),
    );
  }

  Widget _buildEntityChip(BuildContext context, String label, String accountCode,
      GeneralLedgerLoaded state, GeneralLedgerCubit cubit, {String? groupPrefix}) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final textPrimary = AppTheme.getTextPrimary(context);

    // Check if the current account matches this chip
    bool isSelected = false;
    if (state.filter.accountId != null) {
      if (groupPrefix != null) {
        isSelected = state.filter.accountId!.startsWith(groupPrefix) && state.filter.accountId!.length >= 4;
      } else {
        isSelected = state.filter.accountId == accountCode;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : textPrimary,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            cubit.setAccountId(accountCode);
          } else {
            cubit.setAccountId(null);
          }
        },
        backgroundColor: primary.withAlpha(20),
        selectedColor: primary,
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? primary : primary.withAlpha(50),
          ),
        ),
      ),
    );
  }
}
