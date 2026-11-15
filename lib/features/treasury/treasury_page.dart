import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/treasury_model.dart';
import '../../data/models/unified_transaction_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'widgets/unified_transaction_details_modal.dart';
import 'widgets/simplified_custody_expense_dialog.dart';
import '../../data/models/expense_category_model.dart';
import '../../data/models/treasury_stats_model.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/dao/exchange_rate_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../core/router.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/account_model.dart';
import '../../data/dao/shareholder_dao.dart';
import 'treasury_cubit.dart';
import 'treasury_state.dart';
import '../suppliers/widgets/multi_invoice_payment_dialog.dart';
import 'receive_payment_dialog.dart';
import 'treasury_pdf_service.dart';
import '../../data/dao/purchase_dao.dart';
import '../../data/models/purchase_model.dart';
import '../../data/services/supplier_settlement_service.dart';
import '../../data/services/chart_of_accounts_service.dart';
import '../../data/models/cost_center.dart';
import 'widgets/coa_expense_dropdown.dart';
import '../../core/widgets/password_verification_dialog.dart';
import 'widgets/edit_confirmed_treasury_transaction_dialog.dart';
import 'widgets/cost_center_selector_field.dart';
import 'widgets/branch_selector_field.dart';
import 'widgets/expense_sub_account_dialog.dart';
import '../../core/widgets/beneficiary_selector_field.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class TreasuryPage extends StatelessWidget {
  const TreasuryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TreasuryCubit()..init(),
      child: const _TreasuryView(),
    );
  }
}

class _TreasuryView extends StatefulWidget {
  const _TreasuryView();

  @override
  State<_TreasuryView> createState() => _TreasuryViewState();
}

class _TreasuryViewState extends State<_TreasuryView> {
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
            _buildHeader(),
            const SizedBox(height: 20),
            Expanded(
              child: BlocConsumer<TreasuryCubit, TreasuryState>(
                listener: _onStateChange,
                builder: (_, state) {
                  if (state is TreasuryLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is TreasuryError) {
                    return _buildError(state);
                  }
                  if (state is TreasuryLoaded) {
                    return _buildContent(state);
                  }
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onStateChange(BuildContext context, TreasuryState state) {
    if (state is TreasuryError && state.message.contains('not authenticated')) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return;
    }
    if (state is TreasuryLoaded && state.errorMessage != null) {
      _showSnackBar(state.errorMessage!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<TreasuryCubit>().clearError();
        }
      });
    }
  }

  // ── Header ──

  Widget _buildHeader() {
    return BlocBuilder<TreasuryCubit, TreasuryState>(
      builder: (_, state) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isAdmin =
            state is TreasuryLoaded && (state.isAdmin || state.hasOwnerSafe);
        final screenWidth = MediaQuery.of(context).size.width;
        final isNarrow = screenWidth < 900;

        final titleRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: isDark ? 0.1 : 0.18),
                borderRadius: BorderRadius.circular(12),
                border: isDark ? null : Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.account_balance_outlined,
                  color: AppTheme.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('الخزينة الرئيسية',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo')),
                  Text(
                      isAdmin || (state is TreasuryLoaded && state.hasOwnerSafe)
                          ? 'مدير النظام (الخزينة)'
                          : 'العهدة الخاصة بي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          ],
        );

        Widget buildActiveTreasuryComment(TreasuryLoaded state) {
          return Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : const Color(0xFFCCFBF1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isDark
                      ? AppTheme.accent.withValues(alpha: 0.3)
                      : const Color(0xFF14B8A6)),
            ),
            child: Text(
              'أنت الآن تستخدم: ${state.selectedTreasury?.displayName ?? state.treasuryForCurrentUser?.displayName ?? 'الخزينة الرئيسية'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          );
        }

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              if (state is TreasuryLoaded) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _buildActionButtonsList(state),
                  ),
                ),
                buildActiveTreasuryComment(state),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(children: [
              Expanded(child: titleRow),
              if (state is TreasuryLoaded) _buildActionButtons(state),
            ]),
            if (state is TreasuryLoaded) buildActiveTreasuryComment(state),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons(TreasuryLoaded state) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: _buildActionButtonsList(state));
  }

  List<Widget> _buildActionButtonsList(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTreasury = state.selectedTreasury ?? state.treasuryForCurrentUser;
    return [
      if (state.isAdmin || state.hasOwnerSafe)
        _actionBtn(Icons.add_circle_outline, 'إضافة خزنة جديدة',
            AppTheme.success, () => _showCreateTreasurySheet(state)),
      if (state.isAdmin || state.hasOwnerSafe)
        _actionBtn(Icons.add_card_outlined, 'صرف عهدة جديدة', AppTheme.primary,
            () => _showDisburseSheet(state)),
      _actionBtn(Icons.swap_horiz_rounded, 'تحويل عهدة', AppTheme.info,
          () => _showTransferSheet(state)),
      if (state.isAdmin || state.hasOwnerSafe)
        _actionBtn(Icons.assignment_return_outlined, 'إرجاع عهدة',
            Colors.deepOrange, () => _showReturnCustodySheet(state)),
      if (state.selectedTreasury?.isMain == true)
        _actionBtn(Icons.currency_exchange, 'تحويل عملة', AppTheme.accent,
            () => _showCurrencyExchangeSheet(state)),
      if (state.selectedTreasury != null)
        _actionBtn(
            Icons.payments_outlined,
            'استلام نقدي',
            const Color.fromARGB(255, 22, 255, 84),
            () => _showReceivePaymentDialog()),
      if (activeTreasury != null)
        _actionBtn(
            Icons.shopping_cart_outlined,
            activeTreasury.isEmployee ? 'صرف مصروف عهدة' : 'صرف مصروف',
            AppTheme.warning, () {
          if (activeTreasury.isEmployee) {
            _showSimplifiedCustodyExpenseDialog(activeTreasury, state);
          } else {
            _showExpenseSheet(state);
          }
        }),
      if (state.selectedTreasury != null)
        _actionBtn(Icons.receipt_long_outlined, 'سداد مورد (متعدد)', Colors.amber,
            () => _showMultiInvoicePaymentDialog()),
      const SizedBox(width: 8),
      IconButton(
        icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white70 : Colors.black),
        tooltip: 'تحديث',
        onPressed: () => context.read<TreasuryCubit>().loadAll(reset: true),
      ),
    ];
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.1 : 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: color.withValues(alpha: isDark ? 0.3 : 0.5),
                  width: 1.2),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }

  // ── Error ──

  Widget _buildError(TreasuryError state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 72, color: AppTheme.danger.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('حدث خطأ',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.danger,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(state.message,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('إعادة المحاولة'),
            onPressed: () => context.read<TreasuryCubit>().loadAll(reset: true),
          ),
        ],
      ),
    );
  }

  // ── Main Content ──

  Widget _buildContent(TreasuryLoaded state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 700;

    if (isNarrow) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          if (state.isAdmin || state.hasOwnerSafe) ...[
            _buildDashboardCards(state),
            const SizedBox(height: 16),
            SizedBox(height: 350, child: _buildTreeView(state)),
            const SizedBox(height: 16),
           // SizedBox(height: 350, child: _buildStatsPanel(state)),
          ] else ...[
            SizedBox(
                height: 350,
                child:
                    _buildSingleTreasury(state, state.treasuryForCurrentUser)),
          ],
          const SizedBox(height: 16),
          SizedBox(height: 500, child: _buildTransactions(state)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isAdmin || state.hasOwnerSafe) ...[
          _buildDashboardCards(state),
          const SizedBox(height: 16),
          Expanded(
            flex: 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildTreeView(state)),
                const SizedBox(width: 16),
               // Expanded(flex: 3, child: _buildStatsPanel(state)),
              ],
            ),
          ),
        ] else ...[
          Expanded(
            flex: 2,
            child: _buildSingleTreasury(state, state.treasuryForCurrentUser),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          flex: 3,
          child: _buildTransactions(state),
        ),
      ],
    );
  }

  // ── Dashboard Cards (Admin) ──

  Widget _buildDashboardCards(TreasuryLoaded state) {
    final stats = state.stats;
    double curTot(String cur) => state.currencyTotals
        .where((c) => c.currency == cur)
        .fold(0.0, (sum, c) => sum + c.total);
    final totalEgp = curTot('EGP');
    final totalUsd = curTot('USD');
    final totalEur = curTot('EUR');
    final totalGbp = curTot('GBP');

    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _dashboardCard(
            'إجمالي الخزائن (ج.م)',
            AppUtils.formatCurrency(totalEgp),
            Icons.account_balance_wallet_outlined,
            AppTheme.primary,
          ),
          _dashboardCard(
            'إجمالي الخزائن (\$)',
            AppUtils.formatNumber(totalUsd),
            Icons.monetization_on_outlined,
            AppTheme.info,
          ),
          _dashboardCard(
            'إجمالي الخزائن (€)',
            AppUtils.formatNumber(totalEur),
            Icons.euro_outlined,
            const Color(0xFFF59E0B),
          ),
          _dashboardCard(
            'إجمالي الخزائن (£)',
            AppUtils.formatNumber(totalGbp),
            Icons.monetization_on_outlined,
            const Color(0xFFEC4899),
          ),
          // _dashboardCard(
          //   'عهد الموظفين',
          //   '${state.employeeTreasuries.length} موظف',
          //   Icons.people_outline,
          //   AppTheme.accent,
          //   subtitle: AppUtils.formatCurrency(state.totalEmployeeCustody),
          // ),
          // _dashboardCard(
          //   'إجمالي المصروفات',
          //   stats != null
          //       ? _formatExpensesByCurrency(stats.expensesByCurrency)
          //       : '---',
          //   Icons.receipt_long_outlined,
          //   AppTheme.warning,
          // ),
          // if (stats != null)
          //   _dashboardCard(
          //     'إجمالي الحركات',
          //     '${stats.totalTransactions} حركة',
          //     Icons.swap_vert_rounded,
          //     AppTheme.neonCyan,
          //   ),
        ],
      ),
    );
  }

  Widget _dashboardCard(String label, String value, IconData icon, Color color,
      {String? subtitle}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 240,
      margin: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  color.withValues(alpha: 0.1),
                  color.withValues(alpha: 0.03),
                ]
              : [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0.08),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.2 : 0.4),
          width: 1.2,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.15 : 0.22),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo')),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontFamily: 'Cairo')),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.textMuted : Colors.black,
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Tree View (Admin) ──

  Widget _buildTreeView(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('شجرة العهد',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    if (state.mainTreasury != null) ...[
                      _buildTreasuryCard(state.mainTreasury!, state, true),
                      const SizedBox(height: 8),
                    ],
                    if (state.employeeTreasuries.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('العهد الفرعية',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                      ...state.employeeTreasuries.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _buildTreasuryCard(t, state, false),
                        ),
                      ),
                    ],
                    if (state.treasuries.where((t) => !t.isMain && !t.isEmployee).isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('خزائن أخرى',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                      ...state.treasuries.where((t) => !t.isMain && !t.isEmployee).map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _buildTreasuryCard(t, state, false),
                        ),
                      ),
                    ],
                    if (state.employeeTreasuries.isEmpty &&
                        state.mainTreasury == null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('لا توجد عهد',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stats Panel (Admin) ──

  Widget _buildStatsPanel(TreasuryLoaded state) {
    final stats = state.stats;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.analytics_outlined,
                    color: AppTheme.neonCyan, size: 18),
                const SizedBox(width: 8),
                const Text('الإحصائيات',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                const Spacer(),
                InkWell(
                  onTap: () => context.read<TreasuryCubit>().refreshStats(),
                  child: const Icon(Icons.refresh,
                      color: AppTheme.textSecondary, size: 16),
                ),
              ]),
              const SizedBox(height: 12),
              if (stats == null)
                const Expanded(
                  child: Center(
                    child: Text('لا توجد إحصائيات',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontFamily: 'Cairo')),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      _statSectionHeader('إجمالي المصروفات', AppTheme.warning),
                      ..._statCurrencyRows(
                          stats.expensesByCurrency, AppTheme.warning),
                      const SizedBox(height: 8),
                      _statSectionHeader('إجمالي الإيداعات', AppTheme.success),
                      ..._statCurrencyRows(
                          stats.depositsByCurrency, AppTheme.success),
                      const Divider(height: 16, color: AppTheme.border),
                      // const Text('المصروفات حسب الحساب',
                      //     maxLines: 1,
                      //     overflow: TextOverflow.ellipsis,
                      //     style: TextStyle(
                      //         fontSize: 15,
                      //         fontWeight: FontWeight.bold,
                      //         color: AppTheme.textSecondary,
                      //         fontFamily: 'Cairo')),
                      // const SizedBox(height: 8),
                      // if (stats.categoryBreakdown.isEmpty)
                      //   const Text('لا توجد مصروفات مصنفة',
                      //       style: TextStyle(
                      //           fontSize: 13,
                      //           color: AppTheme.textMuted,
                      //           fontFamily: 'Cairo'))
                      // else
                      //   ...stats.categoryBreakdown.map((cat) =>
                      //       _categoryBreakdownRow(cat, stats.totalExpenses)),
                      // const Divider(height: 16, color: AppTheme.border),
                      // const Text('الإيرادات حسب الحساب',
                      //     maxLines: 1,
                      //     overflow: TextOverflow.ellipsis,
                      //     style: TextStyle(
                      //         fontSize: 15,
                      //         fontWeight: FontWeight.bold,
                      //         color: AppTheme.textSecondary,
                      //         fontFamily: 'Cairo')),
                      // const SizedBox(height: 8),
                      // if (stats.revenueBreakdown.isEmpty)
                      //   const Text('لا توجد إيرادات مصنفة',
                      //       style: TextStyle(
                      //           fontSize: 13,
                      //           color: AppTheme.textMuted,
                      //           fontFamily: 'Cairo'))
                      // else
                      //   ...stats.revenueBreakdown.map(
                      //       (cat) => _categoryBreakdownRow(cat, cat.total)),
                      // const Divider(height: 16, color: AppTheme.border),
                      const Text('عهد الموظفين حسب العملة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo')),
                      const SizedBox(height: 8),
                      if (stats.employeeCustodyBreakdown.isEmpty)
                        const Text('لا توجد عهد',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                                fontFamily: 'Cairo'))
                      else
                        ...stats.employeeCustodyBreakdown.map((ec) => _statRow(
                              ec.currency,
                              AppUtils.formatNumber(ec.total),
                              AppTheme.primary,
                            )),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo')),
        ),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
                fontFamily: 'Cairo')),
      ]),
    );
  }

  Widget _statSectionHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo')),
      ]),
    );
  }

  static const _currencyNames = {
    'EGP': 'جنية',
    'USD': 'دولار',
    'EUR': 'يورو',
    'GBP': 'استرليني',
  };

  String _formatExpensesByCurrency(List<CurrencyTotal> items) {
    final nonZero = items.where((e) => e.total > 0).toList();
    if (nonZero.isEmpty) return '0.00';
    return nonZero
        .map((e) => '${AppUtils.formatNumber(e.total)} ${e.currency}')
        .join(' | ');
  }

  List<Widget> _statCurrencyRows(List<CurrencyTotal> items, Color color) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
          child: Text('0.00',
              style: TextStyle(
                  fontSize: 13,
                  color: color.withAlpha(150),
                  fontFamily: 'Cairo')),
        ),
      ];
    }
    return items.where((e) => e.total > 0).map((e) {
      final name = _currencyNames[e.currency] ?? e.currency;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
        child: Row(children: [
          Text(name,
              style: TextStyle(
                  fontSize: 13,
                  color: color.withAlpha(180),
                  fontFamily: 'Cairo')),
          const SizedBox(width: 8),
          Text(AppUtils.formatCurrency(e.total, e.currency),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                  fontFamily: 'Cairo')),
        ]),
      );
    }).toList();
  }

  Widget _categoryBreakdownRow(CategoryBreakdown cat, double total) {
    final percentage =
        total > 0 ? (cat.total / total * 100).toStringAsFixed(1) : '0.0';
    final catColor = _parseHexColor(cat.color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: catColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  cat.code.isNotEmpty ? '${cat.code} - ${cat.name}' : cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontFamily: 'Cairo')),
            ),
            Text('${AppUtils.formatNumber(cat.total)} ($percentage%)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Cairo')),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total > 0 ? cat.total / total : 0,
              backgroundColor: catColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(catColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  // ── Single Treasury (Employee) ──

  Widget _buildSingleTreasury(TreasuryLoaded state, TreasuryModel? treasury) {
    if (treasury == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text('ليس لديك عهدة',
                style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo')),
          ],
        ),
      );
    }
    return _buildCurrencyCards(treasury, state);
  }

  // ── Treasury Card ──

  Widget _buildTreasuryCard(
      TreasuryModel treasury, TreasuryLoaded state, bool isMain) {
    final activeTreasuryId =
        state.selectedTreasury?.id ?? state.treasuryForCurrentUser?.id;
    final isSelected = activeTreasuryId == treasury.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.read<TreasuryCubit>().selectTreasury(treasury),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: isDark
                      ? [
                          AppTheme.warning.withValues(alpha: 0.25),
                          AppTheme.warning.withValues(alpha: 0.1),
                        ]
                      : [
                          const Color(0xFFFEF3C7),
                          const Color(0xFFFDE68A),
                        ],
                )
              : null,
          color: isSelected
              ? null
              : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark
                    ? AppTheme.warning.withValues(alpha: 0.6)
                    : const Color(0xFFD97706))
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isMain ? Icons.account_balance : Icons.person,
                  size: 20,
                  color: isMain
                      ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                      : AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  treasury.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              Icon(Icons.chevron_left,
                  color: isSelected
                      ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                  size: 18),
            ]),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: treasury.balances
                    .where((b) => b.balance > 0)
                    .map((b) => Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${b.currency}: ${AppUtils.formatCurrency(b.balance, b.currency)}',
                          maxLines: 1,
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                          ),
                        )))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Currency Cards ──

  Widget _buildCurrencyCards(TreasuryModel treasury, TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(treasury.displayName,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                  children: TreasuryDao.supportedCurrencies
                      .map((cur) => _buildCurrencyCard(treasury, cur,
                          treasury.getBalance(cur)?.balance ?? 0.0,
                          state: state))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyCard(
      TreasuryModel treasury, String currency, double balance,
      {TreasuryLoaded? state}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor;
    switch (currency) {
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

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  cardColor.withValues(alpha: 0.12),
                  cardColor.withValues(alpha: 0.04),
                ]
              : [
                  cardColor.withValues(alpha: 0.16),
                  cardColor.withValues(alpha: 0.06),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardColor.withValues(alpha: isDark ? 0.25 : 0.45)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: cardColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(currency,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cardColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo')),
          ]),
          const SizedBox(height: 4),
          Text(
            AppUtils.formatCurrency(balance, currency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyBtn(IconData icon, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isDark ? Colors.white70 : Colors.black),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
      ),
    );
  }

  // ── Date & Currency Filters ──

  Widget _currencyFilterButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<TreasuryCubit, TreasuryState>(
      builder: (ctx, state) {
        final loaded = state is TreasuryLoaded ? state : null;
        final hasFilter = loaded?.selectedCurrencyFilter != null;
        return PopupMenuButton<String?>(
          initialValue: loaded?.selectedCurrencyFilter,
          tooltip: 'تصفية بالعملة',
          onSelected: (val) {
            ctx.read<TreasuryCubit>().setCurrencyFilter(val);
          },
          offset: const Offset(0, 30),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: isDark ? AppTheme.surface : Colors.white,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hasFilter
                  ? AppTheme.primary.withValues(alpha: 0.2)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFilter
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monetization_on_outlined,
                    size: 18,
                    color: hasFilter
                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                        : (isDark ? Colors.white70 : Colors.black)),
                const SizedBox(width: 6),
                Text(
                  hasFilter ? loaded!.selectedCurrencyFilter! : 'العملة',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasFilter
                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                        : (isDark ? Colors.white70 : Colors.black),
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down,
                    size: 18,
                    color: hasFilter
                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                        : (isDark ? Colors.white70 : Colors.black)),
              ],
            ),
          ),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: null,
              child: Text('الكل',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black)),
            ),
            ...TreasuryDao.supportedCurrencies.map((cur) => PopupMenuItem(
                  value: cur,
                  child: Text(cur,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                )),
          ],
        );
      },
    );
  }

  Widget _dateFilterButton({int? treasuryId}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<TreasuryCubit, TreasuryState>(
      builder: (ctx, state) {
        final loaded = state is TreasuryLoaded ? state : null;
        final hasFilter = loaded?.startDate != null || loaded?.endDate != null;
        String dateText = 'تصفية بالتاريخ (من - إلى)';
        if (hasFilter) {
          final sStr = loaded?.startDate != null
              ? DateFormat('yyyy/MM/dd').format(loaded!.startDate!)
              : '';
          final eStr = loaded?.endDate != null
              ? DateFormat('yyyy/MM/dd').format(loaded!.endDate!)
              : '';
          dateText = 'من: $sStr إلى: $eStr';
        }

        return GestureDetector(
          onTap: () async {
            final now = DateTime.now();
            final cubit = ctx.read<TreasuryCubit>();
            final picked = await showDateRangePicker(
              context: ctx,
              firstDate: DateTime(2020),
              lastDate: now.add(const Duration(days: 365)),
              initialDateRange:
                  loaded?.startDate != null && loaded?.endDate != null
                      ? DateTimeRange(
                          start: loaded!.startDate!, end: loaded.endDate!)
                      : DateTimeRange(
                          start: now.subtract(const Duration(days: 30)),
                          end: now),
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
                            primary: Color(0xFF0284C7),
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
              cubit.setDateFilter(picked.start, picked.end);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hasFilter
                  ? AppTheme.primary.withValues(alpha: 0.2)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFilter
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.date_range,
                    size: 18,
                    color: hasFilter
                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                        : (isDark ? Colors.white70 : Colors.black)),
                const SizedBox(width: 6),
                Text(
                  dateText,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasFilter
                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                        : (isDark ? Colors.white70 : Colors.black),
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (hasFilter) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () =>
                        ctx.read<TreasuryCubit>().setDateFilter(null, null),
                    child: const Icon(Icons.close,
                        size: 14, color: AppTheme.danger),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _accountFilterButton(BuildContext ctx, TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFromFilter = state.selectedFromAccountId != null &&
        state.selectedFromAccountId!.isNotEmpty;
    final hasToFilter = state.selectedToAccountId != null &&
        state.selectedToAccountId!.isNotEmpty;
    final hasFilter = hasFromFilter || hasToFilter;

    return GestureDetector(
      onTap: () => _showAccountFilterDialog(ctx, state),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFilter
              ? AppTheme.primary.withValues(alpha: 0.2)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFilter
                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded,
                size: 18,
                color: hasFilter
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? Colors.white70 : Colors.black)),
            const SizedBox(width: 6),
            Text(
              hasFilter ? 'من/إلى حساب' : 'الحساب/الجهة',
              style: TextStyle(
                fontSize: 12,
                color: hasFilter
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? Colors.white70 : Colors.black),
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
            if (hasFilter) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  ctx.read<TreasuryCubit>().setFromAccountFilter(null);
                  ctx.read<TreasuryCubit>().setToAccountFilter(null);
                },
                child:
                    const Icon(Icons.close, size: 14, color: AppTheme.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAccountFilterDialog(BuildContext context, TreasuryLoaded state) {
    String? selectedFrom = state.selectedFromAccountId;
    final toItems = _buildGroupedToItems(state);
    final validToValues = toItems
        .where((i) => i.value != null && !i.value!.startsWith('____header_'))
        .map((i) => i.value!)
        .toSet();
    String? selectedTo = state.selectedToAccountId;
    if (selectedTo != null && !validToValues.contains(selectedTo)) {
      selectedTo = null;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTheme.glassBorder)),
              title: Row(
                children: const [
                  Icon(Icons.filter_alt_outlined,
                      color: AppTheme.primary, size: 20),
                  SizedBox(width: 8),
                  Text('فلتر الحسابات والجهات (من / إلى)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('من حساب / خزنة:',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      value: selectedFrom,
                      dropdownColor: AppTheme.cardBg,
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('جميع الخزائن/الحسابات المصدر',
                                style: TextStyle(fontFamily: 'Cairo'))),
                        ...state.treasuries.map((t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.displayName,
                                  style: const TextStyle(fontFamily: 'Cairo')),
                            )),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedFrom = val),
                    ),
                    const SizedBox(height: 16),
                    const Text('إلى حساب / خزنة / جهة:',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: DropdownButtonFormField<String>(
                        value: selectedTo ?? _kFilterAll,
                        dropdownColor: AppTheme.cardBg,
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 13),
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: toItems,
                        onChanged: (val) => setDialogState(() {
                          selectedTo =
                              (val == null || val == _kFilterAll) ? null : val;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    context.read<TreasuryCubit>().setFromAccountFilter(null);
                    context.read<TreasuryCubit>().setToAccountFilter(null);
                    Navigator.pop(dialogCtx);
                  },
                  child: const Text('إعادة ضبط',
                      style: TextStyle(
                          color: AppTheme.danger, fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  onPressed: () {
                    context
                        .read<TreasuryCubit>()
                        .setFromAccountFilter(selectedFrom);
                    context
                        .read<TreasuryCubit>()
                        .setToAccountFilter(selectedTo);
                    Navigator.pop(dialogCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('تطبيق',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const String _kFilterAll = '__FILTER_ALL__';

  List<DropdownMenuItem<String>> _buildGroupedToItems(TreasuryLoaded state) {
    final items = <DropdownMenuItem<String>>[];
    final transactions = state.transactions;
    final seen = <String>{};

    items.add(const DropdownMenuItem(
      value: _kFilterAll,
      child: Text('الكل (بدون تصفية جهة)',
          style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
    ));

    void addGroup(String label, List<MapEntry<String, String>> entries) {
      if (entries.isEmpty) return;
      items.add(DropdownMenuItem(
        value: '____header_$label',
        enabled: false,
        child: Text('── $label ──',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: AppTheme.primary,
                fontWeight: FontWeight.bold)),
      ));
      for (final e in entries) {
        if (seen.contains(e.key)) continue;
        seen.add(e.key);
        items.add(DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: const TextStyle(fontFamily: 'Cairo'))));
      }
    }

    final customers = <MapEntry<String, String>>[];
    final suppliers = <MapEntry<String, String>>[];
    final clearingAgents = <MapEntry<String, String>>[];
    final shippingCompanies = <MapEntry<String, String>>[];
    final shareholders = <MapEntry<String, String>>[];
    final treasuries = <MapEntry<String, String>>[];

    for (final tx in transactions) {
      if (tx.customerId != null && tx.customerId!.isNotEmpty) {
        customers.add(MapEntry('customer:${tx.customerId}',
            tx.customerName ?? '#${tx.customerId}'));
      }
      if (tx.supplierId != null && tx.supplierId!.isNotEmpty) {
        suppliers.add(MapEntry('supplier:${tx.supplierId}',
            tx.supplierName ?? '#${tx.supplierId}'));
      }
      if (tx.clearingAgentId != null && tx.clearingAgentId!.isNotEmpty) {
        clearingAgents.add(MapEntry('clearing_agent:${tx.clearingAgentId}',
            tx.clearingAgentName ?? '#${tx.clearingAgentId}'));
      }
      if (tx.shippingCompanyId != null && tx.shippingCompanyId!.isNotEmpty) {
        shippingCompanies.add(MapEntry(
            'shipping_company:${tx.shippingCompanyId}',
            tx.shippingCompanyName ?? '#${tx.shippingCompanyId}'));
      }
      if (tx.shareholderId != null && tx.shareholderId!.isNotEmpty) {
        shareholders.add(MapEntry('shareholder:${tx.shareholderId}',
            tx.shareholderName ?? '#${tx.shareholderId}'));
      }
      if (tx.relatedTreasuryId != null &&
          tx.relatedTreasuryId!.isNotEmpty &&
          tx.relatedTreasuryId != tx.treasuryId) {
        treasuries.add(MapEntry('treasury:${tx.relatedTreasuryId}',
            tx.relatedTreasuryName ?? '#${tx.relatedTreasuryId}'));
      }
    }

    addGroup('عملاء', customers);
    addGroup('موردين', suppliers);
    addGroup('مخلصين', clearingAgents);
    addGroup('شركات شحن', shippingCompanies);
    addGroup('مساهمين', shareholders);
    addGroup('خزائن أخرى', treasuries);

    return items;
  }

  String _resolveToFilterLabel(String accountId, TreasuryLoaded state) {
    final parts = accountId.split(':');
    if (parts.length < 2) return accountId;
    final type = parts[0];
    final id = parts.sublist(1).join(':');
    final txs = state.transactions;
    switch (type) {
      case 'customer':
        final tx = txs.firstWhereOrNull((t) => t.customerId == id);
        return tx?.customerName ?? id;
      case 'supplier':
        final tx = txs.firstWhereOrNull((t) => t.supplierId == id);
        return tx?.supplierName ?? id;
      case 'clearing_agent':
        final tx = txs.firstWhereOrNull((t) => t.clearingAgentId == id);
        return tx?.clearingAgentName ?? id;
      case 'shipping_company':
        final tx = txs.firstWhereOrNull((t) => t.shippingCompanyId == id);
        return tx?.shippingCompanyName ?? id;
      case 'shareholder':
        final tx = txs.firstWhereOrNull((t) => t.shareholderId == id);
        return tx?.shareholderName ?? id;
      case 'treasury':
        final tx = txs.firstWhereOrNull((t) => t.relatedTreasuryId == id);
        return tx?.relatedTreasuryName ?? id;
      default:
        return accountId;
    }
  }

  // ── Export Buttons ──

  Widget _exportButtons({int? treasuryId}) {
    return BlocBuilder<TreasuryCubit, TreasuryState>(
      builder: (ctx, state) {
        final loaded = state is TreasuryLoaded ? state : null;
        final txns = loaded?.filteredTransactions ?? [];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _exportBtn(
              Icons.picture_as_pdf_rounded,
              'طباعة PDF',
              () => _exportPdf(ctx, loaded, txns),
              color: const Color(0xFFEF4444),
            ),
            const SizedBox(width: 8),
            _exportBtn(
              Icons.table_chart_outlined,
              'Excel',
              () => _exportExcel(ctx, loaded, txns),
            ),
          ],
        );
      },
    );
  }

  Widget _exportBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultIconColor = color ?? (isDark ? Colors.white70 : Colors.black);
    final defaultTextColor = color ?? (isDark ? Colors.white70 : Colors.black);
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
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              width: 1.2),
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

  Future<void> _exportPdf(BuildContext ctx, TreasuryLoaded? loaded,
      List<TreasuryTransactionModel> txns) async {
    if (loaded == null || loaded.selectedTreasury == null) return;
    if (txns.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('لا توجد حركات للتصدير',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    try {
      final isCustody = loaded.selectedTreasury?.isEmployee == true;
      final currentBal = loaded.selectedTreasury
          ?.getBalance(txns.first.currency)
          ?.balance;
      await TreasuryPdfService.generatePdf(
        treasuryName: loaded.selectedTreasury!.displayName,
        currency: txns.first.currency,
        transactions: txns,
        fromDate: loaded.startDate,
        toDate: loaded.endDate,
        isCustody: isCustody,
        currentBalance: currentBal,
      );
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('تم فتح معاينة طباعة ${txns.length} حركة بنجاح',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('فشل تصدير PDF: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  Future<void> _exportExcel(BuildContext ctx, TreasuryLoaded? loaded,
      List<TreasuryTransactionModel> txns) async {
    if (loaded == null || loaded.selectedTreasury == null) return;
    if (txns.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('لا توجد حركات للتصدير',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    try {
      final dao = TreasuryDao();
      final customerMap = await dao.getCustomerNameMap();
      final supplierMap = await dao.getSupplierNameMap();
      final clearingAgentMap = await dao.getClearingAgentNameMap();
      final shippingCompanyMap = await dao.getShippingCompanyNameMap();
      final shareholderMap = await dao.getShareholderNameMap();

      final excel = Excel.createExcel();
      final sheet = excel['حركات'];

      sheet.setColumnWidth(0, 20);
      sheet.setColumnWidth(1, 16);
      sheet.setColumnWidth(2, 12);
      sheet.setColumnWidth(3, 10);
      sheet.setColumnWidth(4, 30);
      sheet.setColumnWidth(5, 14);
      sheet.setColumnWidth(6, 14);
      sheet.setColumnWidth(7, 30);
      sheet.setColumnWidth(8, 20);

      final headers = [
        'التاريخ والوقت',
        'نوع الحركة',
        'المبلغ',
        'العملة',
        'الوصف',
        'المنشئ',
        'الجهة (العميل/المورد/أخرى)',
      ];
      final headerCell = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 12,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#1B5E20'),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      for (var i = 0; i < headers.length; i++) {
        final cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerCell;
      }

      final dataCell = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
      );
      final dataCellCenter = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      final dataCellAmount = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        numberFormat: NumFormat.standard_2,
      );

      for (var i = 0; i < txns.length; i++) {
        final tx = txns[i];
        final row = i + 1;

        String entityName = '';
        if (tx.customerId != null) {
          entityName = customerMap['${tx.customerId}'] ?? tx.customerName ?? '#${tx.customerId}';
        } else if (tx.supplierId != null) {
          entityName = supplierMap[tx.supplierId] ?? tx.supplierName ?? '#${tx.supplierId}';
        } else if (tx.clearingAgentId != null) {
          entityName = clearingAgentMap[tx.clearingAgentId] ?? tx.clearingAgentName ?? '#${tx.clearingAgentId}';
        } else if (tx.shippingCompanyId != null) {
          entityName = shippingCompanyMap[tx.shippingCompanyId] ?? tx.shippingCompanyName ?? '#${tx.shippingCompanyId}';
        } else if (tx.shareholderId != null) {
          entityName = shareholderMap[tx.shareholderId] ?? tx.shareholderName ?? '#${tx.shareholderId}';
        }

        final dateStr = AppUtils.formatDate(_parseDate(tx.createdAt));

        final values = <dynamic>[
          dateStr,
          tx.typeLabel,
          tx.amount,
          tx.currency,
          tx.description ?? '',
          tx.creatorName ?? '',
          entityName,
        ];

        for (var c = 0; c < values.length; c++) {
          final cell = sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
          final val = values[c];
          if (val is double) {
            cell.value = DoubleCellValue(val);
            cell.cellStyle = dataCellAmount;
          } else if (val is int) {
            cell.value = IntCellValue(val);
            cell.cellStyle = dataCellCenter;
          } else {
            cell.value = TextCellValue(val?.toString() ?? '');
            cell.cellStyle = c == 4 ? dataCell : dataCellCenter;
          }
        }
      }

      final dir = await FileHelper.getExportDirectory();
      final datePart = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'treasury_transactions_$datePart.xlsx';
      final filePath = '${dir.path}/$fileName';
      final bytes = excel.encode();
      if (bytes == null) throw Exception('فشل ترميز ملف Excel');
      await File(filePath).writeAsBytes(bytes);

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('تم تصدير ${txns.length} حركة إلى $fileName',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'فتح',
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('فشل التصدير: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Transactions ──

  Widget _buildTransactions(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredList = state.filteredTransactions;
    final hasActiveFilters =
        (state.searchQuery != null && state.searchQuery!.trim().isNotEmpty) ||
            state.startDate != null ||
            state.endDate != null ||
            (state.selectedCurrencyFilter != null &&
                state.selectedCurrencyFilter != 'ALL') ||
            (state.selectedFromAccountId != null &&
                state.selectedFromAccountId!.isNotEmpty) ||
            (state.selectedToAccountId != null &&
                state.selectedToAccountId!.isNotEmpty);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Controls Row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              color: AppTheme.accent, size: 22),
                          const SizedBox(width: 8),
                          Text('آخر الحركات',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                  fontFamily: 'Cairo')),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.primary.withValues(alpha: 0.2)
                                  : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isDark
                                      ? AppTheme.primary.withValues(alpha: 0.4)
                                      : const Color(0xFF0284C7)),
                            ),
                            child: Text(
                              '${filteredList.length} حركة',
                              style: TextStyle(
                                  color: isDark
                                      ? AppTheme.primary
                                      : const Color(0xFF0369A1),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo'),
                            ),
                          ),
                          const SizedBox(width: 16),
                         // _accountFilterButton(context, state),
                          const SizedBox(width: 10),
                          _currencyFilterButton(),
                          const SizedBox(width: 10),
                          _dateFilterButton(
                              treasuryId: int.tryParse(
                                  state.selectedTreasury?.id ?? '')),
                          const SizedBox(width: 10),
                          _exportButtons(
                              treasuryId: int.tryParse(
                                  state.selectedTreasury?.id ?? '')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Live Search Box (Description, Tx ID #, Treasury & Counterparty names)
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 13),
                        onChanged: (val) =>
                            context.read<TreasuryCubit>().setSearchQuery(val),
                        decoration: InputDecoration(
                          hintText:
                              'بحث بالاسم ..',
                          hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : const Color(0xFF94A3B8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Cairo'),
                          prefixIcon: Icon(Icons.search_rounded,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7), size: 18),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close_rounded,
                                      color: isDark ? Colors.white70 : Colors.black, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    context
                                        .read<TreasuryCubit>()
                                        .setSearchQuery(null);
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: isDark
                                    ? AppTheme.glassBorder
                                        .withValues(alpha: 0.3)
                                    : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: isDark
                                    ? AppTheme.glassBorder
                                        .withValues(alpha: 0.3)
                                    : const Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: isDark ? AppTheme.primary : const Color(0xFF0284C7), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    // Active Filters Chips (If any filter applied)
                    if (hasActiveFilters) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('الفلاتر النشطة:',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                          if (state.searchQuery != null &&
                              state.searchQuery!.trim().isNotEmpty)
                            _buildFilterChip('بحث: "${state.searchQuery}"', () {
                              _searchController.clear();
                              context
                                  .read<TreasuryCubit>()
                                  .setSearchQuery(null);
                            }),
                          if (state.startDate != null || state.endDate != null)
                            _buildFilterChip('التاريخ محدَّد', () {
                              context
                                  .read<TreasuryCubit>()
                                  .setDateFilter(null, null);
                            }),
                          if (state.selectedCurrencyFilter != null &&
                              state.selectedCurrencyFilter != 'ALL')
                            _buildFilterChip(
                                'العملة: ${state.selectedCurrencyFilter}', () {
                              context
                                  .read<TreasuryCubit>()
                                  .setCurrencyFilter(null);
                            }),
                          if (state.selectedFromAccountId != null &&
                              state.selectedFromAccountId!.isNotEmpty)
                            _buildFilterChip('من حساب محدَّد', () {
                              context
                                  .read<TreasuryCubit>()
                                  .setFromAccountFilter(null);
                            }),
                          if (state.selectedToAccountId != null &&
                              state.selectedToAccountId!.isNotEmpty)
                            _buildFilterChip(
                                'إلى جهة: ${_resolveToFilterLabel(state.selectedToAccountId!, state)}',
                                () {
                              context
                                  .read<TreasuryCubit>()
                                  .setToAccountFilter(null);
                            }),
                          InkWell(
                            onTap: () {
                              _searchController.clear();
                              context.read<TreasuryCubit>().clearAllFilters();
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
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
                ),
              ),
              Divider(height: 1, color: isDark ? AppTheme.border : const Color(0xFFE2E8F0)),
              if (filteredList.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded,
                            color: isDark ? AppTheme.textMuted : const Color(0xFF94A3B8), size: 40),
                        const SizedBox(height: 8),
                        Text(
                          hasActiveFilters
                              ? 'لا توجد حركات تطابق الفلاتر المحددة'
                              : 'لا توجد حركات',
                          style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      if (!state.isFetchingMore &&
                          state.hasMore &&
                          scrollInfo.metrics.pixels >=
                              scrollInfo.metrics.maxScrollExtent - 200) {
                        context.read<TreasuryCubit>().loadMoreTransactions();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      itemCount: filteredList.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        if (i == filteredList.length) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        return _buildTransactionRow(filteredList[i]);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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

  Color? _tryParseColor(String hex) {
    try {
      return _parseHexColor(hex);
    } catch (_) {
      return null;
    }
  }

  Widget _buildTransactionRow(TreasuryTransactionModel tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIncoming = tx.isIncoming;
    final arrowColor = isIncoming ? AppTheme.success : AppTheme.danger;
    final Color? catColor =
        tx.categoryColor != null ? _tryParseColor(tx.categoryColor!) : null;
    final state = context.read<TreasuryCubit>().state;
    final isAdmin =
        state is TreasuryLoaded && (state.isAdmin || state.hasOwnerSafe);
    final txDesc = (tx.description != null && tx.description!.isNotEmpty)
        ? tx.description!
        : (tx.notes != null && tx.notes!.isNotEmpty ? tx.notes! : '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: arrowColor.withValues(alpha: isDark ? 0.1 : 0.15),
            borderRadius: BorderRadius.circular(8),
            border: isDark ? null : Border.all(color: arrowColor.withValues(alpha: 0.3)),
          ),
          child: Icon(
            isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
            color: arrowColor,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => _showTransactionDetail(tx),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(tx.typeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black,
                            fontFamily: 'Cairo')),
                  ),
                  if (tx.isDraft) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.6)),
                      ),
                      child: const Text('مسودة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.warning,
                              fontFamily: 'Cairo')),
                    ),
                  ],
                  if (tx.categoryName != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor?.withValues(alpha: 0.15) ??
                            AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: isDark ? null : Border.all(color: (catColor ?? AppTheme.primary).withValues(alpha: 0.3)),
                      ),
                      child: Text(tx.categoryName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: catColor ?? (isDark ? AppTheme.primary : const Color(0xFF0369A1)),
                              fontFamily: 'Cairo')),
                    ),
                  ],
                  if (tx.costCenterId != null && tx.costCenterId!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Builder(
                      builder: (_) {
                        final cc = CostCenterHelper.fromId(tx.costCenterId);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cc.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: cc.color.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            cc.nameAr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cc.color,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text('${tx.currency} ${_formatAmount(tx.amount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: tx.isDraft
                            ? AppTheme.warning
                            : (isDark ? AppTheme.textSecondary : Colors.black),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                if (txDesc.isNotEmpty)
                  Text(txDesc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppTheme.textMuted : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                if (_resolveRelatedParty(tx).isNotEmpty)
                  Text(_resolveRelatedParty(tx),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppTheme.textSecondary.withValues(alpha: 0.7)
                              : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
              ],
            ),
          ),
        ),
        Text(AppUtils.formatDate(_parseDate(tx.createdAt)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.textMuted : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(width: 4),
        _TransactionActions(
          tx: tx,
          isAdmin: isAdmin,
          onView: () => _showTransactionDetail(tx),
          onViewJournalEntry: tx.isDraft ? null : () => _goToJournalEntry(tx),
          onDelete: () => _confirmDelete(tx),
          onEditDraft: tx.isDraft ? () => _showEditTransaction(tx) : null,
          onEditConfirmed: !tx.isDraft ? () => _handleSecuredEditTreasuryTransaction(tx) : null,
          onConfirmDraft: tx.isDraft ? () => _confirmDraftTx(tx) : null,
          onDeleteDraft: tx.isDraft ? () => _deleteDraftTx(tx) : null,
        ),
      ]),
    );
  }

  Future<void> _handleSecuredEditTreasuryTransaction(
      TreasuryTransactionModel tx) async {
    final verified = await showPasswordVerificationDialog(
      context,
      title: 'تأكيد كلمة المرور لتعديل الحركة',
      subtitle:
          'يرجى إدخال كلمة المرور للمتابعة في تعديل بيانات حركة الخزنة #${tx.id}',
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

    final cubit = context.read<TreasuryCubit>();
    final cubitState = cubit.state;
    if (cubitState is! TreasuryLoaded) return;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider<TreasuryCubit>.value(
        value: cubit,
        child: EditConfirmedTreasuryTransactionDialog(
          tx: tx,
          state: cubitState,
          cubit: cubit,
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(2);
  }

  String _resolveRelatedParty(TreasuryTransactionModel tx) {
    if (tx.supplierName != null && tx.supplierName!.isNotEmpty) {
      return 'المورد: ${tx.supplierName}';
    }
    if (tx.customerName != null && tx.customerName!.isNotEmpty) {
      return 'العميل: ${tx.customerName}';
    }
    return '';
  }

  DateTime _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  void _showTransactionDetail(TreasuryTransactionModel tx) {
    UnifiedTransactionDetailsModal.show(
      context,
      UnifiedTransactionModel.fromTreasuryTx(tx),
    );
  }

  void _goToJournalEntry(TreasuryTransactionModel tx) {
    JournalEntryNavigationService.openForTransaction(
      context,
      journalEntryId: tx.journalEntryId,
      entryNumber: tx.entryNumber,
      txId: tx.id,
      description: tx.description,
      sourceType: tx.transactionType,
      sourceId: tx.id,
    );
  }

  void _confirmDelete(TreasuryTransactionModel tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => _buildSheetContainer(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تأكيد الحذف',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 8),
                Text(
                    'هل تريد حذف حركة "${tx.typeLabel}" بمبلغ ${_formatAmount(tx.amount)} ${tx.currency}؟',
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: _btnStyle(AppTheme.danger),
                    onPressed: () {
                      final cubit = context.read<TreasuryCubit>();
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (tx.id != null) {
                        cubit.deleteTransaction(transactionId: tx.id!);
                      }
                    },
                    child: const Text('تأكيد الحذف',
                        style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDraftTx(TreasuryTransactionModel tx) {
    if (tx.id == null) return;
    final txId = int.tryParse(tx.id!);
    if (txId == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          'هل أنت متأكد من تأكيد وترحيل حركة "${tx.typeLabel}" بمبلغ ${_formatAmount(tx.amount)} ${tx.currency} وتحديث الأرصدة والقيود المحاسبية؟',
          style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TreasuryCubit>().confirmDraft(txId);
            },
            child: const Text('تأكيد وترحيل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _deleteDraftTx(TreasuryTransactionModel tx) {
    if (tx.id == null) return;
    final txId = int.tryParse(tx.id!);
    if (txId == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف المسودة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.danger)),
        content: Text(
          'هل تريد حذف مسودة "${tx.typeLabel}" بمبلغ ${_formatAmount(tx.amount)} ${tx.currency} نهائياً؟',
          style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TreasuryCubit>().deleteDraft(txId);
            },
            child: const Text('تأكيد الحذف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditTransaction(TreasuryTransactionModel tx) {
    final cubitState = context.read<TreasuryCubit>().state;
    final treasuryId = cubitState is TreasuryLoaded
        ? int.tryParse(cubitState.selectedTreasury?.id ?? '')
        : null;
    final txType = tx.transactionType;

    // Deposit / Receipt -> open ReceivePaymentDialog with draft data
    if (txType == 'deposit' || txType == 'receipt') {
      showDialog(
        context: context,
        builder: (_) => ReceivePaymentDialog(
          treasuryId: treasuryId,
          draftTx: tx,
        ),
      ).then((success) {
        if (success == true) {
          context.read<TreasuryCubit>().loadAll(reset: true);
        }
      });
      return;
    }

    // Multi-payment -> open MultiInvoicePaymentDialog with draft data
    if (txType == 'multi_payment' ||
        (tx.payload?['is_multi_payment'] == true)) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => MultiInvoicePaymentDialog(
          initialSourceType: tx.payload?['source_type'] ?? 'treasury',
          initialSourceId: int.tryParse(tx.treasuryId ?? ''),
          draftTx: tx,
        ),
      ).then((success) {
        if (success == true) {
          context.read<TreasuryCubit>().loadAll(reset: true);
        }
      });
      return;
    }

    // Currency exchange -> open _showCurrencyExchangeSheet with draft data
    if (txType == 'exchange' || txType == 'currency_exchange' ||
        txType == 'currency_exchange_in' || txType == 'currency_exchange_out') {
      if (cubitState is TreasuryLoaded) {
        _showCurrencyExchangeSheet(cubitState, draftTx: tx);
      }
      return;
    }

    // Default: Expense / Withdrawal -> open _showExpenseSheet with draft data
    if (cubitState is TreasuryLoaded) {
      _showExpenseSheet(cubitState, draftTx: tx);
    }
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontFamily: 'Cairo')),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: valueColor ?? (isDark ? Colors.white : Colors.black),
                    fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  // ── Bottom Sheet: Create Treasury ──

  void _showMultiInvoicePaymentDialog() {
    final state = context.read<TreasuryCubit>().state;
    final treasuryId = state is TreasuryLoaded
        ? int.tryParse(state.selectedTreasury?.id ?? '')
        : null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MultiInvoicePaymentDialog(
        initialSourceType: 'treasury',
        initialSourceId: treasuryId,
      ),
    ).then((success) {
      if (success == true) {
        context.read<TreasuryCubit>().loadAll(reset: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل السداد بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
        );
      }
    });
  }

  void _showReceivePaymentDialog() {
    final state = context.read<TreasuryCubit>().state;
    final treasuryId = state is TreasuryLoaded
        ? int.tryParse(state.selectedTreasury?.id ?? '')
        : null;
    showDialog(
      context: context,
      builder: (_) => ReceivePaymentDialog(treasuryId: treasuryId),
    );
  }

  void _showCreateTreasurySheet(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedType = 'employee';
    String? selectedEmployeeId;
    final isSaving = ValueNotifier(false);
    final existingEmployeeIds = state.employeeTreasuries
        .map((t) => t.userId)
        .whereType<String>()
        .toSet();
    final employeeListFuture = TreasuryDao().getEmployeeList().then(
          (list) => list
              .where((e) => !existingEmployeeIds.contains(e['id']?.toString()))
              .toList(),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => _buildSheetContainer(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إضافة خزنة جديدة',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                _buildTextField(nameCtrl, 'اسم الخزنة', Icons.badge_outlined),
                const SizedBox(height: 12),
                _buildTypeDropdown((val) {
                  setSheetState(() => selectedType = val!);
                },
                    selectedValue: selectedType,
                    mainExists: state.mainTreasury != null),
                const SizedBox(height: 12),
                if (selectedType == 'employee') ...[
                  _buildFutureDropdown(employeeListFuture, (val) {
                    setSheetState(() => selectedEmployeeId = val);
                  }, selectedValue: selectedEmployeeId),
                  const SizedBox(height: 12),
                ],
                _buildTextField(
                    notesCtrl, 'ملاحظات (اختياري)', Icons.notes_outlined),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: isSaving,
                  builder: (_, saving, __) => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: _btnStyle(AppTheme.primary),
                      onPressed: saving
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty) return;
                              isSaving.value = true;
                              await context
                                  .read<TreasuryCubit>()
                                  .createTreasury(
                                    name: nameCtrl.text.trim(),
                                    type: selectedType,
                                    employeeId: selectedEmployeeId,
                                    notes: notesCtrl.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                      child: const Text('إنشاء',
                          style: TextStyle(fontFamily: 'Cairo')),
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

  // ── Bottom Sheet: Disburse ──

  void _showDisburseSheet(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCurrency = 'EGP';
    int? selectedEmployeeTreasuryId;
    final isSaving = ValueNotifier(false);

    double _getMainBalance() {
      if (state.mainTreasury == null) return 0;
      return state.mainTreasury!.getBalance(selectedCurrency)?.balance ?? 0;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => _buildSheetContainer(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('صرف عهدة جديدة',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                _buildEmployeeTreasuryDropdown(
                    state.employeeTreasuries,
                    (val) =>
                        setSheetState(() => selectedEmployeeTreasuryId = val),
                    selectedValue: selectedEmployeeTreasuryId),
                const SizedBox(height: 12),
                _buildFixedEGPCurrencyField(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'رصيد الخزنة الرئيسية: ${_getMainBalance().toStringAsFixed(2)} ج.م',
                    style: TextStyle(
                      color: _getMainBalance() > 0
                          ? (isDark ? Colors.greenAccent : const Color(0xFF15803D))
                          : Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                    amountCtrl, 'المبلغ', Icons.monetization_on_outlined,
                    isNumber: true, onChanged: (_) => setSheetState(() {})),
                const SizedBox(height: 12),
                _buildTextField(
                    descCtrl, 'الوصف (اختياري)', Icons.description_outlined),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: isSaving,
                  builder: (_, saving, __) => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: _btnStyle(AppTheme.primary),
                      onPressed: saving
                          ? null
                          : () async {
                              if (selectedEmployeeTreasuryId == null ||
                                  amountCtrl.text.trim().isEmpty) {
                                return;
                              }
                              final text = amountCtrl.text.trim();
                              if (text.contains('.') &&
                                  (text.startsWith('.') ||
                                      text.endsWith('.'))) {
                                _showSnackBar(
                                    'يجب كتابة أرقام قبل وبعد العلامة العشرية');
                                return;
                              }
                              final amount = double.tryParse(text) ?? 0;
                              if (amount <= 0) {
                                _showSnackBar('المبلغ يجب أن يكون أكبر من صفر');
                                return;
                              }
                              final mainBalance = _getMainBalance();
                              if (amount > mainBalance) {
                                _showSnackBar(
                                    'الرصيد غير كافٍ. الرصيد الحالي: ${mainBalance.toStringAsFixed(2)} $selectedCurrency');
                                return;
                              }
                              isSaving.value = true;
                              await context
                                  .read<TreasuryCubit>()
                                  .createDisbursement(
                                    toTreasuryId: selectedEmployeeTreasuryId!,
                                    currency: selectedCurrency,
                                    amount: amount,
                                    description: descCtrl.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                      child: const Text('صرف',
                          style: TextStyle(fontFamily: 'Cairo')),
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

  // ── Bottom Sheet: Currency Exchange ──

  void _showCurrencyExchangeSheet(TreasuryLoaded state, {TreasuryTransactionModel? draftTx}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? fromCurrency = draftTx?.payload?['from_currency'];
    String? toCurrency = draftTx?.payload?['to_currency'];
    final amountCtrl = TextEditingController(
      text: draftTx != null ? (draftTx.payload?['amount_from'] ?? draftTx.amount.abs()).toString() : '',
    );
    final rateCtrl = TextEditingController(
      text: draftTx?.payload?['exchange_rate']?.toString() ?? '',
    );
    double? systemRate;
    final isSaving = ValueNotifier(false);

    InputDecoration inputDecor(String hint, IconData icon) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            fontSize: 13,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            fontFamily: 'Cairo'),
        prefixIcon: Icon(icon, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), size: 18),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
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
          return _buildSheetContainer(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draftTx != null ? 'تعديل تحويل عملة — #${draftTx.id}' : 'تحويل عملة',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: fromCurrency,
                          decoration: inputDecor(
                              'من عملة', Icons.monetization_on_outlined),
                          dropdownColor: isDark ? AppTheme.surface : Colors.white,
                          items: TreasuryDao.supportedCurrencies
                              .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: TextStyle(
                                          color: isDark ? Colors.white : Colors.black,
                                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                          fontFamily: 'Cairo'))))
                              .toList(),
                          onChanged: (v) async {
                            setSheetState(() {
                              fromCurrency = v;
                              if (fromCurrency != 'EGP') {
                                toCurrency = 'EGP';
                              } else if (toCurrency == 'EGP') {
                                toCurrency = 'USD';
                              }
                            });
                            final foreignCur = (fromCurrency == 'EGP') ? toCurrency : fromCurrency;
                            if (foreignCur != null && foreignCur != 'EGP') {
                              final rate = await ExchangeRateDao().getRate(foreignCur);
                              setSheetState(() {
                                systemRate = rate;
                                rateCtrl.text = rate.toStringAsFixed(4);
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: toCurrency,
                          decoration: inputDecor(
                              'إلى عملة', Icons.monetization_on_outlined),
                          dropdownColor: isDark ? AppTheme.surface : Colors.white,
                          items: TreasuryDao.supportedCurrencies
                              .where((c) {
                                if (c == fromCurrency) return false;
                                if (fromCurrency != 'EGP') return c == 'EGP';
                                return true;
                              })
                              .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: TextStyle(
                                          color: isDark ? Colors.white : Colors.black,
                                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                          fontFamily: 'Cairo'))))
                              .toList(),
                          onChanged: (v) async {
                            setSheetState(() => toCurrency = v);
                            final foreignCur = (fromCurrency == 'EGP') ? toCurrency : fromCurrency;
                            if (foreignCur != null && foreignCur != 'EGP') {
                              final rate = await ExchangeRateDao().getRate(foreignCur);
                              setSheetState(() {
                                systemRate = rate;
                                rateCtrl.text = rate.toStringAsFixed(4);
                              });
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
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) => setSheetState(() {}),
                    decoration: inputDecor(
                        'المبلغ (بالعملة الأولى)', Icons.attach_money),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: rateCtrl,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
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
                    if (enteredAmount <= 0 || enteredRate <= 0 || fromCurrency == null || toCurrency == null) {
                      return const SizedBox.shrink();
                    }

                    double expectedReceived = 0;
                    double expectedGainLoss = 0;
                    final fromBalance = state.mainTreasury?.getBalance(fromCurrency!);
                    double bookRate = 1.0;

                    if (fromCurrency == 'EGP') {
                      bookRate = 1.0;
                      expectedReceived = enteredAmount / enteredRate;
                    } else {
                      if ((fromBalance?.balance ?? 0) > 0 && (fromBalance?.costBase ?? 0) > 0) {
                        bookRate = fromBalance!.costBase / fromBalance.balance;
                      } else if ((fromBalance?.bookRate ?? 0) > 1.0) {
                        bookRate = fromBalance!.bookRate;
                      } else if (systemRate != null && systemRate! > 1.0) {
                        bookRate = systemRate!;
                      } else {
                        bookRate = fromCurrency == 'USD'
                            ? 50.0
                            : (fromCurrency == 'EUR'
                                ? 54.0
                                : (fromCurrency == 'GBP' ? 63.0 : 50.0));
                      }
                      expectedReceived = enteredAmount * enteredRate;
                      final costBaseReleased = enteredAmount * bookRate;
                      expectedGainLoss = expectedReceived - costBaseReleased;
                    }

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.surface.withValues(alpha: 0.6) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('المبلغ المتوقع استلامه:',
                                  style: TextStyle(
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                      fontSize: 12,
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      fontFamily: 'Cairo')),
                              Text(
                                '${expectedReceived.toStringAsFixed(2)} $toCurrency',
                                style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                          if (fromCurrency != 'EGP') ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('التكلفة الدفترية المرجحة:',
                                    style: TextStyle(
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                        fontSize: 12,
                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                        fontFamily: 'Cairo')),
                                Text(
                                  '${(enteredAmount * bookRate).toStringAsFixed(2)} ج.م (بسعر ${bookRate.toStringAsFixed(4)})',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontSize: 12,
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
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
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                        fontSize: 12,
                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                        fontFamily: 'Cairo')),
                                Text(
                                  expectedGainLoss > 0.001
                                      ? '+${expectedGainLoss.toStringAsFixed(2)} ج.م (ربح)'
                                      : expectedGainLoss < -0.001
                                          ? '${expectedGainLoss.toStringAsFixed(2)} ج.م (خسارة)'
                                          : '0.00 ج.م (تعادل)',
                                  style: TextStyle(
                                      color: expectedGainLoss > 0.001
                                          ? (isDark ? Colors.greenAccent : const Color(0xFF15803D))
                                          : Colors.redAccent,
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
                      final availableBalance = fromCurrency != null
                          ? ((state.selectedTreasury ?? state.mainTreasury)?.getBalance(fromCurrency!)?.balance ?? 0.0)
                          : 0.0;
                      final enteredAmount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final isOverBalance = enteredAmount > availableBalance;
                      final isAmountValid = enteredAmount > 0 && !isOverBalance;
                      final enteredRate = double.tryParse(rateCtrl.text.trim()) ?? 0;
                      final isFormValid = fromCurrency != null &&
                          toCurrency != null &&
                          fromCurrency != toCurrency &&
                          (fromCurrency == 'EGP' || toCurrency == 'EGP') &&
                          isAmountValid &&
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
                                      'المبلغ المطلوب تحويله ($enteredAmount) أكبر من الرصيد المتوفر في الخزينة ($availableBalance $fromCurrency)',
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
                              style: _btnStyle(AppTheme.accent),
                              onPressed: (saving || !isFormValid)
                                  ? null
                                  : () async {
                                if (fromCurrency == null ||
                                    toCurrency == null ||
                                    amountCtrl.text.trim().isEmpty ||
                                    rateCtrl.text.trim().isEmpty) {
                                  _showSnackBar('الرجاء إدخال جميع الحقول');
                                  return;
                                }
                                if (fromCurrency == toCurrency) {
                                  _showSnackBar('لا يمكن التحويل لنفس العملة');
                                  return;
                                }
                                if (fromCurrency != 'EGP' &&
                                    toCurrency != 'EGP') {
                                  _showSnackBar(
                                      'يجب أن يكون التحويل من أو إلى الجنيه المصري');
                                  return;
                                }

                                final amountFrom =
                                    double.tryParse(amountCtrl.text.trim()) ??
                                        0;
                                final rate =
                                    double.tryParse(rateCtrl.text.trim()) ?? 0;

                                if (amountFrom <= 0 || rate <= 0) {
                                  _showSnackBar(
                                      'المبالغ وسعر الصرف يجب أن تكون أكبر من صفر');
                                  return;
                                }

                                double amountTo = 0;
                                if (fromCurrency == 'EGP') {
                                  amountTo = amountFrom / rate;
                                } else {
                                  amountTo = amountFrom * rate;
                                }

                                isSaving.value = true;
                                final cubit = context.read<TreasuryCubit>();
                                final treasuryId = int.tryParse(state.selectedTreasury?.id ?? '') ?? 0;

                                if (draftTx != null && draftTx.id != null) {
                                  // Update existing draft
                                  await cubit.updateDraftTransaction(
                                    transactionId: int.parse(draftTx.id!),
                                    amount: amountFrom,
                                    currency: fromCurrency,
                                    payload: {
                                      'from_currency': fromCurrency,
                                      'to_currency': toCurrency,
                                      'amount_from': amountFrom,
                                      'amount_to': amountTo,
                                      'exchange_rate': rate,
                                      'transfer_mode': 'exchange',
                                    },
                                    description: 'تحويل عملة من $fromCurrency ($amountFrom) إلى $toCurrency (${amountTo.toStringAsFixed(2)})',
                                  );
                                } else {
                                  // Save new draft
                                  await cubit.saveDraftCurrencyExchange(
                                    treasuryId: treasuryId,
                                    fromCurrency: fromCurrency!,
                                    toCurrency: toCurrency!,
                                    amountFrom: amountFrom,
                                    amountTo: amountTo,
                                    exchangeRate: rate,
                                  );
                                }
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                _showSnackBar(draftTx != null ? 'تم حفظ تعديلات المسودة' : 'تم حفظ تحويل العملة كمسودة');
                              },
                        child: Text(draftTx != null ? 'حفظ التعديلات' : 'حفظ التحويل',
                            style: const TextStyle(fontFamily: 'Cairo')),
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

  // ── Bottom Sheet: Transfer ──

  void _showTransferSheet(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCurrency = 'EGP';
    String? fromTreasuryId;
    String? toTreasuryId;
    final isSaving = ValueNotifier(false);

    final employeeTreasuries = state.employeeTreasuries;

    // Pre-select first two if available
    if (employeeTreasuries.length >= 2) {
      fromTreasuryId = employeeTreasuries[0].id;
      toTreasuryId = employeeTreasuries[1].id;
    } else if (employeeTreasuries.length == 1) {
      fromTreasuryId = employeeTreasuries[0].id;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final toOptions =
              employeeTreasuries.where((t) => t.id != fromTreasuryId).toList();

          return _buildSheetContainer(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تحويل عهدة',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  Text('من الخزنة',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 4),
                  _buildTreasuryDropdown(employeeTreasuries, (val) {
                    setSheetState(() {
                      fromTreasuryId = val;
                      if (toTreasuryId == val) {
                        toTreasuryId = null;
                      }
                    });
                  }, selectedValue: fromTreasuryId),
                  const SizedBox(height: 12),
                  Text('إلى الخزنة',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 4),
                  _buildTreasuryDropdown(toOptions, (val) {
                    setSheetState(() => toTreasuryId = val);
                  }, selectedValue: toTreasuryId),
                  const SizedBox(height: 12),
                  _buildFixedEGPCurrencyField(),
                  const SizedBox(height: 12),
                  _buildTextField(
                      amountCtrl, 'المبلغ', Icons.monetization_on_outlined,
                      isNumber: true, onChanged: (_) => setSheetState(() {})),
                  const SizedBox(height: 12),
                  _buildTextField(
                      descCtrl, 'الوصف (اختياري)', Icons.description_outlined),
                  const SizedBox(height: 8),
                  // Show available balance from source treasury
                  Builder(builder: (_) {
                    final fromTreasury = employeeTreasuries.firstWhereOrNull(
                        (t) => t.id == fromTreasuryId);
                    final availableBalance =
                        fromTreasury?.getBalance('EGP')?.balance ?? 0.0;
                    final enteredAmount =
                        double.tryParse(amountCtrl.text.trim()) ?? 0;
                    final isOverBalance =
                        enteredAmount > 0 && enteredAmount > availableBalance;
                    return Text(
                      'الرصيد المتاح: ${availableBalance.toStringAsFixed(2)} ج.م',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isOverBalance
                            ? Colors.redAccent
                            : (isDark ? AppTheme.textSecondary : Colors.black),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: isSaving,
                    builder: (_, saving, __) {
                      final fromTreasury = employeeTreasuries.firstWhereOrNull(
                          (t) => t.id == fromTreasuryId);
                      final availableBalance =
                          fromTreasury?.getBalance(selectedCurrency)?.balance ?? 0.0;
                      final enteredAmount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final isOverBalance =
                          enteredAmount > 0 && enteredAmount > availableBalance;

                      return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: _btnStyle(AppTheme.info),
                        onPressed: saving ||
                                fromTreasuryId == null ||
                                toTreasuryId == null ||
                                amountCtrl.text.trim().isEmpty ||
                                isOverBalance
                            ? null
                            : () async {
                                final text = amountCtrl.text.trim();
                                if (text.contains('.') &&
                                    (text.startsWith('.') ||
                                        text.endsWith('.'))) {
                                  _showSnackBar(
                                      'يجب كتابة أرقام قبل وبعد العلامة العشرية');
                                  return;
                                }
                                final amount = double.tryParse(text) ?? 0;
                                if (amount <= 0) {
                                  _showSnackBar(
                                      'المبلغ يجب أن يكون أكبر من صفر');
                                  return;
                                }
                                final fromName = employeeTreasuries
                                        .firstWhereOrNull(
                                            (t) => t.id == fromTreasuryId)
                                        ?.displayName ??
                                    '';
                                final toName = employeeTreasuries
                                        .firstWhereOrNull(
                                            (t) => t.id == toTreasuryId)
                                        ?.displayName ??
                                    '';
                                final autoDesc =
                                    'صادر إلى $toName | وارد من $fromName';
                                final finalDesc = descCtrl.text.trim().isEmpty
                                    ? autoDesc
                                    : descCtrl.text.trim();
                                isSaving.value = true;
                                await context
                                    .read<TreasuryCubit>()
                                    .transferCustody(
                                      fromTreasuryId: fromTreasuryId!,
                                      toTreasuryId: toTreasuryId!,
                                      currency: selectedCurrency,
                                      amount: amount,
                                      description: finalDesc,
                                    );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              },
                        child: const Text('تحويل',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
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

  void _showReturnCustodySheet(TreasuryLoaded state) {
    if (state.mainTreasury == null) {
      _showSnackBar('الخزينة الرئيسية غير موجودة');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCurrency = 'EGP';
    String? fromTreasuryId;
    final isSaving = ValueNotifier(false);

    final employeeTreasuries = state.employeeTreasuries;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return _buildSheetContainer(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إرجاع عهدة',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  Text('من عهدة الموظف',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 4),
                  _buildTreasuryDropdown(employeeTreasuries, (val) {
                    setSheetState(() {
                      fromTreasuryId = val;
                    });
                  }, selectedValue: fromTreasuryId),
                  const SizedBox(height: 12),
                  Text('إلى الخزنة',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.surface.withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      state.mainTreasury?.displayName ?? 'الخزينة الرئيسية',
                      style: TextStyle(
                          color: isDark ? AppTheme.textSecondary : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFixedEGPCurrencyField(),
                  const SizedBox(height: 12),
                  _buildTextField(
                      amountCtrl, 'المبلغ', Icons.monetization_on_outlined,
                      isNumber: true, onChanged: (_) => setSheetState(() {})),
                  const SizedBox(height: 12),
                  _buildTextField(
                      descCtrl, 'الوصف (اختياري)', Icons.description_outlined),
                  const SizedBox(height: 8),
                  // Show available balance from source treasury
                  Builder(builder: (_) {
                    final fromTreasury = employeeTreasuries.firstWhereOrNull(
                        (t) => t.id == fromTreasuryId);
                    final availableBalance =
                        fromTreasury?.getBalance('EGP')?.balance ?? 0.0;
                    final enteredAmount =
                        double.tryParse(amountCtrl.text.trim()) ?? 0;
                    final isOverBalance =
                        enteredAmount > 0 && enteredAmount > availableBalance;
                    return Text(
                      'الرصيد المتاح: ${availableBalance.toStringAsFixed(2)} ج.م',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isOverBalance
                            ? Colors.redAccent
                            : (isDark ? AppTheme.textSecondary : Colors.black),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: isSaving,
                    builder: (_, saving, __) {
                      final fromTreasury = employeeTreasuries.firstWhereOrNull(
                          (t) => t.id == fromTreasuryId);
                      final availableBalance =
                          fromTreasury?.getBalance('EGP')?.balance ?? 0.0;
                      final enteredAmount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final isOverBalance =
                          enteredAmount > 0 && enteredAmount > availableBalance;

                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: _btnStyle(Colors.deepOrange),
                          onPressed: saving ||
                                  fromTreasuryId == null ||
                                  amountCtrl.text.trim().isEmpty ||
                                  isOverBalance
                              ? null
                              : () async {
                                  final text = amountCtrl.text.trim();
                                if (text.contains('.') &&
                                    (text.startsWith('.') ||
                                        text.endsWith('.'))) {
                                  _showSnackBar(
                                      'يجب كتابة أرقام قبل وبعد العلامة العشرية');
                                  return;
                                }
                                final amount = double.tryParse(text) ?? 0;
                                if (amount <= 0) {
                                  _showSnackBar(
                                      'المبلغ يجب أن يكون أكبر من صفر');
                                  return;
                                }
                                final fromName = employeeTreasuries
                                        .firstWhereOrNull(
                                            (t) => t.id == fromTreasuryId)
                                        ?.displayName ??
                                    '';
                                final autoDesc = 'إرجاع عهدة من $fromName';
                                final finalDesc = descCtrl.text.trim().isEmpty
                                    ? autoDesc
                                    : descCtrl.text.trim();
                                isSaving.value = true;
                                await context
                                    .read<TreasuryCubit>()
                                    .returnCustody(
                                      fromTreasuryId: fromTreasuryId!,
                                      toTreasuryId: state.mainTreasury!.id!,
                                      currency: selectedCurrency!,
                                      amount: amount,
                                      description: finalDesc,
                                    );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              },
                        child: const Text('إرجاع العهدة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
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

  // ── Bottom Sheet: Expense (Enhanced with Category) ──

  void _showSimplifiedCustodyExpenseDialog(TreasuryModel treasury, TreasuryLoaded state) {
    SimplifiedCustodyExpenseDialog.show(
      context,
      custodyTreasury: treasury,
      availableCustodies: state.treasuries.where((t) => t.isEmployee).toList(),
      onSuccess: () {
        context.read<TreasuryCubit>().loadAll(reset: true);
      },
    );
  }

  void _showExpenseSheet(TreasuryLoaded state, {TreasuryTransactionModel? draftTx}) {
    final amountCtrl = TextEditingController(
      text: draftTx != null ? draftTx.amount.abs().toStringAsFixed(2) : '',
    );
    final descCtrl = TextEditingController(text: draftTx?.description ?? '');
    String selectedCurrency = draftTx?.currency ?? 'EGP';
    bool _currencyLocked = false;
    int? selectedCategoryId = draftTx != null ? int.tryParse(draftTx.categoryId ?? '') : null;
    String? selectedExpenseAccountId = draftTx?.payload?['expense_account_id']?.toString() ?? draftTx?.categoryId;
    String? selectedCostCenterId = draftTx?.costCenterId ?? draftTx?.payload?['cost_center_id']?.toString();
    dynamic selectedBranchId = draftTx?.branchId ?? draftTx?.payload?['branch_id'];
    String? selectedBranchName = draftTx?.branchName ?? draftTx?.payload?['branch_name'];
    String? _counterpartyType = 'category';
    int? _counterpartyId;
    String? _supplierId;
    String? _counterpartyName;
    SupplierModel? _selectedSupplier;
    PurchaseModel? _selectedInvoice;
    List<PurchaseModel> _invoices = [];
    bool _showCustomerSearch = false;
    bool _showSupplierSearch = false;
    bool _showClearingAgentSearch = false;
    bool _showShippingCompanySearch = false;
    bool _showShareholderSearch = false;
    bool _showCategorySearch = false;
    List<CustomerModel> _customerResults = [];
    List<SupplierModel> _supplierResults = [];
    List<ClearingAgentModel> _clearingAgentResults = [];
    List<ShippingCompanyModel> _shippingCompanyResults = [];
    List<ShareholderModel> _shareholderResults = [];
    final _customerSearchCtrl = TextEditingController();
    final _supplierSearchCtrl = TextEditingController();
    final _clearingAgentSearchCtrl = TextEditingController();
    final _shippingCompanySearchCtrl = TextEditingController();
    final _shareholderSearchCtrl = TextEditingController();
    final isSaving = ValueNotifier(false);

    // Pre-populate counterparty from draft
    if (draftTx != null) {
      if (draftTx.customerId != null && draftTx.customerId!.isNotEmpty && draftTx.customerId != '0') {
        _counterpartyType = 'customer';
        _counterpartyId = int.tryParse(draftTx.customerId!);
        _counterpartyName = draftTx.customerName;
        _customerSearchCtrl.text = draftTx.customerName ?? '';
      } else if (draftTx.supplierId != null && draftTx.supplierId!.isNotEmpty) {
        _counterpartyType = 'supplier';
        _supplierId = draftTx.supplierId;
        _counterpartyName = draftTx.supplierName;
        _supplierSearchCtrl.text = draftTx.supplierName ?? '';
      } else if (draftTx.clearingAgentId != null && draftTx.clearingAgentId!.isNotEmpty && draftTx.clearingAgentId != '0') {
        _counterpartyType = 'clearing_agent';
        _counterpartyId = int.tryParse(draftTx.clearingAgentId!);
        _counterpartyName = draftTx.clearingAgentName;
        _clearingAgentSearchCtrl.text = draftTx.clearingAgentName ?? '';
      } else if (draftTx.shippingCompanyId != null && draftTx.shippingCompanyId!.isNotEmpty && draftTx.shippingCompanyId != '0') {
        _counterpartyType = 'shipping_company';
        _counterpartyId = int.tryParse(draftTx.shippingCompanyId!);
        _counterpartyName = draftTx.shippingCompanyName;
        _shippingCompanySearchCtrl.text = draftTx.shippingCompanyName ?? '';
      } else if (draftTx.shareholderId != null && draftTx.shareholderId!.isNotEmpty) {
        _counterpartyType = 'shareholder';
        _supplierId = draftTx.shareholderId;
        _counterpartyName = draftTx.shareholderName;
        _shareholderSearchCtrl.text = draftTx.shareholderName ?? '';
      } else {
        _counterpartyType = 'category';
      }
    }

    final cubit = context.read<TreasuryCubit>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final currentState = ctx.watch<TreasuryCubit>().state;
            final expenseAccounts = currentState is TreasuryLoaded
                ? currentState.expenseAccounts
                : state.expenseAccounts;

            return _buildSheetContainer(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(draftTx != null ? 'تعديل مصروف — #${draftTx.id}' : 'صرف مصروف',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                              fontFamily: 'Cairo')),
                      const SizedBox(height: 16),

                      // ── بند الصرف والجهة المستفيدة ──
                      BeneficiarySelectorField(
                        initialBeneficiaryType: _counterpartyType == 'category'
                            ? 'expense'
                            : (_counterpartyType == 'supplier' ? 'all_suppliers' : _counterpartyType),
                        initialEntityId: _counterpartyType == 'supplier'
                            ? _supplierId
                            : (_counterpartyType == 'shareholder' ? _supplierId : _counterpartyId?.toString()),
                        initialEntityName: _counterpartyName,
                        initialExpenseAccountId: selectedExpenseAccountId,
                        initialCostCenterId: selectedCostCenterId,
                        expenseAccounts: expenseAccounts,
                        onAccountCreated: () => cubit.loadAll(reset: true),
                        onChanged: (selection) {
                          setSheetState(() {
                            if (selection.isExpense) {
                              _counterpartyType = 'category';
                              selectedExpenseAccountId = selection.expenseAccountId;
                              selectedCostCenterId = selection.costCenterId;
                              _supplierId = null;
                              _counterpartyId = null;
                              _counterpartyName = null;
                            } else if (selection.isSupplier) {
                              _counterpartyType = 'supplier';
                              _supplierId = selection.entityId;
                              _counterpartyId = null;
                              _counterpartyName = selection.entityName;
                              selectedExpenseAccountId = null;
                            } else if (selection.isShippingCompany) {
                              _counterpartyType = 'shipping_company';
                              _counterpartyId = int.tryParse(selection.entityId ?? '');
                              _supplierId = null;
                              _counterpartyName = selection.entityName;
                              selectedExpenseAccountId = null;
                            } else if (selection.isClearingAgent) {
                              _counterpartyType = 'clearing_agent';
                              _counterpartyId = int.tryParse(selection.entityId ?? '');
                              _supplierId = null;
                              _counterpartyName = selection.entityName;
                              selectedExpenseAccountId = null;
                            } else if (selection.isShareholder) {
                              _counterpartyType = 'shareholder';
                              _supplierId = selection.entityId;
                              _counterpartyId = null;
                              _counterpartyName = selection.entityName;
                              selectedExpenseAccountId = null;
                            }

                            if (selection.currency.isNotEmpty && selection.currency != 'MULTI') {
                              selectedCurrency = selection.currency;
                              _currencyLocked = true;
                            } else {
                              _currencyLocked = false;
                            }

                            if (selection.entityName != null && selection.entityName!.isNotEmpty) {
                              if (descCtrl.text.trim().isEmpty ||
                                  descCtrl.text.trim().startsWith('سداد لـ ') ||
                                  descCtrl.text.trim().startsWith('دفعه لـ ')) {
                                descCtrl.text = 'سداد لـ ${selection.entityName}';
                              }
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: AppTheme.glassBorder, height: 1),
                      const SizedBox(height: 12),

                      // ── 3. البيانات المالية (المبلغ والعملة والبيان) ──
                      _buildCurrencyDropdown((val) {
                        setSheetState(() => selectedCurrency = val);
                      },
                          selectedValue: selectedCurrency,
                          locked: _currencyLocked),
                      const SizedBox(height: 12),
                      _buildTextField(
                          amountCtrl, 'المبلغ', Icons.monetization_on_outlined,
                          isNumber: true,
                          onChanged: (_) => setSheetState(() {})),
                      const SizedBox(height: 12),
                      _buildTextField(descCtrl, 'الوصف / البيان (اختياري)',
                          Icons.description_outlined),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<bool>(
                        valueListenable: isSaving,
                        builder: (_, saving, __) {
                          final availableBalance = (state.selectedTreasury ?? state.mainTreasury)
                                  ?.getBalance(selectedCurrency)
                                  ?.balance ??
                              0.0;
                          final enteredAmount =
                              double.tryParse(amountCtrl.text.trim()) ?? 0;
                          final isOverBalance = enteredAmount > availableBalance;
                          final isAmountValid =
                              enteredAmount > 0 && !isOverBalance;

                          final isExpenseAccountValid = _counterpartyType != 'category' ||
                              (selectedExpenseAccountId != null &&
                                  expenseAccounts.any((a) {
                                    if (a['id'].toString() != selectedExpenseAccountId) return false;
                                    final code = (a['account_code'] ?? a['code'] ?? '').toString().trim();
                                    return code.startsWith('31') &&
                                        !code.startsWith('32') &&
                                        (a['is_leaf'] == true || a['allow_posting'] == true);
                                  }));

                          final isFormValid = isAmountValid &&
                              _counterpartyType != null &&
                              isExpenseAccountValid &&
                              !(_counterpartyType == 'category' &&
                                  (selectedExpenseAccountId == null ||
                                   selectedCostCenterId == null ||
                                   selectedCostCenterId!.trim().isEmpty)) &&
                              !(_counterpartyType == 'shareholder' &&
                                  _supplierId == null) &&
                              !((_counterpartyType == 'customer' ||
                                      _counterpartyType == 'clearing_agent' ||
                                      _counterpartyType == 'shipping_company') &&
                                  _counterpartyId == null);

                          return Column(
                            children: [
                              // Double-Entry Accounting Preview Card
                              if (selectedExpenseAccountId != null || _counterpartyType != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF091A2D) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.auto_stories_outlined, size: 14, color: AppTheme.primary),
                                          SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'معاينة القيد المحاسبي المزدوج (Double-Entry Preview)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Text(
                                            'مدين (Dr): ',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.success,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          Expanded(
                                            child: Builder(
                                              builder: (_) {
                                                final bName = selectedBranchName;
                                                final branchText = bName != null && bName.isNotEmpty ? ' [الفرع: $bName]' : '';
                                                if (_counterpartyType == 'category') {
                                                  final match = expenseAccounts.firstWhereOrNull(
                                                    (a) => a['id'].toString() == selectedExpenseAccountId,
                                                  );
                                                  final name = match != null
                                                      ? AccountModel.fromMap(match).displayName
                                                      : 'حساب المصروف';
                                                  final cc = selectedCostCenterId != null && selectedCostCenterId!.isNotEmpty
                                                      ? CostCenterHelper.fromId(selectedCostCenterId)
                                                      : null;
                                                  final ccText = cc != null ? ' [المركز: ${cc.nameAr}]' : '';
                                                  return Text(
                                                    '$name$branchText$ccText',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: isDark ? Colors.white : Colors.black,
                                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                        fontFamily: 'Cairo'),
                                                  );
                                                } else {
                                                  return Text(
                                                    '${_counterpartyName ?? 'الحساب المقابل'}$branchText',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: isDark ? Colors.white : Colors.black,
                                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                        fontFamily: 'Cairo'),
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Text(
                                            'دائن (Cr): ',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.danger,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              (state.selectedTreasury ?? state.mainTreasury)?.name ?? 'الخزينة الحالية',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? Colors.white70 : Colors.black87,
                                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
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
                                          'المبلغ المطلوب صرفه ($enteredAmount) أكبر من الرصيد المتوفر في الخزينة ($availableBalance $selectedCurrency)',
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
                                child: ElevatedButton.icon(
                                  style: _btnStyle(AppTheme.warning),
                                  onPressed: (saving || !isFormValid)
                                      ? null
                                      : () async {
                                      if (amountCtrl.text.trim().isEmpty) return;
                                      final text = amountCtrl.text.trim();
                                      if (text.contains('.') &&
                                          (text.startsWith('.') || text.endsWith('.'))) {
                                        _showSnackBar('يجب كتابة أرقام قبل وبعد العلامة العشرية');
                                        return;
                                      }
                                      final amount = double.tryParse(text) ?? 0;
                                      if (amount <= 0) {
                                        _showSnackBar('المبلغ يجب أن يكون أكبر من صفر');
                                        return;
                                      }
                                      if (_counterpartyType == 'category') {
                                        if (selectedCostCenterId == null || selectedCostCenterId!.trim().isEmpty) {
                                          _showSnackBar('يرجى تحديد مركز التكلفة / القسم المستفيد');
                                          return;
                                        }
                                        if (selectedExpenseAccountId == null) {
                                          _showSnackBar('يرجى اختيار حساب المصروف من شجرة الحسابات');
                                          return;
                                        }
                                        final selectedAcc = expenseAccounts.firstWhereOrNull(
                                          (a) => a['id'].toString() == selectedExpenseAccountId,
                                        );
                                        final accCode = (selectedAcc?['account_code'] ?? selectedAcc?['code'] ?? '').toString().trim();
                                        if (accCode.isEmpty || !accCode.startsWith('31') || accCode.startsWith('32')) {
                                          _showSnackBar('حساب المصروف غير صالح. يجب اختيار حساب نقدي ضمن مجموعة المصروفات التشغيلية والإدارية (31)');
                                          return;
                                        }
                                        if (selectedAcc?['is_leaf'] != true && selectedAcc?['allow_posting'] != true) {
                                          _showSnackBar('يجب اختيار حساب تحليلي فرعي يقبل الترحيل');
                                          return;
                                        }
                                      }
                                      isSaving.value = true;
                                      String finalDesc = descCtrl.text.trim();

                                      if (draftTx != null && draftTx.id != null) {
                                        // Update existing draft
                                        await cubit.updateDraftTransaction(
                                          transactionId: int.parse(draftTx.id!),
                                          amount: amount,
                                          currency: selectedCurrency,
                                          description: finalDesc.isEmpty ? null : finalDesc,
                                          categoryId: _counterpartyType == 'category' ? null : selectedCategoryId,
                                          customerId: _counterpartyType == 'customer' ? _counterpartyId : null,
                                          supplierId: _counterpartyType == 'supplier' ? _supplierId : null,
                                          clearingAgentId: _counterpartyType == 'clearing_agent' ? _counterpartyId : null,
                                          shippingCompanyId: _counterpartyType == 'shipping_company' ? _counterpartyId : null,
                                          shareholderId: _counterpartyType == 'shareholder' ? _supplierId : null,
                                          expenseAccountId: selectedExpenseAccountId != null ? int.tryParse(selectedExpenseAccountId!) : null,
                                          costCenterId: selectedCostCenterId,
                                          branchId: selectedBranchId,
                                        );
                                      } else {
                                        // Save new draft
                                        await cubit.saveDraftExpense(
                                          treasuryId: int.tryParse(state.selectedTreasury!.id!) ?? 0,
                                          currency: selectedCurrency,
                                          amount: amount,
                                          description: finalDesc,
                                          categoryId: _counterpartyType == 'category' ? null : selectedCategoryId,
                                          expenseAccountId: selectedExpenseAccountId,
                                          customerId: _counterpartyType == 'customer' ? _counterpartyId : null,
                                          supplierId: _counterpartyType == 'supplier' ? _supplierId : null,
                                          clearingAgentId: _counterpartyType == 'clearing_agent' ? _counterpartyId : null,
                                          shippingCompanyId: _counterpartyType == 'shipping_company' ? _counterpartyId : null,
                                          shareholderId: _counterpartyType == 'shareholder' ? _supplierId : null,
                                          invoice: _selectedInvoice,
                                          costCenterId: selectedCostCenterId,
                                          branchId: selectedBranchId,
                                        );
                                      }

                                      if (ctx.mounted) Navigator.of(ctx).pop();
                                      _showSnackBar(draftTx != null ? 'تم حفظ تعديلات المسودة بنجاح' : 'تم حفظ المصروف كمسودة بنجاح');
                                    },
                              icon: saving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save_outlined),
                              label: Text(saving ? 'جارٍ الحفظ...' : (draftTx != null ? 'حفظ التعديلات' : 'حفظ المصروف'),
                                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
);
  }

  Widget _expenseSmallBtn(
      BuildContext ctx, String label, bool active, VoidCallback onTap) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? AppTheme.warning.withValues(alpha: 0.15) : const Color(0xFFFEF3C7))
              : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? AppTheme.warning : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: active
                      ? (isDark ? AppTheme.warning : const Color(0xFFB45309))
                      : (isDark ? AppTheme.textSecondary : Colors.black),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 12)),
        ),
      ),
    );
  }

  Widget _expenseCustomerSearch(
      BuildContext ctx,
      TextEditingController ctrl,
      List<CustomerModel> results,
      Future<void> Function(String) onSearch,
      void Function(CustomerModel) onSelect) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: ctrl,
        onChanged: (v) => onSearch(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن عميل...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final c = results[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => onSelect(c),
                  title: Text(c.name,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(
                      'رصيد: ${AppUtils.formatCurrency(c.balance, c.currency)}',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _expenseSupplierSearch(
      BuildContext ctx,
      TextEditingController ctrl,
      List<SupplierModel> results,
      Future<void> Function(String) onSearch,
      void Function(SupplierModel) onSelect) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: ctrl,
        onChanged: (v) => onSearch(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مورد...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final s = results[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => onSelect(s),
                  title: Text(s.name,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(
                      'رصيد: ${AppUtils.formatCurrency(s.outstandingBalance, s.currency)}',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _expenseClearingAgentSearch(
      BuildContext ctx,
      TextEditingController ctrl,
      List<ClearingAgentModel> results,
      Future<void> Function(String) onSearch,
      void Function(ClearingAgentModel) onSelect) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: ctrl,
        onChanged: (v) => onSearch(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مخلص...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final a = results[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => onSelect(a),
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
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _expenseShippingCompanySearch(
      BuildContext ctx,
      TextEditingController ctrl,
      List<ShippingCompanyModel> results,
      Future<void> Function(String) onSearch,
      void Function(ShippingCompanyModel) onSelect) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: ctrl,
        onChanged: (v) => onSearch(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن شركة شحن...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final s = results[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => onSelect(s),
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
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _expenseShareholderSearch(
      BuildContext ctx,
      TextEditingController ctrl,
      List<ShareholderModel> results,
      Future<void> Function(String) onSearch,
      void Function(ShareholderModel) onSelect) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: ctrl,
        onChanged: (v) => onSearch(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مساهم...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final s = results[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => onSelect(s),
                  title: Text(s.name,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.totalDepositsEgp - s.totalWithdrawalsEgp != 0)
                        Text(
                            'جنية: ${AppUtils.formatCurrency(s.totalDepositsEgp - s.totalWithdrawalsEgp)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success)),
                      if (s.totalDepositsUsd - s.totalWithdrawalsUsd != 0)
                        Text(
                            'دولار: ${AppUtils.formatCurrency(s.totalDepositsUsd - s.totalWithdrawalsUsd)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success)),
                      if (s.totalDepositsEur - s.totalWithdrawalsEur != 0)
                        Text(
                            'يورو: ${AppUtils.formatCurrency(s.totalDepositsEur - s.totalWithdrawalsEur)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success)),
                      if (s.totalDepositsGbp - s.totalWithdrawalsGbp != 0)
                        Text(
                            'استرليني: ${AppUtils.formatCurrency(s.totalDepositsGbp - s.totalWithdrawalsGbp)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success)),
                      if (s.totalDepositsEgp - s.totalWithdrawalsEgp == 0 &&
                          s.totalDepositsUsd - s.totalWithdrawalsUsd == 0 &&
                          s.totalDepositsEur - s.totalWithdrawalsEur == 0 &&
                          s.totalDepositsGbp - s.totalWithdrawalsGbp == 0)
                        Text('رصيد: 0',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  void _showAddCategoryInlineSheet(
      BuildContext ctx,
      TextEditingController nameCtrl,
      void Function(void Function()) setSheetState,
      Function(String name, String color) onSave) {
    final colors = [
      '#10B981',
      '#F59E0B',
      '#448AFF',
      '#EC4899',
      '#8B5CF6',
      '#6B7280',
      '#FF5252',
      '#00E5FF',
    ];
    String selectedColor = colors.first;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setInnerState) {
          final isDark = Theme.of(ctx2).brightness == Brightness.dark;
          return _buildSheetContainer(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إضافة تصنيف جديد',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 12),
                  _buildTextField(nameCtrl, 'اسم التصنيف', Icons.label_outline),
                  const SizedBox(height: 12),
                  Text('اختر لون',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((hex) {
                      final c = _parseHexColor(hex);
                      final isSelected = selectedColor == hex;
                      return GestureDetector(
                        onTap: () => setInnerState(() => selectedColor = hex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: isDark ? Colors.white : Colors.black, width: 2)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                        color: c.withValues(alpha: 0.5),
                                        blurRadius: 8)
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: _btnStyle(AppTheme.primary),
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty) return;
                        onSave(nameCtrl.text.trim(), selectedColor);
                        Navigator.of(ctx2).pop();
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('إضافة',
                          style: TextStyle(fontFamily: 'Cairo')),
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

  // ── Bottom Sheet: Return ──

  void _showReturnSheet(TreasuryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCurrency = 'EGP';
    final isSaving = ValueNotifier(false);

    if (state.mainTreasury == null) {
      _showSnackBar('لا توجد خزنة رئيسية للإرجاع إليها');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => _buildSheetContainer(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إرجاع عهدة',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                _buildFixedEGPCurrencyField(),
                const SizedBox(height: 12),
                _buildTextField(
                    amountCtrl, 'المبلغ', Icons.monetization_on_outlined,
                    isNumber: true, onChanged: (_) => setSheetState(() {})),
                const SizedBox(height: 12),
                _buildTextField(
                    descCtrl, 'الوصف (اختياري)', Icons.description_outlined),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: isSaving,
                  builder: (_, saving, __) => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: _btnStyle(AppTheme.accent),
                      onPressed: saving
                          ? null
                          : () async {
                              if (amountCtrl.text.trim().isEmpty) return;
                              final text = amountCtrl.text.trim();
                              if (text.contains('.') &&
                                  (text.startsWith('.') ||
                                      text.endsWith('.'))) {
                                _showSnackBar(
                                    'يجب كتابة أرقام قبل وبعد العلامة العشرية');
                                return;
                              }
                              final amount = double.tryParse(text) ?? 0;
                              if (amount <= 0) {
                                _showSnackBar('المبلغ يجب أن يكون أكبر من صفر');
                                return;
                              }
                              isSaving.value = true;
                              await context.read<TreasuryCubit>().returnCustody(
                                    fromTreasuryId: state.selectedTreasury!.id!,
                                    toTreasuryId: state.mainTreasury!.id!,
                                    currency: selectedCurrency,
                                    amount: amount,
                                    description: descCtrl.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                      child: const Text('إرجاع',
                          style: TextStyle(fontFamily: 'Cairo')),
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

  // ── Bottom Sheet: Manage Categories (Admin) ──

  void _showManageCategoriesSheet(TreasuryLoaded state) {
    final cubit = context.read<TreasuryCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ManageCategoriesSheet(
        cubit: cubit,
        categories: state.categories,
      ),
    );
  }

  // ── Sheet Container ──

  Widget _buildSheetContainer({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xF0051B2B) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // ── Shared Widgets ──

  Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon,
      {bool isNumber = false, ValueChanged<String>? onChanged}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: isNumber
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))]
            : null,
        style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            fontFamily: 'Cairo'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              fontSize: 13,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo'),
          prefixIcon: Icon(icon, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTypeDropdown(ValueChanged<String?> onChanged,
      {String? selectedValue, bool mainExists = false}) {
    final types = mainExists ? ['employee'] : ['employee', 'main'];
    return _dropdown<String>(
      types,
      (v) => v,
      (v) => v == 'employee' ? 'عهدة موظف' : 'خزنة رئيسية',
      'اختر النوع',
      onChanged,
      selectedValue: selectedValue,
    );
  }

  Widget _buildFutureDropdown(Future<List<Map<String, dynamic>>> future,
      ValueChanged<String?> onChanged,
      {String? selectedValue}) {
    return _futureDropdown<Map<String, dynamic>>(
      future,
      (items) => items,
      (e) => e['id'].toString(),
      (e) => e['full_name']?.toString() ?? '',
      'اختر الموظف',
      onChanged,
      selectedValue: selectedValue,
    );
  }

  // FIX 3: null-safe conversion من String لـ int
  Widget _buildEmployeeTreasuryDropdown(
      List<TreasuryModel> treasuries, ValueChanged<int?> onChanged,
      {int? selectedValue}) {
    final filtered = treasuries.where((t) => t.isEmployee).toList();
    return _dropdown<TreasuryModel>(
      filtered,
      (t) => t.id!,
      (t) => t.displayName,
      'اختر الخزنة',
      (val) {
        if (val == null) {
          onChanged(null);
          return;
        }
        final parsed = int.tryParse(val);
        onChanged(parsed);
      },
      selectedValue: selectedValue?.toString(),
    );
  }

  Widget _buildTreasuryDropdown(
      List<TreasuryModel> treasuries, ValueChanged<String?> onChanged,
      {String? selectedValue}) {
    return _dropdown<TreasuryModel>(
      treasuries,
      (t) => t.id!,
      (t) => t.displayName,
      'اختر الخزنة المستهدفة',
      (val) => onChanged(val),
      selectedValue: selectedValue,
    );
  }

  Widget _buildCurrencyDropdown(ValueChanged<String> onChanged,
      {String? selectedValue, bool locked = false}) {
    return _dropdown<String>(
      TreasuryDao.supportedCurrencies,
      (c) => c,
      (c) => c,
      'اختر العملة',
      locked
          ? (_) {}
          : (val) => onChanged(val ?? TreasuryDao.supportedCurrencies.first),
      selectedValue: selectedValue,
    );
  }

  Widget _buildFixedEGPCurrencyField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
          const SizedBox(width: 8),
          Text(
            'العملة: جنيه مصري (EGP)',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(
    List<ExpenseCategoryModel> categories,
    ValueChanged<int?> onChanged, {
    int? selectedValue,
  }) {
    return _dropdown<ExpenseCategoryModel>(
      categories,
      (c) => c.id,
      (c) => c.name,
      'اختر التصنيف (اختياري)',
      (val) {
        if (val == null) {
          onChanged(null);
          return;
        }
        onChanged(int.tryParse(val));
      },
      selectedValue: selectedValue?.toString(),
    );
  }

  Widget _dropdown<T>(
    List<T> items,
    dynamic Function(T) value,
    String Function(T) label,
    String hint,
    ValueChanged<String?> onChanged, {
    String? selectedValue,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xDD05192D) : Colors.white,
          value: selectedValue,
          hint: Text(hint,
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontFamily: 'Cairo')),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: '${value(item)}',
              child: Text(label(item),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Cairo')),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _futureDropdown<T>(
    Future<List<T>> future,
    List<T> Function(List<T>) identity,
    String Function(T) value,
    String Function(T) label,
    String hint,
    ValueChanged<String?> onChanged, {
    String? selectedValue,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<T>>(
      future: future,
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            child: Text('لا توجد بيانات',
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo')),
          );
        }
        final items = snap.data!;
        return _dropdown<T>(items, value, label, hint, onChanged,
            selectedValue: selectedValue);
      },
    );
  }

  ButtonStyle _btnStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo'),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.success.withValues(alpha: 0.8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold)),
        Text(value,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: (isBold || !isDark) ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}

// ─── Manage Categories Bottom Sheet (Separate Widget) ─────────────────────

class _ManageCategoriesSheet extends StatefulWidget {
  final TreasuryCubit cubit;
  final List<ExpenseCategoryModel> categories;

  const _ManageCategoriesSheet({
    required this.cubit,
    required this.categories,
  });

  @override
  State<_ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<_ManageCategoriesSheet> {
  static const List<String> _colorOptions = [
    '#10B981',
    '#F59E0B',
    '#448AFF',
    '#EC4899',
    '#8B5CF6',
    '#6B7280',
    '#FF5252',
    '#00E5FF',
  ];

  TreasuryCubit get _cubit => widget.cubit;
  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<TreasuryCubit, TreasuryState>(
        builder: (ctx, state) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final categories =
              state is TreasuryLoaded ? state.categories : widget.categories;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xF0051B2B) : Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, -4),
                            ),
                          ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Row(children: [
                          const Icon(Icons.category_outlined,
                              color: AppTheme.neonCyan, size: 20),
                          const SizedBox(width: 8),
                          Text('إدارة تصنيفات المصروفات',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                  fontFamily: 'Cairo')),
                          const Spacer(),
                          InkWell(
                            onTap: () => _showAddCategoryDialog(),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add,
                                  color: AppTheme.primary, size: 18),
                            ),
                          ),
                        ]),
                      ),
                      Divider(height: 1, color: isDark ? AppTheme.border : const Color(0xFFE2E8F0)),
                      if (categories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('لا توجد تصنيفات',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo')),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(12),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemCount: categories.length,
                            itemBuilder: (_, i) =>
                                _buildCategoryItem(categories[i]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryItem(ExpenseCategoryModel cat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catColor = _parseColor(cat.color);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cat.isActive
                ? catColor.withValues(alpha: 0.2)
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: catColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: catColor.withValues(alpha: 0.4), blurRadius: 6),
            ],
          ),
        ),
        title: Text(cat.name,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cat.isActive ? (isDark ? Colors.white : Colors.black) : AppTheme.textMuted,
                fontFamily: 'Cairo')),
        trailing: const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildCurrencyDropdown(ValueChanged<String> onChanged,
      {String? selectedValue, bool locked = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xDD05192D) : Colors.white,
          value: selectedValue,
          hint: Text('اختر العملة',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'Cairo')),
          items: TreasuryDao.supportedCurrencies
              .map((c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(c,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ))
              .toList(),
          onChanged: locked
              ? null
              : (val) =>
                  onChanged(val ?? TreasuryDao.supportedCurrencies.first),
        ),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    String selectedColor = _colorOptions.first;
    String selectedCurrency = 'EGP';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) {
          final isDark = Theme.of(ctx2).brightness == Brightness.dark;
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xF0051B2B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إضافة تصنيف جديد',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: nameCtrl,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'اسم التصنيف',
                      hintStyle: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo'),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildCurrencyDropdown((val) {
                  setInner(() => selectedCurrency = val);
                }, selectedValue: selectedCurrency),
                const SizedBox(height: 12),
                Text('اختر لون',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                        fontFamily: 'Cairo')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _colorOptions.map((hex) {
                    final c = _parseColor(hex);
                    final isSelected = selectedColor == hex;
                    return GestureDetector(
                      onTap: () => setInner(() => selectedColor = hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: isDark ? Colors.white : Colors.black, width: 2)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                      color: c.withValues(alpha: 0.5),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      await _cubit.createCategory(
                        name: nameCtrl.text.trim(),
                        color: selectedColor,
                        currency: selectedCurrency,
                      );
                      if (!ctx2.mounted) return;
                      final state = _cubit.state;
                      if (state is TreasuryLoaded && state.errorMessage != null)
                        return;
                      Navigator.of(ctx2).pop();
                    },
                    child: const Text('إضافة',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditCategoryDialog(ExpenseCategoryModel cat) {
    final nameCtrl = TextEditingController(text: cat.name);
    String selectedColor = cat.color;
    String selectedCurrency = cat.currency;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) {
          final isDark = Theme.of(ctx2).brightness == Brightness.dark;
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xF0051B2B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تعديل: ${cat.name}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: nameCtrl,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'اسم التصنيف',
                      hintStyle: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo'),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildCurrencyDropdown((val) {
                  setInner(() => selectedCurrency = val);
                }, selectedValue: selectedCurrency),
                const SizedBox(height: 12),
                Text('اختر لون',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                        fontFamily: 'Cairo')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _colorOptions.map((hex) {
                    final c = _parseColor(hex);
                    final isSelected = selectedColor == hex;
                    return GestureDetector(
                      onTap: () => setInner(() => selectedColor = hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: isDark ? Colors.white : Colors.black, width: 2)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                      color: c.withValues(alpha: 0.5),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.info,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      await _cubit.updateCategory(
                        id: cat.id,
                        name: nameCtrl.text.trim(),
                        color: selectedColor,
                        currency: selectedCurrency,
                      );
                      if (!ctx2.mounted) return;
                      final state = _cubit.state;
                      if (state is TreasuryLoaded && state.errorMessage != null)
                        return;
                      Navigator.of(ctx2).pop();
                    },
                    child: const Text('حفظ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleCategory(ExpenseCategoryModel cat) async {
    await _cubit.updateCategory(
      id: cat.id,
      isActive: !cat.isActive,
    );
  }

  void _deleteCategory(ExpenseCategoryModel cat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xF0051B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('حذف التصنيف',
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد من حذف "${cat.name}"؟',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('إلغاء',
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () async {
              await _cubit.deleteCategory(cat.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حذف',
                style: TextStyle(
                    color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

class _TransactionActions extends StatelessWidget {
  final TreasuryTransactionModel tx;
  final bool isAdmin;
  final VoidCallback onView;
  final VoidCallback? onViewJournalEntry;
  final VoidCallback onDelete;
  final VoidCallback? onEditDraft;
  final VoidCallback? onEditConfirmed;
  final VoidCallback? onConfirmDraft;
  final VoidCallback? onDeleteDraft;

  const _TransactionActions({
    required this.tx,
    required this.isAdmin,
    required this.onView,
    this.onViewJournalEntry,
    required this.onDelete,
    this.onEditDraft,
    this.onEditConfirmed,
    this.onConfirmDraft,
    this.onDeleteDraft,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    if (tx.isDraft) {
      if (onEditDraft != null) {
        buttons.add(
          _ActionIcon(
            icon: Icons.edit_outlined,
            tooltip: 'تعديل المسودة',
            color: AppTheme.primary,
            onTap: onEditDraft!,
          ),
        );
      }
      if (onConfirmDraft != null) {
        buttons.add(
          _ActionIcon(
            icon: Icons.check_circle_outline,
            tooltip: 'تأكيد وترحيل المسودة',
            color: AppTheme.success,
            onTap: onConfirmDraft!,
          ),
        );
      }
      if (onDeleteDraft != null) {
        buttons.add(
          _ActionIcon(
            icon: Icons.delete_outline,
            tooltip: 'حذف المسودة',
            isWarning: true,
            onTap: onDeleteDraft!,
          ),
        );
      }
    } else {
      buttons.add(
        _ActionIcon(
          icon: Icons.remove_red_eye_outlined,
          tooltip: 'عرض تفاصيل الحركة',
          onTap: onView,
        ),
      );

      if (onEditConfirmed != null) {
        buttons.add(
          _ActionIcon(
            icon: Icons.edit_outlined,
            tooltip: 'تعديل الحركة (محمي بكلمة مرور)',
            color: const Color(0xFF0284C7),
            onTap: onEditConfirmed!,
          ),
        );
      }

      if (onViewJournalEntry != null) {
        buttons.add(
          _ActionIcon(
            icon: Icons.book_outlined,
            tooltip: 'عرض القيد المحاسبي',
            onTap: onViewJournalEntry!,
          ),
        );
      }
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: buttons,
        );
      },
    );
  }
}

class _ActionIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isWarning;
  final Color? color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    this.isWarning = false,
    this.color,
    required this.onTap,
  });

  @override
  State<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends State<_ActionIcon> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = widget.color ??
        (isDark ? Colors.white.withValues(alpha: 140) : const Color(0xFF475569));
    final hoverColor = widget.color ??
        (widget.isWarning
            ? AppTheme.danger
            : (isDark ? AppTheme.primary : const Color(0xFF0284C7)));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovered ? hoverColor : defaultColor,
            ),
          ),
        ),
      ),
    );
  }
}
