import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme.dart';
import '../../data/dao/account_dao.dart';
import '../../data/models/account_model.dart';
import '../../data/services/account_validation_service.dart';
import 'widgets/account_journal_entries_dialog.dart';

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

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 1200 ? 1200.0 : screenWidth;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: contentWidth,
          child: Padding(
            padding: const EdgeInsets.all(24),
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
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.account_tree_rounded,
              color: AppTheme.primary, size: 28),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'شجرة الحسابات (دليل الحسابات)',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Cairo',
              ),
            ),
            Text(
              'الهيكل المالي المحاسبي الشامل — مصنف ومترجم بالكامل',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const Spacer(),
        _buildHeaderActionButton(
          icon: Icons.unfold_more_rounded,
          label: 'توسيع الكل',
          color: Colors.blueGrey,
          onPressed: _expandAll,
        ),
        const SizedBox(width: 8),
        _buildHeaderActionButton(
          icon: Icons.unfold_less_rounded,
          label: 'طي الكل',
          color: Colors.blueGrey,
          onPressed: _collapseAll,
        ),
        const SizedBox(width: 8),
        _buildHeaderActionButton(
          icon: Icons.refresh_rounded,
          label: 'تحديث',
          color: AppTheme.accent,
          onPressed: () => context.read<ChartOfAccountsCubit>().loadAccounts(),
        ),
        const SizedBox(width: 8),
        // _buildHeaderActionButton(
        //   icon: Icons.add_circle_outline_rounded,
        //   label: 'إضافة حساب جديد',
        //   color: AppTheme.success,
        //   onPressed: () => _showAddAccountDialog(context),
        // ),
      ],
    );
  }

  Widget _buildInstructionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.touch_app_rounded, color: AppTheme.accent, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '💡 نصيحة: انقر نقراً مزدوجاً (Double Click) على أي حساب أو فرع رئيسي لعرض كافة قيود اليومية والحركات المالية المندرجة تحته مباشرة.',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 12.5,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w500,
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
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
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
    final accounts = state.accounts;
    if (accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 54, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'لا توجد حسابات مسجلة في شجرة الحسابات',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
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

    // Build tree structure
    final fullTree = _buildTree(accounts);
    final filteredTree = _filterTree(fullTree, _searchController.text, _selectedTypeFilter);

    // Calculate totals per category
    final stats = _calculateCategoryStats(accounts);

    return Column(
      children: [
        // Category KPI Stats
        _buildStatsRow(stats, accounts.length),
        const SizedBox(height: 14),

        // Search & Type Filter Bar
        _buildSearchAndFilterBar(),
        const SizedBox(height: 14),

        // Tree view
        Expanded(
          child: filteredTree.isEmpty
              ? _buildNoResultsState()
              : Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filteredTree.length,
                      itemBuilder: (context, index) {
                        return _buildAccountNodeWidget(
                          node: filteredTree[index],
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10.5,
                      fontFamily: 'Cairo',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          color: color,
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
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 10,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
                onChanged: (val) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث بالكود أو الاسم العربي أو الإنجليزي...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.accent, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white70, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1)),
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
              _buildTypeChip('asset', 'أصول', AppTheme.success),
              _buildTypeChip('liability', 'خصوم', Colors.orangeAccent),
              _buildTypeChip('equity', 'حقوق ملكية', Colors.purpleAccent),
              _buildTypeChip('revenue', 'إيرادات', const Color(0xFF00E5FF)),
              _buildTypeChip('expense', 'مصروفات', AppTheme.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, Color? color) {
    final isSelected = _selectedTypeFilter == type;
    final activeColor = color ?? AppTheme.primary;

    return InkWell(
      onTap: () => setState(() => _selectedTypeFilter = type),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? activeColor
                : Colors.white.withValues(alpha: 0.08),
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
                color: isSelected ? activeColor : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

  Widget _buildBalanceWidget(AccountNode node) {
    final balancesByCurrency = node.totalBalancesByCurrency;

    // Single EGP currency or no currency data: show simple balance
    if (balancesByCurrency.isEmpty || (balancesByCurrency.length == 1 && (balancesByCurrency.keys.first == 'EGP' || balancesByCurrency.keys.first == 'ج.م'))) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _currencyFormat.format(node.totalBalance),
          style: TextStyle(
            color: node.totalBalance >= 0
                ? Colors.white70
                : AppTheme.danger,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
      );
    }

    // Multi-currency: show per-currency breakdown
    final buffer = StringBuffer();
    final entries = balancesByCurrency.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) buffer.write(' | ');
      buffer.write('${entries[i].key}: ${_currencyFormat.format(entries[i].value)}');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Tooltip(
        message: 'حساب بعملات متعددة (${balancesByCurrency.length} عملات)',
        child: Text(
          buffer.toString(),
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
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

    for (final account in accounts) {
      final id = account.id ?? '';
      if (id.isEmpty || processedIds.contains(id)) continue;
      processedIds.add(id);

      final node = AccountNode(account: account, children: []);
      nodeMap[id] = node;

      final parentId = account.parentId;
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

      final parentId = account.parentId;
      if (parentId == null || parentId.isEmpty || !nodeMap.containsKey(parentId)) {
        if (!rootNodes.contains(node)) {
          rootNodes.add(node);
        }
      }
    }

    rootNodes.sort((a, b) => a.account.code.compareTo(b.account.code));
    return rootNodes;
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
            code.contains(q);

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
  }) {
    final account = node.account;
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expandedNodes[account.id ?? ''] ?? false;
    final isActive = account.isActive && !account.isArchived;

    final typeColor = _getAccountTypeColor(account.type);
    final typeLabel = _getAccountTypeLabel(account.type);

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
          hoverColor: Colors.white.withValues(alpha: 0.04),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0),
              left: 16.0,
              top: 7,
              bottom: 7,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse icon
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
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_left_rounded,
                        size: 18,
                        color: AppTheme.accent,
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
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    account.code,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Arabic Display Name
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.displayName,
                          style: TextStyle(
                            color: !isActive ? Colors.orange : Colors.white,
                            fontSize: 13.5,
                            fontWeight: hasChildren
                                ? FontWeight.bold
                                : FontWeight.w500,
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
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
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
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${node.children.length} فرعي',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
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
                    // Add child account (hidden for 2100 and its branch)
                    if (!_is2100Branch(account, allAccounts))
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 17),
                        color: AppTheme.success,
                        onPressed: () => _showAddAccountDialog(
                          context,
                          parentAccount: account,
                        ),
                        tooltip: 'إضافة حساب فرعي تحت هذا الحساب',
                      ),
                    // Edit
                    // IconButton(
                    //   icon: const Icon(Icons.edit_outlined, size: 17),
                    //   color: Colors.white70,
                    //   onPressed: () => _showEditAccountDialog(
                    //     context,
                    //     account,
                    //     allAccounts,
                    //   ),
                    //   tooltip: 'تعديل',
                    // ),
                    // // Delete
                    // IconButton(
                    //   icon: const Icon(Icons.delete_outline, size: 17),
                    //   color: AppTheme.danger,
                    //   onPressed: () => _confirmDeleteAccount(context, account),
                    //   tooltip: 'حذف أو أرشفة',
                    // ),
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

        // Children nodes
        if (isExpanded && hasChildren)
          ...node.children.map(
            (child) => _buildAccountNodeWidget(
              node: child,
              level: level + 1,
              allAccounts: allAccounts,
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
      default:
        return type;
    }
  }

  void _showAddAccountDialog(BuildContext parentCtx, {AccountModel? parentAccount}) {
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
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
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
                style: const TextStyle(
                  color: Colors.white,
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
                    decoration: const InputDecoration(
                      labelText: 'كود الحساب المحاسبي (مثال: 1011)*',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),

                  // Arabic Name (Primary)
                  TextField(
                    controller: arabicNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الحساب بالعربي (مثال: بنك مصر - جاري)*',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),

                  // English Name (Optional)
                  TextField(
                    controller: englishNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الحساب بالإنجليزي (اختياري)',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),

                  // Type
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: currentType,
                    decoration: const InputDecoration(
                      labelText: 'نوع الحساب المحاسبي',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    items: [
                      DropdownMenuItem(
                          value: 'asset',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: const Text('أصول (Asset)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'liability',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('خصوم (Liability)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'equity',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('حقوق ملكية (Equity)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'revenue',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('إيرادات (Revenue)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo')))),
                      DropdownMenuItem(
                          value: 'expense',
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('مصروفات (Expense)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo')))),
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
                    decoration: const InputDecoration(
                      labelText: 'الحساب الأب (الفرع الرئيسي التابع له)',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: const Text(
                            'حساب رئيسي (بدون أب)',
                            style: TextStyle(
                                color: AppTheme.accent, fontFamily: 'Cairo'),
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
                              style: const TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo'),
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
              child: const Text(
                'إلغاء',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo'),
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
    List<AccountModel> rawAccounts,
  ) {
    final codeController = TextEditingController(text: account.code);
    final arabicNameController =
        TextEditingController(text: account.displayName);
    final englishNameController =
        TextEditingController(text: account.name);
    String currentType = account.type.toLowerCase();
    if (!['asset', 'liability', 'equity', 'revenue', 'expense'].contains(currentType)) {
      currentType = 'asset';
    }
    String? selectedParentId = account.parentId;

    final uniqueAccounts = <String, AccountModel>{};
    for (var acc in rawAccounts) {
      if (acc.id != null) {
        uniqueAccounts[acc.id!] = acc;
      }
    }
    final allAccounts = uniqueAccounts.values.toList();

    if (selectedParentId != null && !allAccounts.any((a) => a.id == selectedParentId && a.id != account.id)) {
      selectedParentId = null;
    }

    final cubit = parentCtx.read<ChartOfAccountsCubit>();

    showDialog(
      context: parentCtx,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              const Icon(Icons.edit, color: AppTheme.accent, size: 22),
              const SizedBox(width: 10),
              Text(
                'تعديل الحساب (${account.displayName})',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'كود الحساب',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: arabicNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الحساب بالعربي',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: englishNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الحساب بالإنجليزي (اختياري)',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: currentType,
                    decoration: const InputDecoration(
                      labelText: 'نوع الحساب',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    items: const [
                      DropdownMenuItem(
                          value: 'asset',
                          child: Text('أصول (Asset)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo'))),
                      DropdownMenuItem(
                          value: 'liability',
                          child: Text('خصوم (Liability)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo'))),
                      DropdownMenuItem(
                          value: 'equity',
                          child: Text('حقوق ملكية (Equity)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo'))),
                      DropdownMenuItem(
                          value: 'revenue',
                          child: Text('إيرادات (Revenue)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo'))),
                      DropdownMenuItem(
                          value: 'expense',
                          child: Text('مصروفات (Expense)',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Cairo'))),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        currentType = value ?? 'asset';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: selectedParentId,
                    decoration: const InputDecoration(
                      labelText: 'الحساب الأب',
                      labelStyle: TextStyle(
                          color: Colors.white70, fontFamily: 'Cairo'),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary)),
                    ),
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: const Text(
                            'حساب رئيسي (بدون أب)',
                            style: TextStyle(
                                color: AppTheme.accent, fontFamily: 'Cairo'),
                          ),
                        ),
                      ),
                      ...allAccounts
                          .where((a) => a.id != account.id)
                          .map(
                            (acc) => DropdownMenuItem<String?>(
                              value: acc.id,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  '${acc.code} - ${acc.displayName}',
                                  style: const TextStyle(
                                      color: Colors.white, fontFamily: 'Cairo'),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'إلغاء',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo'),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                final arName = arabicNameController.text.trim();
                final enName = englishNameController.text.trim();

                final primaryName = enName.isNotEmpty ? enName : arName;
                final arabicName = arName.isNotEmpty ? arName : enName;

                final error = await cubit.updateAccount(
                  id: account.id!,
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
                      content: Text('تم تعديل الحساب بنجاح'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text(
                'حفظ التعديلات',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext pageCtx, AccountModel account) async {
    if (account.id == null) return;

    final validator = AccountValidationService();
    final result = await validator.validateDeletion(account.id!.toString());

    if (!pageCtx.mounted) return;

    if (result.canHardDelete) {
      _showConfirmDialog(
        pageCtx,
        title: 'تأكيد الحذف النهائي',
        content:
            'هل أنت متأكد من حذف الحساب "${account.displayName}" (${account.code}) نهائياً؟\n\nهذا الحساب غير مستخدم في أي معاملات أو قيود يومية.',
        confirmLabel: 'حذف نهائي',
        confirmColor: AppTheme.danger,
        onConfirm: () async {
          final r = await validator.permanentDeleteAccount(account.id!);
          if (!pageCtx.mounted) return;
          ScaffoldMessenger.of(pageCtx).showSnackBar(
            SnackBar(
              content: Text(
                r.success
                    ? 'تم حذف الحساب نهائياً'
                    : (r.message ?? 'فشل الحذف'),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor:
                  r.success ? AppTheme.success : AppTheme.danger,
            ),
          );
          if (r.success && pageCtx.mounted) {
            pageCtx.read<ChartOfAccountsCubit>().loadAccounts();
          }
        },
      );
    } else if (result.canArchive) {
      final refsText = result.references
          .map((r) => '  • ${r.displayLabel} (${r.rowCount})')
          .join('\n');

      _showConfirmDialog(
        pageCtx,
        title: 'أرشفة الحساب',
        content:
            'الحساب "${account.displayName}" مرتبط بمعاملات سابقة في:\n$refsText\n\nهل تريد أرشفته بدلاً من حذفه؟\nسيتم إخفاؤه من القوائم النشطة مع الحفاظ على سلامة القيود السابقة.',
        confirmLabel: 'أرشفة الحساب',
        confirmColor: Colors.orange,
        onConfirm: () async {
          final r = await validator.archiveAccount(account.id!);
          if (!pageCtx.mounted) return;
          ScaffoldMessenger.of(pageCtx).showSnackBar(
            SnackBar(
              content: Text(
                r.success
                    ? 'تم أرشفة الحساب بنجاح'
                    : (r.message ?? 'فشل الأرشفة'),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor:
                  r.success ? AppTheme.success : AppTheme.danger,
            ),
          );
          if (r.success && pageCtx.mounted) {
            pageCtx.read<ChartOfAccountsCubit>().loadAccounts();
          }
        },
      );
    } else {
      final refsText = result.references.isNotEmpty
          ? '\n\nالمراجع المرتبطة:\n${result.references.map((r) => '  • ${r.displayLabel} (${r.rowCount})').join('\n')}'
          : '';

      _showInfoDialog(
        pageCtx,
        title: 'لا يمكن حذف الحساب',
        content: '${result.reason ?? 'سبب غير معروف'}$refsText',
      );
    }
  }

  void _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Text(content,
            style: const TextStyle(
                color: Colors.white70, fontFamily: 'Cairo', height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context,
      {required String title, required String content}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(title,
            style: const TextStyle(color: Colors.orange, fontFamily: 'Cairo')),
        content: SingleChildScrollView(
          child: Text(content,
              style: const TextStyle(
                  color: Colors.white70, fontFamily: 'Cairo', height: 1.5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('حسناً',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo')),
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

  Future<void> loadAccounts() async {
    emit(ChartOfAccountsLoading());
    try {
      final accounts = await _dao.getAll();
      emit(ChartOfAccountsLoaded(accounts));
    } catch (e) {
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

  Future<String?> deleteAccount(String id) async {
    try {
      final result = await _dao.delete(id);
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