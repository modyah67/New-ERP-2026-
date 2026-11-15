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
import '../../core/widgets/password_verification_dialog.dart';
import 'widgets/edit_confirmed_bank_transaction_dialog.dart';
import '../../core/widgets/beneficiary_selector_field.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                Text('الحسابات البنكية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                colors: isDark
                    ? [
                        cardColor.withValues(alpha: isSelected ? 0.25 : 0.15),
                        cardColor.withValues(alpha: isSelected ? 0.10 : 0.05),
                      ]
                    : [
                        cardColor.withValues(alpha: isSelected ? 0.18 : 0.08),
                        Colors.white,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: cardColor.withValues(alpha: isSelected ? 0.2 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? cardColor.withValues(alpha: isDark ? 0.6 : 0.9)
                    : cardColor.withValues(alpha: isDark ? 0.3 : 0.35),
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
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                  fontWeight: FontWeight.w600,
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
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
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
                label: state.startDate != null && state.endDate != null
                    ? 'من: ${DateFormat('yyyy/MM/dd').format(state.startDate!)} إلى: ${DateFormat('yyyy/MM/dd').format(state.endDate!)}'
                    : (state.startDate != null
                        ? 'من: ${DateFormat('yyyy/MM/dd').format(state.startDate!)}'
                        : 'تصفية بالتاريخ (من - إلى)'),
                isActive: state.startDate != null || state.endDate != null,
                onTap: () => _showDateRangePicker(state),
                showClear: state.startDate != null || state.endDate != null,
                onClear: () => context
                    .read<BankAccountsCubit>()
                    .setDateFilter(null, null, clear: true),
              ),
              const SizedBox(width: 10),
              _exportBtn(
                Icons.picture_as_pdf_rounded,
                'طباعة PDF',
                () => _exportPdf(state),
                color: const Color(0xFFEF4444),
              ),
              const SizedBox(width: 8),
              _exportBtn(
                Icons.table_chart_outlined,
                'Excel',
                () => _exportExcel(state),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _searchController,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w600),
            onChanged: (val) =>
                context.read<BankAccountsCubit>().setSearchQuery(val),
            decoration: InputDecoration(
              hintText:
                  'بحث في رقم القيد، البيان، اسم الحساب، المورد أو العميل...',
              hintStyle: TextStyle(
                  color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF64748B),
                  fontSize: 11.5,
                  fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppTheme.accent, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: isDark ? Colors.white70 : Colors.black54, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        context.read<BankAccountsCubit>().setSearchQuery('');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: isDark ? AppTheme.glassBorder.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: isDark ? AppTheme.glassBorder.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFilter = state.accountFilter != null;
    return PopupMenuButton<int?>(
      initialValue: state.accountFilter,
      tooltip: 'فلتر الحساب البنكي',
      onSelected: (val) {
        context.read<BankAccountsCubit>().setAccountFilter(val);
      },
      offset: const Offset(0, 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppTheme.surface : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFilter
              ? AppTheme.primary.withValues(alpha: 0.2)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasFilter
                  ? AppTheme.primary
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance,
                size: 18, color: hasFilter ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87)),
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
                color: hasFilter ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87),
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18, color: hasFilter ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87)),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Text('جميع الحسابات',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        ),
        ...state.accounts.map((acc) => PopupMenuItem(
              value: acc.id,
              child: Text('${acc.name} (${acc.currency})',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
            )),
      ],
    );
  }

  Widget _currencyFilterDropdown(BankAccountsLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      color: isDark ? AppTheme.surface : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFilter
              ? AppTheme.primary.withValues(alpha: 0.2)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasFilter
                  ? AppTheme.primary
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on_outlined,
                size: 18, color: hasFilter ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(width: 6),
            Text(
              hasFilter ? state.currencyFilter! : 'العملة',
              style: TextStyle(
                fontSize: 12,
                color: hasFilter ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87),
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18, color: hasFilter ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87)),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Text('الكل',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        ),
        ...currencies.map((cur) => PopupMenuItem(
              value: cur,
              child: Text(cur,
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
            )),
      ],
    );
  }

  Future<void> _showDateRangePicker(BankAccountsLoaded state) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    surface: AppTheme.cardBg,
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
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

  Widget _exportBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultIconColor = color ?? (isDark ? Colors.white70 : Colors.black87);
    final defaultTextColor = color ?? (isDark ? Colors.white70 : Colors.black87);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color != null
              ? color.withValues(alpha: isDark ? 0.15 : 0.08)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: color != null
                  ? color.withValues(alpha: 0.5)
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: defaultIconColor),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: defaultTextColor,
                    fontFamily: 'Cairo')),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.2)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isActive
                  ? AppTheme.primary
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 18, color: isActive ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isActive ? AppTheme.primary : (isDark ? Colors.white70 : Colors.black87),
                    fontFamily: 'Cairo',
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.bold)),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
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
                      color: isDark
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : const Color(0xFFF1F5F9),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? Colors.transparent : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 1,
                            child: Text('#',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('التاريخ',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('النوع',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('المبلغ',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 2,
                            child: Text('الرصيد',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        Expanded(
                            flex: 3,
                            child: Text('البيان / الجهة',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo'))),
                        const SizedBox(width: 60),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final typeLabel = tx.isDeposit
        ? 'إيداع'
        : (tx.type.contains('exchange') ? 'تحويل عملة' : 'صرف');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تأكيد وترحيل الحركة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black)),
        content: Text(
          'هل أنت متأكد من تأكيد وترحيل حركة "$typeLabel" بمبلغ ${AppUtils.formatNumber(tx.amount)} وتحديث الأرصدة والقيود المحاسبية؟',
          style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? AppTheme.textSecondary : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B))),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final typeLabel = tx.isDeposit
        ? 'إيداع'
        : (tx.type.contains('exchange') ? 'تحويل عملة' : 'صرف');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف المسودة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: AppTheme.danger)),
        content: Text(
          'هل تريد حذف مسودة "$typeLabel" بمبلغ ${AppUtils.formatNumber(tx.amount)} نهائياً؟',
          style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? AppTheme.textSecondary : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B))),
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

  Future<void> _handleSecuredEditBankTransaction(
      BankAccountTransactionModel tx, BankAccountsLoaded state) async {
    final verified = await showPasswordVerificationDialog(
      context,
      title: 'تأكيد كلمة المرور لتعديل الحركة البنكية',
      subtitle:
          'يرجى إدخال كلمة المرور للمتابعة في تعديل بيانات الحركة #${tx.journalEntryId ?? tx.id}',
      expectedPassword: 'eslam2026',
    );

    if (!mounted) return;

    if (!verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'كلمة المرور غير صحيحة أو تم إلغاء العملية، تم منع فتح شاشة التعديل',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.danger,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final cubit = context.read<BankAccountsCubit>();
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider<BankAccountsCubit>.value(
        value: cubit,
        child: EditConfirmedBankTransactionDialog(
          tx: tx,
          state: state,
          cubit: cubit,
        ),
      ),
    );
  }

  Widget _buildTransactionRow(
      BankAccountTransactionModel tx, BankAccountsLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          hoverColor: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.03),
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
                        : (isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
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
                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                            fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
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
                              : (isDark ? Colors.white : Colors.black),
                          fontWeight: FontWeight.bold,
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
                                color: isDark
                                    ? (tx.isDraft ? Colors.white : AppTheme.textSecondary)
                                    : Colors.black,
                                fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                                fontSize: 11,
                                fontFamily: 'Cairo')),
                        if (unifiedTx.relatedPartyName != null &&
                            unifiedTx.relatedPartyName!.isNotEmpty)
                          Text(unifiedTx.relatedPartyName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? AppTheme.textSecondary
                                          .withValues(alpha: 0.7)
                                      : const Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo')),
                      ],
                    )),
                SizedBox(
                  width: 120,
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
                          icon: const Icon(Icons.edit_outlined,
                              size: 16, color: AppTheme.accent),
                          tooltip: 'تعديل الحركة (محمي بكلمة مرور)',
                          onPressed: () => _handleSecuredEditBankTransaction(tx, state),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          constraints: const BoxConstraints(),
                        ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.print_outlined,
                              size: 16, color: AppTheme.accent),
                          tooltip: 'طباعة السند',
                          onPressed: () =>
                              TreasuryPdfService.printVoucher(unifiedTx),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          constraints: const BoxConstraints(),
                        ),
                        if (isChequeTx)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 2.0),
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

  static const List<Map<String, dynamic>> _bankSupplierTypeOptions = [
    {
      'key': 'all',
      'label': 'جميع الأنواع',
      'icon': Icons.all_inclusive_rounded,
      'color': AppTheme.primary,
    },
    {
      'key': 'crop',
      'label': 'موردين محاصيل',
      'icon': Icons.agriculture_rounded,
      'color': Color(0xFF10B981),
    },
    {
      'key': 'transport',
      'label': 'موردين نقل',
      'icon': Icons.local_shipping_rounded,
      'color': Color(0xFF0284C7),
    },
    {
      'key': 'station',
      'label': 'موردين محطات',
      'icon': Icons.factory_rounded,
      'color': Color(0xFFF59E0B),
    },
    {
      'key': 'deduction',
      'label': 'موردين تخصيمات',
      'icon': Icons.assignment_outlined,
      'color': Color(0xFF8B5CF6),
    },
    {
      'key': 'packaging',
      'label': 'موردين تعبئة',
      'icon': Icons.inventory_2_outlined,
      'color': Color(0xFF06B6D4),
    },
    {
      'key': 'shared',
      'label': 'موردين مشتركين',
      'icon': Icons.sync_alt_rounded,
      'color': Color(0xFFEC4899),
    },
  ];

  Color _getBankSupplierTypeColor(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase();
    final c = (code ?? '').trim();
    if (t == 'crop') return const Color(0xFF10B981);
    if (t == 'transport' || c.startsWith('6')) return const Color(0xFF0284C7);
    if (t == 'station' || c.startsWith('85') || c.startsWith('86') || c.startsWith('87') || c.startsWith('88') || c.startsWith('89')) {
      return const Color(0xFFF59E0B);
    }
    if (t == 'deduction' || t == 'deductions' || c.startsWith('4')) return const Color(0xFF8B5CF6);
    if (t == 'packaging' || c.startsWith('70') || c.startsWith('71') || c.startsWith('72') || c.startsWith('73') || c.startsWith('74')) {
      return const Color(0xFF06B6D4);
    }
    if (t == 'shared' || c.startsWith('75') || c.startsWith('76') || c.startsWith('77') || c.startsWith('78') || c.startsWith('79')) {
      return const Color(0xFFEC4899);
    }
    return AppTheme.primary;
  }

  IconData _getBankSupplierTypeIcon(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase();
    final c = (code ?? '').trim();
    if (t == 'crop') return Icons.agriculture_rounded;
    if (t == 'transport' || c.startsWith('6')) return Icons.local_shipping_rounded;
    if (t == 'station' || c.startsWith('85') || c.startsWith('86') || c.startsWith('87') || c.startsWith('88') || c.startsWith('89')) {
      return Icons.factory_rounded;
    }
    if (t == 'deduction' || t == 'deductions' || c.startsWith('4')) return Icons.assignment_outlined;
    if (t == 'packaging' || c.startsWith('70') || c.startsWith('71') || c.startsWith('72') || c.startsWith('73') || c.startsWith('74')) {
      return Icons.inventory_2_outlined;
    }
    if (t == 'shared' || c.startsWith('75') || c.startsWith('76') || c.startsWith('77') || c.startsWith('78') || c.startsWith('79')) {
      return Icons.sync_alt_rounded;
    }
    return Icons.business_outlined;
  }

  String _getBankSupplierTypeLabel(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase();
    final c = (code ?? '').trim();
    if (t == 'crop') return 'مورد محصول';
    if (t == 'transport' || c.startsWith('6')) return 'مورد نقل';
    if (t == 'station' || c.startsWith('85') || c.startsWith('86') || c.startsWith('87') || c.startsWith('88') || c.startsWith('89')) {
      return 'مورد محطة';
    }
    if (t == 'deduction' || t == 'deductions' || c.startsWith('4')) return 'مورد تخصيم';
    if (t == 'packaging' || c.startsWith('70') || c.startsWith('71') || c.startsWith('72') || c.startsWith('73') || c.startsWith('74')) {
      return 'مورد تعبئة';
    }
    if (t == 'shared' || c.startsWith('75') || c.startsWith('76') || c.startsWith('77') || c.startsWith('78') || c.startsWith('79')) {
      return 'مورد مشترك';
    }
    return 'مورد';
  }

  String _formatBankSupplierBalances(SupplierModel s) {
    if (s.currentBalancesByCurrency.isNotEmpty) {
      final active = s.currentBalancesByCurrency.entries
          .where((en) => en.value.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((en) {
          final sym = SupplierModel.getCurrencySymbol(en.key);
          final dir = en.value > 0.001 ? '(له)' : '(عليه)';
          return '${AppUtils.formatNumber(en.value.abs())} $sym $dir';
        }).join('  •  ');
      }
    } else if (s.initialBalancesByCurrency.isNotEmpty) {
      final active = s.initialBalancesByCurrency.entries
          .where((en) => en.value.amount.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((en) {
          final sym = SupplierModel.getCurrencySymbol(en.key);
          return '${AppUtils.formatNumber(en.value.amount.abs())} $sym';
        }).join('  •  ');
      }
    }
    final sym = SupplierModel.getCurrencySymbol(s.currency.isNotEmpty && s.currency != 'MULTI' ? s.currency : 'EGP');
    final dir = s.outstandingBalance > 0.001 ? '(له)' : (s.outstandingBalance < -0.001 ? '(عليه)' : '');
    return '${AppUtils.formatCurrency(s.outstandingBalance.abs())} $sym $dir'.trim();
  }

  Widget _buildBankSelectedSupplierCard({
    required SupplierModel supplier,
    required String currentCurrency,
    required bool isDark,
    required VoidCallback onClear,
    required ValueChanged<String> onCurrencyTapped,
  }) {
    final isEgpOnly = supplier.isEgpOnlySupplier;
    final allCurrencies = isEgpOnly
        ? <String>['EGP']
        : (<String>{'EGP', 'USD', 'EUR', 'GBP'}..addAll(supplier.currentBalancesByCurrency.keys)).toList();

    final color = _getBankSupplierTypeColor(supplier.supplierType, supplier.supplierCode);
    final icon = _getBankSupplierTypeIcon(supplier.supplierType, supplier.supplierCode);
    final typeLabel = _getBankSupplierTypeLabel(supplier.supplierType, supplier.supplierCode);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1E3D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            supplier.name,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (supplier.supplierCode.isNotEmpty)
                      Text(
                        'كود: ${supplier.supplierCode}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onClear,
                tooltip: 'تغيير المورد',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
          ),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 13, color: isDark ? AppTheme.accent : const Color(0xFF0F766E)),
              const SizedBox(width: 5),
              Text(
                'أرصدة المورد بالعملات (انقر لتحديد العملة):',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allCurrencies.map((c) {
              final bal = supplier.currentBalancesByCurrency[c] ??
                  (supplier.currency == c ? supplier.outstandingBalance : 0.0);
              final isSelectedCurrency = currentCurrency == c;
              final sym = SupplierModel.getCurrencySymbol(c);

              final isCredit = bal > 0.001; // له
              final isDebit = bal < -0.001;  // عليه

              final statusText = isCredit ? '(له)' : (isDebit ? '(عليه)' : '(0)');
              final statusColor = isCredit
                  ? const Color(0xFF059669)
                  : (isDebit ? const Color(0xFFDC2626) : const Color(0xFF64748B));

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEgpOnly ? null : () => onCurrencyTapped(c),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelectedCurrency
                          ? (isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFE0F2FE))
                          : (isDark ? const Color(0xFF0A1630) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelectedCurrency ? const Color(0xFF0284C7) : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        width: isSelectedCurrency ? 1.6 : 1.0,
                      ),
                      boxShadow: isSelectedCurrency
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelectedCurrency) ...[
                          const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '$c: ',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: isSelectedCurrency ? FontWeight.bold : FontWeight.w600,
                            color: isSelectedCurrency ? const Color(0xFF0369A1) : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          ),
                        ),
                        Text(
                          '${AppUtils.formatNumber(bal.abs())} $sym',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: statusColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
    SupplierModel? selectedSupplierModel;
    String supplierCategory = 'all';
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
      return await CustomerDao().search(q.trim(), limit: 20, customerType: 'export');
    }

    Future<List<SupplierModel>> searchSuppliers(String q, [String category = 'all']) async {
      final trimmed = q.trim();
      final types = (category != 'all') ? [category] : null;

      if (trimmed.isEmpty) {
        if (category == 'transport') {
          return await SupplierDao().getAllSuppliers(supplierTypes: ['transport']);
        } else if (types != null) {
          return await SupplierDao().getAllSuppliers(supplierTypes: types);
        } else {
          return await SupplierDao().getAll(limit: 25);
        }
      } else {
        return await SupplierDao().search(
          trimmed,
          limit: 25,
          supplierTypes: types,
          includeTransportSuppliers: category == 'all' || category == 'transport',
        );
      }
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
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final isEgpOnlySupplier = selectedSupplierModel?.isEgpOnlySupplier ?? false;
          final depositCurrencies = isEgpOnlySupplier ? const ['EGP'] : const ['EGP', 'USD', 'EUR', 'GBP'];
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
                      : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: active
                          ? AppTheme.success
                          : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                ),
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          color: active
                              ? AppTheme.success
                              : (isDark ? AppTheme.textSecondary : Colors.black87),
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
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                      color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                      fontFamily: 'Cairo'),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                  filled: true,
                  fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
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
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A1630) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: isDark ? null : Border.all(color: const Color(0xFFCBD5E1)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إيداع في حساب بنكي',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
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
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
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
                          fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('deposit_cur_${isEgpOnlySupplier}_$currency'),
                        value: depositCurrencies.contains(currency) ? currency : 'EGP',
                        dropdownColor: isDark ? const Color(0xCC05192D) : Colors.white,
                        items: depositCurrencies
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: isDark ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold)),
                                ))
                            .toList(),
                        onChanged: (currencyLocked || isEgpOnlySupplier)
                            ? null
                            : (v) => setSheetState(() => currency = v ?? 'EGP'),
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
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
                            'عميل (تصدير)', counterpartyType == 'customer', () {
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
                            'مورد', counterpartyType == 'supplier', () async {
                      setSheetState(() {
                        counterpartyType = 'supplier';
                        showSupplierSearch = true;
                        showCustomerSearch = false;
                        showClearingAgentSearch = false;
                        showShippingCompanySearch = false;
                        showShareholderSearch = false;
                        counterpartyId = null;
                        supplierId = null;
                        selectedSupplierModel = null;
                        counterpartyName = null;
                        supplierSearchCtrl.clear();
                        supplierResults = [];
                        currency = 'EGP';
                        currencyLocked = false;
                      });
                      final list = await searchSuppliers('', supplierCategory);
                      setSheetState(() {
                        supplierResults = list;
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
                      dropdownColor: isDark ? const Color(0xCC05192D) : Colors.white,
                      hint: Text('اختر حساب الإيرادات...',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
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
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black)),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setSheetState(() => selectedRevenueAccountId = v),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold),
                      underline:
                          Container(height: 1, color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
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
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black)),
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
                                      Text('رصيد: 0',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
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
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black)),
                                subtitle: Text(
                                    'عملة: ${c.currency} — رصيد: ${AppUtils.formatNumber(c.balance)}',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                              ))
                          .toList(),
                    ),
                  ],
                  if (showSupplierSearch) ...[
                    if (selectedSupplierModel != null)
                      _buildBankSelectedSupplierCard(
                        supplier: selectedSupplierModel!,
                        currentCurrency: currency,
                        isDark: isDark,
                        onClear: () async {
                          setSheetState(() {
                            selectedSupplierModel = null;
                            supplierId = null;
                            counterpartyName = null;
                            supplierSearchCtrl.clear();
                            currencyLocked = false;
                          });
                          final list = await searchSuppliers('', supplierCategory);
                          setSheetState(() {
                            supplierResults = list;
                          });
                        },
                        onCurrencyTapped: (c) {
                          setSheetState(() {
                            currency = c;
                            currencyLocked = false;
                          });
                        },
                      )
                    else ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: _bankSupplierTypeOptions.map((opt) {
                            final key = opt['key'] as String;
                            final label = opt['label'] as String;
                            final icon = opt['icon'] as IconData;
                            final color = opt['color'] as Color;
                            final isSelected = supplierCategory == key;

                            return Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: InkWell(
                                onTap: () async {
                                  setSheetState(() {
                                    supplierCategory = key;
                                  });
                                  final list = await searchSuppliers(supplierSearchCtrl.text, key);
                                  setSheetState(() {
                                    supplierResults = list;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? color.withValues(alpha: 0.18)
                                        : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? color : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 13, color: isSelected ? color : (isDark ? Colors.white70 : const Color(0xFF475569))),
                                      const SizedBox(width: 5),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF334155)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildSearchField(
                        ctrl: supplierSearchCtrl,
                        hint: 'ابحث عن مورد بالاسم أو الكود...',
                        onChanged: (v) async {
                          supplierResults = await searchSuppliers(v, supplierCategory);
                          setSheetState(() {});
                        },
                        results: supplierResults
                            .map((s) {
                              final color = _getBankSupplierTypeColor(s.supplierType, s.supplierCode);
                              final icon = _getBankSupplierTypeIcon(s.supplierType, s.supplierCode);
                              final label = _getBankSupplierTypeLabel(s.supplierType, s.supplierCode);

                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(icon, color: color, size: 18),
                                ),
                                onTap: () async {
                                  setSheetState(() {
                                    selectedSupplierModel = s;
                                    supplierId = s.id;
                                    counterpartyName = s.name;
                                    supplierSearchCtrl.text = s.name;
                                    supplierResults = [];
                                    if (s.isEgpOnlySupplier) {
                                      currency = 'EGP';
                                      currencyLocked = true;
                                    } else if (s.currency.isNotEmpty && s.currency != 'MULTI') {
                                      currency = s.currency;
                                      currencyLocked = true;
                                    } else {
                                      currency = 'EGP';
                                      currencyLocked = false;
                                    }
                                  });
                                  if (s.id != null) {
                                    try {
                                      final live = await SupplierDao().getSupplierBalancesByCurrency(s.id!);
                                      if (live.isNotEmpty && selectedSupplierModel?.id == s.id) {
                                        setSheetState(() {
                                          selectedSupplierModel = selectedSupplierModel!.copyWith(currentBalancesByCurrency: live);
                                        });
                                      }
                                    } catch (_) {}
                                  }
                                },
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        s.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Row(
                                  children: [
                                    if (s.supplierCode.isNotEmpty) ...[
                                      Text(
                                        'كود: ${s.supplierCode}',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                        ),
                                      ),
                                      const Text('  |  ', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    ],
                                    Expanded(
                                      child: Text(
                                        'الأرصدة: ${_formatBankSupplierBalances(s)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ],
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
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black)),
                                subtitle: Text('عملة: ${a.currency}',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
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
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black)),
                                subtitle: Text('عملة: ${s.currency}',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'الوصف (اختياري)',
                      hintStyle: TextStyle(
                          color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                          fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.description_outlined,
                          color: AppTheme.success),
                      filled: true,
                      fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
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
                                    ? (counterpartyType == 'customer' && counterpartyName != null && counterpartyName!.isNotEmpty && !descCtrl.text.trim().contains(counterpartyName!)
                                        ? '${descCtrl.text.trim()} - العميل: $counterpartyName (سداد حساب العميل)'
                                        : descCtrl.text.trim())
                                    : counterpartyType == 'customer' && counterpartyName != null && counterpartyName!.isNotEmpty
                                        ? 'إيداع بنكي من العميل $counterpartyName (سداد حساب العميل)'
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
    SupplierModel? selectedSupplierModel;
    String? shareholderId =
        counterpartyType == 'shareholder' ? draftTx?.relatedPartyId : null;
    String? counterpartyName = draftTx?.relatedPartyName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final isEgpOnlySupplier = selectedSupplierModel?.isEgpOnlySupplier ?? false;
          final withdrawCurrencies = isEgpOnlySupplier ? const ['EGP'] : const ['EGP', 'USD', 'EUR', 'GBP'];
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

          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A1630) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: isDark ? null : Border.all(color: const Color(0xFFCBD5E1)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('صرف من حساب بنكي',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
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
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
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
                          fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('withdraw_cur_${isEgpOnlySupplier}_$currency'),
                        value: withdrawCurrencies.contains(currency) ? currency : 'EGP',
                        dropdownColor: isDark ? const Color(0xCC05192D) : Colors.white,
                        items: withdrawCurrencies
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: isDark ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold)),
                                ))
                            .toList(),
                        onChanged: (currencyLocked || isEgpOnlySupplier)
                            ? null
                            : (v) => setSheetState(() => currency = v ?? 'EGP'),
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
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
                  BeneficiarySelectorField(
                    initialBeneficiaryType: counterpartyType == 'expense'
                        ? 'expense'
                        : (counterpartyType == 'supplier' ? 'all_suppliers' : counterpartyType),
                    initialEntityId: counterpartyType == 'supplier'
                        ? supplierId
                        : (counterpartyType == 'shareholder' ? shareholderId : counterpartyId?.toString()),
                    initialEntityName: counterpartyName,
                    initialExpenseAccountId: selectedExpenseAccountId?.toString(),
                    expenseAccounts: expenseAccounts,
                    onAccountCreated: () => context.read<BankAccountsCubit>().loadAll(),
                    onChanged: (selection) {
                      setSheetState(() {
                        if (selection.isExpense) {
                          counterpartyType = 'expense';
                          selectedExpenseAccountId = int.tryParse(selection.expenseAccountId ?? '');
                          supplierId = null;
                          counterpartyId = null;
                          shareholderId = null;
                          counterpartyName = null;
                          selectedSupplierModel = null;
                        } else if (selection.isSupplier) {
                          counterpartyType = 'supplier';
                          supplierId = selection.entityId;
                          counterpartyId = null;
                          shareholderId = null;
                          counterpartyName = selection.entityName;
                          selectedExpenseAccountId = null;
                          selectedSupplierModel = selection.supplierModel;
                        } else if (selection.isShippingCompany) {
                          counterpartyType = 'shipping_company';
                          counterpartyId = int.tryParse(selection.entityId ?? '');
                          supplierId = null;
                          shareholderId = null;
                          counterpartyName = selection.entityName;
                          selectedExpenseAccountId = null;
                          selectedSupplierModel = null;
                        } else if (selection.isClearingAgent) {
                          counterpartyType = 'clearing_agent';
                          counterpartyId = int.tryParse(selection.entityId ?? '');
                          supplierId = null;
                          shareholderId = null;
                          counterpartyName = selection.entityName;
                          selectedExpenseAccountId = null;
                          selectedSupplierModel = null;
                        } else if (selection.isShareholder) {
                          counterpartyType = 'shareholder';
                          shareholderId = selection.entityId;
                          counterpartyId = null;
                          supplierId = null;
                          counterpartyName = selection.entityName;
                          selectedExpenseAccountId = null;
                          selectedSupplierModel = null;
                        }

                        if (selection.currency.isNotEmpty && selection.currency != 'MULTI') {
                          currency = selection.currency;
                          currencyLocked = true;
                        } else {
                          currencyLocked = false;
                        }

                        if (selection.entityName != null && selection.entityName!.isNotEmpty) {
                          if (descCtrl.text.trim().isEmpty ||
                              descCtrl.text.trim().startsWith('تحويل بنكي إلى ') ||
                              descCtrl.text.trim().startsWith('سداد لـ ')) {
                            descCtrl.text = 'تحويل بنكي إلى ${selection.entityName}';
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'الوصف (اختياري)',
                      hintStyle: TextStyle(
                          color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                          fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.description_outlined,
                          color: AppTheme.danger),
                      filled: true,
                      fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
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
                                          ? (counterpartyType == 'customer' && counterpartyName != null && counterpartyName!.isNotEmpty && !descCtrl.text.trim().contains(counterpartyName!)
                                              ? '${descCtrl.text.trim()} - العميل: $counterpartyName'
                                              : descCtrl.text.trim())
                                          : counterpartyType == 'customer' && counterpartyName != null && counterpartyName!.isNotEmpty
                                              ? 'صرف للعميل $counterpartyName'
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        hintStyle: TextStyle(
            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            fontSize: 13,
            fontFamily: 'Cairo'),
        prefixIcon: Icon(icon,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            size: 18),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
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
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A1630) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFCBD5E1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تحويل عملة',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
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
                          dropdownColor:
                              isDark ? AppTheme.surface : Colors.white,
                          items: fromOptions
                              .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.bold,
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
                          dropdownColor:
                              isDark ? AppTheme.surface : Colors.white,
                          items: toOptions
                              .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.bold,
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
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo'),
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
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo'),
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
                        color: isDark
                            ? AppTheme.surface.withValues(alpha: 0.6)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('المبلغ المتوقع استلامه:',
                                  style: TextStyle(
                                      color: isDark
                                          ? AppTheme.textSecondary
                                          : const Color(0xFF475569),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo')),
                              Text(
                                '${expectedReceived.toStringAsFixed(2)} ${toAcc.currency}',
                                style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
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
                                Text('التكلفة الدفترية المرجحة:',
                                    style: TextStyle(
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : const Color(0xFF475569),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Cairo')),
                                Text(
                                  '${(enteredAmount * bookRate).toStringAsFixed(2)} ج.م (بسعر ${bookRate.toStringAsFixed(4)})',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('فروق العملة المحققة المتوقعة:',
                                    style: TextStyle(
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : const Color(0xFF475569),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Cairo')),
                                Text(
                                  expectedGainLoss > 0.001
                                      ? '+${expectedGainLoss.toStringAsFixed(2)} ج.م (ربح)'
                                      : expectedGainLoss < -0.001
                                          ? '${expectedGainLoss.toStringAsFixed(2)} ج.م (خسارة)'
                                          : '0.00 ج.م (تعادل)',
                                  style: TextStyle(
                                      color: expectedGainLoss > 0.001
                                          ? (isDark ? Colors.greenAccent : const Color(0xFF16A34A))
                                          : expectedGainLoss < -0.001
                                              ? (isDark ? Colors.redAccent : const Color(0xFFDC2626))
                                              : (isDark ? Colors.white70 : Colors.black87),
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
