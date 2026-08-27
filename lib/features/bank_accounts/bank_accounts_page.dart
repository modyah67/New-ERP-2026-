import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/bank_account_dao.dart';
import '../../data/dao/exchange_rate_dao.dart';
import '../../data/models/bank_account_model.dart';
import '../suppliers/widgets/multi_invoice_payment_dialog.dart';
import '../../data/models/bank_account_transaction_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/account_model.dart';
import '../../data/models/unified_transaction_model.dart';
import '../../data/services/chart_of_accounts_cache_service.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../core/router.dart';
import '../treasury/widgets/unified_transaction_details_modal.dart';
import '../treasury/treasury_pdf_service.dart';
import 'bank_accounts_cubit.dart';
import 'bank_accounts_state.dart';
import 'bank_account_export_service.dart';

class BankAccountsPage extends StatelessWidget {
  const BankAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BankAccountsCubit()..loadAll(),
      child: const _BankAccountsView(),
    );
  }
}

class _BankAccountsView extends StatefulWidget {
  const _BankAccountsView();

  @override
  State<_BankAccountsView> createState() => _BankAccountsViewState();
}

class _BankAccountsViewState extends State<_BankAccountsView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance, color: AppTheme.primary, size: 28),
                const SizedBox(width: 12),
                const Text('الحسابات البنكية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: BlocConsumer<BankAccountsCubit, BankAccountsState>(
                listener: (_, state) {
                  if (state is BankAccountsError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(state.message),
                          backgroundColor: AppTheme.danger),
                    );
                  }
                },
                builder: (_, state) {
                  if (state is BankAccountsLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is BankAccountsLoaded) {
                    return _buildContent(state);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BankAccountsLoaded state) {
    final accounts = state.accounts;
    if (accounts.isEmpty) {
      return const Center(
        child: Text('لا توجد حسابات بنكية',
            style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo')),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _pageActionButton(
                icon: Icons.add_circle_outline,
                label: 'إيداع',
                color: AppTheme.success,
                onPressed: () => _showUnifiedDepositSheet(state),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _pageActionButton(
                icon: Icons.remove_circle_outline,
                label: 'صرف',
                color: AppTheme.danger,
                onPressed: () => _showUnifiedWithdrawSheet(state),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _pageActionButton(
                icon: Icons.currency_exchange,
                label: 'تحويل عملة',
                color: AppTheme.accent,
                onPressed: () => _showCurrencyExchangeSheet(state),
              ),
            ),
            const SizedBox(width: 12),
            // Expanded(
            //   child: _pageActionButton(
            //     icon: Icons.receipt_long_outlined,
            //     label: 'سداد مورد (متعدد)',
            //     color: Colors.amber,
            //     onPressed: () => _showMultiInvoicePaymentDialog(state),
            //   ),
            // ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 600;
            if (isDesktop) {
              int columns = accounts.length;
              if (columns == 0) columns = 1;
              if (constraints.maxWidth / columns < 160 && columns > 1) {
                columns = (constraints.maxWidth / 160).floor();
                if (columns < 1) columns = 1;
              }
              final spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - ((columns - 1) * spacing)) / columns -
                      0.1;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: accounts
                    .map((acc) => SizedBox(
                          width: cardWidth,
                          height: 150,
                          child: _buildBankCard(account: acc, state: state),
                        ))
                    .toList(),
              );
            }

            return SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  return SizedBox(
                    width: 160,
                    child: _buildBankCard(account: accounts[i], state: state),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        if (state.selectedAccountId != null) ...[
          _buildTransactionsHeader(state),
          const SizedBox(height: 12),
          Expanded(child: _buildTransactionsList(state)),
        ] else
          Expanded(
            child: Center(
              child: Text(
                'اضغط على حساب لعرض الحركات',
                style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBankCard({
    required BankAccountModel account,
    required BankAccountsLoaded state,
  }) {
    final Color cardColor;
    switch (account.currency) {
      case 'EGP':
        cardColor = const Color(0xFF10B981);
        break;
      case 'USD':
        cardColor = const Color(0xFF448AFF);
        break;
      case 'EUR':
        cardColor = const Color(0xFFF59E0B);
        break;
      case 'GBP':
        cardColor = const Color(0xFFEC4899);
        break;
      default:
        cardColor = AppTheme.primary;
    }

    final isSelected = state.selectedAccountId == account.id;

    return GestureDetector(
      onTap: () {
        context.read<BankAccountsCubit>().loadTransactions(account.id);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cardColor.withValues(alpha: isSelected ? 0.25 : 0.15),
                  cardColor.withValues(alpha: isSelected ? 0.10 : 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? cardColor.withValues(alpha: 0.6)
                    : cardColor.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: cardColor.withValues(alpha: 0.5),
                              blurRadius: 8),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(account.currency,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cardColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  fontFamily: 'Cairo')),
                          Text(account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                  fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppUtils.formatNumber(account.balance),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  Widget _buildTransactionsHeader(BankAccountsLoaded state) {
    final account = state.accounts.firstWhere(
      (a) => a.id == state.selectedAccountId,
      orElse: () => state.accounts.first,
    );
    final filteredList = state.filteredTransactions;
    final hasActiveFilters = state.searchQuery.trim().isNotEmpty ||
        state.startDate != null ||
        state.endDate != null ||
        (state.currencyFilter != null && state.currencyFilter!.isNotEmpty) ||
        state.accountFilter != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  color: AppTheme.accent, size: 22),
              const SizedBox(width: 8),
              Text('حركات ${account.name}',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Cairo')),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${filteredList.length} حركة',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
              ),
              const SizedBox(width: 16),
              // _accountFilterDropdown(state),
              // const SizedBox(width: 10),
              // _currencyFilterDropdown(state),
              // const SizedBox(width: 10),
              _dateFilterBtn(
                label: state.startDate != null
                    ? 'من: ${DateFormat('MM/dd').format(state.startDate!)}'
                    : 'التاريخ',
                isActive: state.startDate != null || state.endDate != null,
                onTap: () => _showDateRangePicker(state),
                showClear: state.startDate != null || state.endDate != null,
                onClear: () => context
                    .read<BankAccountsCubit>()
                    .setDateFilter(null, null, clear: true),
              ),
              const SizedBox(width: 10),
            //  _exportBtn(Icons.picture_as_pdf, 'PDF', () => _exportPdf(state)),
              const SizedBox(width: 8),
              _exportBtn(Icons.table_chart_outlined, 'Excel',
                  () => _exportExcel(state)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
            onChanged: (val) =>
                context.read<BankAccountsCubit>().setSearchQuery(val),
            decoration: InputDecoration(
              hintText:
                  'بحث في رقم القيد، البيان، اسم الحساب، المورد أو العميل...',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11.5,
                  fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppTheme.accent, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        context.read<BankAccountsCubit>().setSearchQuery('');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: AppTheme.glassBorder.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: AppTheme.glassBorder.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
        ),
        if (hasActiveFilters) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('الفلاتر النشطة:',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      fontFamily: 'Cairo')),
              if (state.searchQuery.trim().isNotEmpty)
                _buildFilterChip('بحث: "${state.searchQuery}"', () {
                  _searchController.clear();
                  context.read<BankAccountsCubit>().setSearchQuery('');
                }),
              if (state.startDate != null || state.endDate != null)
                _buildFilterChip('التاريخ محدَّد', () {
                  context
                      .read<BankAccountsCubit>()
                      .setDateFilter(null, null, clear: true);
                }),
              if (state.currencyFilter != null &&
                  state.currencyFilter!.isNotEmpty)
                _buildFilterChip('العملة: ${state.currencyFilter}', () {
                  context.read<BankAccountsCubit>().setCurrencyFilter(null);
                }),
              if (state.accountFilter != null)
                _buildFilterChip('حساب محدَّد', () {
                  context.read<BankAccountsCubit>().setAccountFilter(null);
                }),
              InkWell(
                onTap: () {
                  _searchController.clear();
                  context.read<BankAccountsCubit>().clearAllFilters();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('مسح الكل',
                      style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: 10,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _accountFilterDropdown(BankAccountsLoaded state) {
    final hasFilter = state.accountFilter != null;
    return PopupMenuButton<int?>(
      initialValue: state.accountFilter,
      tooltip: 'فلتر الحساب البنكي',
      onSelected: (val) {
        context.read<BankAccountsCubit>().setAccountFilter(val);
      },
      offset: const Offset(0, 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFilter
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasFilter ? AppTheme.primary : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance,
                size: 18, color: hasFilter ? AppTheme.primary : Colors.white70),
            const SizedBox(width: 6),
            Text(
              hasFilter
                  ? state.accounts
                      .firstWhere((a) => a.id == state.accountFilter,
                          orElse: () => state.accounts.first)
                      .name
                  : 'الحساب',
              style: TextStyle(
                fontSize: 12,
                color: hasFilter ? AppTheme.primary : Colors.white70,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18, color: hasFilter ? AppTheme.primary : Colors.white70),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: null,
          child: Text('جميع الحسابات',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
        ),
        ...state.accounts.map((acc) => PopupMenuItem(
              value: acc.id,
              child: Text('${acc.name} (${acc.currency})',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
            )),
      ],
    );
  }

  Widget _currencyFilterDropdown(BankAccountsLoaded state) {
    final hasFilter =
        state.currencyFilter != null && state.currencyFilter!.isNotEmpty;
    const currencies = ['EGP', 'USD', 'EUR', 'GBP'];
    return PopupMenuButton<String?>(
      initialValue: state.currencyFilter,
      tooltip: 'تصفية بالعملة',
      onSelected: (val) {
        context.read<BankAccountsCubit>().setCurrencyFilter(val);
      },
      offset: const Offset(0, 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFilter
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasFilter ? AppTheme.primary : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on_outlined,
                size: 18, color: hasFilter ? AppTheme.primary : Colors.white70),
            const SizedBox(width: 6),
            Text(
              hasFilter ? state.currencyFilter! : 'العملة',
              style: TextStyle(
                fontSize: 12,
                color: hasFilter ? AppTheme.primary : Colors.white70,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18, color: hasFilter ? AppTheme.primary : Colors.white70),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: null,
          child: Text('الكل',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
        ),
        ...currencies.map((cur) => PopupMenuItem(
              value: cur,
              child: Text(cur,
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
            )),
      ],
    );
  }

  Future<void> _showDateRangePicker(BankAccountsLoaded state) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: state.startDate != null && state.endDate != null
          ? DateTimeRange(start: state.startDate!, end: state.endDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.cardBg,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      context.read<BankAccountsCubit>().setDateFilter(picked.start, picked.end);
    }
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.primary, fontSize: 10, fontFamily: 'Cairo')),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 12, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _exportBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  Widget _dateFilterBtn({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool showClear = false,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isActive ? AppTheme.primary : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 18, color: isActive ? AppTheme.primary : Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isActive ? AppTheme.primary : Colors.white70,
                    fontFamily: 'Cairo',
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal)),
            if (showClear && onClear != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClear,
                child:
                    const Icon(Icons.close, size: 14, color: AppTheme.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(BankAccountsLoaded state) {
    final filteredList = state.filteredTransactions;
    final hasActiveFilters = state.searchQuery.trim().isNotEmpty ||
        state.startDate != null ||
        state.endDate != null ||
        (state.currencyFilter != null && state.currencyFilter!.isNotEmpty) ||
        state.accountFilter != null;

    if (state.isSaving) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filteredList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppTheme.textMuted, size: 40),
            const SizedBox(height: 8),
            Text(
              hasActiveFilters
                  ? 'لا توجد حركات تطابق الفلاتر المحددة'
                  : 'لا توجد حركات في هذا الحساب',
              style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo'),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth =
              constraints.maxWidth > 700 ? constraints.maxWidth : 700.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minWidth,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                            flex: 1,
                            child: Text('#',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('التاريخ',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('النوع',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('المبلغ',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('الرصيد',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 3,
                            child: Text('البيان / الجهة',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        SizedBox(width: 60),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: filteredList.length,
                      itemBuilder: (ctx, index) {
                        final tx = filteredList[index];
                        return _buildTransactionRow(tx, state);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  (String?, String?) _extractRelatedParty(String? description) {
    if (description == null || description.isEmpty) return (null, null);
    final lower = description.toLowerCase();
    if (lower.contains('للمورد') || lower.contains('المورد')) {
      final match =
          RegExp(r'(?:للمورد|المورد)[\s\-:]+([^\-]+?)(?:\s*-\s*فاتورة|\s*$)')
              .firstMatch(description);
      if (match != null) {
        final name = match.group(1)?.trim();
        if (name != null && name.isNotEmpty) return (name, 'supplier');
      }
    }
    if (lower.contains('للعميل') || lower.contains('العميل')) {
      final match =
          RegExp(r'(?:للعميل|العميل)[\s\-:]+([^\-]+?)(?:\s*-\s*فاتورة|\s*$)')
              .firstMatch(description);
      if (match != null) {
        final name = match.group(1)?.trim();
        if (name != null && name.isNotEmpty) return (name, 'customer');
      }
    }
    return (null, null);
  }

  void _confirmDraftTx(BankAccountTransactionModel tx) {
    final txId = tx.id;
    if (txId <= 0) return;

    final typeLabel = tx.isDeposit
        ? 'إيداع'
        : (tx.type.contains('exchange') ? 'تحويل عملة' : 'صرف');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد وترحيل الحركة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        content: Text(
          'هل أنت متأكد من تأكيد وترحيل حركة "$typeLabel" بمبلغ ${AppUtils.formatNumber(tx.amount)} وتحديث الأرصدة والقيود المحاسبية؟',
          style: const TextStyle(
              fontFamily: 'Cairo', color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<BankAccountsCubit>()
                  .confirmDraft(transactionId: txId);
            },
            child: const Text('تأكيد وترحيل',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _deleteDraftTx(BankAccountTransactionModel tx) {
    final txId = tx.id;
    if (txId <= 0) return;

    final typeLabel = tx.isDeposit
        ? 'إيداع'
        : (tx.type.contains('exchange') ? 'تحويل عملة' : 'صرف');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف المسودة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: AppTheme.danger)),
        content: Text(
          'هل تريد حذف مسودة "$typeLabel" بمبلغ ${AppUtils.formatNumber(tx.amount)} نهائياً؟',
          style: const TextStyle(
              fontFamily: 'Cairo', color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<BankAccountsCubit>()
                  .deleteDraft(transactionId: txId);
            },
            child: const Text('تأكيد الحذف',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditTransaction(
      BankAccountTransactionModel tx, BankAccountsLoaded state) {
    if (tx.type == 'deposit' || tx.type == 'receipt') {
      _showUnifiedDepositSheet(state, draftTx: tx);
    } else if (tx.type == 'currency_exchange_out' ||
        tx.type == 'currency_exchange_in' ||
        tx.type == 'exchange') {
      _showCurrencyExchangeSheet(state, draftTx: tx);
    } else {
      _showUnifiedWithdrawSheet(state, draftTx: tx);
    }
  }

  Widget _buildTransactionRow(
      BankAccountTransactionModel tx, BankAccountsLoaded state) {
    final isDeposit = tx.isDeposit;
    final typeColor = tx.isDraft
        ? AppTheme.warning
        : (isDeposit ? const Color(0xFF14B8A6) : const Color(0xFFEC4899));
    final dateStr = DateFormat('yyyy-MM-dd').format(tx.createdAt);
    final amountStr =
        '${isDeposit ? '+' : '-'}${AppUtils.formatNumber(tx.amount)}';
    final isChequeTx = tx.description?.contains('شيك') ?? false;

    final bankAcc = state.accounts.firstWhere((a) => a.id == tx.bankAccountId,
        orElse: () => state.accounts.first);

    String? partyName = tx.relatedPartyName;
    String? partyType = tx.relatedPartyType;
    if (partyName == null || partyName.isEmpty) {
      final fallback = _extractRelatedParty(tx.description);
      partyName = fallback.$1;
      partyType = fallback.$2;
    }

    final unifiedTx = UnifiedTransactionModel(
      id: tx.id.toString(),
      journalEntryId: tx.journalEntryId,
      entryNumber:
          tx.journalEntryId != null ? '#${tx.journalEntryId}' : '#${tx.id}',
      accountCategory: 'bank',
      accountSourceId: tx.bankAccountId.toString(),
      accountSourceName: bankAcc.name,
      transactionType: tx.type,
      currency: bankAcc.currency,
      amount: tx.amount,
      balanceBefore: tx.balanceBefore,
      balanceAfter: tx.balanceAfter,
      description: tx.description ?? '',
      referenceNumber: tx.referenceNumber,
      createdBy: tx.createdBy,
      creatorName: tx.createdByName,
      createdAt: tx.createdAt.toIso8601String(),
      relatedPartyName: partyName,
      relatedPartyType: partyType,
    );

    String typeLabelText;
    if (tx.isDraft) {
      typeLabelText = isDeposit
          ? 'مسودة إيداع'
          : (tx.type.contains('exchange') ? 'مسودة تحويل' : 'مسودة صرف');
    } else {
      typeLabelText = isDeposit
          ? 'إيداع'
          : (tx.type.contains('exchange') ? 'تحويل عملة' : 'صرف');
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tx.isDraft
              ? () => _showEditTransaction(tx, state)
              : () => UnifiedTransactionDetailsModal.show(context, unifiedTx),
          hoverColor: Colors.white.withValues(alpha: 0.03),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: tx.isDraft
                  ? AppTheme.warning.withValues(alpha: 0.04)
                  : null,
              border: Border(
                bottom: BorderSide(
                    color: tx.isDraft
                        ? AppTheme.warning.withValues(alpha: 0.2)
                        : AppTheme.divider,
                    width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 1,
                    child: Text(
                        tx.isDraft
                            ? '#مسودة-${tx.id}'
                            : '#${tx.journalEntryId ?? tx.id}',
                        style: TextStyle(
                            color: tx.isDraft
                                ? AppTheme.warning
                                : AppTheme.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'Cairo'))),
                Expanded(
                    flex: 2,
                    child: Text(dateStr,
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontFamily: 'Cairo'))),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: tx.isDraft
                          ? Border.all(
                              color: AppTheme.warning.withValues(alpha: 0.5),
                              width: 0.5)
                          : null,
                    ),
                    child: Text(
                      typeLabelText,
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(amountStr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                      tx.isDraft
                          ? '—'
                          : '${AppUtils.formatNumber(tx.balanceAfter)} ${bankAcc.currency}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: tx.isDraft
                              ? AppTheme.textMuted
                              : Colors.white,
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ),
                Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tx.description ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: tx.isDraft
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                                fontSize: 11,
                                fontFamily: 'Cairo')),
                        if (unifiedTx.relatedPartyName != null &&
                            unifiedTx.relatedPartyName!.isNotEmpty)
                          Text(unifiedTx.relatedPartyName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.7),
                                  fontFamily: 'Cairo')),
                      ],
                    )),
                SizedBox(
                  width: tx.isDraft ? 110 : 90,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (tx.isDraft) ...[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 17, color: AppTheme.accent),
                          tooltip: 'تعديل المسودة',
                          onPressed: () => _showEditTransaction(tx, state),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline,
                              size: 17, color: AppTheme.success),
                          tooltip: 'تأكيد وترحيل المسودة',
                          onPressed: () => _confirmDraftTx(tx),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 17, color: AppTheme.danger),
                          tooltip: 'حذف المسودة',
                          onPressed: () => _deleteDraftTx(tx),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(),
                        ),
                      ] else ...[
                        IconButton(
                          icon: const Icon(Icons.book_outlined,
                              size: 16, color: AppTheme.accent),
                          tooltip: 'عرض القيد المحاسبي',
                          onPressed: () {
                            JournalEntryNavigationService.openForTransaction(
                              context,
                              journalEntryId: tx.journalEntryId,
                              txId: tx.id,
                              description: tx.description,
                              sourceType: tx.relatedPartyType,
                              sourceId: tx.relatedPartyId,
                            );
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.print_outlined,
                              size: 16, color: AppTheme.accent),
                          onPressed: () =>
                              TreasuryPdfService.printVoucher(unifiedTx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        if (isChequeTx)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(Icons.lock_outline,
                                size: 14, color: AppTheme.textMuted),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showUnifiedDepositSheet(BankAccountsLoaded state,
      {BankAccountTransactionModel? draftTx}) async {
    final revenueAccounts =
        await ChartOfAccountsCacheService().getRevenueAccounts();
    final amountCtrl = TextEditingController(
        text: draftTx != null ? draftTx.amount.toString() : '');
    final descCtrl = TextEditingController(text: draftTx?.description ?? '');
    final isSaving = ValueNotifier(false);
    final initialBankAcc = draftTx != null
        ? state.accounts.firstWhere((a) => a.id == draftTx.bankAccountId,
            orElse: () => state.accounts.first)
        : null;
    String currency = initialBankAcc?.currency ?? 'EGP';
    bool currencyLocked = draftTx != null;
    int? selectedRevenueAccountId = draftTx?.payload['revenue_account_id'] != null
        ? int.tryParse('${draftTx!.payload['revenue_account_id']}')
        : null;
    String? counterpartyType = draftTx?.relatedPartyType ?? draftTx?.payload['counterparty_type'];
    int? counterpartyId = (counterpartyType == 'customer' ||
                counterpartyType == 'clearing_agent' ||
                counterpartyType == 'shipping_company') &&
            draftTx?.relatedPartyId != null
        ? int.tryParse(draftTx!.relatedPartyId!)
        : null;
    String? supplierId =
        counterpartyType == 'supplier' ? draftTx?.relatedPartyId : null;
    String? shareholderId =
        counterpartyType == 'shareholder' ? draftTx?.relatedPartyId : null;
    String? counterpartyName = draftTx?.relatedPartyName;
    bool showCustomerSearch = false;
    bool showSupplierSearch = false;
    bool showClearingAgentSearch = false;
    bool showShippingCompanySearch = false;
    bool showShareholderSearch = false;
    List<CustomerModel> customerResults = [];
    List<SupplierModel> supplierResults = [];
    List<ClearingAgentModel> clearingAgentResults = [];
    List<ShippingCompanyModel> shippingCompanyResults = [];
    List<ShareholderModel> shareholderResults = [];
    final customerSearchCtrl = TextEditingController();
    final supplierSearchCtrl = TextEditingController();
    final clearingAgentSearchCtrl = TextEditingController();
    final shippingCompanySearchCtrl = TextEditingController();
    final shareholderSearchCtrl = TextEditingController();

    Future<List<CustomerModel>> searchCustomers(String q) async {
      if (q.trim().isEmpty) return [];
      return await CustomerDao().search(q.trim(), limit: 20);
    }

    Future<List<SupplierModel>> searchSuppliers(String q) async {
      if (q.trim().isEmpty) return [];
      return await SupplierDao().search(q.trim(), limit: 20);
    }

    Future<List<ClearingAgentModel>> searchClearingAgents(String q) async {
      if (q.trim().isEmpty) return [];
      return await ClearingAgentDao().search(q.trim(), limit: 20);
    }

    Future<List<ShippingCompanyModel>> searchShippingCompanies(String q) async {
      if (q.trim().isEmpty) return [];
      return await ShippingCompanyDao().search(q.trim(), limit: 20);
    }

    Future<List<ShareholderModel>> searchShareholders(String q) async {
      if (q.trim().isEmpty) return [];
      return await ShareholderDao().search(q.trim(), limit: 20);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool isEntityValid = true;
          if (counterpartyType == 'customer') {
            isEntityValid = counterpartyId != null;
          } else if (counterpartyType == 'supplier') {
            isEntityValid = supplierId != null;
          } else if (counterpartyType == 'shareholder') {
            isEntityValid = shareholderId != null;
          } else if (counterpartyType == 'clearing_agent' ||
              counterpartyType == 'shipping_company') {
            isEntityValid = counterpartyId != null;
          } else if (counterpartyType == 'revenue') {
            isEntityValid = selectedRevenueAccountId != null;
          }

          final matchingAccounts =
              state.accounts.where((a) => a.currency == currency).toList();
          final selectedAccount =
              matchingAccounts.length == 1 ? matchingAccounts.first : null;

          Widget buildSmallBtn(String label, bool active, VoidCallback onTap) {
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.success.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: active ? AppTheme.success : AppTheme.glassBorder),
                ),
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          color: active
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11)),
                ),
              ),
            );
          }

          Widget buildSearchField({
            required TextEditingController ctrl,
            required String hint,
            required ValueChanged<String> onChanged,
            required List<Widget> results,
          }) {
            return Column(children: [
              TextField(
                controller: ctrl,
                onChanged: onChanged,
                style:
                    const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              if (results.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: Column(children: results),
                ),
            ]);
          }

          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0A1630),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('إيداع في حساب بنكي',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d*')),
                        ],
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          prefixIcon: const Icon(Icons.attach_money,
                              color: AppTheme.success),
                          suffixText: currency,
                          suffixStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success),
                          filled: true,
                          fillColor: AppTheme.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        value: currency,
                        dropdownColor: const Color(0xCC05192D),
                        items: ['EGP', 'USD', 'EUR', 'GBP']
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style:
                                          const TextStyle(fontFamily: 'Cairo')),
                                ))
                            .toList(),
                        onChanged: currencyLocked
                            ? null
                            : (v) => setSheetState(() => currency = v ?? 'EGP'),
                        style: const TextStyle(
                            fontFamily: 'Cairo', color: Colors.white),
                      ),
                    ),
                  ]),
                  if (currency != 'EGP') ...[
                    const SizedBox(height: 8),
                    FutureBuilder<double>(
                      future: ExchangeRateDao().getRate(currency),
                      builder: (context, snapshot) {
                        final rate = snapshot.data ?? 0.0;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
                              const SizedBox(width: 8),
                              Text(
                                snapshot.connectionState == ConnectionState.waiting
                                    ? 'جارٍ جلب سعر الصرف...'
                                    : 'سعر الصرف الحالي المسجل:  $currency = ${rate > 0 ? AppUtils.formatCurrency(rate, "EGP") : "غير محدد"}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  if (selectedAccount != null) ...[
                    const SizedBox(height: 8),
                    Text('الحساب: ${selectedAccount.name}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.success,
                            fontFamily: 'Cairo')),
                  ],
                  if (matchingAccounts.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text('لا يوجد حساب بهذه العملة',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.danger,
                            fontFamily: 'Cairo')),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(Icons.people_outline,
                        size: 14, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text('المصدر',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                            fontFamily: 'Cairo')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    // Expanded(
                    //     child: buildSmallBtn(
                    //         'إيرادات', counterpartyType == 'revenue', () {
                    //   setSheetState(() {
                    //     counterpartyType = 'revenue';
                    //     showCustomerSearch = false;
                    //     showSupplierSearch = false;
                    //     showShareholderSearch = false;
                    //     showClearingAgentSearch = false;
                    //     showShippingCompanySearch = false;
                    //     counterpartyId = null;
                    //     counterpartyName = null;
                    //     currency = 'EGP';
                    //     currencyLocked = false;
                    //   });
                    // })),
                    const SizedBox(width: 6),
                    Expanded(
                        child: buildSmallBtn(
                            'عميل', counterpartyType == 'customer', () {
                      setSheetState(() {
                        counterpartyType = 'customer';
                        showCustomerSearch = true;
                        showSupplierSearch = false;
                        showShareholderSearch = false;
                        showClearingAgentSearch = false;
                        showShippingCompanySearch = false;
                        counterpartyId = null;
                        counterpartyName = null;
                        customerSearchCtrl.clear();
                        customerResults = [];
                        currency = 'EGP';
                        currencyLocked = false;
                      });
                    })),
                    const SizedBox(width: 6),
                    Expanded(
                        child: buildSmallBtn(
                            'مورد', counterpartyType == 'supplier', () {
                      setSheetState(() {
                        counterpartyType = 'supplier';
                        showSupplierSearch = true;
                        showCustomerSearch = false;
                        showClearingAgentSearch = false;
                        showShippingCompanySearch = false;
                        showShareholderSearch = false;
                        counterpartyId = null;
                        supplierId = null;
                        counterpartyName = null;
                        supplierSearchCtrl.clear();
                        supplierResults = [];
                        currency = 'EGP';
                        currencyLocked = false;
                      });
                    })),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: buildSmallBtn(
                            'مساهم', counterpartyType == 'shareholder', () {
                      setSheetState(() {
                        counterpartyType = 'shareholder';
                        showShareholderSearch = true;
                        showCustomerSearch = false;
                        showSupplierSearch = false;
                        showClearingAgentSearch = false;
                        showShippingCompanySearch = false;
                        counterpartyId = null;
                        counterpartyName = null;
                        shareholderId = null;
                        shareholderSearchCtrl.clear();
                        shareholderResults = [];
                        currencyLocked = false;
                      });
                    })),
                    // const SizedBox(width: 6),
                    // Expanded(
                    //     child: buildSmallBtn(
                    //         'مخلص', counterpartyType == 'clearing_agent', () {
                    //   setSheetState(() {
                    //     counterpartyType = 'clearing_agent';
                    //     showClearingAgentSearch = true;
                    //     showCustomerSearch = false;
                    //     showSupplierSearch = false;
                    //     showShippingCompanySearch = false;
                    //     showShareholderSearch = false;
                    //     counterpartyId = null;
                    //     counterpartyName = null;
                    //     clearingAgentSearchCtrl.clear();
                    //     clearingAgentResults = [];
                    //     currency = 'EGP';
                    //     currencyLocked = false;
                    //   });
                    // })),
                    // const SizedBox(width: 6),
                    // Expanded(
                    //     child: buildSmallBtn(
                    //         'شحن', counterpartyType == 'shipping_company', () {
                    //   setSheetState(() {
                    //     counterpartyType = 'shipping_company';
                    //     showShippingCompanySearch = true;
                    //     showShareholderSearch = false;
                    //     showCustomerSearch = false;
                    //     showSupplierSearch = false;
                    //     showClearingAgentSearch = false;
                    //     counterpartyId = null;
                    //     counterpartyName = null;
                    //     shippingCompanySearchCtrl.clear();
                    //     shippingCompanyResults = [];
                    //     currency = 'EGP';
                    //     currencyLocked = false;
                    //   });
                    // })),
                    const SizedBox(width: 6),
                    Expanded(
                        child: buildSmallBtn(
                            'رصيد افتتاحي', counterpartyType == null, () {
                      setSheetState(() {
                        counterpartyType = null;
                        showCustomerSearch = false;
                        showSupplierSearch = false;
                        showClearingAgentSearch = false;
                        showShippingCompanySearch = false;
                        showShareholderSearch = false;
                        counterpartyId = null;
                        counterpartyName = null;
                        currency = 'EGP';
                        currencyLocked = false;
                      });
                    })),
                  ]),
                  if (counterpartyType == 'revenue') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(Icons.account_balance_wallet,
                          size: 14, color: AppTheme.success),
                      const SizedBox(width: 6),
                      Text('حساب الإيرادات',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success,
                              fontFamily: 'Cairo')),
                    ]),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: selectedRevenueAccountId,
                      isExpanded: true,
                      dropdownColor: const Color(0xCC05192D),
                      hint: const Text('اختر حساب الإيرادات...',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: AppTheme.textSecondary)),
                      items: revenueAccounts.map((a) {
                        final id = int.tryParse(a['id'].toString());
                        final accountModel = AccountModel.fromMap(a);
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                '${accountModel.displayName} - ${accountModel.code}',
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.white)),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setSheetState(() => selectedRevenueAccountId = v),
                      style: const TextStyle(
                          fontFamily: 'Cairo', color: Colors.white),
                      underline:
                          Container(height: 1, color: AppTheme.glassBorder),
                    ),
                    if (selectedRevenueAccountId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('يجب اختيار حساب الإيرادات',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.danger,
                                fontFamily: 'Cairo')),
                      ),
                  ],
                  if (showShareholderSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: shareholderSearchCtrl,
                      hint: 'ابحث عن مساهم...',
                      onChanged: (v) async {
                        shareholderResults = await searchShareholders(v);
                        setSheetState(() {});
                      },
                      results: shareholderResults
                          .map((s) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    shareholderId = s.id?.toString();
                                    counterpartyName = s.name;
                                    shareholderSearchCtrl.text = s.name;
                                    shareholderResults = [];
                                    currencyLocked = false;
                                  });
                                },
                                title: Text(s.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (s.totalDepositsEgp -
                                            s.totalWithdrawalsEgp !=
                                        0)
                                      Text(
                                          'جنية: ${AppUtils.formatCurrency(s.totalDepositsEgp - s.totalWithdrawalsEgp)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsUsd -
                                            s.totalWithdrawalsUsd !=
                                        0)
                                      Text(
                                          'دولار: ${AppUtils.formatCurrency(s.totalDepositsUsd - s.totalWithdrawalsUsd)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsEur -
                                            s.totalWithdrawalsEur !=
                                        0)
                                      Text(
                                          'يورو: ${AppUtils.formatCurrency(s.totalDepositsEur - s.totalWithdrawalsEur)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsGbp -
                                            s.totalWithdrawalsGbp !=
                                        0)
                                      Text(
                                          'استرليني: ${AppUtils.formatCurrency(s.totalDepositsGbp - s.totalWithdrawalsGbp)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsEgp -
                                                s.totalWithdrawalsEgp ==
                                            0 &&
                                        s.totalDepositsUsd -
                                                s.totalWithdrawalsUsd ==
                                            0 &&
                                        s.totalDepositsEur -
                                                s.totalWithdrawalsEur ==
                                            0 &&
                                        s.totalDepositsGbp -
                                                s.totalWithdrawalsGbp ==
                                            0)
                                      const Text('رصيد: 0',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.textSecondary)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showCustomerSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: customerSearchCtrl,
                      hint: 'ابحث عن عميل...',
                      onChanged: (v) async {
                        customerResults = await searchCustomers(v);
                        setSheetState(() {});
                      },
                      results: customerResults
                          .map((c) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    counterpartyId = int.tryParse(c.id ?? '');
                                    counterpartyName = c.name;
                                    customerSearchCtrl.text = c.name;
                                    customerResults = [];
                                    if (c.currency.isNotEmpty) {
                                      currency = c.currency;
                                      currencyLocked = true;
                                    }
                                  });
                                },
                                title: Text(c.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text(
                                    'عملة: ${c.currency} — رصيد: ${AppUtils.formatNumber(c.balance)}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showSupplierSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: supplierSearchCtrl,
                      hint: 'ابحث عن مورد...',
                      onChanged: (v) async {
                        supplierResults = await searchSuppliers(v);
                        setSheetState(() {});
                      },
                      results: supplierResults
                          .map((s) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    supplierId = s.id;
                                    counterpartyName = s.name;
                                    supplierSearchCtrl.text = s.name;
                                    supplierResults = [];
                                    if (s.currency.isNotEmpty) {
                                      currency = s.currency;
                                      currencyLocked = true;
                                    } else {
                                      currencyLocked = false;
                                    }
                                  });
                                },
                                title: Text(s.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text(
                                    'رصيد: ${AppUtils.formatNumber(s.outstandingBalance)}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showClearingAgentSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: clearingAgentSearchCtrl,
                      hint: 'ابحث عن مخلص...',
                      onChanged: (v) async {
                        clearingAgentResults = await searchClearingAgents(v);
                        setSheetState(() {});
                      },
                      results: clearingAgentResults
                          .map((a) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    counterpartyId = int.tryParse(a.id ?? '');
                                    counterpartyName = a.name;
                                    clearingAgentSearchCtrl.text = a.name;
                                    clearingAgentResults = [];
                                    if (a.currency.isNotEmpty) {
                                      currency = a.currency;
                                      currencyLocked = true;
                                    }
                                  });
                                },
                                title: Text(a.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text('عملة: ${a.currency}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showShippingCompanySearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: shippingCompanySearchCtrl,
                      hint: 'ابحث عن شركة شحن...',
                      onChanged: (v) async {
                        shippingCompanyResults =
                            await searchShippingCompanies(v);
                        setSheetState(() {});
                      },
                      results: shippingCompanyResults
                          .map((s) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    counterpartyId = s.id;
                                    counterpartyName = s.name;
                                    shippingCompanySearchCtrl.text = s.name;
                                    shippingCompanyResults = [];
                                    if (s.currency.isNotEmpty) {
                                      currency = s.currency;
                                      currencyLocked = true;
                                    }
                                  });
                                },
                                title: Text(s.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text('عملة: ${s.currency}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'الوصف (اختياري)',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.description_outlined,
                          color: AppTheme.success),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: isSaving,
                    builder: (_, saving, __) => SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (saving ||
                                matchingAccounts.isEmpty ||
                                !isEntityValid)
                            ? null
                            : () async {
                                final amount =
                                    double.tryParse(amountCtrl.text.trim()) ??
                                        0;
                                if (amount <= 0) return;
                                isSaving.value = true;
                                final targetAccount =
                                    selectedAccount ?? matchingAccounts.first;
                                final desc = descCtrl.text.trim().isNotEmpty
                                    ? descCtrl.text.trim()
                                    : counterpartyType != null
                                        ? 'إيداع بنكي - ${counterpartyName ?? ''}'
                                        : 'رصيد افتتاحي';
                                try {
                                    // Build entity fields for counterparty
                                    String? eType;
                                    String? eId;
                                    if (counterpartyType == 'customer' && counterpartyId != null) {
                                      eType = 'customer';
                                      eId = counterpartyId.toString();
                                    } else if (counterpartyType == 'supplier' && supplierId != null) {
                                      eType = 'supplier';
                                      eId = supplierId;
                                    } else if (counterpartyType == 'shareholder' && shareholderId != null) {
                                      eType = 'shareholder';
                                      eId = shareholderId;
                                    } else if (counterpartyType == 'clearing_agent' && counterpartyId != null) {
                                      eType = 'clearing_agent';
                                      eId = counterpartyId.toString();
                                    } else if (counterpartyType == 'shipping_company' && counterpartyId != null) {
                                      eType = 'shipping_company';
                                      eId = counterpartyId.toString();
                                    }

                                    if (draftTx != null) {
                                      await context
                                          .read<BankAccountsCubit>()
                                          .updateDraft(
                                            transactionId: draftTx.id,
                                            bankAccountId: targetAccount.id,
                                            type: 'deposit',
                                            amount: amount,
                                            description: desc,
                                            entityType: eType,
                                            entityId: eId,
                                            counterpartyName: counterpartyName,
                                            payload: {
                                              'counterparty_type': counterpartyType,
                                              if (selectedRevenueAccountId != null)
                                                'revenue_account_id': selectedRevenueAccountId,
                                              'source_type': counterpartyType ?? (selectedRevenueAccountId != null ? 'revenue' : 'opening_balance'),
                                            },
                                          );
                                    } else {
                                      await context
                                          .read<BankAccountsCubit>()
                                          .saveDraft(
                                            bankAccountId: targetAccount.id,
                                            type: 'deposit',
                                            amount: amount,
                                            description: desc,
                                            entityType: eType,
                                            entityId: eId,
                                            counterpartyName: counterpartyName,
                                            payload: {
                                              'counterparty_type': counterpartyType,
                                              if (selectedRevenueAccountId != null)
                                                'revenue_account_id': selectedRevenueAccountId,
                                              'source_type': counterpartyType ?? (selectedRevenueAccountId != null ? 'revenue' : 'opening_balance'),
                                            },
                                          );
                                    }
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(draftTx != null ? 'تم تحديث المسودة بنجاح' : 'تم حفظ المسودة بنجاح',
                                            style: const TextStyle(fontFamily: 'Cairo')),
                                        backgroundColor: AppTheme.success,
                                      ),
                                    );
                                    Navigator.of(ctx).pop();
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '$e',
                                                style: const TextStyle(
                                                    fontFamily: 'Cairo')),
                                            backgroundColor: AppTheme.danger));
                                  }
                                }
                                isSaving.value = false;
                              },
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('حفظ كمسودة',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  // ── Bottom Sheet: Create Unified Withdraw ──
  void _showMultiInvoicePaymentDialog(BankAccountsLoaded state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const MultiInvoicePaymentDialog(
        initialSourceType: 'bank',
      ),
    ).then((success) {
      if (success == true) {
        context.read<BankAccountsCubit>().loadAll();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل السداد بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
        );
      }
    });
  }

  Future<void> _showUnifiedWithdrawSheet(BankAccountsLoaded state,
      {BankAccountTransactionModel? draftTx}) async {
    final expenseAccounts =
        await ChartOfAccountsCacheService().getExpenseAccounts();
    final amountCtrl = TextEditingController(
        text: draftTx != null ? draftTx.amount.toString() : '');
    final descCtrl = TextEditingController(text: draftTx?.description ?? '');
    final isSaving = ValueNotifier(false);
    final initialBankAcc = draftTx != null
        ? state.accounts.firstWhere((a) => a.id == draftTx.bankAccountId,
            orElse: () => state.accounts.first)
        : null;
    String currency = initialBankAcc?.currency ?? 'EGP';
    bool currencyLocked = draftTx != null;
    int? selectedExpenseAccountId = draftTx?.payload['expense_account_id'] != null
        ? int.tryParse('${draftTx!.payload['expense_account_id']}')
        : null;
    String? counterpartyType = draftTx?.relatedPartyType ?? draftTx?.payload['counterparty_type'];
    int? counterpartyId = (counterpartyType == 'customer' ||
                counterpartyType == 'clearing_agent' ||
                counterpartyType == 'shipping_company') &&
            draftTx?.relatedPartyId != null
        ? int.tryParse(draftTx!.relatedPartyId!)
        : null;
    String? supplierId =
        counterpartyType == 'supplier' ? draftTx?.relatedPartyId : null;
    String? shareholderId =
        counterpartyType == 'shareholder' ? draftTx?.relatedPartyId : null;
    String? counterpartyName = draftTx?.relatedPartyName;
    bool showCustomerSearch = false;
    bool showSupplierSearch = false;
    bool showClearingAgentSearch = false;
    bool showShippingCompanySearch = false;
    bool showShareholderSearch = false;
    bool showExpenseSearch = false;
    List<Map<String, dynamic>> expenseResults = [];
    final expenseSearchCtrl = TextEditingController();
    List<CustomerModel> customerResults = [];
    List<SupplierModel> supplierResults = [];
    List<ClearingAgentModel> clearingAgentResults = [];
    List<ShippingCompanyModel> shippingCompanyResults = [];
    List<ShareholderModel> shareholderResults = [];
    final customerSearchCtrl = TextEditingController();
    final supplierSearchCtrl = TextEditingController();
    final clearingAgentSearchCtrl = TextEditingController();
    final shippingCompanySearchCtrl = TextEditingController();
    final shareholderSearchCtrl = TextEditingController();

    Future<List<CustomerModel>> searchCustomers(String q) async {
      if (q.trim().isEmpty) return [];
      return await CustomerDao().search(q.trim(), limit: 20);
    }

    Future<List<SupplierModel>> searchSuppliers(String q) async {
      if (q.trim().isEmpty) return [];
      return await SupplierDao().search(q.trim(), limit: 20);
    }

    Future<List<ClearingAgentModel>> searchClearingAgents(String q) async {
      if (q.trim().isEmpty) return [];
      return await ClearingAgentDao().search(q.trim(), limit: 20);
    }

    Future<List<ShippingCompanyModel>> searchShippingCompanies(String q) async {
      if (q.trim().isEmpty) return [];
      return await ShippingCompanyDao().search(q.trim(), limit: 20);
    }

    Future<List<ShareholderModel>> searchShareholders(String q) async {
      if (q.trim().isEmpty) return [];
      return await ShareholderDao().search(q.trim(), limit: 20);
    }

    void searchExpenses(String q) {
      if (q.trim().isEmpty) {
        expenseResults = [];
      } else {
        expenseResults = expenseAccounts.where((a) {
          final m = AccountModel.fromMap(a);
          return m.displayName.toLowerCase().contains(q.toLowerCase()) || m.code.contains(q);
        }).toList();
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool isEntitySelected = false;
          if (counterpartyType != null) {
            switch (counterpartyType) {
              case 'supplier': isEntitySelected = supplierId != null; break;
              case 'customer': isEntitySelected = counterpartyId != null; break;
              case 'shareholder': isEntitySelected = shareholderId != null; break;
              case 'clearing_agent': isEntitySelected = counterpartyId != null; break;
              case 'shipping_company': isEntitySelected = counterpartyId != null; break;
              case 'expense': isEntitySelected = selectedExpenseAccountId != null; break;
            }
          }

          final matchingAccounts =
              state.accounts.where((a) => a.currency == currency).toList();
          final selectedAccount =
              matchingAccounts.length == 1 ? matchingAccounts.first : null;

          Widget buildSmallBtn(String label, bool active, VoidCallback onTap) {
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.danger.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: active ? AppTheme.danger : AppTheme.glassBorder),
                ),
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          color:
                              active ? AppTheme.danger : AppTheme.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11)),
                ),
              ),
            );
          }

          Widget buildSearchField({
            required TextEditingController ctrl,
            required String hint,
            required ValueChanged<String> onChanged,
            required List<Widget> results,
          }) {
            return Column(children: [
              TextField(
                controller: ctrl,
                onChanged: onChanged,
                style:
                    const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              if (results.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: Column(children: results),
                ),
            ]);
          }

          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0A1630),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صرف من حساب بنكي',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: amountCtrl,
                        onChanged: (_) => setSheetState(() {}),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d*')),
                        ],
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          prefixIcon: const Icon(Icons.attach_money,
                              color: AppTheme.danger),
                          suffixText: currency,
                          suffixStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppTheme.danger),
                          filled: true,
                          fillColor: AppTheme.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        value: currency,
                        dropdownColor: const Color(0xCC05192D),
                        items: ['EGP', 'USD', 'EUR', 'GBP']
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style:
                                          const TextStyle(fontFamily: 'Cairo')),
                                ))
                            .toList(),
                        onChanged: currencyLocked
                            ? null
                            : (v) => setSheetState(() => currency = v ?? 'EGP'),
                        style: const TextStyle(
                            fontFamily: 'Cairo', color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ]),
                  if (selectedAccount != null) ...[
                    const SizedBox(height: 8),
                    Text('الحساب: ${selectedAccount.name}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.danger,
                            fontFamily: 'Cairo')),
                  ],
                  if (matchingAccounts.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text('لا يوجد حساب بهذه العملة',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.danger,
                            fontFamily: 'Cairo')),
                  ],
                  const SizedBox(height: 12),
                  const Text('الجهة (إلزامي)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  Row(children: [
                    // Expanded(
                    //     child: buildSmallBtn(
                    //         'مورد', counterpartyType == 'supplier', () {
                    //   setSheetState(() {
                    //     counterpartyType = 'supplier';
                    //     showSupplierSearch = true;
                    //     showShareholderSearch = false;
                    //     showCustomerSearch = false;
                    //     showClearingAgentSearch = false;
                    //     showShippingCompanySearch = false;
                    //     showExpenseSearch = false;
                    //     counterpartyId = null;
                    //     counterpartyName = null;
                    //     supplierId = null;
                    //     supplierSearchCtrl.clear();
                    //     supplierResults = [];
                    //     currencyLocked = false;
                    //   });
                    // })),
                    // const SizedBox(width: 8),
                    Expanded(
                        child: buildSmallBtn(
                            'مساهم', counterpartyType == 'shareholder', () {
                      setSheetState(() {
                        counterpartyType = 'shareholder';
                        showShareholderSearch = true;
                        showSupplierSearch = false;
                        showCustomerSearch = false;
                        showClearingAgentSearch = false;
                        showShippingCompanySearch = false;
                        showExpenseSearch = false;
                        counterpartyId = null;
                        counterpartyName = null;
                        shareholderId = null;
                        shareholderSearchCtrl.clear();
                        shareholderResults = [];
                        currencyLocked = false;
                      });
                    })),
                    const SizedBox(width: 8),
                    // Expanded(
                    //     child: buildSmallBtn(
                    //         'مخلص', counterpartyType == 'clearing_agent', () {
                    //   setSheetState(() {
                    //     counterpartyType = 'clearing_agent';
                    //     showClearingAgentSearch = true;
                    //     showSupplierSearch = false;
                    //     showCustomerSearch = false;
                    //     showShippingCompanySearch = false;
                    //     showShareholderSearch = false;
                    //     showExpenseSearch = false;
                    //     counterpartyId = null;
                    //     counterpartyName = null;
                    //     clearingAgentSearchCtrl.clear();
                    //     clearingAgentResults = [];
                    //     currencyLocked = false;
                    //   });
                    // })),
                    // const SizedBox(width: 8),
                    // Expanded(
                    //     child: buildSmallBtn(
                    //         'شحن', counterpartyType == 'shipping_company', () {
                    //   setSheetState(() {
                    //     counterpartyType = 'shipping_company';
                    //     showShippingCompanySearch = true;
                    //     showSupplierSearch = false;
                    //     showShareholderSearch = false;
                    //     showCustomerSearch = false;
                    //     showClearingAgentSearch = false;
                    //     showExpenseSearch = false;
                    //     counterpartyId = null;
                    //     counterpartyName = null;
                    //     shippingCompanySearchCtrl.clear();
                    //     shippingCompanyResults = [];
                    //     currencyLocked = false;
                    //   });
                    // })),
                    // const SizedBox(width: 8),
                    Expanded(
                        child: buildSmallBtn(
                            'مصروف', counterpartyType == 'expense', () {
                      setSheetState(() {
                        counterpartyType = 'expense';
                        showExpenseSearch = true;
                        showSupplierSearch = false;
                        showShippingCompanySearch = false;
                        showShareholderSearch = false;
                        showCustomerSearch = false;
                        showClearingAgentSearch = false;
                        counterpartyId = null;
                        counterpartyName = null;
                        expenseSearchCtrl.clear();
                        expenseResults = [];
                        currency = 'EGP';
                        currencyLocked = false;
                      });
                    })),
                  ]),
                  if (showSupplierSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: supplierSearchCtrl,
                      hint: 'ابحث عن مورد...',
                      onChanged: (v) async {
                        supplierResults = await searchSuppliers(v);
                        setSheetState(() {});
                      },
                      results: supplierResults
                          .map((s) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    supplierId = s.id;
                                    counterpartyName = s.name;
                                    supplierSearchCtrl.text = s.name;
                                    supplierResults = [];
                                    if (s.currency.isNotEmpty) {
                                      currency = s.currency;
                                      currencyLocked = true;
                                    } else {
                                      currencyLocked = false;
                                    }
                                  });
                                },
                                title: Text(s.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text(
                                    'عملة: ${s.currency} — رصيد: ${AppUtils.formatNumber(s.outstandingBalance)}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showShareholderSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: shareholderSearchCtrl,
                      hint: 'ابحث عن مساهم...',
                      onChanged: (v) async {
                        shareholderResults = await searchShareholders(v);
                        setSheetState(() {});
                      },
                      results: shareholderResults
                          .map((s) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    shareholderId = s.id?.toString();
                                    counterpartyName = s.name;
                                    shareholderSearchCtrl.text = s.name;
                                    shareholderResults = [];
                                    currencyLocked = false;
                                  });
                                },
                                title: Text(s.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (s.totalDepositsEgp -
                                            s.totalWithdrawalsEgp !=
                                        0)
                                      Text(
                                          'جنية: ${AppUtils.formatCurrency(s.totalDepositsEgp - s.totalWithdrawalsEgp)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsUsd -
                                            s.totalWithdrawalsUsd !=
                                        0)
                                      Text(
                                          'دولار: ${AppUtils.formatCurrency(s.totalDepositsUsd - s.totalWithdrawalsUsd)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsEur -
                                            s.totalWithdrawalsEur !=
                                        0)
                                      Text(
                                          'يورو: ${AppUtils.formatCurrency(s.totalDepositsEur - s.totalWithdrawalsEur)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsGbp -
                                            s.totalWithdrawalsGbp !=
                                        0)
                                      Text(
                                          'استرليني: ${AppUtils.formatCurrency(s.totalDepositsGbp - s.totalWithdrawalsGbp)}',
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.success)),
                                    if (s.totalDepositsEgp -
                                                s.totalWithdrawalsEgp ==
                                            0 &&
                                        s.totalDepositsUsd -
                                                s.totalWithdrawalsUsd ==
                                            0 &&
                                        s.totalDepositsEur -
                                                s.totalWithdrawalsEur ==
                                            0 &&
                                        s.totalDepositsGbp -
                                                s.totalWithdrawalsGbp ==
                                            0)
                                      const Text('رصيد: 0',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppTheme.textSecondary)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showCustomerSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: customerSearchCtrl,
                      hint: 'ابحث عن عميل...',
                      onChanged: (v) async {
                        customerResults = await searchCustomers(v);
                        setSheetState(() {});
                      },
                      results: customerResults
                          .map((c) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    counterpartyId = int.tryParse(c.id ?? '');
                                    counterpartyName = c.name;
                                    customerSearchCtrl.text = c.name;
                                    customerResults = [];
                                    if (c.currency.isNotEmpty) {
                                      currency = c.currency;
                                      currencyLocked = true;
                                    }
                                  });
                                },
                                title: Text(c.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text(
                                    'عملة: ${c.currency} — رصيد: ${AppUtils.formatNumber(c.balance)}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showClearingAgentSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: clearingAgentSearchCtrl,
                      hint: 'ابحث عن مخلص...',
                      onChanged: (v) async {
                        clearingAgentResults = await searchClearingAgents(v);
                        setSheetState(() {});
                      },
                      results: clearingAgentResults
                          .map((a) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    counterpartyId = int.tryParse(a.id ?? '');
                                    counterpartyName = a.name;
                                    clearingAgentSearchCtrl.text = a.name;
                                    clearingAgentResults = [];
                                    if (a.currency.isNotEmpty) {
                                      currency = a.currency;
                                      currencyLocked = true;
                                    }
                                  });
                                },
                                title: Text(a.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text('عملة: ${a.currency}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showShippingCompanySearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: shippingCompanySearchCtrl,
                      hint: 'ابحث عن شركة شحن...',
                      onChanged: (v) async {
                        shippingCompanyResults =
                            await searchShippingCompanies(v);
                        setSheetState(() {});
                      },
                      results: shippingCompanyResults
                          .map((s) => ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    counterpartyId = s.id;
                                    counterpartyName = s.name;
                                    shippingCompanySearchCtrl.text = s.name;
                                    shippingCompanyResults = [];
                                    if (s.currency.isNotEmpty) {
                                      currency = s.currency;
                                      currencyLocked = true;
                                    }
                                  });
                                },
                                title: Text(s.name,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                                subtitle: Text('عملة: ${s.currency}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showExpenseSearch) ...[
                    const SizedBox(height: 8),
                    buildSearchField(
                      ctrl: expenseSearchCtrl,
                      hint: 'ابحث عن حساب مصروف...',
                      onChanged: (v) {
                        searchExpenses(v);
                        setSheetState(() {});
                      },
                      results: expenseResults
                          .map((a) {
                            final m = AccountModel.fromMap(a);
                            return ListTile(
                                dense: true,
                                onTap: () {
                                  setSheetState(() {
                                    selectedExpenseAccountId = int.tryParse(a['id'].toString());
                                    counterpartyName = '${m.displayName} - ${m.code}';
                                    expenseSearchCtrl.text = counterpartyName!;
                                    expenseResults = [];
                                    currencyLocked = false;
                                  });
                                },
                                title: Text('${m.displayName} - ${m.code}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.white)),
                              );
                          })
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'الوصف (اختياري)',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.description_outlined,
                          color: AppTheme.danger),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: isSaving,
                    builder: (_, saving, __) {
                      final currentAmount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final availableBalance = matchingAccounts.isNotEmpty
                          ? matchingAccounts.first.balance
                          : 0.0;
                      final isOverBalance = currentAmount > availableBalance;

                      return Column(
                        children: [
                          if (isOverBalance)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.danger),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: AppTheme.danger, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'المبلغ المطلوب أكبر من المتوفر في الحساب',
                                      style: TextStyle(
                                          color: AppTheme.danger,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.danger,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: (saving ||
                                      matchingAccounts.isEmpty ||
                                      !isEntitySelected ||
                                      isOverBalance)
                                  ? null
                                  : () async {
                                      final amount = double.tryParse(
                                              amountCtrl.text.trim()) ??
                                          0;
                                      if (amount <= 0) return;
                                      isSaving.value = true;
                                      final targetAccount =
                                          selectedAccount ?? matchingAccounts.first;
                                      final desc = descCtrl.text.trim().isNotEmpty
                                          ? descCtrl.text.trim()
                                          : counterpartyType != null
                                              ? 'تحويل بنكي إلى ${counterpartyName ?? ''}'
                                              : '';
                                      try {
                                        if (counterpartyType != null) {
                                          if (counterpartyType == 'shareholder' &&
                                              shareholderId == null) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx).showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'يُرجى اختيار المساهم',
                                                          style: TextStyle(
                                                              fontFamily: 'Cairo')),
                                                      backgroundColor:
                                                          AppTheme.danger));
                                            }
                                            isSaving.value = false;
                                            return;
                                          }
                                          if (counterpartyType == 'expense' &&
                                              selectedExpenseAccountId == null) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx).showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'يُرجى اختيار حساب المصروف',
                                                          style: TextStyle(
                                                              fontFamily: 'Cairo')),
                                                      backgroundColor:
                                                          AppTheme.danger));
                                            }
                                            isSaving.value = false;
                                            return;
                                          }
                                        }

                                        String? eType;
                                        String? eId;
                                        if (counterpartyType == 'supplier' && supplierId != null) {
                                          eType = 'supplier';
                                          eId = supplierId;
                                        } else if (counterpartyType == 'customer' && counterpartyId != null) {
                                          eType = 'customer';
                                          eId = counterpartyId.toString();
                                        } else if (counterpartyType == 'shareholder' && shareholderId != null) {
                                          eType = 'shareholder';
                                          eId = shareholderId;
                                        } else if (counterpartyType == 'clearing_agent' && counterpartyId != null) {
                                          eType = 'clearing_agent';
                                          eId = counterpartyId.toString();
                                        } else if (counterpartyType == 'shipping_company' && counterpartyId != null) {
                                          eType = 'shipping_company';
                                          eId = counterpartyId.toString();
                                        }

                                        if (draftTx != null) {
                                          await context
                                              .read<BankAccountsCubit>()
                                              .updateDraft(
                                                transactionId: draftTx.id,
                                                bankAccountId: targetAccount.id,
                                                type: 'withdraw',
                                                amount: amount,
                                                description: desc,
                                                entityType: eType,
                                                entityId: eId,
                                                counterpartyName: counterpartyName,
                                                payload: {
                                                  'counterparty_type': counterpartyType,
                                                  if (selectedExpenseAccountId != null)
                                                    'expense_account_id': selectedExpenseAccountId,
                                                },
                                              );
                                        } else {
                                          await context
                                              .read<BankAccountsCubit>()
                                              .saveDraft(
                                                bankAccountId: targetAccount.id,
                                                type: 'withdraw',
                                                amount: amount,
                                                description: desc,
                                                entityType: eType,
                                                entityId: eId,
                                                counterpartyName: counterpartyName,
                                                payload: {
                                                  'counterparty_type': counterpartyType,
                                                  if (selectedExpenseAccountId != null)
                                                    'expense_account_id': selectedExpenseAccountId,
                                                },
                                              );
                                        }
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(
                                              content: Text(draftTx != null ? 'تم تحديث المسودة بنجاح' : 'تم حفظ المسودة بنجاح',
                                                  style: const TextStyle(fontFamily: 'Cairo')),
                                              backgroundColor: AppTheme.success,
                                            ),
                                          );
                                          Navigator.of(ctx).pop();
                                        }
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      '$e',
                                                      style: const TextStyle(
                                                          fontFamily: 'Cairo')),
                                                  backgroundColor: AppTheme.danger));
                                        }
                                      }
                                      isSaving.value = false;
                                    },
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : Text(draftTx != null ? 'تحديث المسودة' : 'حفظ كمسودة',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                          ],
                        );
                      },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCurrencyExchangeSheet(BankAccountsLoaded state,
      {BankAccountTransactionModel? draftTx}) {
    int? fromAccountId = draftTx?.bankAccountId ??
        (draftTx?.payload['from_account_id'] != null
            ? int.tryParse('${draftTx!.payload['from_account_id']}')
            : null);
    int? toAccountId = draftTx?.payload['to_account_id'] != null
        ? int.tryParse('${draftTx!.payload['to_account_id']}')
        : null;
    final amountCtrl = TextEditingController(
        text: draftTx != null
            ? (draftTx.payload['amount_from']?.toString() ??
                draftTx.amount.toString())
            : '');
    final rateCtrl = TextEditingController(
        text: draftTx?.payload['exchange_rate']?.toString() ?? '');
    double? systemRate;
    final isSaving = ValueNotifier(false);

    InputDecoration inputDecor(String hint, IconData icon) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo'),
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final fromOptions = state.accounts.where((a) {
            if (toAccountId == null) return true;
            final toAcc =
                state.accounts.firstWhere((acc) => acc.id == toAccountId);
            if (a.id == toAccountId || a.currency == toAcc.currency) return false;
            if (toAcc.currency != 'EGP') return a.currency == 'EGP';
            return true;
          }).toList();

          final toOptions = state.accounts.where((a) {
            if (fromAccountId == null) return true;
            final fromAcc =
                state.accounts.firstWhere((acc) => acc.id == fromAccountId);
            if (a.id == fromAccountId || a.currency == fromAcc.currency) return false;
            if (fromAcc.currency != 'EGP') return a.currency == 'EGP';
            return true;
          }).toList();

          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0A1630),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تحويل عملة',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: fromAccountId,
                          decoration:
                              inputDecor('من حساب', Icons.account_balance),
                          dropdownColor: AppTheme.surface,
                          items: fromOptions
                              .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'Cairo'))))
                              .toList(),
                          onChanged: (v) async {
                            setSheetState(() => fromAccountId = v);
                            if (fromAccountId != null) {
                              final fromAcc = state.accounts.firstWhere((a) => a.id == fromAccountId);
                              final toAcc = toAccountId != null ? state.accounts.firstWhere((a) => a.id == toAccountId) : null;
                              final foreignCur = fromAcc.currency != 'EGP' ? fromAcc.currency : toAcc?.currency;
                              if (foreignCur != null && foreignCur != 'EGP') {
                                final r = await ExchangeRateDao().getRate(foreignCur);
                                setSheetState(() {
                                  systemRate = r;
                                  rateCtrl.text = r.toStringAsFixed(4);
                                });
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: toAccountId,
                          decoration:
                              inputDecor('إلى حساب', Icons.account_balance),
                          dropdownColor: AppTheme.surface,
                          items: toOptions
                              .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'Cairo'))))
                              .toList(),
                          onChanged: (v) async {
                            setSheetState(() => toAccountId = v);
                            if (toAccountId != null) {
                              final toAcc = state.accounts.firstWhere((a) => a.id == toAccountId);
                              final fromAcc = fromAccountId != null ? state.accounts.firstWhere((a) => a.id == fromAccountId) : null;
                              final foreignCur = toAcc.currency != 'EGP' ? toAcc.currency : fromAcc?.currency;
                              if (foreignCur != null && foreignCur != 'EGP') {
                                final r = await ExchangeRateDao().getRate(foreignCur);
                                setSheetState(() {
                                  systemRate = r;
                                  rateCtrl.text = r.toStringAsFixed(4);
                                });
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) => setSheetState(() {}),
                    decoration: inputDecor(
                        'المبلغ (من الحساب الأول)', Icons.attach_money),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: rateCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) => setSheetState(() {}),
                    decoration: inputDecor(
                        'سعر الصرف (مقابل الجنيه المصري)', Icons.trending_up),
                  ),
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final enteredAmount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    final enteredRate = double.tryParse(rateCtrl.text.trim()) ?? 0;
                    if (enteredAmount <= 0 || enteredRate <= 0 || fromAccountId == null || toAccountId == null) {
                      return const SizedBox.shrink();
                    }

                    final fromAcc = state.accounts.where((a) => a.id == fromAccountId).firstOrNull;
                    final toAcc = state.accounts.where((a) => a.id == toAccountId).firstOrNull;
                    if (fromAcc == null || toAcc == null) return const SizedBox.shrink();

                    double expectedReceived = 0;
                    double expectedGainLoss = 0;
                    double bookRate = 1.0;

                    if (fromAcc.currency == 'EGP') {
                      bookRate = 1.0;
                      expectedReceived = enteredAmount / enteredRate;
                    } else {
                      if (fromAcc.balance > 0 && fromAcc.costBase > 0) {
                        bookRate = fromAcc.costBase / fromAcc.balance;
                      } else if (fromAcc.bookRate > 1.0) {
                        bookRate = fromAcc.bookRate;
                      } else if (systemRate != null && systemRate! > 1.0) {
                        bookRate = systemRate!;
                      } else {
                        bookRate = fromAcc.currency == 'USD'
                            ? 50.0
                            : (fromAcc.currency == 'EUR'
                                ? 54.0
                                : (fromAcc.currency == 'GBP' ? 63.0 : 50.0));
                      }
                      expectedReceived = enteredAmount * enteredRate;
                      final costBaseReleased = enteredAmount * bookRate;
                      expectedGainLoss = expectedReceived - costBaseReleased;
                    }

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المبلغ المتوقع استلامه:',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                      fontFamily: 'Cairo')),
                              Text(
                                '${expectedReceived.toStringAsFixed(2)} ${toAcc.currency}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                          if (fromAcc.currency != 'EGP') ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('التكلفة الدفترية المرجحة:',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                        fontFamily: 'Cairo')),
                                Text(
                                  '${(enteredAmount * bookRate).toStringAsFixed(2)} ج.م (بسعر ${bookRate.toStringAsFixed(4)})',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('فروق العملة المحققة المتوقعة:',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                        fontFamily: 'Cairo')),
                                Text(
                                  expectedGainLoss > 0.001
                                      ? '+${expectedGainLoss.toStringAsFixed(2)} ج.م (ربح)'
                                      : expectedGainLoss < -0.001
                                          ? '${expectedGainLoss.toStringAsFixed(2)} ج.م (خسارة)'
                                          : '0.00 ج.م (تعادل)',
                                  style: TextStyle(
                                      color: expectedGainLoss > 0.001
                                          ? Colors.greenAccent
                                          : expectedGainLoss < -0.001
                                              ? Colors.redAccent
                                              : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<bool>(
                    valueListenable: isSaving,
                    builder: (_, saving, __) {
                      final fromAcc = fromAccountId != null
                          ? state.accounts.where((a) => a.id == fromAccountId).firstOrNull
                          : null;
                      final availableBalance = fromAcc?.balance ?? 0.0;
                      final enteredAmount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final isOverBalance = enteredAmount > availableBalance;
                      final enteredRate = double.tryParse(rateCtrl.text.trim()) ?? 0;
                      final isFormValid = fromAccountId != null &&
                          toAccountId != null &&
                          fromAccountId != toAccountId &&
                          enteredAmount > 0 &&
                          !isOverBalance &&
                          enteredRate > 0;

                      return Column(
                        children: [
                          if (isOverBalance && enteredAmount > 0)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.danger),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppTheme.danger, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'المبلغ المطلوب تحويله ($enteredAmount) أكبر من الرصيد المتوفر في الحساب ($availableBalance ${fromAcc?.currency ?? ''})',
                                      style: const TextStyle(
                                          color: AppTheme.danger,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: (saving || !isFormValid)
                                  ? null
                                  : () async {
                                void showSnack(String msg) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(msg,
                                        style: const TextStyle(
                                            fontFamily: 'Cairo')),
                                    backgroundColor: AppTheme.danger,
                                  ));
                                }

                                if (fromAccountId == null ||
                                    toAccountId == null ||
                                    amountCtrl.text.trim().isEmpty ||
                                    rateCtrl.text.trim().isEmpty) {
                                  showSnack('الرجاء إدخال جميع الحقول');
                                  return;
                                }

                                final amountFrom =
                                    double.tryParse(amountCtrl.text.trim()) ??
                                        0;
                                final rate =
                                    double.tryParse(rateCtrl.text.trim()) ?? 0;

                                if (amountFrom <= 0 || rate <= 0) {
                                  showSnack(
                                      'المبالغ وسعر الصرف يجب أن تكون أكبر من صفر');
                                  return;
                                }

                                final fromAcc = state.accounts
                                    .firstWhere((a) => a.id == fromAccountId);
                                final toAcc = state.accounts
                                    .firstWhere((a) => a.id == toAccountId);

                                if (fromAcc.currency != 'EGP' &&
                                    toAcc.currency != 'EGP') {
                                  showSnack(
                                      'يجب أن يكون التحويل من أو إلى حساب بالجنيه المصري');
                                  return;
                                }

                                double amountTo = 0;
                                if (fromAcc.currency == 'EGP') {
                                  amountTo = amountFrom / rate;
                                } else {
                                  amountTo = amountFrom * rate;
                                }

                                isSaving.value = true;
                                try {
                                  if (draftTx != null) {
                                    await context
                                        .read<BankAccountsCubit>()
                                        .updateDraft(
                                          transactionId: draftTx.id,
                                          bankAccountId: fromAccountId,
                                          type: 'currency_exchange_out',
                                          amount: amountFrom,
                                          description:
                                              'تحويل عملة من ${fromAcc.name} إلى ${toAcc.name}',
                                          payload: {
                                            'from_account_id': fromAccountId,
                                            'to_account_id': toAccountId,
                                            'amount_from': amountFrom,
                                            'amount_to': amountTo,
                                            'exchange_rate': rate,
                                          },
                                        );
                                  } else {
                                    await context
                                        .read<BankAccountsCubit>()
                                        .saveDraft(
                                          bankAccountId: fromAccountId!,
                                          type: 'currency_exchange_out',
                                          amount: amountFrom,
                                          description:
                                              'تحويل عملة من ${fromAcc.name} إلى ${toAcc.name}',
                                          payload: {
                                            'from_account_id': fromAccountId,
                                            'to_account_id': toAccountId,
                                            'amount_from': amountFrom,
                                            'amount_to': amountTo,
                                            'exchange_rate': rate,
                                          },
                                        );
                                  }
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            draftTx != null
                                                ? 'تم تحديث المسودة بنجاح'
                                                : 'تم حفظ المسودة بنجاح',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo')),
                                        backgroundColor: AppTheme.success,
                                      ),
                                    );
                                    Navigator.of(ctx).pop();
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text('$e',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo')),
                                        backgroundColor: AppTheme.danger,
                                      ),
                                    );
                                  }
                                }
                                isSaving.value = false;
                              },
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                draftTx != null
                                    ? 'تحديث المسودة'
                                    : 'حفظ كمسودة',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  },
),
    );
  }

  Future<void> _exportPdf(BankAccountsLoaded state) async {
    final account = state.accounts.firstWhere(
        (a) => a.id == state.selectedAccountId,
        orElse: () => state.accounts.first);
    final filteredList = state.filteredTransactions;
    if (filteredList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا توجد حركات للتصدير',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.warning),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف PDF...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      await BankAccountExportService.exportPdf(
        account: account,
        transactions: filteredList,
        startDate: state.startDate,
        endDate: state.endDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'تم تصدير ${filteredList.length} حركة إلى PDF بنجاح',
                  style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في التصدير: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _exportExcel(BankAccountsLoaded state) async {
    final account = state.accounts.firstWhere(
        (a) => a.id == state.selectedAccountId,
        orElse: () => state.accounts.first);
    final filteredList = state.filteredTransactions;
    if (filteredList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا توجد حركات للتصدير',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.warning),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف Excel...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      await BankAccountExportService.exportExcel(
        account: account,
        transactions: filteredList,
        startDate: state.startDate,
        endDate: state.endDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'تم تصدير ${filteredList.length} حركة إلى Excel بنجاح',
                  style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في التصدير: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}
