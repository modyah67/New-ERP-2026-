import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_state_notifier.dart';
import '../../features/auth/auth_cubit.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/services/shipment_profitability_service.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/models/export_shipment_model.dart';

class ProfitDashboardPage extends StatefulWidget {
  const ProfitDashboardPage({super.key});

  @override
  State<ProfitDashboardPage> createState() => _ProfitDashboardPageState();
}

class _ProfitDashboardPageState extends State<ProfitDashboardPage> {
  final _dao = ExportShipmentDao();
  final _profitabilityService = ShipmentProfitabilityService();
  Map<String, dynamic>? _summary;
  List<ExportShipmentModel> _shipments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final allShipments = await _dao.getAll(limit: 200, excludeStatus: 'cancelled');
      final shipments = allShipments.where((s) => s.isConfirmed).toList();
      // Use profitability snapshot DAO for summary if available
      final summary = await _dao.getProfitSummary();
      
      // Calculations moved to async method
      if (mounted) {
        setState(() {
          _shipments = shipments;
          _summary = summary;
          _loading = false;
        });
      }
      
      _calculateMissingProfitability();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _calculateMissingProfitability() async {
    bool updated = false;
    for (int i = 0; i < _shipments.length; i++) {
      if (!mounted) break;
      // If total landed cost is 0 or net profit is not recorded
      if (_shipments[i].totalLandedCost > 0 && _shipments[i].netProfitEgp != 0) continue;
      try {
        final result = await _profitabilityService.calculateShipment(_shipments[i].id!.toString());
        if (mounted) {
          setState(() {
            _shipments[i] = _shipments[i].copyWith(
              netProfit: result.netProfit,
              netProfitEgp: result.netProfit,
              totalLandedCost: result.totalCost,
              totalRevenueEgp: result.revenueEgp,
              totalRevenueForeign: result.revenueEur,
              totalFruitCost: result.fruitCost,
              totalPackingMaterialCost: result.packingCost,
              grossProfit: result.grossProfit,
            );
          });
          updated = true;
        }
      } catch (e) {
        debugPrint('Error calculating costs for shipment ${_shipments[i].id}: $e');
      }
    }
    if (updated && mounted) {
      setState(() {
        _recalculateSummaryFromList();
      });
    }
  }

  void _recalculateSummaryFromList() {
    double totalRev = 0;
    double totalCost = 0;
    double totalProf = 0;
    for (final s in _shipments) {
      totalRev += s.totalRevenueEgp;
      totalCost += s.totalLandedCost > 0
          ? s.totalLandedCost
          : (s.totalFruitCost + s.totalPackingMaterialCost);
      totalProf += s.netProfitEgp;
    }
    _summary = {
      'total_revenue_egp': totalRev,
      'total_cost_egp': totalCost,
      'net_profit_egp': totalProf,
      'shipment_count': _shipments.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: authNotifier,
      builder: (context, authState, _) {
        final bool hideProfit;
        if (authState is AuthAuthenticated && !authState.isAdmin) {
          hideProfit = true;
        } else {
          hideProfit = false;
        }
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: AppTheme.background,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
                ),
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _loading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                      : _buildContent(hideProfit),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 20, right: 20),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.trending_up, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('لوحة الربحية',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool hideProfit) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (!hideProfit) ...[
            _buildSummaryCards(),
            const SizedBox(height: 20),
          ],
          _buildShipmentList(hideProfit),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final rev = (_summary?['total_revenue_egp'] as num?)?.toDouble() ?? 0;
    final cost = (_summary?['total_cost_egp'] as num?)?.toDouble() ?? 0;
    final profit = (_summary?['net_profit_egp'] as num?)?.toDouble() ?? 0;
    final count = (_summary?['shipment_count'] as num?)?.toInt() ?? 0;
    final isProfit = profit >= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final cards = [
          _summaryCard('إجمالي الإيرادات', 'EGP ${_fmt(rev)}', AppTheme.success, Icons.arrow_upward),
          _summaryCard('إجمالي التكاليف', 'EGP ${_fmt(cost)}', AppTheme.warning, Icons.arrow_downward),
          _summaryCard('صافي الأرباح', 'EGP ${_fmt(profit)}', isProfit ? AppTheme.success : AppTheme.danger, isProfit ? Icons.trending_up : Icons.trending_down),
          _summaryCard('عدد الشحنات', '$count', AppTheme.primary, Icons.flight_outlined),
        ];

        if (isMobile) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(width: 150, child: cards[0]),
                const SizedBox(width: 10),
                SizedBox(width: 150, child: cards[1]),
                const SizedBox(width: 10),
                SizedBox(width: 150, child: cards[2]),
                const SizedBox(width: 10),
                SizedBox(width: 130, child: cards[3]),
              ],
            ),
          );
        } else {
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
              const SizedBox(width: 10),
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ],
          );
        }
      },
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo'),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildShipmentList(bool hideProfit) {
    if (_shipments.isEmpty) {
      return const Center(
        child: Column(
          children: [
            SizedBox(height: 40),
            Icon(Icons.inbox_outlined, color: AppTheme.textSecondary, size: 48),
            SizedBox(height: 12),
            Text('لا توجد شحنات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ],
        ),
      );
    }

    return AppTheme.glassCardWidget(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppTheme.primary.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.list_alt, color: AppTheme.primary, size: 16),
                ),
                const SizedBox(width: 8),
                const Text('قائمة الشحنات',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ],
            ),
          ),
          const Divider(color: AppTheme.glassBorder, height: 1),
          ..._shipments.map((s) => _shipmentTile(s, hideProfit)),
        ],
      ),
    );
  }

  Widget _shipmentTile(ExportShipmentModel s, bool hideP) {
    final profit = s.netProfitEgp;
    final isProfit = profit >= 0;
    final color = isProfit ? AppTheme.success : AppTheme.danger;
    final margin = s.profitMarginPercent;

    return InkWell(
      onTap: () async {
        final res = await context.push('/exports/costing/${s.id}');
        if (res == true) {
          _load();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UIUtils.shipmentNoText(s.shipmentNo,
                      style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                  Text(s.country ?? '—',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  const Text('كراتين', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
                  Text('${s.cartonsCount}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'Cairo')),
                ],
              ),
            ),
            if (!hideP) ...[
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    const Text('الربح', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
                    Text('EGP ${_fmt(profit)}',
                        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withAlpha(40)),
                  ),
                  child: Text('${margin.toStringAsFixed(1)}%',
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      textAlign: TextAlign.center),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_left, color: AppTheme.textSecondary.withAlpha(100), size: 20),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}
