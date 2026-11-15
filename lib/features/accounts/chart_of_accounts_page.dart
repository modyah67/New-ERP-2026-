import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/widgets/password_verification_dialog.dart';
import '../../data/dao/account_dao.dart';
import '../../data/models/account_model.dart';
import '../../data/services/account_validation_service.dart';
import 'services/advanced_coa_pdf_service.dart';
import 'widgets/account_journal_entries_dialog.dart';
import '../../data/services/account_ledger_service.dart';
import '../../data/services/opening_balance_gl_sync_service.dart';
import '../accounting/account_statement_pdf_service.dart';

class ChartOfAccountsPage extends StatelessWidget {
  const ChartOfAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChartOfAccountsCubit()..loadAccounts(),
      child: const _ChartOfAccountsView(),
    );
  }
}

class _ChartOfAccountsView extends StatefulWidget {
  const _ChartOfAccountsView();

  @override
  State<_ChartOfAccountsView> createState() => _ChartOfAccountsViewState();
}

class _ChartOfAccountsViewState extends State<_ChartOfAccountsView> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedNodes = {};
  String _selectedTypeFilter = 'all'; // 'all', 'asset', 'liability', 'equity', 'revenue', 'expense'
  bool _isSyncingBalances = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  Future<void> _manualSyncOpeningBalances() async {
    if (_isSyncingBalances) return;
    setState(() => _isSyncingBalances = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text(
              'جاري مزامنة الأرصدة الافتتاحية للموردين والعملاء مع القيود المحاسبية...',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ],
        ),
        backgroundColor: Color(0xFF6366F1),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      await OpeningBalanceGlSyncService.instance.syncAllEntities();
      if (!mounted) return;
      await context.read<ChartOfAccountsCubit>().loadAccounts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تمت مزامنة الأرصدة الافتتاحية وتحديث شجرة الحسابات بنجاح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء مزامنة الأرصدة: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingBalances = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeCubit.isCurrentDark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    final contentWidth = screenWidth < 1200 ? 1200.0 : screenWidth;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.lightBackground,
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: contentWidth,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 12 : 24,
              isMobile ? 56 : 24,
              isMobile ? 12 : 24,
              isMobile ? 16 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildInstructionBanner(),
            const SizedBox(height: 16),
            Expanded(
              child: BlocConsumer<ChartOfAccountsCubit, ChartOfAccountsState>(
                listener: (ctx, state) {
                  if (state is ChartOfAccountsError) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          state.message,
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  }
                },
                builder: (_, state) {
                  if (state is ChartOfAccountsLoading) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.accent),
                          SizedBox(height: 12),
                          Text(
                            'جاري تحميل شجرة الحسابات...',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (state is ChartOfAccountsLoaded) {
                    return _buildContent(state);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = ThemeCubit.isCurrentDark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.of(context).size.width;
        final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
        final isNarrow = effectiveW < 1350;

        final titleSection = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.account_tree_rounded,
                  color: AppTheme.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'شجرة الحسابات (دليل الحسابات - 5 مستويات هرمية)',
                    style: TextStyle(
                      fontSize: isNarrow ? 16 : 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'الهيكل المالي المحاسبي الشامل (المعيار القياسي المعتمد: 5 مستويات هرمية) — مصنف ومترجم بالكامل',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        );

        final actionButtons = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildHeaderActionButton(
              icon: Icons.unfold_more_rounded,
              label: 'توسيع الكل',
              color: Colors.blueGrey,
              onPressed: _expandAll,
            ),
            _buildHeaderActionButton(
              icon: Icons.unfold_less_rounded,
              label: 'طي الكل',
              color: Colors.blueGrey,
              onPressed: _collapseAll,
            ),
            _buildHeaderActionButton(
              icon: Icons.refresh_rounded,
              label: 'تحديث',
              color: AppTheme.accent,
              onPressed: () => context.read<ChartOfAccountsCubit>().loadAccounts(),
            ),
            _buildHeaderActionButton(
              icon: Icons.sync_rounded,
              label: 'مزامنة الأرصدة الافتتاحية',
              color: const Color(0xFF6366F1),
              isLoading: _isSyncingBalances,
              onPressed: _manualSyncOpeningBalances,
            ),
            _buildHeaderActionButton(
              icon: Icons.picture_as_pdf_rounded,
              label: 'طباعة الدليل (PDF)',
              color: const Color(0xFF0D9488),
              onPressed: () {
                final state = context.read<ChartOfAccountsCubit>().state;
                if (state is ChartOfAccountsLoaded && state.accounts.isNotEmpty) {
                  AdvancedCoaPdfService.printPdf(state.accounts);
                }
              },
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleSection,
              const SizedBox(height: 12),
              actionButtons,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleSection),
            const SizedBox(width: 16),
            actionButtons,
          ],
        );
      },
    );
  }

  Widget _buildInstructionBanner() {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.accent.withValues(alpha: 0.08) : const Color(0xFFCCFBF1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.accent.withValues(alpha: 0.25) : const Color(0xFF0D9488).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, color: isDark ? AppTheme.accent : const Color(0xFF0F766E), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '💡 نصيحة: انقر نقراً مزدوجاً (Double Click) على أي حساب أو فرع رئيسي لعرض كافة قيود اليومية والحركات المالية المندرجة تحته مباشرة.',
              style: TextStyle(
                color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                fontSize: 12.5,
                fontFamily: 'Cairo',
                fontWeight: isDark ? FontWeight.w500 : FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        elevation: 0,
      ),
    );
  }

  Widget _buildContent(ChartOfAccountsLoaded state) {
    final isDark = ThemeCubit.isCurrentDark;
    final accounts = state.accounts;
    if (accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 54, color: isDark ? AppTheme.textSecondary : Colors.black54),
            const SizedBox(height: 12),
            Text(
              'لا توجد حسابات مسجلة في شجرة الحسابات',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddAccountDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة حساب أول',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }

    final query = _searchController.text.trim();
    final isSearching = query.isNotEmpty;

    // 1. Core financial tree (Roots 1, 2, 3, 4) strictly restricted to primary financial categories
    final fullTree = _buildTree(accounts);
    final filteredTree = _filterTree(fullTree, _searchController.text, _selectedTypeFilter);

    // 2. Search query exception for system & intermediary accounts:
    List<AccountNode> systemSearchResults = [];
    if (isSearching) {
      final q = query.toLowerCase();
      final tf = _selectedTypeFilter.toLowerCase();

      final matchingSystemAccounts = accounts.where((account) {
        final code = account.code.trim();
        final type = account.type.trim().toLowerCase();
        final isSystemAccount = code.startsWith('9') || type == 'system';

        if (!isSystemAccount) return false;
        if (code == '9' || code == '91' || code == '9000') return false;

        final matchesType = tf == 'all' || type == tf;
        if (!matchesType) return false;

        final nameAr = account.displayName.toLowerCase();
        final nameEn = account.name.toLowerCase();

        return nameAr.contains(q) ||
            nameEn.contains(q) ||
            code.toLowerCase().contains(q) ||
            'حسابات نظامية'.contains(q) ||
            'نظامي'.contains(q) ||
            'وسيط'.contains(q);
      }).toList();

      matchingSystemAccounts.sort((a, b) => a.code.compareTo(b.code));

      systemSearchResults = matchingSystemAccounts.map((acc) {
        return AccountNode(account: acc, children: []);
      }).toList();
    }

    final displayTree = [...filteredTree, ...systemSearchResults];

    // Calculate totals per category
    final stats = _calculateCategoryStats(accounts);
    final visibleCount = stats.values.fold<int>(0, (sum, item) => sum + item.count);

    return Column(
      children: [
        // Category KPI Stats
        _buildStatsRow(stats, visibleCount > 0 ? visibleCount : accounts.length),
        const SizedBox(height: 14),

        // Search & Type Filter Bar
        _buildSearchAndFilterBar(),
        const SizedBox(height: 14),

        // Tree view
        Expanded(
          child: displayTree.isEmpty
              ? _buildNoResultsState()
              : Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFCBD5E1)),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: displayTree.length,
                      itemBuilder: (context, index) {
                        return _buildAccountNodeWidget(
                          node: displayTree[index],
                          level: 0,
                          allAccounts: accounts,
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Map<String, ({int count, double balance, Map<String, double> balancesByCurrency})> _calculateCategoryStats(
      List<AccountModel> accounts) {
    final Map<String, ({int count, double balance, Map<String, double> balancesByCurrency})> map = {
      'asset': (count: 0, balance: 0.0, balancesByCurrency: {}),
      'liability': (count: 0, balance: 0.0, balancesByCurrency: {}),
      'equity': (count: 0, balance: 0.0, balancesByCurrency: {}),
      'revenue': (count: 0, balance: 0.0, balancesByCurrency: {}),
      'expense': (count: 0, balance: 0.0, balancesByCurrency: {}),
    };

    for (final a in accounts) {
      final typeKey = a.type.toLowerCase();
      if (map.containsKey(typeKey)) {
        final cur = map[typeKey]!;
        final newBalancesByCurrency = Map<String, double>.from(cur.balancesByCurrency);
        for (final entry in a.balancesByCurrency.entries) {
          newBalancesByCurrency[entry.key] = (newBalancesByCurrency[entry.key] ?? 0.0) + entry.value;
        }
        map[typeKey] = (
          count: cur.count + 1,
          balance: cur.balance + a.balance,
          balancesByCurrency: newBalancesByCurrency,
        );
      }
    }
    return map;
  }

  Widget _buildStatsRow(
      Map<String, ({int count, double balance, Map<String, double> balancesByCurrency})> stats, int totalCount) {
    final assetStat = stats['asset'] ?? (count: 0, balance: 0.0, balancesByCurrency: {});
    final liabStat = stats['liability'] ?? (count: 0, balance: 0.0, balancesByCurrency: {});
    final equityStat = stats['equity'] ?? (count: 0, balance: 0.0, balancesByCurrency: {});
    final revStat = stats['revenue'] ?? (count: 0, balance: 0.0, balancesByCurrency: {});
    final expStat = stats['expense'] ?? (count: 0, balance: 0.0, balancesByCurrency: {});

    return Row(
      children: [
        _buildStatCard(
          title: 'إجمالي الحسابات',
          value: '$totalCount حساب',
          subtitle: 'الدليل الكامل',
          color: AppTheme.accent,
          icon: Icons.account_tree,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'الأصول (Assets)',
          value: '${assetStat.count} حساب',
          subtitle: _buildCurrencySubtitle(assetStat.balancesByCurrency, assetStat.balance),
          color: AppTheme.success,
          icon: Icons.account_balance_wallet,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'الخصوم (Liabilities)',
          value: '${liabStat.count} حساب',
          subtitle: _buildCurrencySubtitle(liabStat.balancesByCurrency, liabStat.balance),
          color: Colors.orangeAccent,
          icon: Icons.credit_card,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'حقوق الملكية (Equity)',
          value: '${equityStat.count} حساب',
          subtitle: _buildCurrencySubtitle(equityStat.balancesByCurrency, equityStat.balance),
          color: Colors.purpleAccent,
          icon: Icons.business_center,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'الإيرادات (Revenues)',
          value: '${revStat.count} حساب',
          subtitle: _buildCurrencySubtitle(revStat.balancesByCurrency, revStat.balance),
          color: const Color(0xFF00E5FF),
          icon: Icons.trending_up,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'المصروفات (Expenses)',
          value: '${expStat.count} حساب',
          subtitle: _buildCurrencySubtitle(expStat.balancesByCurrency, expStat.balance),
          color: AppTheme.danger,
          icon: Icons.trending_down,
        ),
      ],
    );
  }

  String _buildCurrencySubtitle(Map<String, double> balancesByCurrency, double fallbackBalance) {
    if (balancesByCurrency.isEmpty) {
      return _currencyFormat.format(fallbackBalance);
    }
    final activeCurrencies = balancesByCurrency.entries.where((e) => e.value.abs() >= 0.01).toList();
    if (activeCurrencies.length <= 1) {
      if (activeCurrencies.length == 1) {
        final curr = activeCurrencies.first.key;
        final displayCurr = (curr == 'EGP' || curr == 'ج.م') ? '' : ' $curr';
        return '${_currencyFormat.format(activeCurrencies.first.value)}$displayCurr';
      }
      return _currencyFormat.format(fallbackBalance);
    }
    return activeCurrencies
        .map((e) {
          final curr = (e.key == 'EGP' || e.key == 'ج.م') ? '' : '${e.key}: ';
          return '$curr${_currencyFormat.format(e.value)}';
        })
        .join(' | ');
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final isDark = ThemeCubit.isCurrentDark;
    final valueColor = isDark
        ? color
        : (color == AppTheme.accent
            ? const Color(0xFF0284C7)
            : (color == AppTheme.success
                ? const Color(0xFF15803D)
                : (color == Colors.orangeAccent
                    ? const Color(0xFFC2410C)
                    : (color == Colors.purpleAccent
                        ? const Color(0xFF7E22CE)
                        : (color == const Color(0xFF00E5FF)
                            ? const Color(0xFF0284C7)
                            : color)))));

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? color.withValues(alpha: 0.2)
                : const Color(0xFFCBD5E1),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (isDark ? color : valueColor).withValues(alpha: isDark ? 0.12 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: isDark ? color : valueColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 10.5,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          color: valueColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black,
                            fontSize: 10,
                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFCBD5E1),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          // Search input
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
                onChanged: (val) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث بالكود أو الاسم العربي أو الإنجليزي...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF64748B),
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: isDark ? AppTheme.accent : const Color(0xFF0D9488), size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: isDark ? Colors.white70 : Colors.black87, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? AppTheme.accent : Colors.black, width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Type Filters
          Wrap(
            spacing: 6,
            children: [
              _buildTypeChip('all', 'الكل', null),
              _buildTypeChip('asset', 'أصول', isDark ? AppTheme.success : const Color(0xFF15803D)),
              _buildTypeChip('liability', 'خصوم', isDark ? Colors.orangeAccent : const Color(0xFFC2410C)),
              _buildTypeChip('equity', 'حقوق ملكية', isDark ? Colors.purpleAccent : const Color(0xFF7E22CE)),
              _buildTypeChip('revenue', 'إيرادات', isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7)),
              _buildTypeChip('expense', 'مصروفات', isDark ? AppTheme.danger : const Color(0xFFDC2626)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, Color? color) {
    final isDark = ThemeCubit.isCurrentDark;
    final isSelected = _selectedTypeFilter == type;
    final activeColor = color ?? (isDark ? AppTheme.primary : const Color(0xFF0284C7));

    return InkWell(
      onTap: () => setState(() => _selectedTypeFilter = type),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: isDark ? 0.2 : 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? activeColor
                    : (isDark ? Colors.white70 : Colors.black),
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded,
              size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text(
            'لا توجد حسابات مطابقة لمعايير البحث والتصفية',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              _selectedTypeFilter = 'all';
              setState(() {});
            },
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('إعادة ضبط البحث',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }



  void _expandAll() {
    final state = context.read<ChartOfAccountsCubit>().state;
    if (state is ChartOfAccountsLoaded) {
      setState(() {
        for (final a in state.accounts) {
          if (a.id != null) _expandedNodes[a.id!] = true;
        }
      });
    }
  }

  void _collapseAll() {
    setState(() {
      _expandedNodes.clear();
    });
  }

  List<AccountNode> _buildTree(List<AccountModel> accounts) {
    final Map<String, AccountNode> nodeMap = {};
    final Map<String, List<String>> parentToChildrenMap = {};
    final rootNodes = <AccountNode>[];
    final processedIds = <String>{};

    // Build code-to-id map for prefix-based parent fallback resolution
    final codeToIdMap = <String, String>{};
    const obsoleteLegacyCodes = {
      '112', '1121', '1112', '1113', '1114', '1115', '1116',
      '1213', '1214', '12122', '12123', '12124',
      '1222', '1223', '1224', '1225', '1232', '1233', '1234', '1235',
      '1242', '1243', '1244', '1245', '1246', '1247', '1248',
      '124101', '124102',
      '2123', '2124', '2125', '2126',
    };

    for (final account in accounts) {
      final id = account.id ?? '';
      final code = account.code.trim();
      if (obsoleteLegacyCodes.contains(code)) continue;
      if (id.isNotEmpty && code.isNotEmpty) {
        codeToIdMap[code] = id;
      }
    }

    for (final account in accounts) {
      if (account.isArchived || !account.isActive) continue;
      if (obsoleteLegacyCodes.contains(account.code.trim())) continue;
      final id = account.id ?? '';
      if (id.isEmpty || processedIds.contains(id)) continue;
      processedIds.add(id);

      final node = AccountNode(account: account, children: []);
      nodeMap[id] = node;

      var parentId = account.parentId;
      // Fallback: resolve parent by code prefix if parentId is missing
      if ((parentId == null || parentId.isEmpty || !codeToIdMap.values.contains(parentId)) &&
          account.code.trim().length > 1) {
        final code = account.code.trim();
        for (int len = code.length - 1; len >= 1; len--) {
          final prefix = code.substring(0, len);
          if (codeToIdMap.containsKey(prefix)) {
            parentId = codeToIdMap[prefix];
            break;
          }
        }
      }

      if (parentId != null && parentId.isNotEmpty) {
        parentToChildrenMap.putIfAbsent(parentId, () => []).add(id);
      }
    }

    for (final account in accounts) {
      final id = account.id ?? '';
      if (id.isEmpty) continue;

      final node = nodeMap[id];
      if (node == null) continue;

      final childIds = parentToChildrenMap[id] ?? [];
      for (final childId in childIds) {
        final childNode = nodeMap[childId];
        if (childNode != null && !node.children.contains(childNode)) {
          node.children.add(childNode);
        }
      }
      // Keep children sorted in canonical numerical code order
      node.children.sort((a, b) => a.account.code.compareTo(b.account.code));

      var parentId = account.parentId;
      if ((parentId == null || parentId.isEmpty || !nodeMap.containsKey(parentId)) &&
          account.code.trim().length > 1) {
        final code = account.code.trim();
        for (int len = code.length - 1; len >= 1; len--) {
          final prefix = code.substring(0, len);
          if (codeToIdMap.containsKey(prefix)) {
            parentId = codeToIdMap[prefix];
            break;
          }
        }
      }

      if (parentId == null || parentId.isEmpty || !nodeMap.containsKey(parentId)) {
        if (!rootNodes.contains(node)) {
          rootNodes.add(node);
        }
      }
    }

    // Filter Level 1 root accounts:
    // Strictly display the core 4 primary accounting roots in the Level 1 list:
    // 1 - الأصول (Assets - Range 1)
    // 2 - الخصوم وحقوق الملكية (Liabilities & Equity - Range 2)
    // 3 - المصروفات والتكاليف (Expenses & Costs - Range 3)
    // 4 - الإيرادات (Revenues - Range 4)
    final visibleRoots = rootNodes.where((node) {
      final code = node.account.code.trim();
      final type = node.account.type.trim().toLowerCase();
      // Exclude root group 9 and system/intermediary root groups from Level 1 display
      if (code == '9' || code.startsWith('9') || type == 'system') {
        return false;
      }
      return true;
    }).toList();

    int getCategoryPriority(AccountModel acc) {
      final code = acc.code.trim();
      final type = acc.type.trim().toLowerCase();

      if (code.startsWith('1')) return 1;
      if (code.startsWith('2')) return 2;
      if (code.startsWith('3')) return 3;
      if (code.startsWith('4')) return 4;
      if (code.startsWith('5')) return 5;
      if (code.startsWith('6') || code.startsWith('7')) return 6;
      if (code.startsWith('9')) return 7;

      if (type == 'asset') return 1;
      if (type == 'liability') return 2;
      if (type == 'equity') return 3;
      if (type == 'revenue') return 4;
      if (type == 'expense') return 5;
      if (type == 'system') return 7;

      return 99;
    }

    visibleRoots.sort((a, b) {
      final prioA = getCategoryPriority(a.account);
      final prioB = getCategoryPriority(b.account);
      if (prioA != prioB) {
        return prioA.compareTo(prioB);
      }
      return a.account.code.compareTo(b.account.code);
    });
    return visibleRoots;
  }

  List<AccountNode> _filterTree(
      List<AccountNode> nodes, String query, String typeFilter) {
    final q = query.trim().toLowerCase();
    final tf = typeFilter.toLowerCase();

    if (q.isEmpty && tf == 'all') {
      return nodes;
    }

    List<AccountNode> filterNodes(List<AccountNode> list) {
      final result = <AccountNode>[];

      for (final node in list) {
        final account = node.account;
        final nameAr = account.displayName.toLowerCase();
        final nameEn = account.name.toLowerCase();
        final code = account.code.toLowerCase();
        final type = account.type.toLowerCase();

        final matchesQuery = q.isEmpty ||
            nameAr.contains(q) ||
            nameEn.contains(q) ||
            code.contains(q) ||
            account.levelLabel.toLowerCase().contains(q);

        final matchesType = tf == 'all' || type == tf;

        final filteredChildren = filterNodes(node.children);

        if ((matchesQuery && matchesType) || filteredChildren.isNotEmpty) {
          result.add(AccountNode(
            account: account,
            children: filteredChildren,
          ));
        }
      }
      return result;
    }

    return filterNodes(nodes);
  }

  List<AccountModel> _collectAllBranchAccounts(AccountNode node) {
    final list = <AccountModel>[node.account];
    for (final child in node.children) {
      list.addAll(_collectAllBranchAccounts(child));
    }
    return list;
  }

  bool _is2100Branch(AccountModel account, List<AccountModel> allAccounts) {
    final code = account.code.trim();
    if (code == '2100' || code == '2101' || code == '2102' || code == '2105') {
      return true;
    }
    String? currentParentId = account.parentId;
    int depth = 0;
    while (currentParentId != null && depth < 10) {
      final parent = allAccounts.where((a) => a.id == currentParentId).firstOrNull;
      if (parent == null) break;
      if (parent.code.trim() == '2100') return true;
      currentParentId = parent.parentId;
      depth++;
    }
    return false;
  }

  Widget _buildAccountNodeWidget({
    required AccountNode node,
    required int level,
    required List<AccountModel> allAccounts,
    AccountModel? parentAccount,
    bool isOperationalChild = false,
  }) {
    final isDark = ThemeCubit.isCurrentDark;
    final account = node.account;
    final hasChildren = node.children.isNotEmpty;
    final isSearching = _searchController.text.trim().isNotEmpty;
    final isExpanded = isSearching || (_expandedNodes[account.id ?? ''] ?? false);
    final isActive = account.isActive && !account.isArchived;

    // 5-level evaluation rule (1 digit = L1, 2 = L2, 3 = L3, 4 = L4, 5 = L5).
    final isOperational = isOperationalChild ||
        account.isOperationalSubEntity ||
        (parentAccount != null && parentAccount.evaluatedLevel >= 5) ||
        (level >= 4 && account.code.trim().length > 5);

    final typeColor = _getAccountTypeColor(account.type);
    final typeLabel = _getAccountTypeLabel(account.type);

    // Clamped visual level for padding/indentation (0 to 5 max)
    final clampedIndent = level.clamp(0, 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            if (hasChildren) {
              setState(() {
                _expandedNodes[account.id ?? ''] = !isExpanded;
              });
            } else {
              _openAccountJournalEntries(node);
            }
          },
          onDoubleTap: () => _openAccountJournalEntries(node),
          hoverColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (clampedIndent * 22.0),
              left: 16.0,
              top: 7,
              bottom: 7,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse icon or visual tree connector for leaf nodes
                if (hasChildren)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedNodes[account.id ?? ''] = !isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_left_rounded,
                        size: 18,
                        color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                      ),
                    ),
                  )
                else if (isOperational)
                  Container(
                    width: 22,
                    alignment: Alignment.center,
                    child: Text(
                      '└──',
                      style: TextStyle(
                        color: isDark ? AppTheme.accent.withValues(alpha: 0.8) : const Color(0xFF0284C7),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (level > 0)
                  Container(
                    width: 22,
                    alignment: Alignment.center,
                    child: Text(
                      '├──',
                      style: TextStyle(
                        color: isDark ? Colors.white.withValues(alpha: 0.25) : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 22),
                const SizedBox(width: 8),

                // Account Type Icon
                Icon(
                  _getAccountTypeIcon(account.type),
                  size: 18,
                  color: typeColor,
                ),
                const SizedBox(width: 10),

                // Code Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? AppTheme.accent : const Color(0xFF0284C7)).withValues(alpha: isDark ? 0.12 : 0.1),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: (isDark ? AppTheme.accent : const Color(0xFF0284C7)).withValues(alpha: isDark ? 0.25 : 0.4)),
                  ),
                  child: Text(
                    account.code,
                    style: TextStyle(
                      color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Explicit Strict 4-Level Badge or Operational Sub-Entity Badge
                _buildAccountLevelBadge(account, isOperational: isOperational),
                const SizedBox(width: 10),

                // Arabic Display Name
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.displayName,
                          style: TextStyle(
                            color: !isActive ? Colors.orange : (isDark ? Colors.white : Colors.black),
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (account.name.isNotEmpty &&
                          account.name != account.displayName) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${account.name})',
                          style: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF475569),
                            fontSize: 11,
                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                      if (hasChildren) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${node.children.length} فرعي',
                            style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Balance
                // _buildBalanceWidget(node),
                // const SizedBox(width: 10),

                // Type Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // View Journal Entries button
                    IconButton(
                      icon: const Icon(Icons.receipt_long_rounded, size: 17),
                      color: AppTheme.accent,
                      onPressed: () => _openAccountJournalEntries(node),
                      tooltip: 'عرض قيود وحركات الحساب (دبل كليك)',
                    ),
                    // Dedicated PDF Print / Export button for this node/branch
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      color: const Color(0xFFEF4444),
                      onPressed: () => _printAccountStatementDirect(node),
                      tooltip: 'طباعة وتصدير كشف حساب PDF',
                    ),
                    // Add child account (allowed for Levels 1 to 4; hidden for Level 5 leaves, operational sub-entities, and system accounts)
                    if (!_is2100Branch(account, allAccounts) && !isOperational && account.evaluatedLevel < 5 && !account.code.trim().startsWith('9'))
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 17),
                        color: AppTheme.success,
                        onPressed: () => _showAddAccountDialog(
                          context,
                          parentAccount: account,
                        ),
                        tooltip: 'إضافة حساب فرعي تحت هذا الحساب',
                      ),
                    // Edit account name button (strictly limited to analytical/operational accounts; Levels 1-3 and system accounts are protected)
                    if (!account.isArchived &&
                        (account.evaluatedLevel >= 4 || isOperational || account.code.trim().length >= 4) &&
                        !account.code.trim().startsWith('9') &&
                        account.type.trim().toLowerCase() != 'system')
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        color: AppTheme.accent,
                        onPressed: () async {
                          final verified = await showPasswordVerificationDialog(
                            context,
                            title: 'تأكيد كلمة المرور لتعديل الحساب',
                            subtitle:
                                'يرجى إدخال كلمة المرور لتعديل مسمى الحساب "${account.displayName}" (${account.code})',
                          );
                          if (!verified || !mounted) return;
                          _showEditAccountDialog(context, account);
                        },
                        tooltip: 'تعديل مسمى الحساب',
                      ),
                    // Delete account button (strictly limited to analytical/operational accounts; Levels 1-3 and system accounts are protected)
                    if (!account.isArchived &&
                        (account.evaluatedLevel >= 4 || isOperational || account.code.trim().length >= 4) &&
                        !account.code.trim().startsWith('9') &&
                        account.type.trim().toLowerCase() != 'system')
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        color: AppTheme.danger,
                        onPressed: () async {
                          final verified = await showPasswordVerificationDialog(
                            context,
                            title: 'تأكيد كلمة المرور لحذف الحساب',
                            subtitle:
                                'يرجى إدخال كلمة المرور لحذف الحساب "${account.displayName}" (${account.code})',
                          );
                          if (!verified || !mounted) return;
                          _handleDeleteAccount(context, node, allAccounts);
                        },
                        tooltip: 'حذف هذا الحساب',
                      ),
                  ],
                ),

                if (!isActive)
                  const Tooltip(
                    message: '⚠ حساب معطل (مؤرشف)',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Children nodes (clamped level up to 5, propagating operational sub-entity status)
        if (isExpanded && hasChildren)
          ...node.children.map(
            (child) => _buildAccountNodeWidget(
              node: child,
              level: (level + 1).clamp(0, 5),
              allAccounts: allAccounts,
              parentAccount: account,
              isOperationalChild: account.evaluatedLevel >= 5 || isOperational,
            ),
          ),
      ],
    );
  }

  void _openAccountJournalEntries(AccountNode node) {
    final allBranchAccounts = _collectAllBranchAccounts(node);
    final isBranch = node.children.isNotEmpty;

    AccountJournalEntriesDialog.show(
      context,
      account: node.account,
      allBranchAccounts: allBranchAccounts,
      isBranch: isBranch,
    );
  }

  Future<void> _printAccountStatementDirect(AccountNode node) async {
    final allBranchAccounts = _collectAllBranchAccounts(node);
    final isBranch = node.children.isNotEmpty;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'جاري تحضير كشف الحساب (${node.account.code} - ${node.account.entityHeaderTitle})...',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      List<String> accountIds = [];
      if (isBranch && allBranchAccounts.isNotEmpty) {
        accountIds = allBranchAccounts
            .map((a) => a.id ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      } else if (node.account.id != null) {
        accountIds = [node.account.id!];
      }

      if (accountIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد بيانات حساب للطباعة', style: TextStyle(fontFamily: 'Cairo')),
            ),
          );
        }
        return;
      }

      final result = await AccountLedgerService().getAccountLedger(
        accountIds: accountIds,
        accountType: node.account.type,
      );

      await AccountStatementPdfService.printLedgerStatement(
        account: node.account,
        entries: result.entries,
        openingBalance: result.openingBalance,
        totalDebit: result.totalDebit,
        totalCredit: result.totalCredit,
        closingBalance: result.closingBalance,
        currency: result.currency.isNotEmpty ? result.currency : 'EGP',
        isBranch: isBranch,
      );
    } catch (e) {
      debugPrint('Error direct printing account statement: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر طباعة كشف الحساب: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  IconData _getAccountTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'asset':
        return Icons.account_balance_wallet_rounded;
      case 'liability':
        return Icons.credit_card_rounded;
      case 'equity':
        return Icons.business_center_rounded;
      case 'revenue':
        return Icons.trending_up_rounded;
      case 'expense':
        return Icons.trending_down_rounded;
      case 'system':
        return Icons.tune_rounded;
      default:
        return Icons.account_balance_rounded;
    }
  }

  Color _getAccountTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'asset':
        return AppTheme.success;
      case 'liability':
        return Colors.orangeAccent;
      case 'equity':
        return Colors.purpleAccent;
      case 'revenue':
        return const Color(0xFF00E5FF);
      case 'expense':
        return AppTheme.danger;
      case 'system':
        return Colors.tealAccent;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _getAccountTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'asset':
        return 'أصول';
      case 'liability':
        return 'خصوم';
      case 'equity':
        return 'حقوق ملكية';
      case 'revenue':
        return 'إيرادات';
      case 'expense':
        return 'مصروفات';
      case 'system':
        return 'حسابات نظامية';
      default:
        return type;
    }
  }

  /// Builds a clean badge strictly honoring the 4-level standard:
  /// Level 1: مستوى 1 - رئيسي (Indigo)
  /// Level 2: مستوى 2 - مجموعة (Sky Blue)
  /// Level 3: مستوى 3 - فرعي (Amber)
  /// Builds a clean badge strictly honoring the 5-level standard:
  /// Level 1: مستوى 1 - رئيسي (Indigo)
  /// Level 2: مستوى 2 - مجموعة (Sky Blue)
  /// Level 3: مستوى 3 - فرعي (Amber)
  /// Level 4: مستوى 4 - تحليلي (Teal - terminal analytical control groups)
  /// Level 5: مستوى 5 - حساب ترحيل (Emerald - standard for all posting accounts & dynamic sub-ledgers)
  Widget _buildAccountLevelBadge(AccountModel account, {bool isOperational = false}) {
    final isDark = ThemeCubit.isCurrentDark;
    final cleanCode = account.code.trim();
    final isSystemAccount = cleanCode.startsWith('9') || account.type.trim().toLowerCase() == 'system';

    if (isSystemAccount) {
      final badgeColor = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: badgeColor.withValues(alpha: isDark ? 0.35 : 0.4),
            width: 0.8,
          ),
        ),
        child: Text(
          'حسابات نظامية / خلفية',
          style: TextStyle(
            color: badgeColor,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            fontFamily: 'Cairo',
          ),
        ),
      );
    }

    final lvl = account.evaluatedLevel.clamp(1, 5);
    final label = account.levelLabel;

    Color badgeColor;
    switch (lvl) {
      case 1:
        badgeColor = isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA); // Indigo 400 / 700
        break;
      case 2:
        badgeColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1); // Sky 400 / 700
        break;
      case 3:
        badgeColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309); // Amber 400 / 700
        break;
      case 4:
        badgeColor = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E); // Teal 400 / 700
        break;
      case 5:
      default:
        badgeColor = isDark ? const Color(0xFF34D399) : const Color(0xFF047857); // Emerald 400 / 700
        break;
    }

    final badgeBg = badgeColor.withValues(alpha: isDark ? 0.12 : 0.10);
    final borderColor = badgeColor.withValues(alpha: isDark ? 0.3 : 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontWeight: FontWeight.bold,
          fontSize: 10.5,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  void _showAddAccountDialog(BuildContext parentCtx, {AccountModel? parentAccount}) {
    final isDark = ThemeCubit.isCurrentDark;
    final codeController = TextEditingController();
    final arabicNameController = TextEditingController();
    final englishNameController = TextEditingController();
    String currentType = parentAccount?.type ?? 'asset';
    String? selectedParentId = parentAccount?.id;

    final cubit = parentCtx.read<ChartOfAccountsCubit>();
    final rawAccounts = cubit.state is ChartOfAccountsLoaded
        ? (cubit.state as ChartOfAccountsLoaded).accounts
        : <AccountModel>[];

    final uniqueAccounts = <String, AccountModel>{};
    for (var acc in rawAccounts) {
      if (acc.id != null) {
        uniqueAccounts[acc.id!] = acc;
      }
    }
    final allAccounts = uniqueAccounts.values.toList();

    if (selectedParentId != null && !allAccounts.any((a) => a.id == selectedParentId)) {
      selectedParentId = null;
    }

    showDialog(
      context: parentCtx,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
          ),
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: [
              const Icon(Icons.add_circle_outline,
                  color: AppTheme.success, size: 22),
              const SizedBox(width: 10),
              Text(
                parentAccount != null
                    ? 'إضافة حساب فرعي تحت (${parentAccount.displayName})'
                    : 'إضافة حساب جديد إلى شجرة الحسابات',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          ),
          content: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: 'كود الحساب المحاسبي (مثال: 1011)*',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                    ),
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),

                  // Arabic Name (Primary)
                  TextField(
                    controller: arabicNameController,
                    decoration: InputDecoration(
                      labelText: 'اسم الحساب بالعربي (مثال: بنك مصر - جاري)*',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                    ),
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),

                  // English Name (Optional)
                  TextField(
                    controller: englishNameController,
                    decoration: InputDecoration(
                      labelText: 'اسم الحساب بالإنجليزي (اختياري)',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                    ),
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),

                  // Type
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: currentType,
                    decoration: InputDecoration(
                      labelText: 'نوع الحساب المحاسبي',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    items: [
                      DropdownMenuItem(
                          value: 'asset',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('أصول (Asset)',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'liability',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('خصوم (Liability)',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'equity',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('حقوق ملكية (Equity)',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'revenue',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('إيرادات (Revenue)',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'expense',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('مصروفات (Expense)',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo')))),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        currentType = value ?? 'asset';
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Parent Account selector
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: selectedParentId,
                    decoration: InputDecoration(
                      labelText: 'الحساب الأب (الفرع الرئيسي التابع له)',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            'حساب رئيسي (بدون أب)',
                            style: TextStyle(
                                color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo'),
                          ),
                        ),
                      ),
                      ...allAccounts.map(
                        (acc) => DropdownMenuItem<String?>(
                          value: acc.id,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              '${acc.code} - ${acc.displayName}',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo'),
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedParentId = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'إلغاء',
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo'),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                final arName = arabicNameController.text.trim();
                final enName = englishNameController.text.trim();

                if (code.isEmpty) {
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text('يرجى إدخال كود الحساب'),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                  return;
                }

                if (arName.isEmpty && enName.isEmpty) {
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text('يرجى إدخال اسم الحساب بالعربي'),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                  return;
                }

                final primaryName = enName.isNotEmpty ? enName : arName;
                final arabicName = arName.isNotEmpty ? arName : enName;

                final error = await cubit.addAccount(
                  code: code,
                  name: primaryName,
                  accountName: arabicName,
                  type: currentType.trim(),
                  parentId: selectedParentId,
                );

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();

                if (!parentCtx.mounted) return;
                if (error != null) {
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    SnackBar(
                      content: Text(error),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text('تم إضافة الحساب بنجاح'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text(
                'إضافة الحساب',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAccountDialog(
    BuildContext parentCtx,
    AccountModel account,
  ) {
    final isDark = ThemeCubit.isCurrentDark;
    final arabicNameController =
        TextEditingController(text: account.displayName);
    final englishNameController = TextEditingController(
        text: account.name != account.displayName ? account.name : '');
    final cubit = parentCtx.read<ChartOfAccountsCubit>();

    showDialog(
      context: parentCtx,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_note_rounded,
                  color: AppTheme.accent, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'تعديل مسمى الحساب',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Locked Account Metadata Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              account.code,
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildAccountLevelBadge(account),
                          const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded,
                                  color: isDark ? Colors.white38 : const Color(0xFF64748B), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'كود ثابت',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : const Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '🔒 كود الحساب وتصنيفه مقفلان لحماية التسلسل المحاسبي وسلامة قيود اليومية المرتبطة.',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : const Color(0xFF475569),
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Arabic Name Field
                TextField(
                  controller: arabicNameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'اسم الحساب بالعربي *',
                    hintText: 'أدخل المسمى العربي للحساب...',
                    labelStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        fontFamily: 'Cairo'),
                    prefixIcon: const Icon(Icons.title_rounded,
                        color: AppTheme.accent, size: 18),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                    focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                  ),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 14),

                // English Name Field (Optional)
                TextField(
                  controller: englishNameController,
                  decoration: InputDecoration(
                    labelText: 'اسم الحساب بالإنجليزي (اختياري)',
                    hintText: 'Account English name (optional)...',
                    labelStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo'),
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.language_rounded,
                        color: isDark ? Colors.white38 : const Color(0xFF64748B), size: 18),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
                    focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                  ),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'إلغاء',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo'),
            ),
          ),

          ElevatedButton.icon(
            onPressed: () async {
              final arName = arabicNameController.text.trim();
              final enName = englishNameController.text.trim();

              if (arName.isEmpty) {
                ScaffoldMessenger.of(parentCtx).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال اسم الحساب بالعربي'),
                    backgroundColor: AppTheme.danger,
                  ),
                );
                return;
              }

              final error = await cubit.updateAccountName(
                id: account.id!,
                arabicName: arName,
                englishName: enName.isNotEmpty ? enName : null,
              );

              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();

              if (!parentCtx.mounted) return;
              if (error != null) {
                ScaffoldMessenger.of(parentCtx).showSnackBar(
                  SnackBar(
                    content: Text(error),
                    backgroundColor: AppTheme.danger,
                  ),
                );
              } else {
                ScaffoldMessenger.of(parentCtx).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'تم تعديل مسمى الحساب (${account.code} - $arName) بنجاح',
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                    backgroundColor: AppTheme.success,
                  ),
                );
              }
            },
            icon: const Icon(Icons.save_rounded, size: 17),
            label: const Text(
              'حفظ التعديلات',
              style: TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(
      BuildContext pageCtx, AccountNode node, List<AccountModel> allAccounts) async {
    final account = node.account;
    if (account.id == null) return;

    // 1. Guard against deleting critical primary root accounts (Levels 1-3 or system accounts)
    if (account.evaluatedLevel < 4 &&
        !account.isOperationalSubEntity &&
        account.code.trim().length < 4) {
      _showSafetyWarningDialog(
        pageCtx,
        title: 'لا يمكن حذف الحسابات الرئيسية',
        message:
            'الحساب "${account.displayName}" (${account.code}) هو حساب رئيسي (${account.levelLabel}).\n\nلحماية الهيكل المحاسبي، تقتصر إمكانية الحذف على الحسابات التحليلية والتشغيلية المضافة.',
        icon: Icons.shield_outlined,
      );
      return;
    }

    if (account.code.trim().startsWith('9') ||
        account.type.trim().toLowerCase() == 'system') {
      _showSafetyWarningDialog(
        pageCtx,
        title: 'لا يمكن حذف الحسابات النظامية',
        message:
            'الحساب "${account.displayName}" (${account.code}) هو حساب نظامي/وسيط تابع للبنية التحتية للنظام ولا يمكن حذفه.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    // 2. Child nodes check (both in-tree children and any database accounts referencing it as parent)
    final hasChildren = node.children.isNotEmpty ||
        allAccounts.any((a) => a.parentId == account.id);
    if (hasChildren) {
      final childCount = node.children.isNotEmpty
          ? node.children.length
          : allAccounts.where((a) => a.parentId == account.id).length;
      _showSafetyWarningDialog(
        pageCtx,
        title: 'لا يمكن حذف الحساب لوجود تفرعات',
        message:
            'الحساب "${account.displayName}" (${account.code}) يحتوي على ($childCount) حسابات فرعية مندرجة تحته.\n\nلحماية ترابط شجرة الحسابات، يجب حذف أو إعادة تعيين الحسابات الفرعية أولاً قبل حذف هذا الحساب.',
        icon: Icons.account_tree_outlined,
      );
      return;
    }

    // 3. Active financial balance check
    if (account.balance.abs() > 0.001 || node.totalBalance.abs() > 0.001) {
      _showSafetyWarningDialog(
        pageCtx,
        title: 'لا يمكن حذف الحساب لوجود رصيد مالي',
        message:
            'الحساب "${account.displayName}" (${account.code}) يحتوي على رصيد مالي نشط (${_currencyFormat.format(account.balance)}).\n\nلحماية سلامة القوائم المالية وميزان المراجعة، يمنع حذف أي حساب يحتوي على رصيد غير صفري.',
        icon: Icons.account_balance_wallet_outlined,
      );
      return;
    }

    // 4. Verify transaction history & foreign key references
    showDialog(
      context: pageCtx,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      ),
    );

    int txCount = 0;
    AccountDeletionResult? valResult;
    try {
      final validator = AccountValidationService();
      valResult = await validator.validateDeletion(account.id!);

      final typedId = int.tryParse(account.id!);
      final data = await Supabase.instance.client
          .from('v_journal_entry_lines')
          .select('id')
          .eq('account_id', typedId ?? account.id!)
          .limit(1);
      txCount = (data as List).length;
    } catch (e) {
      debugPrint('Error validating account deletion: $e');
    } finally {
      if (pageCtx.mounted) {
        Navigator.of(pageCtx, rootNavigator: true).pop();
      }
    }

    if (!pageCtx.mounted) return;

    final hasReferences = valResult != null && !valResult.canHardDelete;
    if (txCount > 0 || hasReferences) {
      final refsDetails = (valResult != null && valResult.references.isNotEmpty)
          ? '\n\nالمعاملات المرتبطة بالحساب:\n${valResult.references.map((r) => '  • ${r.displayLabel}: ${r.rowCount} حركة مسجلة').join('\n')}'
          : '';

      _showSafetyWarningDialog(
        pageCtx,
        title: 'لا يمكن حذف الحساب لوجود حركات مالية',
        message:
            'الحساب "${account.displayName}" (${account.code}) مسجل عليه قيود يومية أو معاملات مالية سابقة في النظام.$refsDetails\n\nلحماية التسلسل المحاسبي وسلامة الدفاتر وقيود اليومية، يمنع نهائياً حذف أي حساب شارك في معاملات مالية.',
        icon: Icons.history_edu_rounded,
      );
      return;
    }

    // 5. Account is completely safe: prompt confirmation dialog
    _showDeleteConfirmationDialog(
      pageCtx,
      account: account,
      onConfirm: () async {
        final cubit = pageCtx.read<ChartOfAccountsCubit>();
        final error = await cubit.deleteAccount(account.id!);

        if (!pageCtx.mounted) return;
        if (error == null) {
          ScaffoldMessenger.of(pageCtx).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'تم حذف الحساب "${account.displayName}" (${account.code}) نهائياً وتحديث الدليل بنجاح',
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ],
              ),
              backgroundColor: AppTheme.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(pageCtx).showSnackBar(
            SnackBar(
              content: Text(
                'تعذر حذف الحساب: $error',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      },
    );
  }

  void _showDeleteConfirmationDialog(
    BuildContext context, {
    required AccountModel account,
    required VoidCallback onConfirm,
  }) {
    final isDark = ThemeCubit.isCurrentDark;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.danger.withValues(alpha: isDark ? 0.3 : 0.5)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: AppTheme.danger, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'تأكيد حذف الحساب',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من رغبتك في حذف الحساب التالي نهائياً؟',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      account.code,
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      account.displayName,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: isDark ? 0.1 : 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.success.withValues(alpha: isDark ? 0.25 : 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      color: AppTheme.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم التحقق: الحساب فارغ تماماً ولا يحتوي على فروع أو معاملات مالية.',
                      style: TextStyle(
                        color: isDark ? AppTheme.success : const Color(0xFF047857),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'إلغاء',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 17),
            label: const Text(
              'نعم، حذف نهائي',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSafetyWarningDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
  }) {
    final isDark = ThemeCubit.isCurrentDark;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.orange.withValues(alpha: isDark ? 0.3 : 0.5)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.orange, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 12.5,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'حسناً، فهمت',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// BLoC State
abstract class ChartOfAccountsState {}

class ChartOfAccountsInitial extends ChartOfAccountsState {}

class ChartOfAccountsLoading extends ChartOfAccountsState {}

class ChartOfAccountsLoaded extends ChartOfAccountsState {
  final List<AccountModel> accounts;

  ChartOfAccountsLoaded(this.accounts);
}

class ChartOfAccountsError extends ChartOfAccountsState {
  final String message;

  ChartOfAccountsError(this.message);
}

// BLoC Cubit
class ChartOfAccountsCubit extends Cubit<ChartOfAccountsState> {
  final AccountDao _dao = AccountDao();

  ChartOfAccountsCubit() : super(ChartOfAccountsInitial());

  @override
  void emit(ChartOfAccountsState state) {
    if (isClosed) return;
    super.emit(state);
  }

  Future<void> loadAccounts({bool syncEntities = false}) async {
    if (isClosed) return;
    emit(ChartOfAccountsLoading());
    try {
      if (syncEntities) {
        try {
          await OpeningBalanceGlSyncService.instance.syncAllEntities();
        } catch (_) {}
      }
      if (isClosed) return;
      final accounts = await _dao.getAll();
      if (isClosed) return;
      emit(ChartOfAccountsLoaded(accounts));
    } catch (e) {
      if (isClosed) return;
      emit(ChartOfAccountsError(e.toString()));
    }
  }

  Future<String?> addAccount({
    required String code,
    required String name,
    String? accountName,
    required String type,
    String? parentId,
  }) async {
    try {
      if (await _dao.codeExists(code)) {
        return 'كود الحساب موجود بالفعل';
      }

      if (parentId != null && parentId.isNotEmpty) {
        final parent = await _dao.getById(parentId);
        if (parent == null) {
          return 'الحساب الأب غير موجود';
        }
      }

      final account = AccountModel(
        code: code,
        name: name,
        accountName: accountName,
        type: type,
        parentId: parentId,
      );

      await _dao.insert(account);
      await loadAccounts();
      return null;
    } catch (e) {
      return 'فشل إضافة الحساب: $e';
    }
  }

  Future<String?> updateAccount({
    required String id,
    required String code,
    required String name,
    String? accountName,
    required String type,
    String? parentId,
  }) async {
    try {
      if (await _dao.codeExists(code, excludeId: id)) {
        return 'كود الحساب موجود بالفعل';
      }

      if (parentId != null && parentId.isNotEmpty) {
        final parent = await _dao.getById(parentId);
        if (parent == null) {
          return 'الحساب الأب غير موجود';
        }
        if (parentId == id) {
          return 'لا يمكن جعل الحساب أباً لنفسه';
        }
      }

      final account = AccountModel(
        id: id,
        code: code,
        name: name,
        accountName: accountName,
        type: type,
        parentId: parentId,
      );

      await _dao.update(account);
      await loadAccounts();
      return null;
    } catch (e) {
      return 'فشل تعديل الحساب: $e';
    }
  }

  /// Safely update only the display names of an account without altering
  /// account_code, account_type, or parent_id, guaranteeing data integrity.
  Future<String?> updateAccountName({
    required String id,
    required String arabicName,
    String? englishName,
  }) async {
    try {
      if (arabicName.trim().isEmpty) {
        return 'يرجى إدخال اسم الحساب بالعربي';
      }

      final cleanArabic = arabicName.trim();
      final cleanEnglish = (englishName != null && englishName.trim().isNotEmpty)
          ? englishName.trim()
          : cleanArabic;

      await _dao.updateName(
        id: id,
        accountName: cleanArabic,
        name: cleanEnglish,
      );

      await loadAccounts();
      return null;
    } catch (e) {
      return 'فشل تعديل مسمى الحساب: $e';
    }
  }

  Future<String?> deleteAccount(String id) async {
    try {
      final result = await _dao.permanentDelete(id);
      if (result.success) {
        await loadAccounts();
        return null;
      }
      return result.message ?? 'فشل حذف الحساب';
    } catch (e) {
      return 'فشل حذف الحساب: $e';
    }
  }
}

// Tree Node Helper
class AccountNode {
  final AccountModel account;
  final List<AccountNode> children;

  AccountNode({
    required this.account,
    required this.children,
  });

  double get totalBalance {
    if (children.isEmpty) return account.balance;
    double sum = account.balance;
    for (final child in children) {
      sum += child.totalBalance;
    }
    return sum;
  }

  /// Aggregate per-currency balances across all children (recursive)
  Map<String, double> get totalBalancesByCurrency {
    final result = <String, double>{};

    // Add this account's own per-currency balances
    for (final entry in account.balancesByCurrency.entries) {
      result[entry.key] = (result[entry.key] ?? 0.0) + entry.value;
    }

    // Recursively add children's per-currency balances
    for (final child in children) {
      final childCurrencies = child.totalBalancesByCurrency;
      for (final entry in childCurrencies.entries) {
        result[entry.key] = (result[entry.key] ?? 0.0) + entry.value;
      }
    }

    // Remove zero entries
    result.removeWhere((_, v) => v.abs() < 0.001);
    return result;
  }

  /// Whether this subtree has balances in more than one currency
  bool get isMultiCurrency => totalBalancesByCurrency.length > 1;
}