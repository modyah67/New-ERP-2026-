import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/export_invoice_model.dart';
import 'export_dashboard_cubit.dart';
import 'export_dashboard_state.dart';

class ExportDashboardPage extends StatefulWidget {
  const ExportDashboardPage({super.key});

  @override
  State<ExportDashboardPage> createState() => _ExportDashboardPageState();
}

class _ExportDashboardPageState extends State<ExportDashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExportDashboardCubit>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.cyberBg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.cyberBg, Color(0xFF0D2137), AppTheme.cyberBg],
            ),
          ),
          child: BlocBuilder<ExportDashboardCubit, ExportDashboardState>(
            builder: (context, state) {
              if (state is ExportDashboardLoading) return _buildLoading();
              if (state is ExportDashboardLoaded) return _buildContent(state);
              if (state is ExportDashboardError) return _buildError(state);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _shimmerContainer(width: 60, height: 60, radius: 30),
          const SizedBox(height: 20),
          _shimmerContainer(width: 200, height: 16, radius: 8),
          const SizedBox(height: 12),
          _shimmerContainer(width: 140, height: 12, radius: 6),
        ],
      ),
    );
  }

  Widget _shimmerContainer({double width = double.infinity, double height = 16, double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildError(ExportDashboardError state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 40),
          ),
          const SizedBox(height: 16),
          Text(state.message, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 14)),
          const SizedBox(height: 20),
          _buildGlassButton('إعادة المحاولة', Icons.refresh_rounded, () => context.read<ExportDashboardCubit>().load()),
        ],
      ),
    );
  }

  Widget _buildContent(ExportDashboardLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(state),
          const SizedBox(height: 16),
          _buildKpiGrid(state),
          const SizedBox(height: 20),
          _buildCurrencyPanel(),
          const SizedBox(height: 20),
          _buildMonthlyChart(state),
          const SizedBox(height: 20),
          _buildRecentTable(state),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────

  Widget _buildHeader(ExportDashboardLoaded state) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.15), blurRadius: 12),
                  ],
                ),
                child: const Icon(Icons.analytics_outlined, color: AppTheme.neonCyan, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تحليلات التصدير', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    Text('${state.totalInvoices} فاتورة مصدرة', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
                  ],
                ),
              ),
              _buildGlassButton('تحديث', Icons.refresh_rounded, () => context.read<ExportDashboardCubit>().load()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.neonCyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.neonCyan, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppTheme.neonCyan, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── KPI Grid ───────────────────────────────────

  Widget _buildKpiGrid(ExportDashboardLoaded state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            _kpiCard(
              icon: Icons.inventory_2_outlined,
              label: 'إجمالي كمية الصادرات',
              value: '${AppUtils.formatNumber(state.totalCartons.toDouble())} كرتونة',
              sub: '${state.totalPallets} باليتة',
              color: AppTheme.emerald,
            ),
            _kpiCard(
              icon: Icons.monitor_weight_outlined,
              label: 'الوزن الصافي الإجمالي',
              value: '${AppUtils.formatNumber(state.totalNetWeight / 1000)} الطن',
              sub: '${AppUtils.formatNumber(state.totalNetWeight)} كجم',
              color: AppTheme.neonCyan,
            ),
            _kpiCard(
              icon: Icons.scale_outlined,
              label: 'الأوزان القائمة',
              value: '${AppUtils.formatNumber(state.totalGrossWeight / 1000)} الطن',
              sub: _tareRatio(state),
              color: AppTheme.warning,
            ),
            _kpiCard(
              icon: Icons.local_shipping_outlined,
              label: 'توزيع وسائل النقل',
              value: 'بحري ${state.seaCount}',
              sub: 'جوي ${state.airCount}',
              color: AppTheme.info,
            ),
          ],
        );
      },
    );
  }

  String _tareRatio(ExportDashboardLoaded state) {
    if (state.totalGrossWeight == 0) return '0% تغليف';
    final pct = ((state.totalGrossWeight - state.totalNetWeight) / state.totalGrossWeight * 100);
    return '${pct.toStringAsFixed(1)}% تغليف';
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xB3141A24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const Spacer(),
                    Container(
                      width: 36, height: 3,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 6)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontFamily: 'Cairo')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Currency Panel ─────────────────────────────

  Widget _buildCurrencyPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xB3141A24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('التحصيل المالي متعدد العملات', Icons.account_balance_wallet_outlined),
                const SizedBox(height: 16),
                _currencyRow('USD', '\$', 48400, const Color(0xFF2196F3)),
                const SizedBox(height: 10),
                _currencyRow('EUR', '€', 32200, const Color(0xFF1565C0)),
                const SizedBox(height: 10),
                _currencyRow('GBP', '£', 18100, const Color(0xFFE91E63)),
                const SizedBox(height: 10),
                _currencyRow('EGP', 'ج.م', 1250000, const Color(0xFF10B981)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currencyRow(String code, String symbol, double amount, Color color) {
    final maxVal = 1250000.0;
    final pct = (amount / maxVal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$symbol $code', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
            const Spacer(),
            Text('${AppUtils.formatNumber(amount)} $symbol', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Monthly Chart ──────────────────────────────

  Widget _buildMonthlyChart(ExportDashboardLoaded state) {
    if (state.monthlyData.isEmpty) return const SizedBox();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xB3141A24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('الشحنات الشهرية', Icons.bar_chart_rounded),
                const SizedBox(height: 20),
                SizedBox(
                  height: 160,
                  child: _BarChart(data: state.monthlyData),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Recent Table ───────────────────────────────

  Widget _buildRecentTable(ExportDashboardLoaded state) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xB3141A24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('أحدث الشحنات الصادرة', Icons.receipt_long_outlined),
                const SizedBox(height: 12),
                if (state.recentInvoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('لا توجد فواتير', style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo'))),
                  )
                else
                  ...state.recentInvoices.map(_buildInvoiceRow),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceRow(ExportInvoiceModel inv) {
    final isSea = inv.transportMode == 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(inv.invoiceNo, style: const TextStyle(color: AppTheme.neonCyan, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Cairo'))),
          Expanded(flex: 4, child: Text(inv.customerName ?? '—', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isSea ? Icons.directions_boat_outlined : Icons.flight_outlined, size: 14, color: isSea ? AppTheme.info : AppTheme.warning),
                const SizedBox(width: 4),
                Text(isSea ? 'بحري' : 'جوي', style: TextStyle(color: isSea ? AppTheme.info : AppTheme.warning, fontSize: 11, fontFamily: 'Cairo')),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text('${AppUtils.formatNumber(inv.totalNetWeight)} كجم', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'))),
          GestureDetector(
            onTap: () => _openPreview(inv),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: const Text('معاينة', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
            ),
          ),
        ],
      ),
    );
  }

  void _openPreview(ExportInvoiceModel inv) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primary, size: 48),
              const SizedBox(height: 12),
              Text('معاينة: ${inv.invoiceNo}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 8),
              const Text('سيتم فتح معاينة PDF قريباً', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
        ],
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppTheme.neonCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.neonCyan, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ],
    );
  }
}

// ── Custom Bar Chart ──────────────────────────────

class _BarChart extends StatelessWidget {
  final List<MonthlyBucket> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();
    int max = 0;
    for (final b in data) {
      if (b.count > max) max = b.count;
    }
    final maxCount = max.toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = (constraints.maxWidth - (data.length - 1) * 6) / data.length;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((bucket) {
            final fraction = maxCount > 0 ? bucket.count / maxCount : 0.0;
            final height = fraction * 130;
            return Padding(
              padding: EdgeInsets.only(left: data.last == bucket ? 0 : 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: barWidth.clamp(16, 40),
                    height: height.clamp(4, 130),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppTheme.neonCyan.withValues(alpha: 0.3),
                          AppTheme.neonCyan,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.2), blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${bucket.month}', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9, fontFamily: 'Cairo')),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
