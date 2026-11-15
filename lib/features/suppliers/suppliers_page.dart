import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/supplier_model.dart';
import '../../data/dao/treasury_dao.dart';
import '../statements/supplier_consolidated_statement_pdf_service.dart';
import 'supplier_cubit.dart';
import 'supplier_state.dart';
import 'supplier_form_dialog.dart';
import 'master_codes_directory_pdf_service.dart';
import '../../core/ui_utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../core/widgets/password_verification_dialog.dart';
import 'widgets/multi_currency_balance_badge.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String _selectedFilter = 'all';
  bool _showKpiStrip = true;

  static const _filterOptions = [
    {
      'key': 'all',
      'label': 'عرض الكل',
      'icon': Icons.grid_view_rounded,
      'color': AppTheme.primary,
    },
    {
      'key': 'crop',
      'label': 'موردين المحاصيل (50000 - 59999)',
      'icon': Icons.eco_outlined,
      'color': Color(0xFF10B981),
    },
    {
      'key': 'packaging',
      'label': 'موردين مواد التعبئة والتغليف (70000 - 74999)',
      'icon': Icons.inventory_2_outlined,
      'color': Color(0xFF38BDF8),
    },
    {
      'key': 'shared',
      'label': 'الموردين المشتركين (75000 - 79999)',
      'icon': Icons.all_inclusive_outlined,
      'color': Color(0xFFF59E0B),
    },
  ];

  List<SupplierModel> _filterSuppliers(List<SupplierModel> suppliers, String filter) {
    if (filter == 'all') return suppliers;
    return suppliers.where((s) {
      final codeNum = int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), ''));
      switch (filter) {
        case 'crop':
          return s.supplierType == 'crop' ||
              (codeNum != null && codeNum >= 50000 && codeNum <= 59999);
        case 'packaging':
          return s.supplierType == 'packaging' ||
              (codeNum != null && codeNum >= 70000 && codeNum <= 74999);
        case 'shared':
          return s.supplierType == 'shared' ||
              (codeNum != null && codeNum >= 75000 && codeNum <= 79999);
        default:
          return true;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
   // context.read<SupplierCubit>().loadAll(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 768;
          final isShortHeight = constraints.maxHeight < 620;
          final padding = isCompact ? 12.0 : (isShortHeight ? 14.0 : 20.0);
          final gap = isShortHeight ? 10.0 : 14.0;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: BlocBuilder<SupplierCubit, SupplierState>(
              builder: (context, state) {
                final cubit = context.read<SupplierCubit>();
                final allSuppliers = state is SupplierLoaded ? state.suppliers : <SupplierModel>[];
                final filteredSuppliers = _filterSuppliers(allSuppliers, _selectedFilter);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(
                      context,
                      cubit,
                      state,
                      filteredSuppliers,
                      isCompact: isCompact,
                      isShortHeight: isShortHeight,
                    ),
                    SizedBox(height: gap),
                    if (_showKpiStrip && constraints.maxHeight >= 400) ...[
                      _buildKpiStrip(state, isShortHeight: isShortHeight),
                      SizedBox(height: gap),
                    ],
                    _buildFilterChips(state, isShortHeight: isShortHeight),
                    SizedBox(height: isShortHeight ? 8 : 10),
                    _buildSearchBar(cubit, state, isShortHeight: isShortHeight),
                    SizedBox(height: gap),
                    Expanded(child: _buildTable(context, cubit, state, filteredSuppliers)),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    SupplierCubit cubit,
    SupplierState state,
    List<SupplierModel> filteredSuppliers, {
    bool isCompact = false,
    bool isShortHeight = false,
  }) {
    final suppliers = state is SupplierLoaded ? state.suppliers : <SupplierModel>[];
    final isDark = ThemeCubit.isCurrentDark;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 768;
        final isMobile = isNarrow;

        final titleSection = Row(
          mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Container(
              width: isShortHeight ? 34 : (isMobile ? 38 : 44),
              height: isShortHeight ? 34 : (isMobile ? 38 : 44),
              decoration: BoxDecoration(
                color: (isDark ? AppTheme.primary : AppTheme.lightPrimary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.people_outline, color: isDark ? AppTheme.primary : AppTheme.lightPrimary, size: isShortHeight ? 18 : (isMobile ? 20 : 22)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'الموردون',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isShortHeight ? 20 : (isMobile ? 22 : 28),
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(
                          _showKpiStrip ? Icons.analytics : Icons.analytics_outlined,
                          size: 18,
                          color: _showKpiStrip ? AppTheme.primary : (isDark ? Colors.white54 : Colors.black45),
                        ),
                        tooltip: _showKpiStrip ? 'إخفاء شريط الإحصائيات' : 'إظهار شريط الإحصائيات',
                        onPressed: () => setState(() => _showKpiStrip = !_showKpiStrip),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      ),
                    ],
                  ),
                  Text(
                    _selectedFilter == 'all'
                        ? '${suppliers.length} مورد'
                        : '${filteredSuppliers.length} من أصل ${suppliers.length} مورد',
                    style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontFamily: 'Cairo',
                      fontSize: isShortHeight ? 11 : 13,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          children: [
            IconButton(
              icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white : const Color(0xFF0F172A), size: isShortHeight ? 20 : 22),
              tooltip: 'تحديث',
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: () => cubit.loadAll(reset: true),
            ),
            if (filteredSuppliers.isNotEmpty) ...[
              IconButton(
                icon: Icon(Icons.print_outlined, color: isDark ? Colors.white70 : const Color(0xFF334155), size: isShortHeight ? 20 : 22),
                tooltip: 'طباعة كشف حساب مجمع',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: () => _printStatement(filteredSuppliers),
              ),
              IconButton(
                icon: Icon(Icons.picture_as_pdf_outlined, color: isDark ? Colors.white70 : const Color(0xFF334155), size: isShortHeight ? 20 : 22),
                tooltip: 'حفظ PDF',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: () => _savePdf(filteredSuppliers),
              ),
            ],
            ElevatedButton.icon(
              icon: Icon(Icons.menu_book_rounded, size: isShortHeight ? 16 : 18),
              label: Text(isMobile ? 'دليل الأكواد' : 'دليل الأكواد الشامل', style: TextStyle(fontSize: isShortHeight ? 12 : 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: isShortHeight ? 10 : 14, vertical: isShortHeight ? 8 : 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              onPressed: _printMasterCodesDirectory,
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.add, size: isShortHeight ? 16 : 18),
              label: Text(isMobile ? 'إضافة مورد' : 'إضافة مورد جديد', style: TextStyle(fontSize: isShortHeight ? 12 : 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                    horizontal: isShortHeight ? 10 : (isMobile ? 14 : 18), vertical: isShortHeight ? 8 : 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              onPressed: () async {
                if (!ReadOnlyGuard.check(context)) return;
                await cubit.prepareAddForm();
                if (context.mounted) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => BlocProvider.value(
                      value: cubit,
                      child: const SupplierFormDialog(),
                    ),
                  );
                }
              },
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleSection,
              SizedBox(height: isShortHeight ? 6 : 10),
              Align(alignment: AlignmentDirectional.centerStart, child: actions),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: titleSection),
            actions,
          ],
        );
      },
    );
  }

  // ── KPI Summary Strip ──

  Widget _buildKpiStrip(SupplierState state, {bool isShortHeight = false}) {
    final loaded = state is SupplierLoaded ? state : null;
    final isLoading = state is SupplierLoading;

    final total     = loaded?.suppliers.length ?? 0;
    final cropCnt   = loaded?.cropCount ?? 0;
    final packCnt   = loaded?.packagingCount ?? 0;
    final sharedCnt = loaded?.sharedCount ?? 0;
    final currencies = loaded?.activeCurrencies ?? [];
    final totalEgpCurrent = loaded?.totalCurrentBalanceEgp ?? 0.0;
    final totalEgpInitial = loaded?.totalInitialBalanceEgp ?? 0.0;
    final rates = loaded?.exchangeRates ?? const {'EGP': 1.0};

    // Segregate balances by currency for Card 2 & Card 3
    final activeNonZeroCurrent = currencies.where((c) => c.nativeCurrentBalance.abs() > 0.001).toList();
    final activeNonZeroInitial = currencies.where((c) => c.nativeInitialBalance.abs() > 0.001).toList();

    // Card 2: Current balances headline & subtitle
    final String card2Value;
    final String card2Subtitle;
    if (isLoading) {
      card2Value = '…';
      card2Subtitle = '';
    } else if (currencies.isEmpty || activeNonZeroCurrent.isEmpty) {
      card2Value = '0.00 ج.م';
      card2Subtitle = 'لا توجد أرصدة مستحقة حالياً';
    } else if (activeNonZeroCurrent.length == 1) {
      final c = activeNonZeroCurrent.first;
      card2Value = SupplierModel.formatCurrency(c.nativeCurrentBalance, c.currency);
      card2Subtitle = c.currency == 'EGP'
          ? 'إجمالي الرصيد بالعملة المحلية'
          : 'معادل بالجنيه: ≈ ${AppUtils.formatNumber(totalEgpCurrent.abs())} ج.م';
    } else {
      final egpItem = activeNonZeroCurrent.where((c) => c.currency == 'EGP').firstOrNull;
      final foreignItems = activeNonZeroCurrent.where((c) => c.currency != 'EGP').toList();
      final parts = <String>[];
      if (egpItem != null) {
        parts.add('${AppUtils.formatNumber(egpItem.nativeCurrentBalance.abs())} ج.م');
      }
      for (final f in foreignItems) {
        parts.add(SupplierModel.formatCurrency(f.nativeCurrentBalance, f.currency));
      }
      card2Value = parts.join('  +  ');
      card2Subtitle = 'إجمالي معادل تقديري: ≈ ${AppUtils.formatNumber(totalEgpCurrent.abs())} ج.م';
    }

    // Card 3: Initial balances headline & subtitle
    final String card3Value;
    final String card3Subtitle;
    if (isLoading) {
      card3Value = '…';
      card3Subtitle = '';
    } else if (currencies.isEmpty || activeNonZeroInitial.isEmpty) {
      card3Value = '0.00 ج.م';
      card3Subtitle = 'لا توجد أرصدة افتتاحية مسجلة';
    } else if (activeNonZeroInitial.length == 1) {
      final c = activeNonZeroInitial.first;
      card3Value = SupplierModel.formatCurrency(c.nativeInitialBalance, c.currency);
      card3Subtitle = c.currency == 'EGP'
          ? 'إجمالي الأرصدة الافتتاحية'
          : 'معادل بالجنيه: ≈ ${AppUtils.formatNumber(totalEgpInitial.abs())} ج.م';
    } else {
      final egpItem = activeNonZeroInitial.where((c) => c.currency == 'EGP').firstOrNull;
      final foreignItems = activeNonZeroInitial.where((c) => c.currency != 'EGP').toList();
      final parts = <String>[];
      if (egpItem != null) {
        parts.add('${AppUtils.formatNumber(egpItem.nativeInitialBalance.abs())} ج.م');
      }
      for (final f in foreignItems) {
        parts.add(SupplierModel.formatCurrency(f.nativeInitialBalance, f.currency));
      }
      card3Value = parts.join('  +  ');
      card3Subtitle = 'إجمالي معادل افتتاحي: ≈ ${AppUtils.formatNumber(totalEgpInitial.abs())} ج.م';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;

        final cards = [
          // Card 1 — Total suppliers + type breakdown
          _buildKpiCard(
            icon: Icons.people_alt_outlined,
            label: 'إجمالي الموردين',
            value: isLoading ? '…' : '$total',
            color: AppTheme.primary,
            subtitle: 'محاصيل $cropCnt • تعبئة $packCnt • مشترك $sharedCnt',
            isLoading: isLoading,
            currencyPills: null,
            isShortHeight: isShortHeight,
          ),
          // Card 2 — Current balances (per currency)
          _buildKpiCard(
            icon: Icons.account_balance_wallet_outlined,
            label: 'إجمالي الأرصدة الحالية',
            value: card2Value,
            color: totalEgpCurrent >= 0 ? AppTheme.success : AppTheme.danger,
            subtitle: card2Subtitle,
            isLoading: isLoading,
            currencyPills: currencies.isEmpty
                ? null
                : currencies
                    .map((c) => _CurrencyPill(
                          label: SupplierModel.formatCurrency(
                            c.nativeCurrentBalance,
                            c.currency,
                          ),
                          count: c.supplierCount,
                          isNegative: c.nativeCurrentBalance < 0,
                        ))
                    .toList(),
            isShortHeight: isShortHeight,
          ),
          // Card 3 — Initial balances (per currency)
          _buildKpiCard(
            icon: Icons.history_edu_outlined,
            label: 'إجمالي الأرصدة المبدئية',
            value: card3Value,
            color: AppTheme.warning,
            subtitle: card3Subtitle,
            isLoading: isLoading,
            currencyPills: currencies.isEmpty
                ? null
                : currencies
                    .map((c) => _CurrencyPill(
                          label: SupplierModel.formatCurrency(
                            c.nativeInitialBalance,
                            c.currency,
                          ),
                          count: c.supplierCount,
                          isNegative: false,
                        ))
                    .toList(),
            isShortHeight: isShortHeight,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNarrow)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: cards
                      .map((c) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 12),
                            child: SizedBox(
                              width: math.max(260.0, (constraints.maxWidth - 24) * 0.72),
                              child: c,
                            ),
                          ))
                      .toList(),
                ),
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
            // Rate reference bar (only when foreign currencies are present)
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
    bool isShortHeight = false,
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
          padding: EdgeInsets.symmetric(
            horizontal: isShortHeight ? 14 : 18,
            vertical: isShortHeight ? 8 : 12,
          ),
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
                    width: isShortHeight ? 34 : 40,
                    height: isShortHeight ? 34 : 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: isDark ? 0.15 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: iconColor.withValues(alpha: isDark ? 0.25 : 0.3)),
                    ),
                    child: Icon(icon, color: iconColor, size: isShortHeight ? 18 : 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: isShortHeight ? 11 : 12,
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
                                fontSize: isShortHeight ? 16 : 19,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w900,
                                color: isDark ? color : const Color(0xFF0F172A),
                                height: 1.1,
                              ),
                            ),
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: isShortHeight ? 10 : 11,
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
              // ── Per-currency breakdown pills ──
              if (!isLoading && currencyPills != null && currencyPills.isNotEmpty) ...[
                SizedBox(height: isShortHeight ? 6 : 10),
                Divider(height: 1, color: isDark ? const Color(0x1AFFFFFF) : AppTheme.lightBorder),
                SizedBox(height: isShortHeight ? 4 : 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
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
              fontWeight: FontWeight.bold,
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(SupplierState state, {bool isShortHeight = false}) {
    final loaded = state is SupplierLoaded ? state : null;
    final suppliers = loaded?.suppliers ?? <SupplierModel>[];

    int getCount(String key) {
      if (key == 'all') return suppliers.length;
      return suppliers.where((s) {
        final codeNum = int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), ''));
        switch (key) {
          case 'crop':
            return s.supplierType == 'crop' ||
                (codeNum != null && codeNum >= 50000 && codeNum <= 59999);
          case 'packaging':
            return s.supplierType == 'packaging' ||
                (codeNum != null && codeNum >= 70000 && codeNum <= 74999);
          case 'shared':
            return s.supplierType == 'shared' ||
                (codeNum != null && codeNum >= 75000 && codeNum <= 79999);
          default:
            return false;
        }
      }).length;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _filterOptions.map((opt) {
          final key = opt['key'] as String;
          final label = opt['label'] as String;
          final icon = opt['icon'] as IconData;
          final color = opt['color'] as Color;
          final isSelected = _selectedFilter == key;
          final count = getCount(key);

          final isDark = ThemeCubit.isCurrentDark;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedFilter = key;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(horizontal: isShortHeight ? 10 : 14, vertical: isShortHeight ? 5 : 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: isDark ? 0.18 : 0.15)
                      : (isDark ? const Color(0xFF0A1E35).withValues(alpha: 0.7) : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color : (isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : (!isDark
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: isShortHeight ? 14 : 16,
                      color: isSelected
                          ? (isDark ? color : (color == AppTheme.primary ? const Color(0xFF0284C7) : color))
                          : (isDark ? AppTheme.textSecondary : const Color(0xFF334155)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isShortHeight ? 11 : 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? (isDark ? Colors.white : (color == AppTheme.primary ? const Color(0xFF0284C7) : color))
                            : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: isDark ? 0.3 : 0.25)
                            : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: isShortHeight ? 10 : 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                            ? (isDark ? color : (color == AppTheme.primary ? const Color(0xFF0284C7) : color))
                            : (isDark ? AppTheme.textSecondary : const Color(0xFF0F172A)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar(SupplierCubit cubit, SupplierState state, {bool isShortHeight = false}) {
    final searchQuery = state is SupplierLoaded ? state.searchQuery : '';

    return SizedBox(
      height: isShortHeight ? 38 : 46,
      child: TextField(
        onChanged: cubit.onSearchChanged,
        style: TextStyle(fontSize: isShortHeight ? 12 : 13, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isShortHeight ? 8 : 12),
          hintText: 'بحث بالاسم أو الكود...',
          prefixIcon: Icon(Icons.search, size: isShortHeight ? 18 : 20),
          suffixIcon: searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.clear, size: isShortHeight ? 16 : 18),
                  onPressed: () => cubit.onSearchChanged(''),
                ),
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context, SupplierCubit cubit, SupplierState state, List<SupplierModel> suppliers) {
    if (state is SupplierLoading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final allSuppliers = state is SupplierLoaded ? state.suppliers : <SupplierModel>[];
    final searchQuery = state is SupplierLoaded ? state.searchQuery : '';

    if (suppliers.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: _buildEmptyState(cubit, searchQuery, allCount: allSuppliers.length),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: _buildDataTable(cubit, suppliers),
        ),
      ),
    );
  }

  Widget _buildDataTable(SupplierCubit cubit, List<SupplierModel> suppliers) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    maxWidth: math.max(constraints.maxWidth, 920),
                  ),
                  child: Column(
                    children: [
                      _buildTableHeader(),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: suppliers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, index) {
                            return _buildTableRow(context, cubit, suppliers[index], index);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableHeader() {
    final isDark = ThemeCubit.isCurrentDark;
    final labelStyle = TextStyle(
      color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
      fontWeight: FontWeight.w600,
      fontFamily: 'Cairo',
      fontSize: 13,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFF1F5F9),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text('#', style: labelStyle)),
          SizedBox(width: 90, child: Text('الكود', style: labelStyle)),
          Expanded(flex: 3, child: Text('الاسم', style: labelStyle)),
          SizedBox(width: 95, child: Text('النوع', style: labelStyle, textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('العنوان', style: labelStyle)),
          SizedBox(width: 100, child: Text('الهاتف', style: labelStyle)),
          SizedBox(width: 150, child: Text('الرصيد الحالي', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 150, child: Text('الرصيد المبدئي', style: labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('إجراءات', style: labelStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildSupplierTypeBadge(String supplierType) {
    final Color color;
    final Color bgColor;
    final String label;
    final IconData icon;

    switch (supplierType) {
      case 'crop':
        color = const Color(0xFF10B981);
        bgColor = const Color(0x1A10B981);
        label = 'محاصيل';
        icon = Icons.eco_outlined;
        break;
      case 'packaging':
        color = const Color(0xFF38BDF8);
        bgColor = const Color(0x1A38BDF8);
        label = 'مواد تعبئة';
        icon = Icons.inventory_2_outlined;
        break;
      case 'shared':
      default:
        color = const Color(0xFFF59E0B);
        bgColor = const Color(0x1AF59E0B);
        label = 'مشترك';
        icon = Icons.all_inclusive_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600, fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, SupplierCubit cubit, SupplierModel supplier, int index) {
    final isEven = index % 2 == 0;
    final isForeign = supplier.isForeignCurrency;
    final isMultiCurrent = isForeign ||
        supplier.supportsMultiCurrency ||
        supplier.hasMultiCurrencyInitialBalance ||
        supplier.currentBalancesByCurrency.length > 1;

    final isMultiInitial = isForeign ||
        supplier.supportsMultiCurrency ||
        supplier.hasMultiCurrencyInitialBalance;

    final loadedRates = cubit.state is SupplierLoaded
        ? (cubit.state as SupplierLoaded).exchangeRates
        : const {'EGP': 1.0};

    final double? initialEgpEq = (isForeign || supplier.supportsMultiCurrency)
        ? (isForeign
            ? (supplier.initialBalancesByCurrency[supplier.currency]?.amountInEgp ??
                (supplier.initialBalance * (loadedRates[supplier.currency] ?? 1.0)))
            : supplier.totalInitialBalanceInEgp)
        : null;

    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      color: isEven
          ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.transparent)
          : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('${index + 1}', style: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ),

          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                supplier.supplierCode.isNotEmpty ? supplier.supplierCode : '—',
                style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              supplier.name,
              style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 95,
            child: Center(
              child: _buildSupplierTypeBadge(supplier.supplierType),
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              supplier.address.isNotEmpty ? supplier.address : '—',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              supplier.phone.isNotEmpty ? supplier.phone : '—',
              style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 13),
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 150,
            child: _buildBalanceCell(
              balanceText: supplier.formattedCurrentBalance,
              isMulti: isMultiCurrent,
              isNegative: supplier.outstandingBalance < 0,
              egpEquivalent: (isForeign || supplier.supportsMultiCurrency)
                  ? supplier.outstandingBalance
                  : null,
              currenciesMap: supplier.currentBalancesByCurrency,
            ),
          ),

          SizedBox(
            width: 150,
            child: _buildBalanceCell(
              balanceText: supplier.formattedInitialBalance,
              isMulti: isMultiInitial,
              isNegative: supplier.initialBalanceDirection == 'DEBIT',
              egpEquivalent: initialEgpEq,
              currenciesMap: supplier.initialBalancesByCurrency.map(
                (k, v) => MapEntry(
                    k, v.direction.toUpperCase() == 'DEBIT' ? -v.amount : v.amount),
              ),
            ),
          ),

          SizedBox(
            width: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showEditDialog(context, cubit, supplier),
                  child: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCell({
    required String balanceText,
    required bool isMulti,
    required bool isNegative,
    double? egpEquivalent,
    Map<String, double>? currenciesMap,
  }) {
    return MultiCurrencyBalanceBadge(
      balanceText: balanceText,
      isMulti: isMulti,
      isNegative: isNegative,
      egpEquivalent: egpEquivalent,
      currenciesMap: currenciesMap,
    );
  }

  Widget _buildEmptyState(SupplierCubit cubit, String searchQuery, {int allCount = 0}) {
    final isCategoryFiltered = _selectedFilter != 'all';
    final activeOption = _filterOptions.firstWhere(
      (opt) => opt['key'] == _selectedFilter,
      orElse: () => _filterOptions.first,
    );
    final activeLabel = activeOption['label'] as String;

    final isDark = ThemeCubit.isCurrentDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCategoryFiltered ? (activeOption['icon'] as IconData) : Icons.people_outline,
              size: 72,
              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.3) : AppTheme.lightTextMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isNotEmpty
                  ? 'لا توجد نتائج مطابقة للبحث'
                  : isCategoryFiltered
                      ? 'لا يوجد موردين في تصنيف "$activeLabel"'
                      : 'لا يوجد موردين بعد',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.textSecondary : AppTheme.lightTextPrimary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery.isNotEmpty
                  ? 'جرب البحث باسم أو كود مختلف أو التبديل إلى تصنيف آخر'
                  : isCategoryFiltered
                      ? 'يمكنك التبديل إلى "عرض الكل" للاطلاع على جميع الموردين ($allCount مورد)'
                      : 'اضغط "إضافة مورد" لإضافة أول مورد',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (isCategoryFiltered) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('عرض كل الموردين', style: TextStyle(fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _selectedFilter = 'all'),
              ),
            ] else if (searchQuery.isEmpty) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة مورد'),
                onPressed: () async {
                  await cubit.prepareAddForm();
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (_) => BlocProvider.value(value: cubit, child: const SupplierFormDialog()),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLedgerSheet(BuildContext context, SupplierModel supplier) {
    final dao = TreasuryDao();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: dao.getLedgerEntries(
              entityType: 'supplier',
              entityId: '${supplier.id}',
            ),
            builder: (_, snap) {
              final entries = snap.data ?? [];
              double runningBalance = supplier.initialBalance;
              return Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
                decoration: BoxDecoration(
                  color: const Color(0xFF05192D),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: AppTheme.glassBorder)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.receipt_long_outlined, color: AppTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('كشف حساب: ${supplier.name}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('الرصيد المبدئي: ${supplier.formattedInitialBalance}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                        const Spacer(),
                        Text('الرصيد الحالي: ${supplier.formattedCurrentBalance}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.success, fontFamily: 'Cairo')),
                      ]),
                      const SizedBox(height: 12),
                      if (snap.connectionState == ConnectionState.waiting)
                        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                      else if (snap.hasError)
                        Center(child: Text('خطأ في التحميل: ${snap.error}', style: const TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')))
                      else if (entries.isEmpty)
                        const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد حركات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))))
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.glassBorder),
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              final entryType = e['entry_type']?.toString() ?? '';
                              final amount = ((e['amount'] as num?)?.toDouble() ?? 0);
                              final isDebit = entryType == 'credit';
                              final refType = e['reference_type']?.toString() ?? '';
                              runningBalance += isDebit ? amount : -amount;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(children: [
                                  Icon(isDebit ? Icons.arrow_downward : Icons.arrow_upward,
                                      size: 16, color: isDebit ? AppTheme.success : AppTheme.warning),
                                  const SizedBox(width: 8),
                                  Expanded(flex: 2, child: Text(
                                    refType == 'opening_balance' ? 'رصيد افتتاحي' :
                                    refType == 'expense' ? 'مصروف' :
                                    refType == 'payment' ? 'دفع' :
                                    refType == 'packing_order_debit_note' ? 'إشعار خصم أمر تعبئة' :
                                    refType == 'reversal' ? 'عكس' : refType,
                                    style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo'))),
                                  Text('${e['currency'] ?? 'EGP'} ${AppUtils.formatNumber(amount)}',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDebit ? AppTheme.success : AppTheme.warning, fontFamily: 'Cairo')),
                                  const SizedBox(width: 16),
                                  Text(AppUtils.formatNumber(runningBalance),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                                ]),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context, SupplierCubit cubit, SupplierModel supplier) async {
    if (!ReadOnlyGuard.check(context)) return;
    final verified = await showPasswordVerificationDialog(context);
    if (!verified) return;
    if (!context.mounted) return;
    await cubit.prepareEditForm(supplier);
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (_) => BlocProvider.value(value: cubit, child: SupplierFormDialog(supplier: supplier)),
      );
    }
  }

  void _showDeleteConfirm(BuildContext context, SupplierCubit cubit, SupplierModel supplier) {
    if (!ReadOnlyGuard.check(context)) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف "${supplier.name}"؟', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final errorCode = await cubit.deleteSupplier(supplier.supplierCode);
              if (errorCode == '23503' && context.mounted) {
                _showFkDeleteError(context, 'المورد');
              }
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  void _showFkDeleteError(BuildContext context, String entityLabel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: Text('لا يمكن حذف $entityLabel',
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هذا $entityLabel مرتبط بفواتير شراء أو معاملات مالية مسجلة داخل النظام، لذلك لا يمكن حذفه حفاظاً على سلامة البيانات المحاسبية.',
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              'إذا كنت لا ترغب في استخدام هذا $entityLabel مستقبلاً، يفضل تعطيله أو إخفاؤه بدلاً من حذفه.',
              style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.7), fontFamily: 'Cairo', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً', style: TextStyle(color: AppTheme.primary, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<void> _printStatement(List<SupplierModel> suppliers) async {
    final state = context.read<SupplierCubit>().state;
    final loaded = state is SupplierLoaded ? state : null;

    try {
      await SupplierConsolidatedStatementPdfService.generateAndPrint(
        suppliers: suppliers,
        balanceByCurrency: loaded?.balanceByCurrency,
        totalCurrentBalanceEgp: loaded?.totalCurrentBalanceEgp,
        totalInitialBalanceEgp: loaded?.totalInitialBalanceEgp,
        cropCount: loaded?.cropCount,
        packagingCount: loaded?.packagingCount,
        sharedCount: loaded?.sharedCount,
        exchangeRates: loaded?.exchangeRates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _savePdf(List<SupplierModel> suppliers) async {
    final state = context.read<SupplierCubit>().state;
    final loaded = state is SupplierLoaded ? state : null;

    try {
      await SupplierConsolidatedStatementPdfService.saveToFile(
        context,
        suppliers: suppliers,
        balanceByCurrency: loaded?.balanceByCurrency,
        totalCurrentBalanceEgp: loaded?.totalCurrentBalanceEgp,
        totalInitialBalanceEgp: loaded?.totalInitialBalanceEgp,
        cropCount: loaded?.cropCount,
        packagingCount: loaded?.packagingCount,
        sharedCount: loaded?.sharedCount,
        exchangeRates: loaded?.exchangeRates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _printMasterCodesDirectory() async {
    try {
      await MasterCodesDirectoryPdfService.generateAndPrint(context);
    } catch (e) {
      if (mounted) {
        UIUtils.showErrorSnackbar(context, 'فشل في طباعة دليل الأكواد الشامل: $e');
      }
    }
  }
}

// ── Private data class for per-currency pill rendering ──────────────────────
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
