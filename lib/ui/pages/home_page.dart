import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../features/auth/auth_cubit.dart';
import '../../features/dashboard/dashboard_cubit.dart';
import '../../features/dashboard/dashboard_state.dart';

import '../../features/dashboard/widgets/kpi_card.dart';
import '../../features/dashboard/widgets/charts_section.dart';
import '../../features/dashboard/widgets/top_fruits_widget.dart';
import '../../features/dashboard/widgets/top_customers_chart.dart';

import '../../features/dashboard/widgets/balances_section.dart';
import '../../features/dashboard/widgets/quick_actions.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final AnimationController _staggerCtrl;
  late final List<Animation<double>> _staggerAnims;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _staggerAnims = List.generate(12, (i) {
      return CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(i * 0.08, 0.6 + i * 0.04, curve: Curves.easeOutCubic),
      );
    });
    _staggerCtrl.forward();
    _loadData();
  }

  void _loadData() {
    context.read<DashboardCubit>()..loadAll()..loadBadgeCounts();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        final authState = context.watch<AuthCubit>().state;
        final userName = authState is AuthAuthenticated
            ? (authState.fullName ?? authState.email ?? 'مستخدم')
            : 'مستخدم';
            
        bool hasHomeAccess = true;
        if (authState is AuthAuthenticated && !authState.isAdmin) {
          hasHomeAccess = authState.allowedPages.contains('/home');
        }

        if (!hasHomeAccess) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 64, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      authState is AuthAuthenticated && authState.allowedPages.isEmpty 
                        ? 'يرجى الانتظار حتى يقوم مدير النظام بتحديد صلاحياتك'
                        : 'عفواً، لا تملك صلاحية للوصول للصفحة الرئيسية',
                      style: const TextStyle(color: Colors.white70, fontSize: 18, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                Expanded(
                  child: state.loading ? _buildLoading() : _buildContent(state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...List.generate(6, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0x1A0A1E3A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.glassBorder.withAlpha(60)),
                  ),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildContent(DashboardState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ROW 1: KPI Cards
          _buildSection(
            _buildKpiRow(state),
            0,
          ),
          const SizedBox(height: 16),

          // ROW 2: Charts
          _buildSection(
            _buildChartsRow(state),
            1,
          ),
          const SizedBox(height: 16),

          // ROW 3: Customers + Timeline + Balances
          _buildSection(
            _buildThirdRow(state),
            2,
          ),
          const SizedBox(height: 16),

          // ROW 4: Shipments + Products + Analytics
          _buildSection(
            _buildFourthRow(state),
            3,
          ),
          const SizedBox(height: 16),

          // ROW 5: Quick Actions
          _buildSection(
            _buildQuickActions(),
            4,
          ),
        ],
      ),
    );
  }

  Widget _buildSection(Widget child, int index) {
    return FadeTransition(
      opacity: _staggerAnims[index],
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(_staggerAnims[index]),
        child: child,
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 16),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = children.length;
        final crossAxisCount = constraints.maxWidth > 1400
            ? (count >= 6 ? 6 : count >= 5 ? 5 : count >= 4 ? 4 : count)
            : constraints.maxWidth > 1100
                ? (count >= 5 ? 5 : count >= 4 ? 4 : count >= 3 ? 3 : count)
                : constraints.maxWidth > 700
                    ? (count >= 3 ? 3 : count >= 2 ? 2 : count)
                    : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: children,
        );
      },
    );
  }

  Widget _buildKpiRow(DashboardState state) {
    final rollingMonthlySales = state.monthlySales.fold<double>(
      0.0,
      (sum, item) => sum + ((item['sales'] as num?)?.toDouble() ?? 0.0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('الأداء المالي', Icons.account_balance_wallet_outlined),
        _buildKpiGrid([
          KpiCard(
            title: 'إجمالي المبيعات',
            value: (state.totalSales?['value'] as num?)?.toDouble() ?? 0.0,
            change: (state.totalSales?['change'] as num?)?.toDouble() ?? 0.0,
            icon: Icons.trending_up,
            color: AppTheme.primary,
            loading: state.loading,
            onTap: () => context.push('/exports'),
          ),
          KpiCard(
            title: 'مبيعات آخر 30 يوم',
            value: rollingMonthlySales,
            change: 0.0,
            icon: Icons.monetization_on_outlined,
            color: AppTheme.accent,
            loading: state.loading,
            onTap: () => context.push('/exports'),
          ),
          KpiCard(
            title: 'مبيعات اليوم',
            value: (state.todaySales?['value'] as num?)?.toDouble() ?? 0.0,
            change: 0.0,
            icon: Icons.today,
            color: AppTheme.cyan,
            loading: state.loading,
            onTap: () => context.push('/exports'),
          ),
          KpiCard(
            title: 'صافي الأرباح',
            value: (state.totalProfit?['value'] as num?)?.toDouble() ?? 0.0,
            change: (state.totalProfit?['change'] as num?)?.toDouble() ?? 0.0,
            icon: Icons.account_balance,
            color: AppTheme.success,
            loading: state.loading,
            onTap: () => context.push('/exports/profit'),
          ),
          KpiCard(
            title: 'إجمالي الإيرادات',
            value: (state.totalSales?['value'] as num?)?.toDouble() ?? 0.0,
            change: 0.0,
            icon: Icons.trending_up,
            color: AppTheme.primary,
            loading: state.loading,
            onTap: () => context.push('/exports/profit'),
          ),
        ]),
        const SizedBox(height: 16),
        _buildSectionHeader('الملخص التشغيلي', Icons.settings_outlined),
        _buildKpiGrid([
          KpiCard(
            title: 'الشحنات النشطة',
            value: (state.activeShipments?['value'] as num?)?.toDouble() ?? 0.0,
            change: (state.activeShipments?['change'] as num?)?.toDouble() ?? 0.0,
            icon: Icons.flight,
            color: AppTheme.primary,
            loading: state.loading,
            onTap: () => context.push('/exports'),
          ),
          KpiCard(
            title: 'العملاء',
            value: (state.customerCount?['value'] as num?)?.toDouble() ?? 0.0,
            change: (state.customerCount?['change'] as num?)?.toDouble() ?? 0.0,
            icon: Icons.people,
            color: AppTheme.warning,
            loading: state.loading,
            onTap: () => context.push('/customers'),
          ),
          KpiCard(
            title: 'الموردين',
            value: (state.supplierCount?['value'] as num?)?.toDouble() ?? 0.0,
            change: 0.0,
            icon: Icons.people_outline,
            color: AppTheme.success,
            loading: state.loading,
            onTap: () => context.push('/suppliers'),
          ),
          KpiCard(
            title: 'الأصناف',
            value: (state.productCount?['value'] as num?)?.toDouble() ?? 0.0,
            change: 0.0,
            icon: Icons.inventory_2_outlined,
            color: AppTheme.accent,
            loading: state.loading,
            onTap: () => context.push('/fruit-types'),
          ),
          KpiCard(
            title: 'أصناف منخفضة المخزون',
            value: (state.lowStockCount?['value'] as num?)?.toDouble() ?? 0.0,
            change: 0.0,
            icon: Icons.warning_amber_outlined,
            color: AppTheme.danger,
            loading: state.loading,
            onTap: () => context.push('/raw-materials', extra: true),
          ),
        ]),
      ],
    );
  }

  Widget _buildChartsRow(DashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 1200) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildChartCard(LineChartWidget(data: state.monthlySales))),
              const SizedBox(width: 10),
              Expanded(flex: 4, child: _buildChartCard(TopFruitsWidget(products: state.topProducts))),
              const SizedBox(width: 10),
              Expanded(flex: 4, child: _buildChartCard(DestinationsMapWidget(destinations: state.exportDestinations))),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: 250, child: _buildChartCard(LineChartWidget(data: state.monthlySales))),
            const SizedBox(height: 10),
            _buildChartCard(TopFruitsWidget(products: state.topProducts)),
            const SizedBox(height: 10),
            _buildChartCard(DestinationsMapWidget(destinations: state.exportDestinations)),
          ],
        );
      },
    );
  }

  Widget _buildThirdRow(DashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 1200) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _buildChartCard(TopCustomersBarChart(customers: state.topCustomers))),
              const SizedBox(width: 10),
              Expanded(flex: 5, child: _buildChartCard(BalancesSection(
                treasuryBalances: state.treasuryBalances,
                bankBalances: state.bankBalances,
              ))),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: 250, child: _buildChartCard(TopCustomersBarChart(customers: state.topCustomers))),
            const SizedBox(height: 10),
            SizedBox(height: 300, child: _buildChartCard(BalancesSection(
              treasuryBalances: state.treasuryBalances,
              bankBalances: state.bankBalances,
            ))),
          ],
        );
      },
    );
  }

  Widget _buildFourthRow(DashboardState state) {
    return const SizedBox.shrink();
  }

  Widget _buildQuickActions() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x1A0A1E3A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withAlpha(60)),
          ),
          child: const QuickActionsGrid(),
        ),
      ),
    );
  }

  Widget _buildChartCard(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x1A0A1E3A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withAlpha(60)),
          ),
          height: 300,
          child: child,
        ),
      ),
    );
  }

}
