import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/shipping_company_model.dart';
import 'shipping_company_cubit.dart';
import 'shipping_company_state.dart';
import 'shipping_company_form_dialog.dart';
import 'shipping_company_pdf_service.dart';

class ShippingCompaniesPage extends StatefulWidget {
  const ShippingCompaniesPage({super.key});

  @override
  State<ShippingCompaniesPage> createState() => _ShippingCompaniesPageState();
}

class _ShippingCompaniesPageState extends State<ShippingCompaniesPage> {
  late final ShippingCompanyCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ShippingCompanyCubit()..init();
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
            child: BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
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
                    Expanded(child: _buildContent(state)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile, ShippingCompanyState state) {
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
          child: Icon(Icons.local_shipping_outlined,
              color: isDark ? AppTheme.accent : AppTheme.lightAccent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'شركات الشحن والخطوط الملاحية',
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
                'إدارة التوكيلات والخطوط الملاحية، متابعة الأرصدة وكشوفات الحساب',
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

    final companies = state is ShippingCompanyLoaded ? state.companies : <ShippingCompanyModel>[];

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
          onPressed: companies.isEmpty ? null : () => _printSummary(companies),
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
          onPressed: companies.isEmpty ? null : () => _savePdf(companies),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await _cubit.prepareAddForm();
            _showFormDialog();
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? 'إضافة' : 'إضافة شركة شحن'),
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

  Widget _buildKpiStrip(ShippingCompanyState state) {
    final loaded = state is ShippingCompanyLoaded ? state : null;
    final isLoading = state is ShippingCompanyLoading;

    final total = loaded?.companies.length ?? 0;
    final currencies = loaded?.activeCurrencies ?? [];
    final totalEgpCurrent = loaded?.totalCurrentBalanceEgp ?? 0.0;
    final totalEgpInitial = loaded?.totalInitialBalanceEgp ?? 0.0;
    final rates = loaded?.exchangeRates ?? const {'EGP': 1.0};

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        final cards = [
          // Card 1 — Total companies
          _buildKpiCard(
            icon: Icons.local_shipping_outlined,
            label: 'إجمالي شركات الشحن',
            value: isLoading ? '…' : '$total',
            color: AppTheme.primary,
            subtitle: 'شركة مسجلة بالمنظومة',
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
                ? 'مستحق لشركات الشحن (دائن)'
                : 'دفعات مقدمة / عليهم (مدين)',
            isLoading: isLoading,
            currencyPills: currencies.isEmpty
                ? null
                : currencies
                    .map((c) => _CurrencyPill(
                          label:
                              '${c.symbol} ${AppUtils.formatNumber(c.nativeCurrentBalance.abs())}',
                          count: c.companyCount,
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
                          count: c.companyCount,
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
    return TextField(
      onChanged: _cubit.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
          buildWhen: (prev, curr) => curr is ShippingCompanyLoaded,
          builder: (context, state) {
            final query =
                state is ShippingCompanyLoaded ? state.searchQuery : '';
            if (query.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => _cubit.onSearchChanged(''),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(ShippingCompanyState state) {
    if (state is ShippingCompanyLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }
    if (state is ShippingCompanyError) {
      return Center(
        child: Text(state.message,
            style: const TextStyle(color: Colors.white70)),
      );
    }
    if (state is! ShippingCompanyLoaded || state.companies.isEmpty) {
      final isDark = ThemeCubit.isCurrentDark;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined,
                color: isDark ? Colors.white24 : AppTheme.lightTextMuted, size: 64),
            const SizedBox(height: 16),
            Text('لا توجد شركات شحن',
                style: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo')),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة شركة شحن'),
              onPressed: () async {
                await _cubit.prepareAddForm();
                _showFormDialog();
              },
            ),
          ],
        ),
      );
    }

    return _buildTable(state);
  }

  Widget _buildTable(ShippingCompanyLoaded state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double minTableWidth = 980.0;
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
                      const Divider(height: 1, color: AppTheme.glassBorder),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollEndNotification &&
                                notification.metrics.pixels >=
                                    notification.metrics.maxScrollExtent - 100) {
                              _cubit.fetchMore();
                            }
                            return false;
                          },
                          child: ListView.separated(
                            itemCount: state.companies.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: AppTheme.glassBorder),
                            itemBuilder: (ctx, i) =>
                                _buildTableRow(ctx, state.companies[i], i),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
          SizedBox(width: 110, child: Text('الهاتف', style: labelStyle)),
          SizedBox(width: 150, child: Text('البريد الإلكتروني', style: labelStyle)),
          SizedBox(width: 85, child: Text('العملة', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 120, child: Text('الرصيد الافتتاحي', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 125, child: Text('الرصيد المالي الحالي', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('إجراءات', style: labelStyle, textAlign: TextAlign.center)),
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

  Widget _buildTableRow(
      BuildContext context, ShippingCompanyModel company, int index) {
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
                      color: isDark ? Colors.white54 : const Color(0xFF475569),
                      fontFamily: 'Cairo',
                      fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                      fontSize: 12))),
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isDark ? AppTheme.accent : AppTheme.lightAccent).withValues(alpha: isDark ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                company.code.isNotEmpty ? company.code : '—',
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
              company.name,
              style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          SizedBox(
              width: 110,
              child: Text(company.phone.isNotEmpty ? company.phone : '—',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      fontFamily: 'Cairo',
                      fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                      fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
          SizedBox(
              width: 150,
              child: Text(company.email.isNotEmpty ? company.email : '—',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      fontFamily: 'Cairo',
                      fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                      fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 85,
            child: Center(
              child: _buildCurrencyBadge(company.currency, company.currencySymbol),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              company.initialBalance == 0.0
                  ? '0.00 ${company.currencySymbol}'
                  : '${company.initialBalance < 0 ? '-' : ''}${company.initialBalance.abs().toStringAsFixed(2)} ${company.currencySymbol}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: company.initialBalance > 0
                    ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
                    : (company.initialBalance < 0 ? AppTheme.danger : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A))),
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
              '${company.currentBalance < 0 ? '-' : ''}${company.currentBalance.abs().toStringAsFixed(2)} ${company.currencySymbol}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: company.currentBalance > 0
                    ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
                    : (company.currentBalance < 0 ? AppTheme.danger : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A))),
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showEditDialog(context, company),
                  child: Icon(Icons.edit_outlined,
                      size: 18, color: isDark ? AppTheme.primary : AppTheme.lightPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFormDialog({ShippingCompanyModel? company}) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: _cubit,
        child: ShippingCompanyFormDialog(company: company),
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, ShippingCompanyModel company) async {
    await _cubit.prepareEditForm(company);
    _showFormDialog(company: company);
  }

  /*
  void _showDeleteConfirm(
      BuildContext context, ShippingCompanyModel company) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF0051B2B),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف شركة الشحن',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد من حذف "${company.name}"؟',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              await _cubit.deleteCompany(company);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حذف',
                style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  */

  Future<void> _printSummary(List<ShippingCompanyModel> companies) async {
    await ShippingCompanyPdfService.printSummary(companies);
  }

  Future<void> _savePdf(List<ShippingCompanyModel> companies) async {
    try {
      final path = await ShippingCompanyPdfService.saveToFile(companies);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ في: $path'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ PDF: $e'), backgroundColor: AppTheme.danger),
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
    this.isNegative = false,
  });
}
