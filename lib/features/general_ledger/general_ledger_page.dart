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

  Widget _buildLoadMoreButton(GeneralLedgerLoaded state, GeneralLedgerCubit cubit) {
    if (!state.hasMore) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: state.isLoadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF16D5FF),
                ),
              )
            : TextButton.icon(
                onPressed: () => cubit.loadMore(),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('تحميل المزيد'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF16D5FF),
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

    var filteredRows = report.rows;
    if (state.searchQuery.isNotEmpty) {
      final q = state.searchQuery.toLowerCase();
      filteredRows = report.rows.where((row) {
        final entryStr = row.entryNumber?.toString() ?? '';
        final desc = row.description ?? '';
        final code = row.accountCode;
        final debitStr = row.debit > 0 ? row.debit.toString() : '';
        final creditStr = row.credit > 0 ? row.credit.toString() : '';
        return entryStr.toLowerCase().contains(q) ||
            desc.toLowerCase().contains(q) ||
            code.toLowerCase().contains(q) ||
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
                'description': row.description ?? '',
                'debit': row.debit,
                'credit': row.credit,
                'balance': row.balance,
                'currency': row.currency,
              },
            )));
    }

    return Container(
      color: AppTheme.sidebarBg,
      child: Column(
        children: [
          Expanded(
            child: ReportingScaffold(
              backgroundColor: AppTheme.sidebarBg,
              headerIcon: Icons.book_outlined,
              headerTitle: state.drillDownAccountCode != null
                  ? 'دفتر الأستاذ — ${state.drillDownAccountCode} ${state.drillDownAccountName ?? ''}'
                  : 'دفتر الأستاذ',
              headerCount: report.transactionCount,
            headerCountLabel: 'قيود',
            headerActions: [
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
            metrics: GeneralLedgerConfig.buildMetrics(report),
            // isBalanced: report.accountId == null ? report.isBalanced : null,
            // totalDebit: report.accountId == null ? report.totalDebit : null,
            // totalCredit: report.accountId == null ? report.totalCredit : null,
            // difference: report.accountId == null ? (report.totalDebit - report.totalCredit) : null,
            // debitLabel: 'إجمالي المدين',
            // creditLabel: 'إجمالي الدائن',
            // differenceLabel: 'الفرق',
            onRefresh: () => cubit.loadReport(refresh: true),
            onFullscreen: () => cubit.toggleFullscreen(),
            exportActions: GeneralLedgerConfig.buildExportActions(
                report: report, context: context),
            columns: GeneralLedgerConfig.columns,
            rows: gridRows,
            cellRenderer: (row, col) =>
                GeneralLedgerConfig.renderCell(row.cells, col, row.isParent),
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
        _buildLoadMoreButton(state, cubit),
      ],
    ));
  }

  Widget _buildFilterContent(
      BuildContext context, GeneralLedgerLoaded state, GeneralLedgerCubit cubit) {
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
              color: AppTheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'حساب محدد',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => cubit.setAccountId(null),
                  child: const Icon(Icons.close,
                      size: 14, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCurrencyFilter(
      BuildContext context, GeneralLedgerLoaded state, GeneralLedgerCubit cubit) {
    return Row(
      children: [
        const Text('العملة:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        const SizedBox(width: 6),
        _buildCurrencyChip(
          label: 'الكل (ج.م)',
          isActive: state.currencyFilter == null,
          onPressed: () => cubit.setCurrencyFilter(null),
        ),
        const SizedBox(width: 4),
        for (final c in ['EGP', 'USD', 'EUR', 'GBP']) ...[
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
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOrError(BuildContext context, GeneralLedgerState state) {
    if (state is GeneralLedgerLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.sidebarBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF16D5FF)),
              SizedBox(height: 16),
              Text(
                'جاري تحميل دفتر الأستاذ...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (state is GeneralLedgerError) {
      return Scaffold(
        backgroundColor: AppTheme.sidebarBg,
        body: ReportingErrorView(
          message: state.message,
          onRetry: () => context.read<GeneralLedgerCubit>().loadReport(),
        ),
      );
    }

    return const Scaffold(backgroundColor: AppTheme.sidebarBg);
  }

  Widget _buildEntityFilters(BuildContext context, GeneralLedgerLoaded state,
      GeneralLedgerCubit cubit) {
    
    String getTreasuryAccount(String? currency) {
      switch (currency) {
        case 'USD': return '11102';
        case 'EUR': return '11103';
        case 'GBP': return '11104';
        default: return '11101';
      }
    }

    String getBankAccount(String? currency) {
      switch (currency) {
        case 'USD': return '11202';
        case 'EUR': return '11203';
        case 'GBP': return '11204';
        default: return '11201';
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          const Text(
            'تصفية حسب الحساب / الجهة:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo'),
          ),
          const SizedBox(width: 12),
          _buildEntityChip('تكلفة المبيعات', '5000', state, cubit),
          _buildEntityChip('الإنتاج التام', '1031', state, cubit),
          _buildEntityChip('المحاصيل (المخزون)', '1030', state, cubit),
          _buildEntityChip('مواد التعبئة', '1040', state, cubit),
          _buildEntityChip('المبيعات', '4000', state, cubit),
          _buildEntityChip('إيرادات التصدير', '4200', state, cubit),
          _buildEntityChip('العملاء', '1020', state, cubit),
          _buildEntityChip('الموردين', '2000', state, cubit),
          _buildEntityChip('المساهمين', '3101', state, cubit),
          _buildEntityChip('المخلصين', '2104', state, cubit),
          _buildEntityChip('شركات الشحن', '2103', state, cubit),
          _buildEntityChip('الخزينة الرئيسية', getTreasuryAccount(state.currencyFilter), state, cubit, groupPrefix: '1110'),
          _buildEntityChip('الحسابات البنكية', getBankAccount(state.currencyFilter), state, cubit, groupPrefix: '1120'),
          _buildEntityChip('المصروفات', '6000', state, cubit),
        ],
      ),
    );
  }

  Widget _buildEntityChip(String label, String accountCode,
      GeneralLedgerLoaded state, GeneralLedgerCubit cubit, {String? groupPrefix}) {
    
    // Check if the current account matches this chip
    bool isSelected = false;
    if (state.filter.accountId != null) {
      if (groupPrefix != null) {
        isSelected = state.filter.accountId!.startsWith(groupPrefix) && state.filter.accountId!.length == 5;
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
            color: isSelected ? Colors.white : AppTheme.textPrimary,
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
        backgroundColor: AppTheme.primary.withAlpha(20),
        selectedColor: AppTheme.primary,
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? AppTheme.primary : AppTheme.primary.withAlpha(50),
          ),
        ),
      ),
    );
  }
}
