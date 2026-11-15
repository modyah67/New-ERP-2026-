import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/clearing_agent_model.dart';
import 'clearance_agents_pdf_service.dart';
import 'clearing_agent_cubit.dart';
import 'clearing_agent_state.dart';
import 'clearing_agent_form_dialog.dart';

class ClearingAgentsPage extends StatefulWidget {
  const ClearingAgentsPage({super.key});

  @override
  State<ClearingAgentsPage> createState() => _ClearingAgentsPageState();
}

class _ClearingAgentsPageState extends State<ClearingAgentsPage> {
  late final ClearingAgentCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ClearingAgentCubit()..init();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        body: Container(
          decoration: AppTheme.backgroundGradient,
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 24),
            child: BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isMobile, state),
                    const SizedBox(height: 16),
                    _buildKpiStrip(state),
                    const SizedBox(height: 16),
                    _buildSearchBar(isMobile),
                    const SizedBox(height: 16),
                    Expanded(child: _buildTable()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile, ClearingAgentState state) {
    final isDark = ThemeCubit.isCurrentDark;
    final titleSection = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: (isDark ? AppTheme.accent : AppTheme.lightAccent).withAlpha(isDark ? 30 : 25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (isDark ? AppTheme.accent : AppTheme.lightAccent).withAlpha(80)),
          ),
          child: Icon(Icons.sailing_outlined, color: isDark ? AppTheme.accent : AppTheme.lightAccent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مخلصو الجمارك والشحن',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                ),
              ),
              Text(
                'إدارة مكاتب التخليص الجمركي البحري والجوي، كشوفات الحساب والشهادات الجمركية',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final agents = state is ClearingAgentLoaded ? state.agents : <ClearingAgentModel>[];

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white70 : const Color(0xFF0F172A)),
          tooltip: 'تحديث البيانات',
          onPressed: () => _cubit.loadAll(reset: true),
        ),
        ElevatedButton.icon(
          onPressed: () => _openConsolidatedPdf(agents),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(isMobile ? 'كشف مجمع' : 'كشف حساب مجمع 📄'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A365D), // Deep Navy
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 18, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: const Color(0xFF38BDF8).withAlpha(80)),
          ),
        ),
        IconButton(
          icon: Icon(Icons.save_alt_rounded, color: isDark ? Colors.white70 : const Color(0xFF334155)),
          tooltip: 'حفظ كشف حساب مجمع كملف PDF',
          onPressed: () => _saveConsolidatedPdf(agents),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await _cubit.prepareAddForm();
            _showFormDialog();
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? 'إضافة' : 'إضافة مخلص جديد'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleSection,
          const SizedBox(height: 12),
          actions,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleSection),
        const SizedBox(width: 16),
        Flexible(child: actions),
      ],
    );
  }

  // ── KPI Summary Strip ──

  Widget _buildKpiStrip(ClearingAgentState state) {
    final loaded = state is ClearingAgentLoaded ? state : null;
    final isLoading = state is ClearingAgentLoading;

    final total = loaded?.agents.length ?? 0;
    final seaCnt = loaded?.seaCount ?? 0;
    final airCnt = loaded?.airCount ?? 0;
    final currencies = loaded?.activeCurrencies ?? [];
    final totalEgpCurrent = loaded?.totalCurrentBalanceEgp ?? 0.0;
    final totalEgpInitial = loaded?.totalInitialBalanceEgp ?? 0.0;
    final rates = loaded?.exchangeRates ?? const {'EGP': 1.0};

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        final cards = [
          // Card 1 — Total agents + type breakdown
          _buildKpiCard(
            icon: Icons.badge_outlined,
            label: 'إجمالي مخلصي الجمارك',
            value: isLoading ? '…' : '$total',
            color: AppTheme.primary,
            subtitle: 'بحري $seaCnt • جوي $airCnt',
            isLoading: isLoading,
            currencyPills: null,
          ),
          // Card 2 — Current balances (per currency)
          _buildKpiCard(
            icon: Icons.account_balance_wallet_outlined,
            label: 'إجمالي الأرصدة الحالية',
            value: isLoading
                ? '…'
                : '${AppUtils.formatNumber(totalEgpCurrent.abs())} ج.م',
            color: totalEgpCurrent >= 0 ? AppTheme.success : AppTheme.danger,
            subtitle: totalEgpCurrent >= 0
                ? 'مستحق للمخلصين (دائن)'
                : 'دفعات مقدمة / عليهم (مدين)',
            isLoading: isLoading,
            currencyPills: currencies.isEmpty
                ? null
                : currencies
                    .map((c) => _CurrencyPill(
                          label:
                              '${c.symbol} ${AppUtils.formatNumber(c.nativeCurrentBalance.abs())}',
                          count: c.agentCount,
                          isNegative: c.nativeCurrentBalance < 0,
                        ))
                    .toList(),
          ),
          // Card 3 — Initial balances (per currency)
          _buildKpiCard(
            icon: Icons.history_edu_outlined,
            label: 'إجمالي الأرصدة الافتتاحية',
            value: isLoading
                ? '…'
                : '${AppUtils.formatNumber(totalEgpInitial.abs())} ج.م',
            color: AppTheme.warning,
            subtitle: 'رصيد افتتاحي معادل بالجنيه المصري',
            isLoading: isLoading,
            currencyPills: currencies.isEmpty
                ? null
                : currencies
                    .map((c) => _CurrencyPill(
                          label:
                              '${c.symbol} ${AppUtils.formatNumber(c.nativeInitialBalance.abs())}',
                          count: c.agentCount,
                          isNegative: false,
                        ))
                    .toList(),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNarrow)
              Column(
                children: cards
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: c,
                        ))
                    .toList(),
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cards
                      .expand((c) => [Expanded(child: c), const SizedBox(width: 12)])
                      .toList()
                    ..removeLast(),
                ),
              ),
            if (!isLoading && rates.length > 1) ..._buildRateBar(rates),
          ],
        );
      },
    );
  }

  List<Widget> _buildRateBar(Map<String, double> rates) {
    final pills = <Widget>[];
    const foreign = ['USD', 'EUR', 'GBP'];
    const symbols = {'USD': '\$', 'EUR': '€', 'GBP': '£'};
    for (final c in foreign) {
      if (rates.containsKey(c)) {
        pills.add(_ratePill('1 ${symbols[c] ?? c} = ${rates[c]!.toStringAsFixed(2)} ج.م'));
      }
    }
    if (pills.isEmpty) return [];
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          Icon(Icons.currency_exchange, size: 12, color: ThemeCubit.isCurrentDark ? AppTheme.textSecondary : const Color(0xFF0F172A)),
          ...pills,
        ],
      ),
    ];
  }

  Widget _ratePill(String text) {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.border.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? AppTheme.border.withValues(alpha: 0.5) : AppTheme.lightBorder),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'Cairo',
          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
          color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
    bool isLoading = false,
    List<_CurrencyPill>? currencyPills,
  }) {
    final isDark = ThemeCubit.isCurrentDark;
    final iconColor = isDark 
        ? color 
        : (color == AppTheme.primary ? AppTheme.lightPrimary : (color == AppTheme.warning ? const Color(0xFFD97706) : color));

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            gradient: isDark
                ? LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      color.withValues(alpha: 0.12),
                      color.withValues(alpha: 0.04),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? color.withValues(alpha: 0.28) : color.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? color.withValues(alpha: 0.08) : const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: isDark ? 0.15 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: iconColor.withValues(alpha: isDark ? 0.25 : 0.3)),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Cairo',
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A),
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (isLoading)
                          SizedBox(
                            height: 18,
                            width: 60,
                            child: LinearProgressIndicator(
                              backgroundColor: color.withValues(alpha: 0.1),
                              color: color.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          )
                        else
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              value,
                              style: TextStyle(
                                fontSize: 19,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w900,
                                color: isDark ? color : const Color(0xFF0F172A),
                                height: 1.1,
                              ),
                            ),
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Cairo',
                              fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : const Color(0xFF475569),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (!isLoading && currencyPills != null && currencyPills.isNotEmpty) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: isDark ? const Color(0x1AFFFFFF) : AppTheme.lightBorder),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: currencyPills.map((p) => _buildCurrencyPillWidget(p)).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyPillWidget(_CurrencyPill pill) {
    final color = pill.isNegative ? AppTheme.danger : AppTheme.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pill.label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${pill.count}',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'Cairo',
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: _cubit.onSearchChanged,
          decoration: InputDecoration(
            hintText: 'بحث بالاسم أو الكود...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
              buildWhen: (prev, curr) => curr is ClearingAgentLoaded,
              builder: (context, state) {
                final query = state is ClearingAgentLoaded ? state.searchQuery : '';
                if (query.isEmpty) return const SizedBox.shrink();
                return IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _cubit.onSearchChanged(''));
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTypeFilter(),
      ],
    );
  }

  Widget _buildTypeFilter() {
    return BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
      buildWhen: (prev, curr) => curr is ClearingAgentLoaded,
      builder: (context, state) {
        final currentFilter = state is ClearingAgentLoaded ? state.typeFilter : 'all';
        return Row(
          children: [
            _buildFilterChip('الكل', 'all', currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip('بحري', 'بحري', currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip('جوي', 'جوي', currentFilter),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value, String currentFilter) {
    final isSelected = currentFilter == value;
    final isDark = ThemeCubit.isCurrentDark;
    final primaryColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    return GestureDetector(
      onTap: () => _cubit.onTypeFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: isDark ? 0.2 : 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : (isDark ? Colors.white.withValues(alpha: 0.1) : AppTheme.lightBorder),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value == 'all' ? Icons.filter_list : (value == 'بحري' ? Icons.sailing_outlined : Icons.flight_outlined),
              size: 16,
              color: isSelected ? primaryColor : (isDark ? AppTheme.textSecondary : const Color(0xFF334155)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : (isDark ? FontWeight.normal : FontWeight.bold),
                color: isSelected ? primaryColor : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A)),
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: BlocConsumer<ClearingAgentCubit, ClearingAgentState>(
            listener: (context, state) {
              if (state is ClearingAgentError) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
              }
            },
            builder: (context, state) {
              if (state is ClearingAgentLoading) return const Center(child: CircularProgressIndicator());
              if (state is ClearingAgentLoaded) {
                if (state.agents.isEmpty) return _buildEmptyState(state.searchQuery);
                return _buildDataTable(state);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(ClearingAgentLoaded state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minTableWidth = 920.0;
        final double tableWidth = constraints.maxWidth > minTableWidth
            ? constraints.maxWidth
            : minTableWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _buildTableHeader(),
                const Divider(height: 1),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      if (!state.isFetchingMore && state.hasMore && scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                        _cubit.fetchMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      itemCount: state.agents.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (listContext, index) {
                        if (index == state.agents.length) {
                          return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
                        }
                        return _buildTableRow(listContext, state.agents[index], index);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    final isDark = ThemeCubit.isCurrentDark;
    final labelStyle = TextStyle(
        color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A),
        fontWeight: FontWeight.bold,
        fontFamily: 'Cairo',
        fontSize: 13);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFF1F5F9),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text('#', style: labelStyle)),
          SizedBox(width: 90, child: Text('الكود', style: labelStyle)),
          Expanded(child: Text('الاسم', style: labelStyle)),
          SizedBox(width: 80, child: Text('النوع', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 110, child: Text('الهاتف', style: labelStyle)),
          SizedBox(width: 85, child: Text('العملة', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 120, child: Text('الرصيد الافتتاحي', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 125, child: Text('الرصيد المالي الحالي', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('إجراءات', style: labelStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildCurrencyBadge(String currency, String symbol) {
    final Color color;
    final Color bg;
    switch (currency.toUpperCase()) {
      case 'USD':
        color = const Color(0xFF10B981);
        bg = const Color(0x1A10B981);
        break;
      case 'EUR':
        color = const Color(0xFF38BDF8);
        bg = const Color(0x1A38BDF8);
        break;
      case 'GBP':
        color = const Color(0xFFA855F7);
        bg = const Color(0x1AA855F7);
        break;
      case 'EGP':
      default:
        color = const Color(0xFFF59E0B);
        bg = const Color(0x1AF59E0B);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$currency ($symbol)',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTableRow(BuildContext listContext, ClearingAgentModel agent, int index) {
    final isDark = ThemeCubit.isCurrentDark;
    final isEven = index % 2 == 0;
    return Container(
      height: 55,
      color: isEven
          ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.transparent)
          : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
              width: 36,
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                      fontFamily: 'Cairo',
                      fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                      fontSize: 13))),
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isDark ? AppTheme.accent : AppTheme.lightAccent).withValues(alpha: isDark ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                agent.code.isNotEmpty ? agent.code : '—',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.accent : AppTheme.lightAccent,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: Text(
              agent.name,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          SizedBox(
            width: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: agent.brokerType == 'بحري'
                    ? (isDark ? Colors.blue.withValues(alpha: 0.1) : const Color(0xFF0284C7).withValues(alpha: 0.12))
                    : (isDark ? Colors.orange.withValues(alpha: 0.1) : const Color(0xFFD97706).withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                agent.brokerType,
                style: TextStyle(
                  fontSize: 11,
                  color: agent.brokerType == 'بحري'
                      ? (isDark ? Colors.blue : const Color(0xFF0284C7))
                      : (isDark ? Colors.orange : const Color(0xFFD97706)),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              agent.phone.isNotEmpty ? agent.phone : '—',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                fontFamily: 'Cairo',
                fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 85,
            child: Center(
              child: _buildCurrencyBadge(agent.currency, agent.currencySymbol),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              agent.initialBalance == 0.0
                  ? '0.00 ${agent.currencySymbol}'
                  : '${agent.initialBalance < 0 ? '-' : ''}${agent.initialBalance.abs().toStringAsFixed(2)} ${agent.currencySymbol}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: agent.initialBalance > 0
                    ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
                    : (agent.initialBalance < 0 ? AppTheme.danger : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A))),
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 125,
            child: Text(
              '${agent.currentBalance < 0 ? '-' : ''}${agent.currentBalance.abs().toStringAsFixed(2)} ${agent.currencySymbol}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: agent.currentBalance > 0
                    ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
                    : (agent.currentBalance < 0 ? AppTheme.danger : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A))),
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showFormDialog(agent: agent),
                  child: Icon(Icons.edit_outlined, size: 17, color: isDark ? AppTheme.primary : AppTheme.lightPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery) {
    final isDark = ThemeCubit.isCurrentDark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 72, color: (isDark ? AppTheme.textSecondary : AppTheme.lightTextMuted).withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا يوجد مخلصين بعد' : 'لا توجد نتائج للبحث',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A), fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'اضغط "إضافة مخلص" لإضافة أول مخلص' : 'جرب كلمة بحث مختلفة',
            style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), fontFamily: 'Cairo', fontSize: 13, fontWeight: isDark ? FontWeight.normal : FontWeight.w600),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة مخلص'),
              onPressed: () async { await _cubit.prepareAddForm(); _showFormDialog(); },
            ),
          ],
        ],
      ),
    );
  }

  void _showFormDialog({ClearingAgentModel? agent}) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(value: _cubit, child: ClearingAgentFormDialog(agent: agent)),
    );
  }

  /*
  void _showDeleteConfirm(BuildContext context, ClearingAgentModel agent) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف "${agent.name}"؟', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () { Navigator.pop(dialogContext); _cubit.deleteAgent(agent); },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
  */

  Future<void> _openConsolidatedPdf(List<ClearingAgentModel> agents) async {
    if (agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات مخلصين للتصدير', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final state = _cubit.state;
    final loaded = state is ClearingAgentLoaded ? state : null;

    try {
      await ClearanceAgentsPdfService.generateAndPrint(
        agents: agents,
        balanceByCurrency: loaded?.balanceByCurrency,
        totalCurrentBalanceEgp: loaded?.totalCurrentBalanceEgp,
        totalInitialBalanceEgp: loaded?.totalInitialBalanceEgp,
        seaCount: loaded?.seaCount,
        airCount: loaded?.airCount,
        exchangeRates: loaded?.exchangeRates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء PDF: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _saveConsolidatedPdf(List<ClearingAgentModel> agents) async {
    if (agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات مخلصين للتصدير', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final state = _cubit.state;
    final loaded = state is ClearingAgentLoaded ? state : null;

    try {
      await ClearanceAgentsPdfService.saveToFile(
        context,
        agents: agents,
        balanceByCurrency: loaded?.balanceByCurrency,
        totalCurrentBalanceEgp: loaded?.totalCurrentBalanceEgp,
        totalInitialBalanceEgp: loaded?.totalInitialBalanceEgp,
        seaCount: loaded?.seaCount,
        airCount: loaded?.airCount,
        exchangeRates: loaded?.exchangeRates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ PDF: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}

class _CurrencyPill {
  final String label;
  final int count;
  final bool isNegative;

  const _CurrencyPill({
    required this.label,
    required this.count,
    required this.isNegative,
  });
}
